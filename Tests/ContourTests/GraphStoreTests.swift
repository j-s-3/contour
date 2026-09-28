import Testing
import Foundation
@testable import Contour

/// `GraphStore.swift` was at 14.00% coverage. `graph`/`checkout`/`diffText`/`analysis`/
/// `phase` are all `private(set)`, and the only production path that populates them is
/// `load()`, which needs a real harness, git checkout and GitHub network call — none of
/// which this suite shells out to or fakes (same category of risk as not faking `pi`/
/// `claude` on `PATH` elsewhere). `handle(_:)` was made `internal` instead of `private` so
/// these can drive the same state transitions the real pipeline drives, with synthetic
/// `PipelineEvent`s, exercising the pure state-machine logic without any of that.
///
/// `load()`, `submitReview`, `retry`, `stopAnalysis`, `ask`/`send` (contextual chat), and
/// `openOnGitHub`/`copyReviewSummary` (AppKit/pasteboard) are left uncovered for the same
/// reason.
struct GraphStoreTests {

    private var sampleGraph: PRGraph { ContourSampleData.publishTriggeredReindex }

    // MARK: - handle(_:) state transitions

    @Test @MainActor func logEventsAppendToTheProgressLog() {
        let store = GraphStore()
        store.handle(.log(PipelineProgressEntry(stage: "Fetch", detail: "started")))
        store.handle(.log(PipelineProgressEntry(stage: "Fetch", detail: "done")))
        #expect(store.progressLog.count == 2)
        #expect(store.progressLog.last?.detail == "done")
    }

    @Test @MainActor func statusEventsRecordPerStageStatus() {
        let store = GraphStore()
        store.handle(.status(.architecture, .running(detail: "2 components found")))
        #expect(store.analysis.status(.architecture) == .running(detail: "2 components found"))
    }

    /// A stage that reopens after the analysis had already finished (a retry) must clear
    /// `isComplete`, or the UI would keep showing the old "done" state while it reruns.
    @Test @MainActor func aRetriedAnalysisStageReopensACompletedAnalysis() {
        let store = GraphStore()
        store.handle(.complete)
        #expect(store.analysis.isComplete)
        store.handle(.status(.architecture, .running(detail: nil)))
        #expect(!store.analysis.isComplete)
    }

    /// A non-analysis stage (fetch/checkout/cache/ticket) running again must not reopen
    /// the analysis — only the six analysis stages count.
    @Test @MainActor func aNonAnalysisStageRunningAgainDoesNotReopenTheAnalysis() {
        let store = GraphStore()
        store.handle(.complete)
        store.handle(.status(.checkingOut, .running(detail: nil)))
        #expect(store.analysis.isComplete)
    }

    @Test @MainActor func graphEventSetsTheGraphButOnlyMovesFromOpeningToReview() {
        let store = GraphStore()
        #expect(store.phase == .idle)
        store.handle(.graph(sampleGraph))
        #expect(store.graph?.pr.number == sampleGraph.pr.number)
        #expect(store.phase == .idle, "the phase only becomes .review when it was .opening")
    }

    @Test @MainActor func graphEventCarriesReviewerStateFromThePreviousGraph() {
        let store = GraphStore()
        store.handle(.graph(sampleGraph))
        store.setReviewerState(.accepted, forDecision: "index-on-publish")
        #expect(store.graph?.decisions.first(where: { $0.id == "index-on-publish" })?.reviewerState == .accepted)

        // A later snapshot of the same PR (e.g. a retried stage) must not lose that mark.
        store.handle(.graph(sampleGraph))
        #expect(store.graph?.decisions.first(where: { $0.id == "index-on-publish" })?.reviewerState == .accepted)
    }

    @Test @MainActor func diffEventSetsBothTheRawTextAndTheParsedFiles() {
        let store = GraphStore()
        let diff = "diff --git a/x.swift b/x.swift\n--- a/x.swift\n+++ b/x.swift\n@@ -1 +1 @@\n-old\n+new\n"
        store.handle(.diff(diff))
        #expect(store.diffText == diff)
        #expect(!store.diffFiles.isEmpty)
    }

    @Test @MainActor func checkoutEventSetsTheCheckout() {
        let store = GraphStore()
        let checkout = RepoCheckout(rootDir: URL(fileURLWithPath: "/tmp/checkout"), headSha: "h", baseSha: "b", symbolIndexPath: nil)
        store.handle(.checkout(checkout))
        #expect(store.checkout?.headSha == "h")
    }

    @Test @MainActor func revalidatingEventRecordsTheHeadItsCarryingOver() {
        let store = GraphStore()
        store.handle(.revalidating(fromHead: "oldsha"))
        #expect(store.analysis.revalidatingFrom == "oldsha")
    }

    @Test @MainActor func fromCacheEventMarksTheAnalysisAsFromCache() {
        let store = GraphStore()
        store.handle(.fromCache)
        #expect(store.analysis.fromCache)
    }

    @Test @MainActor func completeEventMarksTheAnalysisComplete() {
        let store = GraphStore()
        #expect(!store.analysis.isComplete)
        store.handle(.complete)
        #expect(store.analysis.isComplete)
    }

    @Test @MainActor func fatalEventWithNoGraphFailsTheWholeSession() {
        let store = GraphStore()
        store.handle(.fatal("network unreachable"))
        #expect(store.phase == .failed("network unreachable"))
    }

    /// A fatal error once the PR shell is on screen keeps that shell up and degrades every
    /// unfinished analysis section instead of blanking the window.
    @Test @MainActor func fatalEventWithAGraphKeepsTheShellAndDegradesUnfinishedStages() {
        let store = GraphStore()
        store.handle(.graph(sampleGraph))
        store.handle(.status(.behaviorChange, .done))

        store.handle(.fatal("checkout broke"))

        #expect(store.graph != nil, "the PR shell stays on screen")
        #expect(store.progressLog.last?.detail == "failed: checkout broke")
        #expect(store.analysis.status(.behaviorChange) == .done, "an already-done stage is untouched")
        #expect(store.analysis.status(.architecture).failure != nil, "an unfinished stage is degraded to failed")
        #expect(store.analysis.isComplete)
    }

    // MARK: - Navigation stack

    @Test func aFreshStoreStartsOnSummaryWithNoHistory() {
        let store = GraphStore()
        #expect(store.current == .summary)
        #expect(!store.canGoBack)
        #expect(!store.canGoForward)
    }

    @Test func navigatingPushesOntoThePathAndClearsForwardHistory() {
        let store = GraphStore()
        store.navigate(to: .architecture)
        #expect(store.current == .architecture)
        #expect(store.canGoBack)
        #expect(!store.canGoForward)
    }

    @Test func navigatingToTheCurrentTargetIsANoOp() {
        let store = GraphStore()
        store.navigate(to: .architecture)
        let pathCountBefore = store.path.count
        store.navigate(to: .architecture)
        #expect(store.path.count == pathCountBefore)
    }

    @Test func goBackAndGoForwardRestoreThePriorTarget() {
        let store = GraphStore()
        store.navigate(to: .architecture)
        store.navigate(to: .decisions)

        store.goBack()
        #expect(store.current == .architecture)
        #expect(store.canGoForward)

        store.goForward()
        #expect(store.current == .decisions)
        #expect(!store.canGoForward)
    }

    @Test func goBackAtTheRootOfHistoryIsANoOp() {
        let store = GraphStore()
        store.goBack()
        #expect(store.current == .summary)
        #expect(!store.canGoBack)
    }

    @Test func goForwardWithNothingAheadIsANoOp() {
        let store = GraphStore()
        store.goForward()
        #expect(store.current == .summary)
    }

    /// Pushing a new target after going back must clear the forward stack, like a browser:
    /// the abandoned "future" shouldn't come back once the reviewer has gone somewhere new.
    @Test func navigatingAfterGoingBackDiscardsTheAbandonedForwardHistory() {
        let store = GraphStore()
        store.navigate(to: .architecture)
        store.navigate(to: .decisions)
        store.goBack()
        #expect(store.canGoForward)

        store.navigate(to: .flows)
        #expect(!store.canGoForward)
    }

    // MARK: - NavigationTarget.showsDiagram

    @Test func onlyArchitectureAndFlowsRelatedTargetsShowADiagram() {
        let diagramTargets: [NavigationTarget] = [.architecture, .componentDetail("c"), .edgeDetail("e"), .flows, .flowDetail("f"), .flowNodeDetail(flowId: "f", nodeId: "n")]
        for target in diagramTargets {
            #expect(target.showsDiagram, "\(target) should show a diagram")
        }
        let nonDiagramTargets: [NavigationTarget] = [.summary, .decisions, .files, .diff, .decisionDetail("d"), .consideration("c")]
        for target in nonDiagramTargets {
            #expect(!target.showsDiagram, "\(target) should not show a diagram")
        }
    }

    // MARK: - subjectForCurrentLocation

    @Test func subjectDefaultsToPullRequestWithNoGraphAndNoSpecificLocation() {
        let store = GraphStore()
        #expect(store.subjectForCurrentLocation == .pullRequest)
    }

    @Test @MainActor func subjectDefaultsToTheDominantBehaviorChangeOnceAGraphIsLoaded() {
        let store = GraphStore()
        store.handle(.graph(sampleGraph))
        #expect(store.subjectForCurrentLocation == .behaviorChange(sampleGraph.dominantBehaviorChange!.id))
    }

    @Test func subjectForEachDetailTargetMatchesThatTargetsIdentifier() {
        let store = GraphStore()
        let ref = CodeRef(path: "a.swift", startLine: 1, endLine: 2)

        store.navigate(to: .componentDetail("comp"))
        #expect(store.subjectForCurrentLocation == .component("comp"))

        store.navigate(to: .edgeDetail("edge"))
        #expect(store.subjectForCurrentLocation == .relationship("edge"))

        store.navigate(to: .decisionDetail("dec"))
        #expect(store.subjectForCurrentLocation == .decision("dec"))

        store.navigate(to: .consideration("con"))
        #expect(store.subjectForCurrentLocation == .consideration("con"))

        store.navigate(to: .flowDetail("flow"))
        #expect(store.subjectForCurrentLocation == .flow("flow"))

        store.navigate(to: .flowNodeDetail(flowId: "flow", nodeId: "node"))
        #expect(store.subjectForCurrentLocation == .flowNode(flowId: "flow", nodeId: "node"))

        store.navigate(to: .evidence(ref))
        #expect(store.subjectForCurrentLocation == .codeRef(ref))

        store.navigate(to: .diffLocation(ref))
        #expect(store.subjectForCurrentLocation == .codeRef(ref))
    }

    @Test func aFocusedSubjectOverridesWhateverTheCurrentLocationImplies() {
        let store = GraphStore()
        store.navigate(to: .componentDetail("comp"))
        store.focusedSubject = .decision("something-else")
        #expect(store.subjectForCurrentLocation == .decision("something-else"))
    }

    // MARK: - Reviewer actions

    @Test @MainActor func setReviewerStateTogglesOffWhenSetToItsCurrentValue() {
        let store = GraphStore()
        store.handle(.graph(sampleGraph))
        let id = "index-on-publish"
        #expect(store.graph?.decisions.first(where: { $0.id == id })?.reviewerState == .unreviewed)

        store.setReviewerState(.accepted, forDecision: id)
        #expect(store.graph?.decisions.first(where: { $0.id == id })?.reviewerState == .accepted)

        store.setReviewerState(.accepted, forDecision: id)
        #expect(store.graph?.decisions.first(where: { $0.id == id })?.reviewerState == .unreviewed, "setting the same state again clears it")

        store.setReviewerState(.discuss, forDecision: id)
        #expect(store.graph?.decisions.first(where: { $0.id == id })?.reviewerState == .discuss)
    }

    @Test @MainActor func setReviewerStateWithNoGraphIsANoOp() {
        let store = GraphStore()
        store.setReviewerState(.accepted, forDecision: "index-on-publish")
        #expect(store.graph == nil)
    }

    @Test @MainActor func setToReviewMovesTheDecisionToOppositePlacementsForOppositeValues() {
        let store = GraphStore()
        store.handle(.graph(sampleGraph))
        let id = "index-on-publish"

        store.setToReview(true, forDecision: id)
        let placementWhenTrue = store.graph?.decisions.first(where: { $0.id == id })?.reviewerPlacement

        store.setToReview(false, forDecision: id)
        let placementWhenFalse = store.graph?.decisions.first(where: { $0.id == id })?.reviewerPlacement

        #expect(placementWhenTrue != placementWhenFalse)
    }

    @Test @MainActor func setReviewerNoteStoresTheNoteVerbatim() {
        let store = GraphStore()
        store.handle(.graph(sampleGraph))
        let id = "index-on-publish"
        store.setReviewerNote("Looks fine but check the retry path.", forDecision: id)
        #expect(store.graph?.decisions.first(where: { $0.id == id })?.reviewerNote == "Looks fine but check the retry path.")
    }

    @Test @MainActor func setReviewerNoteWithAnUnknownDecisionIdIsANoOp() {
        let store = GraphStore()
        store.handle(.graph(sampleGraph))
        store.setReviewerNote("note", forDecision: "does-not-exist")
        #expect(store.graph?.decisions.allSatisfy { $0.reviewerNote.isEmpty } == true)
    }

    // MARK: - Session lifecycle

    @Test @MainActor func closingEndsTheSessionAndReturnsToIdle() {
        let store = GraphStore()
        store.handle(.graph(sampleGraph))
        store.close()
        #expect(store.phase == .idle)
    }

    @Test @MainActor func dismissingAReviewFailureThatIsntFailedIsANoOp() {
        let store = GraphStore()
        #expect(store.review == .idle)
        store.dismissReviewFailure()
        #expect(store.review == .idle)
    }

    @Test @MainActor func stoppingAnalysisWithoutAPipelineIsNeverPossible() {
        let store = GraphStore()
        #expect(!store.canStopAnalysis, "no pipeline exists outside of load()")
    }
}
