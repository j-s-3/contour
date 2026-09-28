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

    // MARK: - reviewButtonPhase

    /// Each verdict's button only reacts to *its own* verdict being in flight or submitted —
    /// the other verdict's button stays idle even while a review is happening.
    @Test func reviewButtonPhaseTracksOnlyItsOwnVerdict() {
        #expect(ContentView.reviewButtonPhase(for: .submitting(.approve), verdict: .approve) == .submitting)
        #expect(ContentView.reviewButtonPhase(for: .submitting(.approve), verdict: .requestChanges) == .idle)
        #expect(ContentView.reviewButtonPhase(for: .submitted(.requestChanges), verdict: .requestChanges) == .submitted)
        #expect(ContentView.reviewButtonPhase(for: .submitted(.requestChanges), verdict: .approve) == .idle)
    }

    @Test func reviewButtonPhaseIsIdleForFailedOrIdleState() {
        #expect(ContentView.reviewButtonPhase(for: .idle, verdict: .approve) == .idle)
        #expect(ContentView.reviewButtonPhase(for: .failed(.approve, "boom"), verdict: .approve) == .idle)
    }

    // MARK: - sectionBranch / sectionOverlay

    /// Content on screen always wins the branch, whatever the stage's status says — a
    /// `stale` slice from a previous revision, or a stage that's still `running`, is shown
    /// with its overlay rather than a failed/pending placeholder.
    @Test func sectionBranchPrefersContentWheneverThereIsAny() {
        #expect(ContentView.sectionBranch(hasContent: true, status: .pending) == .content(showsOverlay: true))
        #expect(ContentView.sectionBranch(hasContent: true, status: .stale) == .content(showsOverlay: true))
        #expect(ContentView.sectionBranch(hasContent: true, status: .failed("x")) == .content(showsOverlay: true))
    }

    /// A `done` stage with nothing to show (e.g. zero decisions found) still renders the
    /// lens's own `content()`, just without a progress/stopped pill floating over it.
    @Test func sectionBranchShowsContentWithoutOverlayWhenDoneButEmpty() {
        #expect(ContentView.sectionBranch(hasContent: false, status: .done) == .content(showsOverlay: false))
    }

    @Test func sectionBranchFallsBackToFailedStoppedOrPendingWithNoContent() {
        #expect(ContentView.sectionBranch(hasContent: false, status: .failed("network error"))
                == .failed("network error"))
        #expect(ContentView.sectionBranch(hasContent: false, status: .stopped) == .stopped)
        #expect(ContentView.sectionBranch(hasContent: false, status: .pending) == .pending)
        #expect(ContentView.sectionBranch(hasContent: false, status: .running(detail: nil)) == .pending)
    }

    @Test func sectionOverlayShowsProgressOnlyWhileRunningWithText() {
        #expect(ContentView.sectionOverlay(status: .running(detail: nil), progress: "3 found so far")
                == .progress("3 found so far"))
        #expect(ContentView.sectionOverlay(status: .running(detail: nil), progress: nil) == .none)
        #expect(ContentView.sectionOverlay(status: .done, progress: "3 found so far") == .none)
    }

    @Test func sectionOverlayShowsStoppedRegardlessOfProgressText() {
        #expect(ContentView.sectionOverlay(status: .stopped, progress: "3 found so far") == .stopped)
        #expect(ContentView.sectionOverlay(status: .stopped, progress: nil) == .stopped)
    }

    // MARK: - sidebar row derivation

    /// The Flows row only grows a count once the stage is `done`; while running or failed it
    /// stays a bare label rather than showing a stale or zero count.
    @Test func flowsRowTitleAddsTheCountOnlyOnceDone() {
        #expect(ContentView.flowsRowTitle(status: .done, count: 3) == "Flows (3)")
        #expect(ContentView.flowsRowTitle(status: .done, count: 0) == "Flows (0)")
        #expect(ContentView.flowsRowTitle(status: .running(detail: nil), count: 3) == "Flows")
        #expect(ContentView.flowsRowTitle(status: .pending, count: 3) == "Flows")
    }

    /// The Decisions row's checkmark requires both stages done *and* every consideration
    /// actually reviewed; a PR with zero considerations never counts as fully reviewed, and
    /// a single unreviewed consideration blocks it even once both stages finish.
    @Test func decisionsRowIsFullyReviewedRequiresEverythingDoneAndReviewed() {
        #expect(ContentView.decisionsRowIsFullyReviewed(
            decisionsStatus: .done, judgmentStatus: .done, progress: (reviewed: 2, total: 2)))
        #expect(!ContentView.decisionsRowIsFullyReviewed(
            decisionsStatus: .done, judgmentStatus: .done, progress: (reviewed: 0, total: 0)))
        #expect(!ContentView.decisionsRowIsFullyReviewed(
            decisionsStatus: .done, judgmentStatus: .done, progress: (reviewed: 1, total: 2)))
        #expect(!ContentView.decisionsRowIsFullyReviewed(
            decisionsStatus: .running(detail: nil), judgmentStatus: .done, progress: (reviewed: 2, total: 2)))
        #expect(!ContentView.decisionsRowIsFullyReviewed(
            decisionsStatus: .done, judgmentStatus: .pending, progress: (reviewed: 2, total: 2)))
    }

    @Test func diffRowStatusReflectsWhetherTheDiffHasArrived() {
        #expect(ContentView.diffRowStatus(diffText: nil) == .pending)
        #expect(ContentView.diffRowStatus(diffText: "diff --git a b") == .done)
    }
}
