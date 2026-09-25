import Foundation

/// One line of the progress log shown while a PR is being analyzed (§4.1, "real substeps").
struct PipelineProgressEntry: Identifiable, Sendable {
    let id = UUID()
    var stage: String
    var detail: String
}

enum PipelineStage: String, CaseIterable {
    case fetching = "Fetching PR"
    case checkingOut = "Checking out repository"
    case cacheCheck = "Checking cache"
    case jira = "Checking Jira"
    case behaviorChange = "Identifying behavior change"
    case architecture = "Analyzing architecture"
    case intent = "Extracting intent"
    case eli5 = "Writing plain-language summary"
    case decisions = "Extracting decisions"
    case tradeoffs = "Surfacing tradeoffs"
    case flows = "Tracing flows"
    case judgment = "Identifying what needs judgment"
    case done = "Done"
}

/// Orchestrates the whole pipeline from §10: GitHub fetch → local checkout → staged pi
/// calls → assembled PRGraph. Stages run sequentially because each one after the first
/// depends on component/decision IDs from an earlier stage for cross-linking — this is
/// the graph's edges being built, not just independent summarization.
actor AnalysisPipeline {
    private let github = GitHubService()
    private let repoContext = RepoContextService()
    private let analysis = AnalysisService()
    private let jira = JiraService()
    private let cache = AnalysisCache()

    /// Bump this whenever a prompt or JSON schema changes shape — it's baked into the
    /// cache filename, so old cache entries from a previous schema are never mistakenly
    /// decoded against the new one; they just miss and re-run (§13).
    static let pipelineVersion = 4

    struct Result: Sendable {
        var graph: PRGraph
        var checkout: RepoCheckout
        var diff: String
    }

    /// - Parameter forceRefresh: bypass any cached analysis for this exact
    ///   (repo, headSha, baseSha, pipelineVersion) and re-run all six stages. Used by the
    ///   "Re-analyze (ignore cache)" command.
    func run(
        prURL: String,
        forceRefresh: Bool = false,
        onProgress: @escaping @Sendable (PipelineStage, PipelineProgressEntry) -> Void
    ) async throws -> Result {
        onProgress(.fetching, .init(stage: "Fetching PR", detail: "gh pr view"))
        let ctx = try await github.fetchContext(prURL: prURL)

        onProgress(.checkingOut, .init(stage: "Checking out repository", detail: "\(ctx.owner)/\(ctx.repo) @ \(ctx.headSha.prefix(8))"))
        let checkout = try await repoContext.checkout(ctx)

        // A checkout is needed either way (cache hit or miss) so the code viewer has real
        // files to read. The cache only saves the six `pi` calls, not the git operations.
        onProgress(.cacheCheck, .init(stage: "Checking cache", detail: "looking for a previous analysis of this exact commit"))
        if !forceRefresh, let cached = cache.load(
            owner: ctx.owner, repo: ctx.repo, number: ctx.number,
            headSha: ctx.headSha, baseSha: ctx.baseSha, pipelineVersion: Self.pipelineVersion
        ) {
            onProgress(.done, .init(stage: "Done", detail: "using cached analysis — \(cached.graph.decisions.count) decisions, \(cached.graph.components.count) components"))
            return Result(graph: cached.graph, checkout: checkout, diff: cached.diff)
        }

        let contextFile = checkout.rootDir.appendingPathComponent(PromptBuilder.contextFileName)
        try PromptBuilder.contextFileContents(ctx).write(to: contextFile, atomically: true, encoding: .utf8)

        // Best-effort Jira lookup: never fails the pipeline, just returns nil if there's
        // no ticket, `acli` isn't set up, or the lookup errors for any reason (§ new Jira
        // ELI5 feature).
        var jiraTicket: JiraTicketInfo?
        if let key = JiraService.ticketKey(in: ctx) {
            onProgress(.jira, .init(stage: "Checking Jira", detail: "found \(key), fetching ticket"))
            jiraTicket = await jira.fetchTicket(key: key)
            if let jiraTicket {
                onProgress(.jira, .init(stage: "Checking Jira", detail: "\(jiraTicket.key): \(jiraTicket.summary)"))
            } else {
                onProgress(.jira, .init(stage: "Checking Jira", detail: "\(key) referenced, but couldn't fetch it (acli not set up, or ticket not found)"))
            }
        } else {
            onProgress(.jira, .init(stage: "Checking Jira", detail: "no ticket key found in title/branch/commits"))
        }

        // Stage 0: behavior change — the hero of Summary, everything else drills down from
        // this. Runs before architecture on purpose: the reviewer's mental model starts here.
        onProgress(.behaviorChange, .init(stage: "Identifying behavior change", detail: "finding the before/after pipeline"))
        let behaviorRaw = try await analysis.runStage(
            prompt: PromptBuilder.behaviorChangePrompt(), cwd: checkout.rootDir, tier: .fast, stage: .behaviorChange
        ) { p in onProgress(.behaviorChange, .init(stage: "Identifying behavior change", detail: p.detail)) }
        let behavior = try StageDecoding.decode(StageDecoding.BehaviorChangeResult.self, stageLabel: "Identifying behavior change", from: behaviorRaw)

        // Stage 1: architecture — establishes component IDs everything else links against.
        onProgress(.architecture, .init(stage: "Analyzing architecture", detail: "mapping changed files to components"))
        let archRaw = try await analysis.runStage(
            prompt: PromptBuilder.architecturePrompt(), cwd: checkout.rootDir, tier: .fast, stage: .architecture
        ) { p in onProgress(.architecture, .init(stage: "Analyzing architecture", detail: p.detail)) }
        let arch = try StageDecoding.decode(StageDecoding.ArchitectureResult.self, stageLabel: "Analyzing architecture", from: archRaw)

        // Stage 2: intent — independent of components, can run for its own clear provenance.
        onProgress(.intent, .init(stage: "Extracting intent", detail: "reading PR description and commits"))
        let intentRaw = try await analysis.runStage(
            prompt: PromptBuilder.intentPrompt(), cwd: checkout.rootDir, tier: .fast, stage: .intent
        ) { p in onProgress(.intent, .init(stage: "Extracting intent", detail: p.detail)) }
        let intent = try StageDecoding.decode(StageDecoding.IntentResult.self, stageLabel: "Extracting intent", from: intentRaw)

        // Stage 2b: ELI5 — the two plain-language briefs, grounded in Jira when linked.
        onProgress(.eli5, .init(stage: "Writing plain-language summary", detail: jiraTicket != nil ? "grounding in \(jiraTicket!.key)" : "reading PR description and code"))
        let eli5Raw = try await analysis.runStage(
            prompt: PromptBuilder.eli5Prompt(jira: jiraTicket), cwd: checkout.rootDir, tier: .fast, stage: .eli5
        ) { p in onProgress(.eli5, .init(stage: "Writing plain-language summary", detail: p.detail)) }
        let eli5 = try StageDecoding.decode(StageDecoding.ELI5Result.self, stageLabel: "Writing plain-language summary", from: eli5Raw)

        // Stage 3: decisions — the strong-tier stage; needs component IDs for componentIds links.
        onProgress(.decisions, .init(stage: "Extracting decisions", detail: "reading changed code"))
        let decisionsRaw = try await analysis.runStage(
            prompt: PromptBuilder.decisionsPrompt(components: arch.components), cwd: checkout.rootDir, tier: .strong, stage: .decisions
        ) { p in onProgress(.decisions, .init(stage: "Extracting decisions", detail: p.detail)) }
        let decisions = try StageDecoding.decode(StageDecoding.DecisionsResult.self, stageLabel: "Extracting decisions", from: decisionsRaw)

        // Stage 4: tradeoffs — needs decision IDs.
        onProgress(.tradeoffs, .init(stage: "Surfacing tradeoffs", detail: "deriving tradeoff axes"))
        let tradeoffsRaw = try await analysis.runStage(
            prompt: PromptBuilder.tradeoffsPrompt(decisions: decisions.decisions), cwd: checkout.rootDir, tier: .strong, stage: .tradeoffs
        ) { p in onProgress(.tradeoffs, .init(stage: "Surfacing tradeoffs", detail: p.detail)) }
        let tradeoffs = try StageDecoding.decode(StageDecoding.TradeoffsResult.self, stageLabel: "Surfacing tradeoffs", from: tradeoffsRaw)

        // Stage 5: flows + entry points — needs component IDs.
        onProgress(.flows, .init(stage: "Tracing flows", detail: "finding entry points"))
        let flowsRaw = try await analysis.runStage(
            prompt: PromptBuilder.flowsPrompt(components: arch.components, entryHints: []), cwd: checkout.rootDir, tier: .strong, stage: .flows
        ) { p in onProgress(.flows, .init(stage: "Tracing flows", detail: p.detail)) }
        let flows = try StageDecoding.decode(StageDecoding.FlowsResult.self, stageLabel: "Tracing flows", from: flowsRaw)

        // Stage 6: judgment + questions — final synthesis pass, sees everything so far.
        var partial = PRGraph(
            pr: PRSummary(
                repo: "\(ctx.owner)/\(ctx.repo)", number: ctx.number, title: ctx.title, author: ctx.author,
                state: ctx.state, branch: ctx.headRefName, baseBranch: ctx.baseRefName, headSha: ctx.headSha,
                baseSha: ctx.baseSha, intent: intent.intent, filesChanged: ctx.changedFiles,
                additions: ctx.additions, deletions: ctx.deletions
            ),
            components: arch.components,
            decisions: decisions.decisions,
            tradeoffs: tradeoffs.tradeoffs,
            flows: flows.flows,
            entryPoints: flows.entryPoints,
            behaviorChanges: behavior.behaviorChanges,
            architectureEdges: arch.edges,
            boundaries: arch.boundaries
        )
        partial.pr.architectureImpact = arch.architectureImpact
        partial.pr.jiraTicket = jiraTicket
        partial.pr.problemToBeSolved = eli5.problemToBeSolved
        partial.pr.howItWasSolved = eli5.howItWasSolved

        onProgress(.judgment, .init(stage: "Identifying what needs judgment", detail: "final synthesis"))
        let graphSoFarJSON = try Self.compactJSON(partial)
        let judgmentRaw = try await analysis.runStage(
            prompt: PromptBuilder.judgmentPrompt(graphSoFar: graphSoFarJSON), cwd: checkout.rootDir, tier: .strong, stage: .judgment
        ) { p in onProgress(.judgment, .init(stage: "Identifying what needs judgment", detail: p.detail)) }
        let judgment = try StageDecoding.decode(StageDecoding.JudgmentResult.self, stageLabel: "Identifying what needs judgment", from: judgmentRaw)

        partial.pr.needsJudgment = judgment.needsJudgment
        partial.pr.uncertainties = judgment.uncertainties
        partial.questions = judgment.questions
        if let cm = judgment.changeMap, !cm.isEmpty {
            partial.pr.changeMap = cm
        } else {
            partial.pr.changeMap = arch.components.map { ChangeMapEntry(name: $0.title, filesChanged: $0.filesChanged) }
        }

        cache.save(
            owner: ctx.owner, repo: ctx.repo, number: ctx.number, headSha: ctx.headSha, baseSha: ctx.baseSha,
            pipelineVersion: Self.pipelineVersion, graph: partial, diff: ctx.diff
        )

        onProgress(.done, .init(stage: "Done", detail: "\(partial.decisions.count) decisions, \(partial.components.count) components"))
        return Result(graph: partial, checkout: checkout, diff: ctx.diff)
    }

    private static func compactJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
