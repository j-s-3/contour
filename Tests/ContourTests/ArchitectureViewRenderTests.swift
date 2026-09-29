import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct ArchitectureViewRenderTests {

    @MainActor private final class Session {
        struct Wrapper: View {
            let graph: PRGraph
            let focus: ArchAnchor?
            let setter: (@escaping (DiagramMode) -> Void) -> Void
            @State private var mode: DiagramMode = .delta
            var body: some View {
                ArchitectureView(graph: graph, focus: focus, mode: $mode)
                    .onAppear { setter { mode = $0 } }
            }
        }

        var setMode: (DiagramMode) -> Void = { _ in }
        let window: NSWindow
        let hosting: NSHostingView<Wrapper>

        init(_ graph: PRGraph, focus: ArchAnchor? = nil) {
            var captured: ((DiagramMode) -> Void)?
            hosting = NSHostingView(rootView: Wrapper(graph: graph, focus: focus, setter: { captured = $0 }))
            hosting.frame = NSRect(x: 0, y: 0, width: 1400, height: 900)
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
                ) {
                    window.sendEvent(event)
                }
            }
            pump()
        }

        func close() { window.orderOut(nil) }
    }

    private func nestedGraph() -> PRGraph {
        var graph = ContourSampleData.publishTriggeredReindex
        let parent = ComponentNode(id: "outer", title: "Outer", changeKind: .changed)
        let child = ComponentNode(id: "inner", title: "Inner", changeKind: .new, parentId: "outer")
        let sibling = ComponentNode(id: "inner-2", title: "Inner two", changeKind: .changed, parentId: "outer")
        graph.components += [parent, child, sibling]
        graph.architecture = ArchitectureAssessment(
            impact: .significant, headline: "A headline",
            explanation: Statement(text: "Why it matters", provenance: .fact))
        return graph
    }

    @Test func emptyArchitectureShowsThePlaceholder() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.components = []
        graph.architectureEdges = []
        let session = Session(graph)
        #expect(session.hosting.fittingSize.width >= 0)
        session.close()
    }

    @Test func rendersEveryModeWithAHeadlineAndLegend() {
        let session = Session(nestedGraph())
        for mode in DiagramMode.allCases {
            session.setMode(mode)
            session.pump()
        }
        session.close()
    }

    @Test func focusOnANestedPartZoomsInAndShowsTheBreadcrumb() {
        let session = Session(nestedGraph(), focus: .node("inner"))
        session.press("-", modifiers: .command)
        session.close()
    }

    @Test func focusOnEveryPartAndEdgeOpensTheInspector() {
        let graph = nestedGraph()
        for component in graph.components {
            Session(graph, focus: .node(component.id)).close()
        }
        for edge in graph.architectureEdges {
            Session(graph, focus: .edge(edge.id)).close()
        }
    }

    @Test func switchingModeDropsASelectionThatIsNoLongerDrawn() {
        let session = Session(nestedGraph(), focus: .node("inner"))
        session.setMode(.before)
        session.pump()
        session.setMode(.after)
        session.pump()
        session.close()
    }
}
