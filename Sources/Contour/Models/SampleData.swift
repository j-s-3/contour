import Foundation

/// A realistic sample `PRGraph` exercising the full Behavior → System → Components →
/// Implementation → Code hierarchy, for SwiftUI previews and tests. Models a PR that
/// makes publishing a docs page trigger an immediate search reindex instead of waiting for
/// the next nightly rebuild.
enum ContourSampleData {
    static let publishTriggeredReindex: PRGraph = {
        let publishing = ComponentNode(
            id: "page-publishing", title: "Page Publishing", changeKind: .changed,
            summary: Statement(text: "Decides when a published page's search entry needs to be rebuilt.", provenance: .interpretation, confidence: .high),
            refs: [CodeRef(path: "src/main/java/publishing/PagePublisher.java", startLine: 40, endLine: 96)],
            decisionIds: ["index-on-publish"], flowIds: ["publish-index-flow"],
            dependsOnIds: ["search-service", "index-queue"], filesChanged: 3,
            level: .system, implementedBy: ["PagePublisher", "SearchIndexCoordinator"]
        )
        let searchService = ComponentNode(
            id: "search-service", title: "Search Service", changeKind: .touched,
            summary: Statement(text: "External search cluster that indexes page content for site search.", provenance: .fact),
            refs: [], decisionIds: [], flowIds: ["publish-index-flow"],
            dependsOnIds: [], isTrustBoundaryEdge: true, filesChanged: 0,
            level: .system, implementedBy: ["SearchServiceClient"]
        )
        let indexQueue = ComponentNode(
            id: "index-queue", title: "Index Queue", changeKind: .new,
            summary: Statement(text: "Async queue that fans out indexing work so publishes stay fast.", provenance: .interpretation, confidence: .medium),
            refs: [CodeRef(path: "src/main/java/queue/IndexQueue.java", startLine: 1, endLine: 30)],
            decisionIds: ["index-on-publish"], flowIds: ["publish-index-flow"],
            dependsOnIds: [], filesChanged: 2,
            level: .system, implementedBy: ["IndexQueue", "IndexQueueWorker"]
        )
        let publisherImpl = ComponentNode(
            id: "page-publisher-impl", title: "PagePublisher", changeKind: .changed,
            summary: Statement(text: "Calls reindex() from the publish event handler instead of the nightly rebuild.", provenance: .fact),
            refs: [CodeRef(path: "src/main/java/publishing/PagePublisher.java", startLine: 40, endLine: 96)],
            dependsOnIds: ["page-publishing"], filesChanged: 1,
            level: .implementation
        )

        let decision = DecisionNode(
            id: "index-on-publish", title: "Trigger reindexing synchronously on publish",
            decision: Statement(text: "Reindexing now runs on the publish event path instead of waiting for the nightly rebuild.", provenance: .fact),
            rationale: [Statement(text: "Stale search results after publishing were the top support complaint.", provenance: .claim, source: "PR description")],
            alternatives: [Statement(text: "Keep the nightly rebuild and shorten its interval.", provenance: .interpretation, confidence: .medium)],
            consequences: [Statement(text: "Publish latency now includes a queue hop.", provenance: .interpretation, confidence: .medium)],
            confidence: .high,
            refs: [CodeRef(path: "src/main/java/publishing/PagePublisher.java", startLine: 40, endLine: 96)],
            tradeoffIds: ["latency-vs-freshness"], componentIds: ["page-publishing", "index-queue"],
            level: .system
        )

        let tradeoff = TradeoffNode(
            id: "latency-vs-freshness", title: "Publish latency vs. search freshness",
            poleA: "fast publish", poleB: "fresh results", chosen: "poleB",
            explanation: Statement(text: "Accepts a slower publish path in exchange for search results that are never stale.", provenance: .interpretation, confidence: .medium),
            decisionIds: ["index-on-publish"], poleAWeight: 0.75
        )

        let flow = FlowNode(
            id: "publish-index-flow", title: "Publish \u{2192} Reindex",
            steps: [
                FlowStep(id: "step-receive", index: 0, title: "receive page edit", componentId: "page-publishing", changeKind: .unchanged),
                FlowStep(id: "step-store", index: 1, title: "persist page revision", componentId: "page-publishing", changeKind: .unchanged),
                FlowStep(id: "step-enqueue", index: 2, title: "enqueue index job", componentId: "index-queue",
                         externalCalls: ["IndexQueue.enqueue()"], changeKind: .new, isAsyncBoundaryAfter: true),
                FlowStep(id: "step-evaluate", index: 3, title: "call search reindex()", componentId: "search-service",
                         externalCalls: ["SearchServiceClient.reindex()"], changeKind: .changed,
                         caution: "No timeout set on the synchronous search call before this PR queued it."),
                FlowStep(id: "step-update", index: 4, title: "update page search state", componentId: "page-publishing", changeKind: .changed)
            ],
            entryPointId: "publish-endpoint",
            storySteps: [
                Statement(text: "Publish page", provenance: .fact),
                Statement(text: "Save revision", provenance: .fact),
                Statement(text: "Rebuild search entry", provenance: .interpretation, confidence: .high),
                Statement(text: "Update search state", provenance: .fact),
                Statement(text: "Queue indexing", provenance: .fact)
            ]
        )

        let entryPoint = EntryPointNode(
            id: "publish-endpoint", title: "PUT /pages/{slug}", kind: "REST endpoint",
            changeKind: .changed, refs: [CodeRef(path: "src/main/java/rest/PageResource.java", startLine: 55, endLine: 80)],
            flowId: "publish-index-flow", triggersLabel: "Search reindex"
        )

        let edges: [ArchitectureEdge] = [
            ArchitectureEdge(id: "publish-queues", fromId: "page-publishing", toId: "index-queue",
                             label: "queues reindex", flow: .async, change: .new, onCriticalPath: true,
                             decisionIds: ["index-on-publish"], note: "NEW: enqueued on the publish path"),
            ArchitectureEdge(id: "queue-indexes", fromId: "index-queue", toId: "search-service",
                             label: "calls reindex()", flow: .sync, change: .changed, isTrustBoundary: true),
            ArchitectureEdge(id: "publish-updates-search", fromId: "page-publishing", toId: "search-service",
                             label: "updates search state", flow: .sync, change: .existing, isTrustBoundary: true)
        ]
        let boundaries: [SystemBoundary] = [
            SystemBoundary(id: "docs-app", label: "Docs Site", kind: .application,
                           componentIds: ["page-publishing", "index-queue", "page-publisher-impl"]),
            SystemBoundary(id: "search-ext", label: "Search Service", kind: .external, componentIds: ["search-service"])
        ]

        let behaviorChange = BehaviorChange(
            id: "immediate-reindex",
            title: "Publishing now triggers reindexing immediately",
            before: [
                BehaviorStage(label: "Publish page", tag: .both),
                BehaviorStage(label: "Save revision", tag: .both),
                BehaviorStage(label: "Wait for nightly rebuild", tag: .beforeOnly),
                BehaviorStage(label: "Rebuild search entry", tag: .beforeOnly, componentIds: ["page-publishing"]),
                BehaviorStage(label: "Update search state", tag: .both)
            ],
            after: [
                BehaviorStage(label: "Publish page", tag: .both),
                BehaviorStage(label: "Save revision", tag: .both),
                BehaviorStage(label: "Queue indexing", tag: .afterOnly, componentIds: ["index-queue"], flowId: "publish-index-flow"),
                BehaviorStage(label: "Rebuild search entry", tag: .afterOnly, componentIds: ["page-publishing"]),
                BehaviorStage(label: "Update search state", tag: .both)
            ],
            why: Statement(text: "Stale search results after publishing were the top support complaint.", provenance: .claim, source: "PR description"),
            consequence: Statement(text: "Every publish now enqueues an index job instead of waiting up to 24 hours.", provenance: .interpretation, confidence: .high),
            humanQuestion: Statement(text: "Can the index queue absorb a burst of publishes without falling behind?", provenance: .interpretation, confidence: .medium)
        )

        let pr = PRSummary(
            repo: "acme/docs-site", number: 4821, title: "Reindex pages immediately on publish",
            author: "jane-dev", state: "OPEN", branch: "feature/immediate-reindex", baseBranch: "main",
            headSha: "a1b2c3d", baseSha: "9f8e7d6",
            intent: Statement(text: "Make search results reflect newly published pages without waiting for the nightly rebuild.", provenance: .claim, source: "PR description"),
            filesChanged: 6, additions: 210, deletions: 42,
            changeMap: [
                ChangeMapEntry(name: "Page Publishing", filesChanged: 3),
                ChangeMapEntry(name: "Index Queue", filesChanged: 2),
                ChangeMapEntry(name: "Search Service", filesChanged: 1)
            ],
            architectureImpact: Statement(text: "Introduces an async index queue between publishing and search; new trust boundary at the Search Service call.", provenance: .interpretation, confidence: .high),
            needsJudgment: [Statement(text: "No timeout set on the search reindex() call once it's queued.", provenance: .interpretation, confidence: .medium)],
            uncertainties: [Statement(text: "Could not determine the index queue's configured concurrency limit.", provenance: .interpretation, confidence: .low)],
            problemToBeSolved: Statement(text: "Newly published pages could be missing from search for up to a day.", provenance: .claim, source: "PR description"),
            howItWasSolved: Statement(text: "The publish handler now enqueues an immediate reindex instead of relying on the nightly rebuild.", provenance: .interpretation, confidence: .high)
        )

        return PRGraph(
            pr: pr,
            components: [publishing, searchService, indexQueue, publisherImpl],
            decisions: [decision],
            tradeoffs: [tradeoff],
            flows: [flow],
            entryPoints: [entryPoint],
            questions: [],
            behaviorChanges: [behaviorChange],
            architectureEdges: edges,
            boundaries: boundaries
        )
    }()
}
