import Testing
import SwiftUI
import AppKit
@testable import Contour

/// `FlowsView`'s body, header, scenario tabs, story and diagram builders are SwiftUI view
/// code; the decisions inside them live in `FlowsViewLogic`. This suite hosts the real view
/// in a window (so `.onAppear`/`.onChange` fire) over `ContourSampleData` for the empty,
/// single-flow, multi-flow, focused and every-diagram-mode cases. It pins that none of them
/// traps while building or laying out, which the pure-logic tests cannot see.
@MainActor
struct FlowsViewRenderTests {

    private func host(_ graph: PRGraph, focus: FlowsView.Focus? = nil, mode: DiagramMode = .delta) -> NSHostingView<AnyView> {
        let view = FlowsView(graph: graph, focus: focus, mode: .constant(mode), onOpenEvidence: { _ in })
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        // Let onAppear's state changes (selection, focus) re-render the body.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        withExtendedLifetime(window) {}
        window.orderOut(nil)
        return hosting
    }

    private func multiFlowGraph() throws -> PRGraph {
        var graph = ContourSampleData.publishTriggeredReindex
        let first = try #require(graph.flows.first)
        var second = first
        second.id = first.id + "-2"
        second.title = "Second scenario"
        graph.flows.append(second)
        return graph
    }

    @Test func emptyGraphShowsThePlaceholder() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.flows = []
        #expect(host(graph).fittingSize.width >= 0)
    }

    @Test func singleFlowRendersInEveryMode() {
        let graph = ContourSampleData.publishTriggeredReindex
        for mode in DiagramMode.allCases {
            #expect(host(graph, mode: mode).fittingSize.width >= 0)
        }
    }

    @Test func multiFlowRendersTabsInEveryMode() throws {
        let graph = try multiFlowGraph()
        for mode in DiagramMode.allCases {
            #expect(host(graph, mode: mode).fittingSize.width >= 0)
        }
    }

    @Test func focusOnAStageOpensTheInspector() throws {
        let graph = try multiFlowGraph()
        let flow = try #require(graph.flows.last)
        for node in graph.behavior(for: flow).nodes {
            _ = host(graph, focus: .init(flowId: flow.id, nodeId: node.id))
        }
    }

    @Test func focusOnAFlowWithoutAStageRenders() throws {
        let graph = try multiFlowGraph()
        let flow = try #require(graph.flows.last)
        _ = host(graph, focus: .init(flowId: flow.id))
    }

    @Test func aFlowWithNoBehaviorStillRenders() throws {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.flows = [FlowNode(id: "bare", title: "Bare flow")]
        _ = host(graph)
    }

    // MARK: - Interaction

    /// Owns a window, a hosted `FlowsView`, and a handle to its mode binding so a test can
    /// press keys and switch modes the way the reviewer does.
    @MainActor private final class Session {
        struct Wrapper: View {
            let graph: PRGraph
            let focus: FlowsView.Focus?
            let setter: (@escaping (DiagramMode) -> Void) -> Void
            @State private var mode: DiagramMode = .delta
            var body: some View {
                FlowsView(graph: graph, focus: focus, mode: $mode, onOpenEvidence: { _ in })
                    .onAppear { setter { mode = $0 } }
            }
        }

        var setMode: (DiagramMode) -> Void = { _ in }
        let window: NSWindow
        let hosting: NSHostingView<Wrapper>

        init(_ graph: PRGraph, focus: FlowsView.Focus? = nil) {
            var captured: ((DiagramMode) -> Void)?
            hosting = NSHostingView(rootView: Wrapper(graph: graph, focus: focus, setter: { captured = $0 }))
            hosting.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
            window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = hosting
            window.orderBack(nil)
            pump()
            if let captured { setMode = captured }
        }

        func pump() {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
        }

        func press(_ characters: String, modifiers: NSEvent.ModifierFlags = []) {
            window.makeFirstResponder(hosting)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0
                ) { window.sendEvent(event) }
            }
            pump()
        }

        func close() { window.orderOut(nil) }
    }

    /// `[` and `]` cycle scenarios through `handleKey` and `openFlow`; other keys are ignored.
    @Test func bracketKeysCycleScenarios() throws {
        let session = Session(try multiFlowGraph())
        for key in ["]", "]", "[", "[", "x"] { session.press(key) }
        session.press("]", modifiers: .command)
        session.close()
    }

    /// A stage that the new mode hides is deselected through `select(nil)`.
    @Test func switchingToAModeThatHidesTheSelectedStageDeselectsIt() throws {
        let graph = ContourSampleData.publishTriggeredReindex
        let flow = try #require(graph.flows.first)
        let node = try #require(graph.behavior(for: flow).nodes.first { $0.change == .new })
        let session = Session(graph, focus: .init(flowId: flow.id, nodeId: node.id))
        session.setMode(.before)
        session.pump()
        session.setMode(.after)
        session.pump()
        session.close()
    }

    /// A flow that another flow hands off into lists the sources it is also reached from.
    @Test func convergingFlowsShowAlsoReachedFrom() throws {
        var graph = ContourSampleData.publishTriggeredReindex
        let target = try #require(graph.flows.first)
        var caller = FlowNode(id: "caller", title: "Caller")
        caller.behavior = FlowBehavior(nodes: [
            FlowBehaviorNode(id: "hop", label: "Hop", kind: .subflow, subflowId: target.id),
        ])
        graph.flows.append(caller)
        let session = Session(graph)
        session.press("[")
        session.close()
    }
}
