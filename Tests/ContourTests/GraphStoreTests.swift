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
/// `load()` itself is still left uncovered for the same PATH/network reason (it resolves a
/// harness and, once it has one, spawns a `Task` that runs the real pipeline against the
/// network). But every guard in `submitReview`/`retry`/`stopAnalysis`/`ask`/`send` that
/// short-circuits *before* touching a pipeline, a harness or the network is reachable from a
/// store that never called `load()` — `pipeline`, `graph`, `checkout` and `lastPRURL` are all
/// `nil` in that state, which is exactly the branch every one of those guards takes first.
/// This second block of tests drives those guard-only paths, plus the navigation-adjacent
/// `hasOpenPR`/`pullRequestURL` computed properties and the contextual-chat entry points.
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

    /// `stopAnalysis()` guards on `canStopAnalysis` before touching `pipeline`; pins that
    /// calling it on a store that never `load()`ed is a silent no-op, not a crash on a nil
    /// pipeline.
    @Test @MainActor func stopAnalysisWithoutAPipelineIsANoOp() {
        let store = GraphStore()
        store.handle(.graph(sampleGraph))
        store.stopAnalysis()
        #expect(store.graph != nil, "the guard exits before anything about the store changes")
    }

    /// `retry(_:)` falls back to `reopen()` whenever there's no pipeline or checkout to retry
    /// a single stage against — true for every store that never `load()`ed — and `reopen()`
    /// with no `lastPRURL` on file falls further back to `close()`. Pins that whole chain
    /// rather than a crash or a stuck state.
    @Test @MainActor func retryWithoutAPipelineFallsBackToReopenAndThenToClose() {
        let store = GraphStore()
        store.handle(.graph(sampleGraph))
        store.retry(.architecture)
        #expect(store.phase == .idle, "no checkout/pipeline exists outside load(), so retry() reopens, which closes")
    }

    /// `reopen()` with no `lastPRURL` (true for any store that never `load()`ed) closes the
    /// session instead of trying to reload an empty URL.
    @Test @MainActor func reopenWithNoPriorPRJustCloses() {
        let store = GraphStore()
        store.handle(.graph(sampleGraph))
        store.reopen()
        #expect(store.phase == .idle)
    }

    /// `submitReview` guards on `canSubmitReview`, which requires a graph; pins that a store
    /// with nothing open leaves `review` untouched rather than submitting against a URL that
    /// doesn't exist.
    @Test @MainActor func submitReviewWithoutAGraphIsANoOp() {
        let store = GraphStore()
        store.submitReview(.approve)
        #expect(store.review == .idle)
    }

    // MARK: - hasOpenPR / pullRequestURL

    /// `hasOpenPR` tracks `phase != .idle`, not whether the analysis ever produced a graph —
    /// a session that failed to open (no graph at all) still counts as "open" for the
    /// purposes of File ▸ Close Pull Request and the toolbar.
    @Test @MainActor func hasOpenPRIsTrueOnceASessionHasFailedToOpen() {
        let store = GraphStore()
        #expect(!store.hasOpenPR)
        #expect(store.pullRequestURL == nil)

        store.handle(.fatal("network unreachable"))
        #expect(store.hasOpenPR, "a failed-to-open session is still a session, until close()")
        #expect(store.pullRequestURL == nil, "no graph and no stored PR URL means nothing to link to")
    }

    // MARK: - Contextual chat

    /// `ask(about:)` opens (or reuses) that subject's conversation thread; pins the wiring
    /// without needing a harness, since `ConversationStore.open` never touches one.
    @Test @MainActor func askOpensTheThreadForItsSubject() {
        let store = GraphStore()
        store.ask(about: .pullRequest)
        #expect(store.conversations.active?.subject == .pullRequest)
    }

    /// `ask(_:about:)` opens the thread and then calls `send`, whose own guard requires a
    /// graph. Pins that asking a specific question with nothing loaded still opens the
    /// thread (so the reviewer sees where their question went) but sends nothing into it.
    @Test @MainActor func askWithAQuestionOpensTheThreadButSendsNothingWithoutAGraph() {
        let store = GraphStore()
        store.ask("Why this side?", about: .pullRequest)
        #expect(store.conversations.active?.subject == .pullRequest)
        #expect(store.conversations.active?.messages.isEmpty == true, "send()'s graph guard exits before appending anything")
    }

    /// `send(_:in:)` guards on `graph` before ever reaching `ConversationStore.send` (and
    /// therefore the harness); pins that calling it on an unloaded store is a no-op rather
    /// than a crash on force-unwrapping a nil graph.
    @Test @MainActor func sendWithoutAGraphIsANoOp() {
        let store = GraphStore()
        let conversation = store.conversations.open(.pullRequest)
        store.send("does this matter?", in: conversation)
        #expect(conversation.messages.isEmpty)
    }
}
