import Testing
import SwiftUI
@testable import Contour

/// `SummaryViewLogic` is the grouping/filtering/formatting logic CLAUDE.md calls out for
/// this file, pulled out of `SummaryView`/`ConsiderationRow`'s bodies so it's directly
/// testable against plain fixtures — `GlanceFact.Tone`, `StageStatus`, `BehaviorStage`,
/// `Consideration`, and a hand-built `PRGraph` — rather than through the SwiftUI `body`.
/// The rest — the header, hero diagram, considerations list, explore tiles — is view
/// rendering with no UI-testing infrastructure in this suite.
struct SummaryViewTests {

    // MARK: - factTint

    @Test func factTintIsNilForPlainLeavingItAtSecondary() {
        #expect(SummaryViewLogic.factTint(.plain) == nil)
    }

    @Test func factTintMatchesEachNonPlainTone() {
        #expect(SummaryViewLogic.factTint(.good) == .green)
        #expect(SummaryViewLogic.factTint(.caution) == .orange)
        #expect(SummaryViewLogic.factTint(.bad) == .red)
    }

    // MARK: - judgmentWorkingText

    @Test func judgmentWorkingTextLooksForChoicesWhileDecisionsRunAndJudgmentHasntStarted() {
        let text = SummaryViewLogic.judgmentWorkingText(decisionsFound: 0, decisionsStatus: .running(detail: nil), judgmentStatus: .pending)
        #expect(text == "Looking for consequential choices…")
    }

    @Test func judgmentWorkingTextNamesHowManyDecisionsAreFoundSoFar() {
        let text = SummaryViewLogic.judgmentWorkingText(decisionsFound: 3, decisionsStatus: .running(detail: nil), judgmentStatus: .pending)
        #expect(text == "3 decisions found · looking for consequential choices…")
    }

    @Test func judgmentWorkingTextUsesSingularForOneDecision() {
        let text = SummaryViewLogic.judgmentWorkingText(decisionsFound: 1, decisionsStatus: .pending, judgmentStatus: .pending)
        #expect(text == "1 decision found · looking for consequential choices…")
    }

    @Test func judgmentWorkingTextSaysWeighingOnceJudgmentItselfIsRunning() {
        let text = SummaryViewLogic.judgmentWorkingText(decisionsFound: 5, decisionsStatus: .done, judgmentStatus: .running(detail: nil))
        #expect(text == "Weighing what needs your judgment…")
    }

    @Test func judgmentWorkingTextSaysWeighingOnceDecisionsHaveMovedPastRunning() {
        let text = SummaryViewLogic.judgmentWorkingText(decisionsFound: 5, decisionsStatus: .done, judgmentStatus: .pending)
        #expect(text == "Weighing what needs your judgment…")
    }

    // MARK: - navigationTarget(for:)

    @Test func navigationTargetPrefersTheStagesComponent() {
        let stage = BehaviorStage(label: "x", tag: .both, componentIds: ["c1"], flowId: "f1")
        #expect(SummaryViewLogic.navigationTarget(for: stage) == .componentDetail("c1"))
    }

    @Test func navigationTargetFallsBackToTheFlowWithNoComponent() {
        let stage = BehaviorStage(label: "x", tag: .both, flowId: "f1")
        #expect(SummaryViewLogic.navigationTarget(for: stage) == .flowDetail("f1"))
    }

    @Test func navigationTargetFallsBackToArchitectureWithNeither() {
        let stage = BehaviorStage(label: "x", tag: .both)
        #expect(SummaryViewLogic.navigationTarget(for: stage) == .architecture)
    }

    // MARK: - tileDetail

    @Test func tileDetailShowsTheReadySummaryOnceDoneOrStale() {
        #expect(SummaryViewLogic.tileDetail(status: .done, ready: "3 parts", count: 3, noun: "part") == "3 parts")
        #expect(SummaryViewLogic.tileDetail(status: .stale, ready: "3 parts", count: 3, noun: "part") == "3 parts")
    }

    @Test func tileDetailNamesAFailure() {
        #expect(SummaryViewLogic.tileDetail(status: .failed("boom"), ready: "3 parts", count: 3, noun: "part") == "Couldn't be analyzed")
    }

    @Test func tileDetailShowsWhatWasFoundBeforeStoppingOrJustStopped() {
        #expect(SummaryViewLogic.tileDetail(status: .stopped, ready: "3 parts", count: 3, noun: "part") == "3 parts, stopped")
        #expect(SummaryViewLogic.tileDetail(status: .stopped, ready: "0 parts", count: 0, noun: "part") == "Stopped")
    }

    @Test func tileDetailPluralizesTheNounOnlyWhenNeeded() {
        #expect(SummaryViewLogic.tileDetail(status: .stopped, ready: "", count: 1, noun: "part") == "1 part, stopped")
    }

    @Test func tileDetailShowsProgressOrAGenericMessageWhileRunning() {
        #expect(SummaryViewLogic.tileDetail(status: .running(detail: nil), ready: "3 parts", count: 3, noun: "part") == "3 parts so far…")
        #expect(SummaryViewLogic.tileDetail(status: .running(detail: nil), ready: "0 parts", count: 0, noun: "part") == "Analyzing…")
    }

    @Test func tileDetailWaitsWhilePending() {
        #expect(SummaryViewLogic.tileDetail(status: .pending, ready: "3 parts", count: 3, noun: "part") == "Waiting…")
    }

    // MARK: - relatedLinks

    private func graph(decisions: [DecisionNode] = [], components: [ComponentNode] = [], flows: [FlowNode] = []) -> PRGraph {
        var g = PRGraph(pr: PRSummary(
            repo: "acme/shop", number: 1, title: "t", author: "a", state: "OPEN",
            branch: "b", baseBranch: "main", headSha: "head", baseSha: "base",
            intent: Statement(text: "intent", provenance: .claim), filesChanged: 1, additions: 1, deletions: 0
        ))
        g.decisions = decisions
        g.components = components
        g.flows = flows
        return g
    }

    @Test func relatedLinksResolvesADecision() {
        let decision = DecisionNode(id: "d1", title: "Use retries", decision: Statement(text: "x", provenance: .claim), confidence: .high)
        let item = Consideration(id: "q1", question: "?", detail: "", relatedIds: ["d1"])
        let links = SummaryViewLogic.relatedLinks(for: item, graph: graph(decisions: [decision]))
        #expect(links.count == 1)
        #expect(links[0].title == "Use retries")
        #expect(links[0].symbol == "checklist")
        #expect(links[0].target == .decisionDetail("d1"))
    }

    @Test func relatedLinksResolvesAComponent() {
        let component = ComponentNode(id: "c1", title: "Publisher", changeKind: .changed)
        let item = Consideration(id: "q1", question: "?", detail: "", relatedIds: ["c1"])
        let links = SummaryViewLogic.relatedLinks(for: item, graph: graph(components: [component]))
        #expect(links.count == 1)
        #expect(links[0].title == "Publisher")
        #expect(links[0].symbol == "square.stack.3d.up")
        #expect(links[0].target == .componentDetail("c1"))
    }

    @Test func relatedLinksResolvesAFlow() {
        let flow = FlowNode(id: "f1", title: "Publish page")
        let item = Consideration(id: "q1", question: "?", detail: "", relatedIds: ["f1"])
        let links = SummaryViewLogic.relatedLinks(for: item, graph: graph(flows: [flow]))
        #expect(links.count == 1)
        #expect(links[0].title == "Publish page")
        #expect(links[0].symbol == "arrow.triangle.branch")
        #expect(links[0].target == .flowDetail("f1"))
    }

    @Test func relatedLinksDropsIdsThatResolveToNothing() {
        let item = Consideration(id: "q1", question: "?", detail: "", relatedIds: ["does-not-exist"])
        #expect(SummaryViewLogic.relatedLinks(for: item, graph: graph()).isEmpty)
    }

    @Test func relatedLinksKeepsTheOriginalOrderAcrossKinds() {
        let decision = DecisionNode(id: "d1", title: "D", decision: Statement(text: "x", provenance: .claim), confidence: .high)
        let component = ComponentNode(id: "c1", title: "C", changeKind: .changed)
        let item = Consideration(id: "q1", question: "?", detail: "", relatedIds: ["c1", "d1"])
        let links = SummaryViewLogic.relatedLinks(for: item, graph: graph(decisions: [decision], components: [component]))
        #expect(links.map(\.title) == ["C", "D"])
    }

    // MARK: - capitalizedFirst

    @Test func capitalizedFirstCapitalizesOnlyTheFirstLetter() {
        #expect(SummaryViewLogic.capitalizedFirst("observed fact") == "Observed fact")
    }

    @Test func capitalizedFirstOnAnEmptyStringStaysEmpty() {
        #expect(SummaryViewLogic.capitalizedFirst("") == "")
    }

    // MARK: - awaitingBehaviorText

    /// Pins the (initially surprising) polarity: no failure yet reads as "still understanding",
    /// a failed understanding step reads as "moved on to building the before/after" — the
    /// hero never blames the reviewer with raw failure text at this level.
    @Test func awaitingBehaviorTextSaysUnderstandingWhileThatStepHasntFailed() {
        #expect(SummaryViewLogic.awaitingBehaviorText(understandingFailed: false) == "Understanding the change…")
    }

    @Test func awaitingBehaviorTextMovesOnOnceUnderstandingFailed() {
        #expect(SummaryViewLogic.awaitingBehaviorText(understandingFailed: true) == "Building before / after…")
    }

    // MARK: - retryBannerText

    @Test func retryBannerTextNamesAFailure() {
        let text = SummaryViewLogic.retryBannerText(status: .failed("boom"), failureText: "Couldn't build it.", stoppedText: "Stopped early.")
        #expect(text == "Couldn't build it.")
    }

    @Test func retryBannerTextNamesAStop() {
        let text = SummaryViewLogic.retryBannerText(status: .stopped, failureText: "Couldn't build it.", stoppedText: "Stopped early.")
        #expect(text == "Stopped early.")
    }

    @Test func retryBannerTextIsNilOnceNeitherFailedNorStopped() {
        #expect(SummaryViewLogic.retryBannerText(status: .done, failureText: "f", stoppedText: "s") == nil)
        #expect(SummaryViewLogic.retryBannerText(status: .running(detail: nil), failureText: "f", stoppedText: "s") == nil)
        #expect(SummaryViewLogic.retryBannerText(status: .pending, failureText: "f", stoppedText: "s") == nil)
    }

    // MARK: - judgmentTailState

    @Test func judgmentTailStateIsWorkingWhileUnsettled() {
        #expect(SummaryViewLogic.judgmentTailState(status: .pending) == .working)
        #expect(SummaryViewLogic.judgmentTailState(status: .running(detail: nil)) == .working)
        #expect(SummaryViewLogic.judgmentTailState(status: .stale) == .working)
    }

    @Test func judgmentTailStateIsFailedOnceSettledWithAFailure() {
        #expect(SummaryViewLogic.judgmentTailState(status: .failed("boom")) == .failed)
    }

    @Test func judgmentTailStateIsStoppedOnceSettledStopped() {
        #expect(SummaryViewLogic.judgmentTailState(status: .stopped) == .stopped)
    }

    @Test func judgmentTailStateIsSettledOnceDone() {
        #expect(SummaryViewLogic.judgmentTailState(status: .done) == .settled)
    }

    // MARK: - thingsToThinkAboutBranch

    @Test func thingsToThinkAboutBranchShowsThePlaceholderWithNoItemsYet() {
        #expect(SummaryViewLogic.thingsToThinkAboutBranch(items: nil, judgmentStopped: false) == .placeholder)
    }

    @Test func thingsToThinkAboutBranchShowsTheListOnceThereAreItems() {
        let items = [Consideration(id: "q1", question: "?", detail: "")]
        #expect(SummaryViewLogic.thingsToThinkAboutBranch(items: items, judgmentStopped: false) == .list)
        // Even a stopped judgment shows the list it already produced, not the stopped banner.
        #expect(SummaryViewLogic.thingsToThinkAboutBranch(items: items, judgmentStopped: true) == .list)
    }

    @Test func thingsToThinkAboutBranchExplainsAnEmptyListThatStopped() {
        #expect(SummaryViewLogic.thingsToThinkAboutBranch(items: [], judgmentStopped: true) == .stoppedEmpty)
    }

    @Test func thingsToThinkAboutBranchShowsNothingForAnEmptySettledList() {
        #expect(SummaryViewLogic.thingsToThinkAboutBranch(items: [], judgmentStopped: false) == .none)
    }

    // MARK: - visibleConsiderations

    private func considerations(_ n: Int) -> [Consideration] {
        (1...n).map { Consideration(id: "q\($0)", question: "?\($0)", detail: "") }
    }

    @Test func visibleConsiderationsTrimsToTheBudgetWhenCollapsed() {
        let visible = SummaryViewLogic.visibleConsiderations(considerations(8), showAll: false, budget: 5)
        #expect(visible.map(\.id) == ["q1", "q2", "q3", "q4", "q5"])
    }

    @Test func visibleConsiderationsShowsEverythingOnceExpanded() {
        let visible = SummaryViewLogic.visibleConsiderations(considerations(8), showAll: true, budget: 5)
        #expect(visible.count == 8)
    }

    // MARK: - showMoreLabel

    @Test func showMoreLabelIsNilWhenEverythingAlreadyFits() {
        #expect(SummaryViewLogic.showMoreLabel(count: 5, budget: 5, showingAll: false) == nil)
        #expect(SummaryViewLogic.showMoreLabel(count: 3, budget: 5, showingAll: false) == nil)
    }

    @Test func showMoreLabelNamesHowManyMoreWhileCollapsed() {
        #expect(SummaryViewLogic.showMoreLabel(count: 8, budget: 5, showingAll: false) == "Show 3 more")
    }

    @Test func showMoreLabelOffersToCollapseOnceExpanded() {
        #expect(SummaryViewLogic.showMoreLabel(count: 8, budget: 5, showingAll: true) == "Show fewer")
    }

    // MARK: - thingsToThinkAboutHeaderText

    @Test func thingsToThinkAboutHeaderTextIsSingularForOne() {
        #expect(SummaryViewLogic.thingsToThinkAboutHeaderText(count: 1) == "1 THING TO THINK ABOUT")
    }

    @Test func thingsToThinkAboutHeaderTextIsPluralOtherwise() {
        #expect(SummaryViewLogic.thingsToThinkAboutHeaderText(count: 0) == "0 THINGS TO THINK ABOUT")
        #expect(SummaryViewLogic.thingsToThinkAboutHeaderText(count: 4) == "4 THINGS TO THINK ABOUT")
    }

    // MARK: - resolvedProgressText

    @Test func resolvedProgressTextIsNilWithNothingResolvedYet() {
        #expect(SummaryViewLogic.resolvedProgressText(reviewed: 0, total: 4) == nil)
    }

    @Test func resolvedProgressTextNamesTheCountOnceSomethingIsResolved() {
        #expect(SummaryViewLogic.resolvedProgressText(reviewed: 2, total: 4) == "2 of 4 resolved")
    }

    // MARK: - architectureReadyText

    @Test func architectureReadyTextPrefersTheNamedImpact() {
        #expect(SummaryViewLogic.architectureReadyText(impactLabel: "Moderate", partsCount: 9) == "Moderate architectural impact")
    }

    @Test func architectureReadyTextFallsBackToAPartsCount() {
        #expect(SummaryViewLogic.architectureReadyText(impactLabel: nil, partsCount: 3) == "3 parts")
    }

    // MARK: - decisionsReadyText

    @Test func decisionsReadyTextShowsProgressOnceThereIsSomethingToReview() {
        #expect(SummaryViewLogic.decisionsReadyText(reviewed: 1, total: 3, decisionsCount: 5) == "1 of 3 resolved")
    }

    @Test func decisionsReadyTextFallsBackToACountWithNothingToReview() {
        #expect(SummaryViewLogic.decisionsReadyText(reviewed: 0, total: 0, decisionsCount: 5) == "5 identified")
    }

    // MARK: - considerationBadgeHelp

    @Test func considerationBadgeHelpSaysResolvedBeforeAnythingElse() {
        #expect(SummaryViewLogic.considerationBadgeHelp(isResolved: true, isQuestion: true) == "Resolved")
        #expect(SummaryViewLogic.considerationBadgeHelp(isResolved: true, isQuestion: false) == "Resolved")
    }

    @Test func considerationBadgeHelpDistinguishesAnOpenQuestionFromAConcern() {
        #expect(SummaryViewLogic.considerationBadgeHelp(isResolved: false, isQuestion: true)
                == "Open question — the analysis couldn't settle this")
        #expect(SummaryViewLogic.considerationBadgeHelp(isResolved: false, isQuestion: false)
                == "A judgment call worth your attention")
    }

    // MARK: - reviewButtonHelp

    @Test func reviewButtonHelpPointsAtTheDecisionWhenThereIsOne() {
        #expect(SummaryViewLogic.reviewButtonHelp(hasDecision: true) == "Review the decision this question is about")
    }

    @Test func reviewButtonHelpFallsBackToAskingWithNoDecision() {
        #expect(SummaryViewLogic.reviewButtonHelp(hasDecision: false) == "Ask about this")
    }

    // MARK: - whySectionMode

    @Test func whySectionModeShowsWhyAndConsequenceOnlyWithBothAChangeAndContent() {
        #expect(SummaryViewLogic.whySectionMode(hasDominantChange: true, hasWhyOrConsequence: true, awaitingBehavior: false)
                == .whyAndConsequence)
    }

    @Test func whySectionModeIgnoresAChangeWithNeitherWhyNorConsequence() {
        // A dominant change with nothing to say about it falls through to the awaiting check,
        // same as having no change at all.
        #expect(SummaryViewLogic.whySectionMode(hasDominantChange: true, hasWhyOrConsequence: false, awaitingBehavior: true)
                == .placeholder)
        #expect(SummaryViewLogic.whySectionMode(hasDominantChange: true, hasWhyOrConsequence: false, awaitingBehavior: false)
                == .none)
    }

    @Test func whySectionModeShowsThePlaceholderWhileAwaitingWithNoChangeYet() {
        #expect(SummaryViewLogic.whySectionMode(hasDominantChange: false, hasWhyOrConsequence: false, awaitingBehavior: true)
                == .placeholder)
    }

    @Test func whySectionModeShowsNothingOnceSettledWithNoWhyToShow() {
        #expect(SummaryViewLogic.whySectionMode(hasDominantChange: false, hasWhyOrConsequence: false, awaitingBehavior: false)
                == .none)
    }

    // MARK: - toggled / reviewAction

    /// Clicking a row opens it, moves the disclosure to it from another, or closes it.
    @Test func toggledOpensSwitchesAndCloses() {
        #expect(SummaryViewLogic.toggled(nil, "a") == "a")
        #expect(SummaryViewLogic.toggled("b", "a") == "a")
        #expect(SummaryViewLogic.toggled("a", "a") == nil)
    }

    @Test func reviewActionNavigatesWithADecisionAndAsksWithout() {
        #expect(SummaryViewLogic.reviewAction(hasDecision: true) == .navigate)
        #expect(SummaryViewLogic.reviewAction(hasDecision: false) == .ask)
    }
}
