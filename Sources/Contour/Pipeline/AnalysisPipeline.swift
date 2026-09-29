import Foundation

enum PipelineEvent: Sendable {
    case log(PipelineProgressEntry)
    case status(PipelineStage, StageStatus)
    case graph(PRGraph)
    case diff(String)
    case checkout(RepoCheckout)
    case revalidating(fromHead: String?)
    case fromCache
    case complete
    case fatal(String)
}

actor AnalysisPipeline {
    private let repoContext = RepoContextService()
    private let cache: AnalysisCache

    private let harnessID: HarnessID
    private let trackerID: TrackerID
    private let github: GitHubService

    static let pipelineVersion = 13

    nonisolated let events: AsyncStream<PipelineEvent>
    private let continuation: AsyncStream<PipelineEvent>.Continuation

    private var ctx: RawPRContext?
    private var checkout: RepoCheckout?
    private var analysis: AnalysisService?
    private var verifier: CodeRefVerifier?
    private var ticket: TicketInfo?
    private var ticketLookedUp = false
    private var graph: PRGraph?
    private var statuses: [PipelineStage: StageStatus] = [:]
    private var stale: Set<PipelineStage> = []
    private var staleHead: String?
    private var completed: Set<PipelineStage> = []
    private var runTask: Task<Void, Never>?
    private var retryTasks: [PipelineStage: Task<Void, Never>] = [:]

    private let prSourceOverride: (any PRSource)?
    private let checkoutOverride: (@Sendable (RawPRContext) async throws -> RepoCheckout)?
    private let previousRevisionOverride: AnalysisCache.Entry?
    private let mockOverride: AnalysisService.MockOptions?

    init(
        harnessID: HarnessID, trackerID: TrackerID = .github, githubAccess: GitHubAccessMode = .auto,
        cache: AnalysisCache = AnalysisCache(),
        prSourceOverride: (any PRSource)? = nil,
        checkoutOverride: (@Sendable (RawPRContext) async throws -> RepoCheckout)? = nil,
        previousRevisionOverride: AnalysisCache.Entry? = nil,
        mockOverride: AnalysisService.MockOptions? = nil
    ) {
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

    func start(prURL: String, forceRefresh: Bool = false) {
        runTask?.cancel()
        runTask = Task { await run(prURL: prURL, forceRefresh: forceRefresh) }
    }

    func start(offlineContext ctx: RawPRContext, checkout: RepoCheckout, forceRefresh: Bool = true) {
        runTask?.cancel()
        runTask = Task { await runOffline(ctx: ctx, checkout: checkout, forceRefresh: forceRefresh) }
    }

    func cancel() {
        cancelInFlight()
        continuation.finish()
    }

    func stop() {
        cancelInFlight()
        let changes = AnalysisState.stopping(statuses)
        guard !changes.isEmpty else { return }
        if changes[.ticket] != nil { ticketLookedUp = false }
        for stage in PipelineStage.allCases { if let status = changes[stage] { setStatus(stage, status) } }
        let stopped = PipelineStage.allCases.filter { changes[$0] == .stopped }
        continuation.yield(
            .log(
                PipelineProgressEntry(
                    stage: "Stopped",
                    detail: "stopped by the reviewer: \(stopped.map(\.shortLabel).joined(separator: ", "))")))
        finishIfSettled()
    }

    func retry(_ stage: PipelineStage) {
        guard analysis != nil, PipelineStage.analysis.contains(stage), statuses[stage]?.canRetry == true else { return }
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

            analysis = AnalysisService(
                harness: HarnessFactory.make(harnessID, contextDirectory: checkout.rootDir),
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

            analysis = AnalysisService(
                harness: HarnessFactory.make(harnessID, contextDirectory: checkout.rootDir),
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

    private func restoreFromCache(_ ctx: RawPRContext, forceRefresh: Bool) -> Set<PipelineStage> {
        setStatus(.cacheCheck, .running(detail: nil))
        log(.cacheCheck, "looking for a previous analysis of this exact commit")
        var toRun = Set(PipelineStage.analysis)
        defer { setStatus(.cacheCheck, .done) }
        guard !forceRefresh else { return toRun }

        if let cached = cache.load(
            owner: ctx.owner, repo: ctx.repo, number: ctx.number, headSha: ctx.headSha,
            baseSha: ctx.baseSha, pipelineVersion: Self.pipelineVersion)
        {
            var restored = cached.graph
            restored.refreshMetadata(from: ctx)
            graph = restored
            ticket = restored.pr.ticket
            completed = cached.completedStages
            toRun.subtract(completed)
            for stage in completed { setStatus(stage, .done) }
            continuation.yield(.fromCache)
            log(
                .cacheCheck,
                toRun.isEmpty
                    ? "using cached analysis — \(restored.decisions.count) decisions, \(restored.components.count) components"
                    : "resuming a partial analysis — \(toRun.count) stage(s) still to run")
            publish()
            return toRun
        }

        if let previous = previousRevisionOverride
            ?? cache.latestRevision(
                owner: ctx.owner, repo: ctx.repo, number: ctx.number,
                excludingHead: ctx.headSha, pipelineVersion: Self.pipelineVersion)
        {
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
            log(
                .cacheCheck,
                "showing the analysis of \(previous.graph.pr.headSha.prefix(8)) while this revision is analyzed")
            publish()
        }
        return toRun
    }

    private func runStages(_ toRun: Set<PipelineStage>) async {
        await withTaskGroup(of: Void.self) { group in
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
            if toRun.contains(.decisions) {
                group.addTask { await self.execute(.decisions) }
            }
            if toRun.contains(.architecture) || toRun.contains(.flows) {
                group.addTask {
                    if toRun.contains(.architecture) { await self.execute(.architecture) }
                    if toRun.contains(.flows) { await self.execute(.flows) }
                }
            }
        }
        if toRun.contains(.judgment) {
            await execute(.judgment)
        }
    }

    private func lookUpTicket() async {
        guard !ticketLookedUp, let ctx, !Task.isCancelled else { return }
        ticketLookedUp = true
        setStatus(.ticket, .running(detail: nil))
        defer { setStatus(.ticket, .done) }
        guard let source = try? github.source() else { return }
        let tracker = Self.tracker(trackerID, source: source, context: ctx)
        guard let ref = tracker.reference(in: ctx) else {
            log(
                .ticket,
                trackerID == .none
                    ? "issue lookup is turned off"
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

    private func execute(_ stage: PipelineStage) async {
        guard let analysis, let checkout, let verifier, !Task.isCancelled else { return }
        setStatus(stage, .running(detail: nil))
        do {
            let result = try await perform(stage, analysis: analysis, cwd: checkout.rootDir)
            guard !Task.isCancelled else { return }
            let (verified, check) = await verifier.verify(result)
            guard !Task.isCancelled else { return }
            if check.unresolvedCount > 0 {
                log(
                    stage,
                    "\(check.unresolvedCount) of \(check.checked) references couldn't be verified: "
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
            graph?.clear(stage)
            stale.remove(stage)
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
            return .behaviorChange(
                try StageDecoding.decode(StageDecoding.BehaviorChangeResult.self, stageLabel: label, from: raw))

        case .understanding:
            log(stage, ticket.map { "reading the PR, grounded in \($0.key)" } ?? "reading the PR description and code")
            let raw = try await run(PromptBuilder.understandingPrompt(ticket: ticket), .fast)
            return .understanding(
                try StageDecoding.decode(StageDecoding.UnderstandingResult.self, stageLabel: label, from: raw))

        case .architecture:
            log(stage, "mapping changed files to components")
            let raw = try await run(PromptBuilder.architecturePrompt(), .fast)
            return .architecture(
                try StageDecoding.decode(StageDecoding.ArchitectureResult.self, stageLabel: label, from: raw))

        case .decisions:
            log(stage, "reading changed code")
            let raw = try await streamed(
                stage, key: "decisions", as: DecisionNode.self, analysis: analysis, cwd: cwd,
                prompt: PromptBuilder.decisionsPrompt(), tier: .strong, progress: progress)
            return .decisions(
                try StageDecoding.decode(StageDecoding.DecisionsResult.self, stageLabel: label, from: raw).decisions)

        case .flows:
            log(stage, "finding entry points")
            let prompt = PromptBuilder.flowsPrompt(components: graph?.components ?? [], entryHints: [])
            let raw = try await streamed(
                stage, key: "flows", as: FlowNode.self, analysis: analysis, cwd: cwd,
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
            sink.finish()
            await applier.value
            throw error
        }
    }

    private func appendStreamed<Element: Identifiable>(_ element: Element, to stage: PipelineStage)
    where Element.ID == String {
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
        let summary =
            "\(graph?.decisions.count ?? 0) decisions, \(graph?.components.count ?? 0) components"
            + (failed.isEmpty ? "" : "; failed: \(failed.map(\.shortLabel).joined(separator: ", "))")
            + (stopped.isEmpty ? "" : "; stopped: \(stopped.map(\.shortLabel).joined(separator: ", "))")
        continuation.yield(.log(PipelineProgressEntry(stage: "Done", detail: summary)))
        continuation.yield(.complete)
    }

    private func save() {
        guard let ctx, var snapshot = graph else { return }
        for stage in stale { snapshot.clear(stage) }
        cache.save(
            owner: ctx.owner, repo: ctx.repo, number: ctx.number, headSha: ctx.headSha, baseSha: ctx.baseSha,
            pipelineVersion: Self.pipelineVersion, graph: snapshot.linked(), diff: ctx.diff,
            completedStages: completed)
    }

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
