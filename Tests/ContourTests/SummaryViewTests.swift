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
}
