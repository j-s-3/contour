import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
@Suite(.serialized)
struct DecisionsViewInteractionTests {

    @MainActor private final class Recorder {
        var states: [String: ReviewerState] = [:]
        var stateCalls: [(String, ReviewerState)] = []
        var notes: [(String, String)] = []
        var placements: [(String, Bool)] = []
        var asked: [ReviewSubject] = []
        var focused: [ReviewSubject?] = []
    }

    private struct Wrapper: View {
        let recorder: Recorder
        let focus: DecisionsView.Focus?
        @State var graph: PRGraph

        var body: some View {
            DecisionsView(
                graph: graph, focus: focus, discussed: [],
                onSetState: { id, state in
                    recorder.stateCalls.append((id, state))
                    recorder.states[id] = state
                    if let index = graph.decisions.firstIndex(where: { $0.id == id }) {
                        graph.decisions[index].reviewerState = state
                    }
                },
                onSetNote: { id, note in recorder.notes.append((id, note)) },
                onSetToReview: { id, toReview in
                    recorder.placements.append((id, toReview))
                    graph.setToReview(toReview, forDecision: id)
                }
            )
            .environment(
                \.reviewActions,
                ReviewActions(
                    ask: { recorder.asked.append($0) },
                    focus: { recorder.focused.append($0) })
            )
        }
    }

    private final class Session {
        let recorder = Recorder()
        let window: NSWindow
        let hosting: NSHostingView<Wrapper>

        @MainActor
        init(graph: PRGraph, mode: DecisionsView.Mode, focus: DecisionsView.Focus? = nil) {
            _ = NSApplication.shared
            UserDefaults.standard.set(mode.rawValue, forKey: "decisions.mode")
            hosting = NSHostingView(rootView: Wrapper(recorder: recorder, focus: focus, graph: graph))
            hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 1400)
            window = HeadlessWindow(size: hosting.frame.size)
            window.contentView = hosting
            window.orderBack(nil)
            pump()
        }

        @MainActor
        func pump(_ seconds: TimeInterval = 0.05) {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
            hosting.layoutSubtreeIfNeeded()
        }

        @MainActor
        func press(_ characters: String, modifiers: NSEvent.ModifierFlags = []) {
            window.makeFirstResponder(hosting)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0
                ) {
                    window.sendEvent(event)
                }
            }
            pump()
        }

        @MainActor
        func close() {
            window.orderOut(nil)
            UserDefaults.standard.removeObject(forKey: "decisions.mode")
        }
    }

    private func decision(_ id: String, significance: ReviewSignificance, state: ReviewerState = .unreviewed)
        -> DecisionNode
    {
        DecisionNode(
            id: id, title: "Decision \(id)",
            decision: Statement(text: "Did \(id). More.", provenance: .fact),
            confidence: .medium, reviewerState: state,
            question: "Should we \(id)?",
            options: [DecisionOption(label: "Yes", detail: nil, chosen: true), DecisionOption(label: "No")],
            shape: .binary, significance: significance)
    }

    private func graph(review: Int = 3, other: Int = 2) -> PRGraph {
        var g = ContourSampleData.publishTriggeredReindex
        g.decisions =
            (0..<review).map { decision("r\($0)", significance: .high) }
            + (0..<other).map { decision("o\($0)", significance: .low) }
        g.pr.considerations = []
        return g
    }

    private let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    private let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)

    @Test func judgingKeysReportEachStateForTheSelectedDecision() {
        let session = Session(graph: graph(), mode: .list)
        session.press("a")
        session.press("q")
        session.press("c")
        session.pump(0.4)
        #expect(session.recorder.stateCalls.map(\.1) == [.accepted, .questioned, .discuss])
        #expect(session.recorder.stateCalls.allSatisfy { $0.0 == "r0" })
        #expect(session.recorder.asked.count == 1)
        session.close()
    }

    @Test func movingKeysStepThroughTheSequenceAndJudgeTheNewSelection() {
        let session = Session(graph: graph(), mode: .list)
        session.press("j")
        session.press("a")
        session.press(down)
        session.press("q")
        session.press("k")
        session.press(up)
        session.press("c")
        #expect(session.recorder.stateCalls.map(\.0) == ["r1", "r2", "r0"])
        session.close()
    }

    @Test func repeatingTheSameJudgementClearsWithoutAdvancing() {
        let session = Session(graph: graph(), mode: .list)
        session.press("a")
        session.pump(0.4)
        session.press("a")
        session.pump(0.4)
        #expect(session.recorder.stateCalls.map(\.1) == [.accepted, .accepted])
        session.close()
    }

    @Test func acceptingTheLastDecisionInTheSequenceStaysPut() {
        let session = Session(graph: graph(review: 1, other: 0), mode: .list)
        session.press("a")
        session.pump(0.4)
        #expect(session.recorder.stateCalls.map(\.0) == ["r0"])
        session.close()
    }

    @Test func toggleAndUnboundKeysAreHandledOrIgnored() {
        let session = Session(graph: graph(), mode: .list)
        session.press("m")
        session.press(" ")
        session.press("z")
        session.press("a", modifiers: [.command])
        #expect(session.recorder.stateCalls.isEmpty)
        session.close()
    }

    @Test func oneAtATimeWalksForwardAndBackAndOffersTheOtherDecisions() {
        let session = Session(graph: graph(review: 2, other: 1), mode: .oneAtATime)
        session.press("j")
        session.press("j")
        session.press("k")
        session.press("j")
        session.press("j")
        session.press("k")
        session.press("a")
        session.close()
    }

    @Test func oneAtATimeWithOnlyOtherDecisionsStillRenders() {
        let session = Session(graph: graph(review: 0, other: 2), mode: .oneAtATime)
        session.press("j")
        session.press("m")
        #expect(session.recorder.stateCalls.isEmpty)
        session.close()
    }

    @Test func arrivingAtAnOtherDecisionRevealsTheOtherSectionAndSelectsIt() {
        let session = Session(graph: graph(), mode: .list, focus: .init(decisionId: "o1"))
        session.pump(0.4)
        #expect(session.recorder.focused.contains { $0 == .decision("o1") })
        session.close()
    }

    @Test func arrivingAtAReviewDecisionSelectsItAndTheHighlightFades() {
        let session = Session(graph: graph(), mode: .list, focus: .init(decisionId: "r1"))
        session.pump(2.0)
        #expect(session.recorder.focused.contains { $0 == .decision("r1") })
        session.close()
    }

}
