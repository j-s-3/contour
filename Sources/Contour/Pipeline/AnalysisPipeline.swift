import Foundation

/// What the pipeline tells the review as it goes. The review opens on the first `.graph`
/// and fills in from every later one; nothing waits for `.complete`.
enum PipelineEvent: Sendable {
    /// A technical log line, kept behind "Show log".
    case log(PipelineProgressEntry)
    case status(PipelineStage, StageStatus)
    /// A new snapshot of the (linked) graph. Snapshots only ever gain or replace whole
    /// slices; the store carries the reviewer's own marks across them.
    case graph(PRGraph)
    case diff(String)
    case checkout(RepoCheckout)
    /// The graph on screen holds slices from an analysis of this earlier head; nil once
    /// none remain.
    case revalidating(fromHead: String?)
    case fromCache
    /// Every analysis stage has settled, successfully or not.
    case complete
    /// Fetching or checking out failed: there's no PR to show at all.
    case fatal(String)
}

/// Orchestrates the pipeline from §10 as a dependency graph rather than a sequence, so the
/// reviewer gets the review as soon as there's something to review (§ progressive opening):
///
///     fetch ──► PR shell on screen (title, metadata, raw diff)
///       │
///     checkout ──► cache? ──► exact hit: everything on screen, run only what's missing
///       │                └──► earlier revision: shown, marked stale, replaced slice by slice
///       ├── issue lookup ──► understanding (intent + plain-language)   ┐ tier 1
///       ├── behavior change (the before/after hero)                     ┘
///       ├── decisions (streamed, most consequential first)               tier 2
///       ├── architecture ──► flows (streamed)                            tier 3
///       └────────────────────────────────────────────► judgment         needs all of it
///
/// Only architecture → flows and everything → judgment are real dependencies. Decisions
/// used to wait on architecture and flows on decisions, but only to be handed ids for
/// cross-linking; those links are now derived locally from the code both sides cite
/// (`GraphLinker`), which takes two strong-tier calls off the critical path.
///
/// Every analysis stage fails on its own: the slice stays empty, the section says so and
/// offers a retry, and everything else carries on. Only fetch and checkout are fatal.
///
/// The reviewer can stop it at any point (`stop()`): what landed stays, and each stage that
/// hadn't is marked stopped and offers the same Retry, so it resumes one section at a time.
actor AnalysisPipeline {
    private let repoContext = RepoContextService()
    private let cache: AnalysisCache

    /// All three pluggable choices are resolved once per run rather than read per stage,
    /// so changing a setting mid-analysis can't produce a graph built half one way and
    /// half the other.
    private let harnessID: HarnessID
    private let trackerID: TrackerID
    private let github: GitHubService

    /// Bump this whenever a prompt or JSON schema changes shape — it's baked into the
    /// cache filename, so old cache entries from a previous schema are never mistakenly
    /// decoded against the new one; they just miss and re-run (§13).
    static let pipelineVersion = 13

    nonisolated let events: AsyncStream<PipelineEvent>
    private let continuation: AsyncStream<PipelineEvent>.Continuation

    // Per-run state. One pipeline analyzes one PR once, plus any retries.
    private var ctx: RawPRContext?
    private var checkout: RepoCheckout?
    private var analysis: AnalysisService?
    private var verifier: CodeRefVerifier?
    private var ticket: TicketInfo?
    private var ticketLookedUp = false
    /// Unlinked: links are derived on every publish, so a retried stage re-derives them.
    private var graph: PRGraph?
    private var statuses: [PipelineStage: StageStatus] = [:]
    /// Stages whose slice on screen came from an earlier revision.
    private var stale: Set<PipelineStage> = []
    private var staleHead: String?
    /// Stages whose slice was produced for this exact revision.
    private var completed: Set<PipelineStage> = []
    private var runTask: Task<Void, Never>?
    /// Retries run outside `runTask`, so stopping has to reach them separately.
    private var retryTasks: [PipelineStage: Task<Void, Never>] = [:]

    /// Test-only seams (`Tests/ContourTests/PipelineConcurrencyTests.swift`). All three stay
    /// nil in production, where `run()` behaves exactly as before: a real `GitHubService`
    /// fetch, a real `RepoContextService` checkout, and a real `AnalysisCache.latestRevision`
    /// lookup. Tests use them to drive this actor's real scheduling, cancellation and
    /// cache-restoration logic against the mock harness, with no network and no git checkout
    /// — `AnalysisCache` is itself bypassed entirely under `CONTOUR_MOCK_ANALYSIS=1` (see its
    /// doc comment), so `previousRevisionOverride` is the only way to exercise
    /// stale-while-revalidate under the mock harness.
    private let prSourceOverride: (any PRSource)?
    private let checkoutOverride: (@Sendable (RawPRContext) async throws -> RepoCheckout)?
    private let previousRevisionOverride: AnalysisCache.Entry?
    /// Mock analysis for this pipeline alone, instead of the process-wide environment
    /// switch (see `AnalysisService.MockOptions`).
    private let mockOverride: AnalysisService.MockOptions?

    init(harnessID: HarnessID, trackerID: TrackerID = .github, githubAccess: GitHubAccessMode = .auto,
         cache: AnalysisCache = AnalysisCache(),
         prSourceOverride: (any PRSource)? = nil,
         checkoutOverride: (@Sendable (RawPRContext) async throws -> RepoCheckout)? = nil,
         previousRevisionOverride: AnalysisCache.Entry? = nil,
         mockOverride: AnalysisService.MockOptions? = nil) {
        self.harnessID = harnessID
        self.trackerID = trackerID
        self.github = GitHubService(mode: githubAccess)
        self.cache = cache
        self.prSourceOverride = prSourceOverride
        self.checkoutOverride = checkoutOverride
        self.previousRevisionOverride = previousRevisionOverride
        self.mockOverride = mockOverride
        (events, continuation) = AsyncStream.makeStream(of: PipelineEvent.self)
    }

    /// Starts the run. Events arrive on `events` until `cancel()`; the stream stays open
    /// after `.complete` so a retried stage can still report.
    ///
    /// - Parameter forceRefresh: bypass any cached analysis for this exact revision and
    ///   re-run every stage. Used by the "Re-analyze (ignore cache)" command.
    func start(prURL: String, forceRefresh: Bool = false) {
        runTask?.cancel()
        runTask = Task { await run(prURL: prURL, forceRefresh: forceRefresh) }
    }

    /// Test/bench-only seam (`BenchTests`, issue #60): runs the pipeline against a
    /// pre-built context and checkout, skipping the real GitHub fetch and git clone —
    /// the two network-bound steps a repeatable, offline latency measurement has no
    /// business timing. Everything from here on (context-file write, cache lookup, stage
    /// dispatch, verification, graph assembly, linking, publish) is the exact path a real
    /// run takes, with `CONTOUR_MOCK_ANALYSIS=1` standing in for the model calls.
    func start(offlineContext ctx: RawPRContext, checkout: RepoCheckout, forceRefresh: Bool = true) {
        runTask?.cancel()
        runTask = Task { await runOffline(ctx: ctx, checkout: checkout, forceRefresh: forceRefresh) }
    }

    /// Ends the run for good: nothing more is reported, and the stream closes.
    func cancel() {
        cancelInFlight()
        continuation.finish()
    }

    /// "Stop analysis": ends everything in flight — cancelling a task tears down its
    /// harness subprocess — and marks every stage that hadn't settled as stopped. What
    /// already landed stays on screen, and unlike `cancel()` the stream stays open, so each
    /// stopped stage can be resumed on its own with `retry(_:)`.
    func stop() {
        cancelInFlight()
        let changes = AnalysisState.stopping(statuses)
        guard !changes.isEmpty else { return }
        // An interrupted issue lookup found nothing; let a resumed Understanding try again.
        if changes[.ticket] != nil { ticketLookedUp = false }
        for stage in PipelineStage.allCases { if let status = changes[stage] { setStatus(stage, status) } }
        let stopped = PipelineStage.allCases.filter { changes[$0] == .stopped }
        continuation.yield(.log(PipelineProgressEntry(
            stage: "Stopped", detail: "stopped by the reviewer: \(stopped.map(\.shortLabel).joined(separator: ", "))")))
        finishIfSettled()
    }

    /// Re-runs one failed or stopped stage — the per-section Retry.
    func retry(_ stage: PipelineStage) {
        guard analysis != nil, PipelineStage.analysis.contains(stage), statuses[stage]?.canRetry == true else { return }
        // A previous retry of this same stage can still be in flight (Retry clicked more than
        // once before the first attempt had a chance to flip the stage's status away from
        // failed/stopped): cancel it before starting a fresh one, so at most one run of a
        // stage is ever active and the newest call wins rather than racing the graph both
        // would otherwise write into.
        retryTasks[stage]?.cancel()
        retryTasks[stage] = Task {
            if stage == .understanding { await lookUpTicket() }
            await execute(stage)
            guard !Task.isCancelled else { return }
            finishIfSettled()
        }
    }

    private func cancelInFlight() {
        runTask?.cancel()
        runTask = nil
        for task in retryTasks.values { task.cancel() }
        retryTasks = [:]
    }

    // MARK: - The run

    private func run(prURL: String, forceRefresh: Bool) async {
        do {
            setStatus(.fetching, .running(detail: nil))
            let source = try prSourceOverride ?? github.source()
            log(.fetching, "via \(source.describesItself)")
            let ctx = try await source.fetchContext(prURL: prURL)
            self.ctx = ctx
            cache.recordOpened(url: ctx.url, repo: "\(ctx.owner)/\(ctx.repo)", number: ctx.number, title: ctx.title)
            graph = .shell(from: ctx)
            continuation.yield(.diff(ctx.diff))
            publish()
            setStatus(.fetching, .done)

            setStatus(.checkingOut, .running(detail: nil))
            log(.checkingOut, "\(ctx.owner)/\(ctx.repo) @ \(ctx.headSha.prefix(8))")
            let checkout: RepoCheckout
            if let checkoutOverride {
                checkout = try await checkoutOverride(ctx)
            } else {
                checkout = try await repoContext.checkout(ctx)
            }
            self.checkout = checkout
            verifier = CodeRefVerifier(checkout: checkout)
            continuation.yield(.checkout(checkout))
            setStatus(.checkingOut, .done)
            try Task.checkCancellation()

            // Built here rather than at init because the harness needs the checkout root to
            // resolve the context file it hands the model.
            analysis = AnalysisService(harness: HarnessFactory.make(harnessID, contextDirectory: checkout.rootDir),
                                       mock: mockOverride)

            // Written before the cache check, not after: contextual chat reads this file too,
            // and it has to be there when the analysis itself came from the cache.
            let contextFile = checkout.rootDir.appendingPathComponent(PromptBuilder.contextFileName)
            try PromptBuilder.contextFileContents(ctx).write(to: contextFile, atomically: true, encoding: .utf8)

            let toRun = restoreFromCache(ctx, forceRefresh: forceRefresh)
            if toRun.isEmpty {
                setStatus(.ticket, .done)
                finishIfSettled()
                return
            }
            await runStages(toRun)
            // Stopped partway: `stop()` has already settled every stage and reported it.
            guard !Task.isCancelled else { return }
            finishIfSettled()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            continuation.yield(.fatal(error.localizedDescription))
        }
    }

    /// The tail of `run(prURL:forceRefresh:)` — everything from the fetched context and a
    /// ready checkout onward — with the fetch and the real `git clone`/checkout dropped.
    /// See `start(offlineContext:checkout:forceRefresh:)`.
    private func runOffline(ctx: RawPRContext, checkout: RepoCheckout, forceRefresh: Bool) async {
        do {
            self.ctx = ctx
            cache.recordOpened(url: ctx.url, repo: "\(ctx.owner)/\(ctx.repo)", number: ctx.number, title: ctx.title)
            graph = .shell(from: ctx)
            continuation.yield(.diff(ctx.diff))
            publish()
            setStatus(.fetching, .done)

            self.checkout = checkout
            verifier = CodeRefVerifier(checkout: checkout)
            continuation.yield(.checkout(checkout))
            setStatus(.checkingOut, .done)
            try Task.checkCancellation()

            analysis = AnalysisService(harness: HarnessFactory.make(harnessID, contextDirectory: checkout.rootDir),
                                       mock: mockOverride)

            let contextFile = checkout.rootDir.appendingPathComponent(PromptBuilder.contextFileName)
            try PromptBuilder.contextFileContents(ctx).write(to: contextFile, atomically: true, encoding: .utf8)

            let toRun = restoreFromCache(ctx, forceRefresh: forceRefresh)
            if toRun.isEmpty {
                setStatus(.ticket, .done)
                finishIfSettled()
                return
            }
            await runStages(toRun)
            guard !Task.isCancelled else { return }
            finishIfSettled()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            continuation.yield(.fatal(error.localizedDescription))
        }
    }

    /// Puts whatever a previous run left on screen at once, and returns what's still to do.
    private func restoreFromCache(_ ctx: RawPRContext, forceRefresh: Bool) -> Set<PipelineStage> {
        setStatus(.cacheCheck, .running(detail: nil))
        log(.cacheCheck, "looking for a previous analysis of this exact commit")
        var toRun = Set(PipelineStage.analysis)
        defer { setStatus(.cacheCheck, .done) }
        guard !forceRefresh else { return toRun }

        if let cached = cache.load(owner: ctx.owner, repo: ctx.repo, number: ctx.number, headSha: ctx.headSha,
                                   baseSha: ctx.baseSha, pipelineVersion: Self.pipelineVersion) {
            var restored = cached.graph
            restored.refreshMetadata(from: ctx)
            graph = restored
            ticket = restored.pr.ticket
            completed = cached.completedStages
            toRun.subtract(completed)
            for stage in completed { setStatus(stage, .done) }
            continuation.yield(.fromCache)
            log(.cacheCheck, toRun.isEmpty
                ? "using cached analysis — \(restored.decisions.count) decisions, \(restored.components.count) components"
                : "resuming a partial analysis — \(toRun.count) stage(s) still to run")
            publish()
            return toRun
        }

        if let previous = previousRevisionOverride ?? cache.latestRevision(owner: ctx.owner, repo: ctx.repo, number: ctx.number,
                                                                            excludingHead: ctx.headSha, pipelineVersion: Self.pipelineVersion) {
            var restored = previous.graph
            restored.refreshMetadata(from: ctx)
            for stage in PipelineStage.analysis where !previous.completedStages.contains(stage) {
                restored.clear(stage)
            }
            graph = restored
            stale = previous.completedStages
            staleHead = previous.graph.pr.headSha
            for stage in stale { setStatus(stage, .stale) }
            continuation.yield(.revalidating(fromHead: staleHead))
            log(.cacheCheck, "showing the analysis of \(previous.graph.pr.headSha.prefix(8)) while this revision is analyzed")
            publish()
        }
        return toRun
    }

    /// Runs the stages in dependency order with everything independent in parallel.
    private func runStages(_ toRun: Set<PipelineStage>) async {
        await withTaskGroup(of: Void.self) { group in
            // Tier 1: what the PR is for, and the before/after hero.
            group.addTask {
                if toRun.contains(.understanding) {
                    await self.lookUpTicket()
                    await self.execute(.understanding)
                } else {
                    await self.setStatus(.ticket, .done)
                }
            }
            if toRun.contains(.behaviorChange) {
                group.addTask { await self.execute(.behaviorChange) }
            }
            // Tier 2: the decisions the reviewer has to judge.
            if toRun.contains(.decisions) {
                group.addTask { await self.execute(.decisions) }
            }
            // Tier 3: the system around the change. Flows need the architecture's parts.
            if toRun.contains(.architecture) || toRun.contains(.flows) {
                group.addTask {
                    if toRun.contains(.architecture) { await self.execute(.architecture) }
                    if toRun.contains(.flows) { await self.execute(.flows) }
                }
            }
        }
        // Judgment synthesizes everything above, so it goes last — with whatever there is,
        // even if a stage before it failed.
        if toRun.contains(.judgment) {
            await execute(.judgment)
        }
    }

    /// Best-effort issue lookup: never fails the pipeline. Leaves `ticket` nil when there's
    /// no reference, when the tracker isn't set up, or when the lookup errors.
    private func lookUpTicket() async {
        guard !ticketLookedUp, let ctx, !Task.isCancelled else { return }
        ticketLookedUp = true
        setStatus(.ticket, .running(detail: nil))
        defer { setStatus(.ticket, .done) }
        guard let source = try? github.source() else { return }
        let tracker = Self.tracker(trackerID, source: source, context: ctx)
        guard let ref = tracker.reference(in: ctx) else {
            log(.ticket, trackerID == .none ? "issue lookup is turned off"
                                            : "no reference found in title/body/branch/commits")
            return
        }
        log(.ticket, "found \(ref.displayKey), fetching it")
        ticket = await tracker.fetch(ref)
        if let ticket {
            log(.ticket, "\(ticket.key): \(ticket.summary)")
            graph?.pr.ticket = ticket
            publish()
        } else {
            log(.ticket, "\(ref.displayKey) referenced, but couldn't fetch it")
        }
    }

    // MARK: - One stage

    private func execute(_ stage: PipelineStage) async {
        guard let analysis, let checkout, let verifier, !Task.isCancelled else { return }
        setStatus(stage, .running(detail: nil))
        do {
            let result = try await perform(stage, analysis: analysis, cwd: checkout.rootDir)
            guard !Task.isCancelled else { return }
            // Checked before the slice lands, so no ref the checkout can't back is shown as
            // final or used to link decisions to flows.
            let (verified, check) = await verifier.verify(result)
            guard !Task.isCancelled else { return }
            if check.unresolvedCount > 0 {
                log(stage, "\(check.unresolvedCount) of \(check.checked) references couldn't be verified: "
                    + check.unresolved.prefix(5).joined(separator: ", "))
            }
            graph?.apply(verified)
            graph?.record(check, for: stage)
            stale.remove(stage)
            completed.insert(stage)
            setStatus(stage, .done)
            publish()
            save()
        } catch {
            guard !Task.isCancelled else { return }
            // A failed stage shows nothing rather than a half-streamed or previous-revision
            // slice that would read as a conclusion about this code.
            graph?.clear(stage)
            stale.remove(stage)
            // The technical account (raw response, stderr) goes to the log; the section
            // gets a line the reviewer can act on.
            log(stage, "failed: \(error.localizedDescription)")
            setStatus(stage, .failed(stage.failureMessage(for: error)))
            publish()
        }
    }

    private func perform(_ stage: PipelineStage, analysis: AnalysisService, cwd: URL) async throws -> StageResult {
        let label = stage.rawValue
        let progress: @Sendable (AnalysisProgress) -> Void = { [continuation] p in
            continuation.yield(.log(PipelineProgressEntry(stage: label, detail: p.detail)))
        }
        func run(_ prompt: String, _ tier: AnalysisTier) async throws -> [String: Any] {
            try await analysis.runStage(prompt: prompt, cwd: cwd, tier: tier, stage: stage, onProgress: progress)
        }

        switch stage {
        case .behaviorChange:
            log(stage, "finding the before/after pipeline")
            let raw = try await run(PromptBuilder.behaviorChangePrompt(), .fast)
            return .behaviorChange(try StageDecoding.decode(StageDecoding.BehaviorChangeResult.self, stageLabel: label, from: raw))

        case .understanding:
            log(stage, ticket.map { "reading the PR, grounded in \($0.key)" } ?? "reading the PR description and code")
            let raw = try await run(PromptBuilder.understandingPrompt(ticket: ticket), .fast)
            return .understanding(try StageDecoding.decode(StageDecoding.UnderstandingResult.self, stageLabel: label, from: raw))

        case .architecture:
            log(stage, "mapping changed files to components")
            let raw = try await run(PromptBuilder.architecturePrompt(), .fast)
            return .architecture(try StageDecoding.decode(StageDecoding.ArchitectureResult.self, stageLabel: label, from: raw))

        case .decisions:
            log(stage, "reading changed code")
            let raw = try await streamed(stage, key: "decisions", as: DecisionNode.self, analysis: analysis, cwd: cwd,
                                         prompt: PromptBuilder.decisionsPrompt(), tier: .strong, progress: progress)
            return .decisions(try StageDecoding.decode(StageDecoding.DecisionsResult.self, stageLabel: label, from: raw).decisions)

        case .flows:
            log(stage, "finding entry points")
            let prompt = PromptBuilder.flowsPrompt(components: graph?.components ?? [], entryHints: [])
            let raw = try await streamed(stage, key: "flows", as: FlowNode.self, analysis: analysis, cwd: cwd,
                                         prompt: prompt, tier: .strong, progress: progress)
            return .flows(try StageDecoding.decode(StageDecoding.FlowsResult.self, stageLabel: label, from: raw))

        case .judgment:
            log(stage, "final synthesis")
            let graphSoFar = try Self.compactJSON(graph?.linked())
            let raw = try await run(PromptBuilder.judgmentPrompt(graphSoFar: graphSoFar), .strong)
            return .judgment(try StageDecoding.decode(StageDecoding.JudgmentResult.self, stageLabel: label, from: raw))

        case .fetching, .checkingOut, .cacheCheck, .ticket:
            preconditionFailure("\(stage) is not an analysis stage")
        }
    }

    /// Runs a stage whose array elements are shown as the model writes them. Elements pass
    /// through an ordered channel and are all applied before this returns, so none can land
    /// after — and duplicate — the stage's final, authoritative result.
    private func streamed<Element: Decodable & Sendable & Identifiable>(
        _ stage: PipelineStage, key: String, as: Element.Type, analysis: AnalysisService, cwd: URL,
        prompt: String, tier: AnalysisTier, progress: @escaping @Sendable (AnalysisProgress) -> Void
    ) async throws -> [String: Any] where Element.ID == String {
        let (elements, sink) = AsyncStream.makeStream(of: Element.self)
        let applier = Task { for await element in elements { self.appendStreamed(element, to: stage) } }
        do {
            let raw = try await analysis.runStage(
                prompt: prompt, cwd: cwd, tier: tier, stage: stage, streaming: key,
                onElement: { object in
                    if let element = try? StageDecoding.decode(Element.self, from: object) { sink.yield(element) }
                },
                onProgress: progress
            )
            sink.finish()
            await applier.value
            return raw
        } catch {
            // Every element already queued lands (or is dropped by `appendStreamed`'s own
            // `isRunning` guard) before this call returns on failure exactly as on success —
            // otherwise `applier` outlives this call and can append a stale element from an
            // aborted attempt into a later retry of the same stage, once its own status is
            // `.running` again.
            sink.finish()
            await applier.value
            throw error
        }
    }

    /// Appends one streamed element to its slice — unless the slice on screen is from an
    /// earlier revision, which stays whole until this revision's replaces it outright rather
    /// than being mixed with it.
    private func appendStreamed<Element: Identifiable>(_ element: Element, to stage: PipelineStage) where Element.ID == String {
        guard statuses[stage]?.isRunning == true, var g = graph else { return }
        let count: Int
        switch (stage, element) {
        case (.decisions, let decision as DecisionNode):
            if !stale.contains(stage), !g.decisions.contains(where: { $0.id == decision.id }) {
                g.decisions.append(decision)
            }
            count = stale.contains(stage) ? 0 : g.decisions.count
        case (.flows, let flow as FlowNode):
            if !stale.contains(stage), !g.flows.contains(where: { $0.id == flow.id }) {
                g.flows.append(flow)
            }
            count = stale.contains(stage) ? 0 : g.flows.count
        default:
            return
        }
        graph = g
        if count > 0 {
            setStatus(stage, .running(detail: "\(count) found so far"))
            publish()
        }
    }

    // MARK: - Reporting

    private func setStatus(_ stage: PipelineStage, _ status: StageStatus) {
        statuses[stage] = status
        continuation.yield(.status(stage, status))
    }

    private func log(_ stage: PipelineStage, _ detail: String) {
        continuation.yield(.log(PipelineProgressEntry(stage: stage.rawValue, detail: detail)))
    }

    private func publish() {
        guard let graph else { return }
        continuation.yield(.graph(graph.linked()))
    }

    private func finishIfSettled() {
        guard PipelineStage.analysis.allSatisfy({ statuses[$0]?.isSettled == true }) else { return }
        if staleHead != nil, stale.isEmpty {
            staleHead = nil
            continuation.yield(.revalidating(fromHead: nil))
        }
        let failed = PipelineStage.analysis.filter { statuses[$0]?.failure != nil }
        let stopped = PipelineStage.analysis.filter { statuses[$0] == .stopped }
        let summary = "\(graph?.decisions.count ?? 0) decisions, \(graph?.components.count ?? 0) components"
            + (failed.isEmpty ? "" : "; failed: \(failed.map(\.shortLabel).joined(separator: ", "))")
            + (stopped.isEmpty ? "" : "; stopped: \(stopped.map(\.shortLabel).joined(separator: ", "))")
        continuation.yield(.log(PipelineProgressEntry(stage: "Done", detail: summary)))
        continuation.yield(.complete)
    }

    /// Saved as each stage lands, holding only what was produced for this revision, so an
    /// interrupted run resumes rather than restarts and never caches a stale slice as current.
    private func save() {
        guard let ctx, var snapshot = graph else { return }
        for stage in stale { snapshot.clear(stage) }
        cache.save(owner: ctx.owner, repo: ctx.repo, number: ctx.number, headSha: ctx.headSha, baseSha: ctx.baseSha,
                   pipelineVersion: Self.pipelineVersion, graph: snapshot.linked(), diff: ctx.diff,
                   completedStages: completed)
    }

    /// The GitHub tracker needs to know which repo a bare `#123` refers to, which is only
    /// known once the PR has been fetched.
    private static func tracker(_ id: TrackerID, source: any PRSource, context: RawPRContext) -> any IssueTracker {
        switch id {
        case .github: return GitHubIssueTracker(source: source).scoped(to: context)
        case .jira: return JiraTracker()
        case .none: return NoTracker()
        }
    }

    private static func compactJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
