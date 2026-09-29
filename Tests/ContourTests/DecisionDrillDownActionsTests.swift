import Testing

@testable import Contour

@Suite(.serialized)
struct DecisionDrillDownActionsTests {
    private final class Recorder: @unchecked Sendable {
        var targets: [NavigationTarget] = []
        var subjects: [ReviewSubject] = []
    }

    private func drill(_ recorder: Recorder) -> DecisionDrillDownActions {
        var actions = ReviewActions()
        actions.navigate = { recorder.targets.append($0) }
        actions.ask = { recorder.subjects.append($0) }
        return DecisionDrillDownActions(decisionId: "d1", actions: actions)
    }

    @Test func openingEvidenceNavigatesToTheRef() {
        let recorder = Recorder()
        let ref = CodeRef(path: "src/A.swift", startLine: 1, endLine: 5)
        drill(recorder).openEvidence(ref)
        #expect(recorder.targets == [.evidence(ref)])
    }

    @Test func openingALinkNavigatesToItsTarget() {
        let recorder = Recorder()
        drill(recorder).open(.componentDetail("c1"))
        drill(recorder).open(.flowDetail("f1"))
        #expect(recorder.targets == [.componentDetail("c1"), .flowDetail("f1")])
    }

    @Test func askingTargetsTheDecision() {
        let recorder = Recorder()
        drill(recorder).ask()
        #expect(recorder.subjects == [.decision("d1")])
    }

    @Test func edgeLabelUsesComponentTitlesAndFallsBackToIds() {
        var graph = ContourSampleData.publishTriggeredReindex
        let known = graph.components[0]
        let edge = ArchitectureEdge(id: "e", fromId: known.id, toId: "missing-component", label: "calls")
        let label = DecisionDrillDownActions.edgeLabel(edge, in: graph)
        #expect(label == DecisionsViewLogic.edgeTitle(from: known.title, to: "missing-component"))
        graph.components = []
        #expect(
            DecisionDrillDownActions.edgeLabel(edge, in: graph)
                == DecisionsViewLogic.edgeTitle(from: known.id, to: "missing-component"))
    }
}
