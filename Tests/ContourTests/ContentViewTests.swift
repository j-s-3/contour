import Testing
@testable import Contour

/// `ContentView` is the `NavigationSplitView` shell (§4.1); per CLAUDE.md's guidance, its
/// navigation-stack derivation and lens/tab selection logic is pulled out to static
/// functions taking `store.phase`/`store.current`/`store.review` explicitly, so it's
/// testable without a live view. The `body` itself — the split view, toolbar, sidebar rows —
/// stays untested; no UI-testing infrastructure in this suite to host it.
struct ContentViewTests {

    // MARK: - screen

    @Test func screenMapsEveryPhaseToItsOwnNumber() {
        #expect(ContentView.screen(for: .idle) == 0)
        #expect(ContentView.screen(for: .opening) == 1)
        #expect(ContentView.screen(for: .failed("boom")) == 2)
        #expect(ContentView.screen(for: .review) == 3)
    }

    // MARK: - sidebarSubtitle

    @Test func sidebarSubtitleIsNilWithoutASection() {
        #expect(ContentView.sidebarSubtitle(.done, nil) == nil)
        #expect(ContentView.sidebarSubtitle(.pending, nil) == nil)
    }

    @Test func sidebarSubtitlePrefersItsOwnDetailOverTheSectionsWorkingLabel() {
        #expect(ContentView.sidebarSubtitle(.running(detail: "2 found so far"), .decisions) == "2 found so far")
    }

    @Test func sidebarSubtitleFallsBackToTheWorkingLabelWithNoDetail() {
        #expect(ContentView.sidebarSubtitle(.running(detail: nil), .decisions) == ReviewSection.decisions.workingLabel)
    }

    @Test func sidebarSubtitleForEveryRemainingStatus() {
        #expect(ContentView.sidebarSubtitle(.failed("x"), .architecture) == "Couldn't be generated")
        #expect(ContentView.sidebarSubtitle(.stale, .architecture) == "Previous revision")
        #expect(ContentView.sidebarSubtitle(.stopped, .architecture) == "Stopped")
        #expect(ContentView.sidebarSubtitle(.pending, .architecture) == "Waiting…")
        #expect(ContentView.sidebarSubtitle(.done, .architecture) == nil)
    }

    // MARK: - isActive

    @Test func isActiveMatchesTheSameLensDirectly() {
        #expect(ContentView.isActive(.summary, given: .summary))
        #expect(ContentView.isActive(.architecture, given: .architecture))
        #expect(ContentView.isActive(.diff, given: .diffLocation(CodeRef(path: "a.swift", startLine: 1, endLine: 1))))
    }

    @Test func isActiveMatchesADetailScreenToItsParentLens() {
        #expect(ContentView.isActive(.architecture, given: .componentDetail("c")))
        #expect(ContentView.isActive(.architecture, given: .edgeDetail("e")))
        #expect(ContentView.isActive(.decisions, given: .decisionDetail("d")))
        #expect(ContentView.isActive(.decisions, given: .consideration("q")))
        #expect(ContentView.isActive(.flows, given: .flowDetail("f")))
        #expect(ContentView.isActive(.flows, given: .flowNodeDetail(flowId: "f", nodeId: "n")))
    }

    @Test func isActiveIsFalseForUnrelatedLenses() {
        #expect(!ContentView.isActive(.decisions, given: .architecture))
        #expect(!ContentView.isActive(.architecture, given: .flowDetail("f")))
    }

    // MARK: - architectureFocus / flowsFocus / diffFocus

    @Test func architectureFocusNamesTheSelectedNodeOrEdge() {
        #expect(ContentView.architectureFocus(for: .componentDetail("c")) == .node("c"))
        #expect(ContentView.architectureFocus(for: .edgeDetail("e")) == .edge("e"))
        #expect(ContentView.architectureFocus(for: .summary) == nil)
    }

    @Test func flowsFocusNamesTheSelectedFlowAndStage() {
        #expect(ContentView.flowsFocus(for: .flowDetail("f")) == .init(flowId: "f"))
        #expect(ContentView.flowsFocus(for: .flowNodeDetail(flowId: "f", nodeId: "n")) == .init(flowId: "f", nodeId: "n"))
        #expect(ContentView.flowsFocus(for: .summary) == nil)
    }

    @Test func diffFocusNamesTheCodeReferenceOnly() {
        let ref = CodeRef(path: "a.swift", startLine: 5, endLine: 8)
        #expect(ContentView.diffFocus(for: .diffLocation(ref)) == ref)
        #expect(ContentView.diffFocus(for: .diff) == nil)
    }

    // MARK: - decisionsFocus

    @Test func decisionsFocusResolvesADecisionDetailDirectly() {
        let graph = ContourSampleData.publishTriggeredReindex
        #expect(ContentView.decisionsFocus(for: .decisionDetail("index-on-publish"), graph: graph)
                == .init(decisionId: "index-on-publish"))
    }

    /// A consideration carries the Overview question that brought the reviewer here, resolved
    /// back to whichever decision it belongs to.
    @Test func decisionsFocusResolvesAConsiderationToItsOwningDecision() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = [Consideration(id: "q1", question: "Why?", detail: "d", relatedIds: ["d1"])]
        graph.decisions = [DecisionNode(id: "d1", title: "D1", decision: Statement(text: "x", provenance: .fact), confidence: .high)]
        #expect(ContentView.decisionsFocus(for: .consideration("q1"), graph: graph)
                == .init(decisionId: "d1", considerationId: "q1"))
    }

    @Test func decisionsFocusIsNilForAnUnknownConsideration() {
        let graph = ContourSampleData.publishTriggeredReindex
        #expect(ContentView.decisionsFocus(for: .consideration("does-not-exist"), graph: graph) == nil)
    }

    @Test func decisionsFocusIsNilForUnrelatedTargets() {
        let graph = ContourSampleData.publishTriggeredReindex
        #expect(ContentView.decisionsFocus(for: .summary, graph: graph) == nil)
    }

    // MARK: - reviewFailureTitle

    @Test func reviewFailureTitleNamesRequestChangesSpecifically() {
        #expect(ContentView.reviewFailureTitle(for: .failed(.requestChanges, "network error")) == "Couldn't request changes")
    }

    @Test func reviewFailureTitleFallsBackToApproveForEverythingElse() {
        #expect(ContentView.reviewFailureTitle(for: .failed(.approve, "network error")) == "Couldn't approve the pull request")
        #expect(ContentView.reviewFailureTitle(for: .idle) == "Couldn't approve the pull request")
    }
}
