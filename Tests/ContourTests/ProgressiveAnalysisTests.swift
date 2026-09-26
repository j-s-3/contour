import Foundation
import Testing
@testable import Contour

/// Progressive opening: the pieces that let the review appear before the analysis is done
/// and fill in safely while the reviewer works.
struct ProgressiveAnalysisTests {

    // MARK: - Streaming

    private let streamed = #"""
    {"decisions": [
      {"id": "a", "title": "Uses { braces } and \"quotes\" in prose", "n": [1, {"x": "]"}]},
      {"id": "b", "title": "Ünïcödé — ok"},
      {"id": "c", "title": "last"}
    ], "after": [{"id": "not-ours"}]}
    """#

    @Test func extractorYieldsEachElementOnceInOrderHoweverTheTextIsSplit() {
        for chunkSize in [1, 2, 7, 64, streamed.utf8.count] {
            var extractor = StreamingArrayExtractor(key: "decisions")
            var ids: [String] = []
            var chunk = ""
            for ch in streamed {
                chunk.append(ch)
                if chunk.utf8.count >= chunkSize {
                    ids += extractor.consume(chunk).compactMap { $0["id"] as? String }
                    chunk = ""
                }
            }
            ids += extractor.consume(chunk).compactMap { $0["id"] as? String }
            #expect(ids == ["a", "b", "c"], "chunk size \(chunkSize)")
        }
    }

    @Test func extractorIgnoresTextBeforeTheKeyAndAfterTheArray() {
        var extractor = StreamingArrayExtractor(key: "flows")
        #expect(extractor.consume(#"Let me look. {"entryPoints": [{"id": "e"}], "#).isEmpty)
        let found = extractor.consume(#""flows": [{"id": "f1"}]} {"id": "later"}"#)
        #expect(found.compactMap { $0["id"] as? String } == ["f1"])
        #expect(extractor.consume(#", {"id": "f2"}]"#).isEmpty)
    }

    // MARK: - Local linking

    private func fixtures() throws -> (arch: StageDecoding.ArchitectureResult, decisions: [DecisionNode], flows: StageDecoding.FlowsResult) {
        (try StageDecoding.decode(StageDecoding.ArchitectureResult.self, from: MockAnalysisFixtures.response(for: .architecture)),
         try StageDecoding.decode(StageDecoding.DecisionsResult.self, from: MockAnalysisFixtures.response(for: .decisions)).decisions,
         try StageDecoding.decode(StageDecoding.FlowsResult.self, from: MockAnalysisFixtures.response(for: .flows)))
    }

    /// The captured decisions were linked by the model when it was handed the component
    /// list. Linking the same decisions from their code refs alone must land on parts the
    /// model also chose — never on a part it didn't.
    @Test func linkingByCodeRefsAgreesWithTheModelsOwnLinks() throws {
        let (arch, decisions, _) = try fixtures()
        let unlinked = decisions.map { d -> DecisionNode in var d = d; d.componentIds = []; return d }
        let linked = GraphLinker.linkDecisions(unlinked, to: arch.components)
        for (original, derived) in zip(decisions, linked) {
            #expect(!derived.componentIds.isEmpty, "\(original.id) got no component")
            let systemParts = Set(arch.components.filter { $0.level != .implementation }.map(\.id))
            #expect(Set(derived.componentIds).isSubset(of: systemParts))
        }
        // Where the model named exactly one part, the derived links include it.
        let agreeing = zip(decisions, linked).filter { !Set($0.componentIds).isDisjoint(with: $1.componentIds) }
        #expect(agreeing.count >= decisions.count - 1)
    }

    @Test func linkingKeepsLinksTheModelAlreadyMade() throws {
        let (arch, decisions, _) = try fixtures()
        #expect(GraphLinker.linkDecisions(decisions, to: arch.components).map(\.componentIds) == decisions.map(\.componentIds))
    }

    @Test func linkingPrefersTheMostSpecificPart() {
        let ref = CodeRef(path: "src/a.rs", startLine: 10, endLine: 20, blobSha: nil, side: .head)
        var parent = ComponentNode(id: "parent", title: "Parent", changeKind: .changed)
        parent.refs = [ref]
        var child = ComponentNode(id: "child", title: "Child", changeKind: .changed)
        child.refs = [ref]
        child.parentId = "parent"
        var decision = DecisionNode(id: "d", title: "d", decision: Statement(text: "d", provenance: .fact), confidence: .high)
        decision.refs = [CodeRef(path: "src/a.rs", startLine: 15, endLine: 16, blobSha: nil, side: .head)]
        #expect(GraphLinker.linkDecisions([decision], to: [parent, child]).first?.componentIds == ["child"])
    }

    @Test func pinningPutsEachDecisionOnTheOneStageRunningItsCode() {
        func ref(_ path: String, _ a: Int, _ b: Int) -> CodeRef { CodeRef(path: path, startLine: a, endLine: b, blobSha: nil, side: .head) }
        var flow = FlowNode(id: "f", title: "Open a file")
        flow.steps = [FlowStep(id: "s1", index: 0, title: "sample", refs: [ref("src/input.rs", 260, 290)])]
        flow.behavior = FlowBehavior(nodes: [
            FlowBehaviorNode(id: "open", label: "Open file", kind: .trigger, refs: [ref("src/input.rs", 200, 240)]),
            FlowBehaviorNode(id: "inspect", label: "Inspect sample", stepIds: ["s1"]),
            FlowBehaviorNode(id: "render", label: "Render", kind: .outcome, refs: [ref("src/printer.rs", 1, 50)]),
        ], edges: [])
        var sampled = DecisionNode(id: "sample-size", title: "t", decision: Statement(text: "d", provenance: .fact), confidence: .high)
        sampled.refs = [ref("src/input.rs", 270, 275)]
        var vague = DecisionNode(id: "vague", title: "t", decision: Statement(text: "d", provenance: .fact), confidence: .high)
        vague.refs = [ref("src/input.rs", 900, 910)]   // same file as two stages, overlapping neither

        let pinned = GraphLinker.pinDecisions([sampled, vague], to: [flow])[0].behavior!.nodes
        #expect(pinned.first { $0.id == "inspect" }?.decisionIds == ["sample-size"])
        #expect(pinned.allSatisfy { !$0.decisionIds.contains("vague") }, "a same-file tie is not a stage")
    }

    // MARK: - Assembly

    private func context(head: String = "head1") -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/shop/pull/7", owner: "acme", repo: "shop", number: 7,
            title: "Detect binary content", body: "", author: "someone", state: "OPEN", headRefName: "fix",
            baseRefName: "main", headSha: head, baseSha: "base1", isCrossRepository: false,
            headCloneURL: "https://github.com/acme/shop.git", additions: 3, deletions: 1, changedFiles: 2,
            files: ["a.rs"], commits: [], comments: [], reviews: [], diff: "diff"
        )
    }

    @Test func shellHasEverythingTheReviewNeedsToOpenAndNoAnalysis() {
        let shell = PRGraph.shell(from: context())
        #expect(shell.pr.title == "Detect binary content")
        #expect(shell.pr.repo == "acme/shop")
        #expect(shell.pr.intent.provenance == .claim)
        #expect(shell.decisions.isEmpty && shell.components.isEmpty && shell.behaviorChanges.isEmpty)
    }

    /// Slices land in any order and each stage owns its own fields: applying or clearing
    /// one never disturbs another.
    @Test func slicesAreIndependent() throws {
        let (arch, decisions, flows) = try fixtures()
        let behavior = try StageDecoding.decode(StageDecoding.BehaviorChangeResult.self, from: MockAnalysisFixtures.response(for: .behaviorChange))
        let understanding = try StageDecoding.decode(StageDecoding.UnderstandingResult.self, from: MockAnalysisFixtures.response(for: .understanding))
        let judgment = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: MockAnalysisFixtures.response(for: .judgment))
        let results: [StageResult] = [.judgment(judgment), .flows(flows), .decisions(decisions),
                                      .understanding(understanding), .architecture(arch), .behaviorChange(behavior)]

        var inOrder = PRGraph.shell(from: context())
        for r in results.reversed() { inOrder.apply(r) }
        var reversed = PRGraph.shell(from: context())
        for r in results { reversed.apply(r) }
        #expect(inOrder == reversed)

        var cleared = inOrder
        cleared.clear(.architecture)
        #expect(cleared.components.isEmpty && cleared.architecture == nil)
        #expect(cleared.decisions == inOrder.decisions)
        #expect(cleared.flows == inOrder.flows)
        #expect(cleared.behaviorChanges == inOrder.behaviorChanges)
        #expect(cleared.pr.howItWasSolved == inOrder.pr.howItWasSolved)

        cleared.clear(.understanding)
        #expect(cleared.pr.howItWasSolved == nil)
        #expect(cleared.pr.intent.text == "Detect binary content")
    }

    @Test func reviewerMarksSurviveANewSnapshot() throws {
        let (_, decisions, _) = try fixtures()
        var working = PRGraph.shell(from: context())
        working.decisions = Array(decisions.prefix(1))
        working.decisions[0].reviewerState = .accepted
        working.decisions[0].reviewerNote = "fine"

        var next = PRGraph.shell(from: context())
        next.decisions = decisions   // the stage finished: more decisions, marks unknown
        let merged = next.carryingReviewerState(from: working)
        #expect(merged.decisions[0].reviewerState == .accepted)
        #expect(merged.decisions[0].reviewerNote == "fine")
        #expect(merged.decisions.dropFirst().allSatisfy { $0.reviewerState == .unreviewed })
    }

    // MARK: - State

    @Test func aSectionIsAsFarAlongAsItsLeastFinishedStageAndFailuresShow() {
        var state = AnalysisState()
        state.stages[.behaviorChange] = .done
        state.stages[.understanding] = .running(detail: nil)
        #expect(state.sectionStatus(.whatChanged).isRunning)
        state.stages[.understanding] = .done
        #expect(state.sectionStatus(.whatChanged) == .done)
        state.stages[.behaviorChange] = .failed("boom")
        #expect(state.sectionStatus(.whatChanged).failure == "boom")
        #expect(state.failedSections == [.whatChanged])
        #expect(state.remainingCount == 4)
    }

    /// A failed section tells the reviewer which part failed and why in their terms — never
    /// the model's raw output or a CLI's stderr, which stay in the technical log.
    @Test func failureMessagesNameTheSectionAndNeverQuoteRawOutput() {
        let raw = #"{"components": [{"id": "parser", "name": "Pars"#
        let notJSON = AnalysisServiceError.notJSON(harness: "claude", raw: raw)
        #expect(PipelineStage.architecture.failureMessage(for: notJSON)
                == "Couldn't map the architecture. The model's answer wasn't readable.")
        #expect(notJSON.localizedDescription.contains(raw), "the log keeps the raw response")

        let stderr = "fatal: rate limited, retry after 30s"
        let processFailed = AnalysisServiceError.processFailed(
            harness: "claude", ProcessError(command: "claude -p", exitCode: 1, stderr: stderr))
        let decoding = StageDecodingError(stageLabel: "Tracing flows", underlying: CancellationError(), rawJSON: raw)
        for (stage, error) in [(PipelineStage.decisions, processFailed as Error), (.flows, decoding),
                               (.judgment, AnalysisServiceError.emptyResponse(harness: "claude"))] {
            let message = stage.failureMessage(for: error)
            #expect(message.hasPrefix(stage.failureHeadline + ". "))
            #expect(!message.contains(stderr) && !message.contains(raw) && !message.contains("{"))
        }
        #expect(!PipelineStage.flows.checkoutFailureMessage.contains("fatal"))
    }

    // MARK: - Cache

    private func tempCache() -> AnalysisCache {
        AnalysisCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("contour-cache-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func aPartialAnalysisRemembersWhichStagesItHolds() {
        let cache = tempCache()
        let ctx = context()
        cache.save(owner: "acme", repo: "shop", number: 7, headSha: ctx.headSha, baseSha: ctx.baseSha, pipelineVersion: 1,
                   graph: .shell(from: ctx), diff: "d", completedStages: [.decisions, .behaviorChange])
        let entry = cache.load(owner: "acme", repo: "shop", number: 7, headSha: ctx.headSha, baseSha: ctx.baseSha, pipelineVersion: 1)
        #expect(entry?.completedStages == [.decisions, .behaviorChange])
    }

    @Test func latestRevisionFindsTheNewestOtherHeadOfTheSamePR() throws {
        let cache = tempCache()
        for (head, pause) in [("old", 0.0), ("newer", 0.05)] {
            Thread.sleep(forTimeInterval: pause + 0.01)
            let ctx = context(head: head)
            cache.save(owner: "acme", repo: "shop", number: 7, headSha: head, baseSha: ctx.baseSha, pipelineVersion: 1,
                       graph: .shell(from: ctx), diff: "d", completedStages: [.decisions])
        }
        let ctx = context(head: "current")
        cache.save(owner: "acme", repo: "shop", number: 7, headSha: "current", baseSha: ctx.baseSha, pipelineVersion: 1,
                   graph: .shell(from: ctx), diff: "d", completedStages: [.decisions])

        let previous = cache.latestRevision(owner: "acme", repo: "shop", number: 7, excludingHead: "current", pipelineVersion: 1)
        #expect(previous?.graph.pr.headSha == "newer")
        #expect(cache.latestRevision(owner: "acme", repo: "shop", number: 8, excludingHead: "current", pipelineVersion: 1) == nil)
        #expect(cache.latestRevision(owner: "acme", repo: "shop", number: 7, excludingHead: "current", pipelineVersion: 2) == nil)
    }

    // MARK: - Metrics

    @Test func milestonesAreDerivedFromWhatIsOnScreenAndRecordedOnce() {
        let start = Date(timeIntervalSince1970: 1000)
        var metrics = AnalysisMetrics(pr: "x", startedAt: start)
        var state = AnalysisState()
        let shell = PRGraph.shell(from: context())

        metrics.update(state: state, graph: shell, diffAvailable: true, at: start.addingTimeInterval(2))
        #expect(metrics.elapsed(.prShell) == 2)
        #expect(metrics.elapsed(.rawDiff) == 2)
        #expect(metrics.elapsed(.whatChanged) == nil)

        state.stages[.understanding] = .done
        metrics.update(state: state, graph: shell, diffAvailable: true, at: start.addingTimeInterval(5))
        #expect(metrics.elapsed(.whatChanged) == 5)
        #expect(metrics.elapsed(.usefulOverview) == nil)

        state.stages[.behaviorChange] = .done
        metrics.update(state: state, graph: shell, diffAvailable: true, at: start.addingTimeInterval(9))
        #expect(metrics.elapsed(.beforeAfter) == 9)
        #expect(metrics.elapsed(.usefulOverview) == 9)
        #expect(metrics.elapsed(.whatChanged) == 5, "first time only")
    }
}
