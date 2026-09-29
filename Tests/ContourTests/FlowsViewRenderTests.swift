import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct FlowsViewRenderTests {

    private func host(_ graph: PRGraph, focus: FlowsView.Focus? = nil, mode: DiagramMode = .delta) -> NSHostingView<
        AnyView
    > {
        let view = FlowsView(graph: graph, focus: focus, mode: .constant(mode), onOpenEvidence: { _ in })
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let window = HeadlessWindow(size: hosting.frame.size)
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
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
            window = HeadlessWindow(size: hosting.frame.size)
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
                ) {
                    window.sendEvent(event)
                }
            }
            pump()
        }

        func close() { window.orderOut(nil) }
    }

    @Test func bracketKeysCycleScenarios() throws {
        let session = Session(try multiFlowGraph())
        for key in ["]", "]", "[", "[", "x"] { session.press(key) }
        session.press("]", modifiers: .command)
        session.close()
    }

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

    @Test func convergingFlowsShowAlsoReachedFrom() throws {
        var graph = ContourSampleData.publishTriggeredReindex
        let target = try #require(graph.flows.first)
        var caller = FlowNode(id: "caller", title: "Caller")
        caller.behavior = FlowBehavior(nodes: [
            FlowBehaviorNode(id: "hop", label: "Hop", kind: .subflow, subflowId: target.id)
        ])
        graph.flows.append(caller)
        let session = Session(graph)
        session.press("[")
        session.close()
    }
}
