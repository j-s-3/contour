import Foundation
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct BehaviorDiagramRenderTests {

    private func image(
        _ behavior: FlowBehavior, annotations: [FlowAnnotation], mode: DiagramMode,
        selected: String?
    ) -> NSImage? {
        let view = BehaviorDiagramView(
            flowId: "f", behavior: behavior, annotations: annotations, mode: mode, selectedNodeId: selected,
            onSelect: { _ in }, onDrill: { _ in }, onShowImplementation: { _ in },
            onOpenAnnotation: { _ in }, onOpenSubflow: { _ in },
            subflowTitle: { $0 == "sub" ? "Shared" : nil }
        )
        .frame(width: 900, height: 900)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.nsImage
    }

    @Test func everyModeRendersTheSampleFlow() {
        let graph = ContourSampleData.publishTriggeredReindex
        let flow = graph.flows[0]
        for mode in DiagramMode.allCases {
            let behavior = graph.behavior(for: flow).visible(in: mode)
            let ids = Set(behavior.nodes.map(\.id))
            let notes = graph.annotations(for: flow).filter { ids.contains($0.nodeId) }
            let rendered = image(behavior, annotations: notes, mode: mode, selected: "queue")
            #expect((rendered?.size.width ?? 0) > 0, "mode \(mode)")
        }
    }

    @Test func crowdedAnnotationsRenderTheOverflowChip() {
        let behavior = ContourSampleData.publishTriggeredReindex.flows[0].behavior!
        let notes = (0..<6).map {
            FlowAnnotation(
                kind: $0 % 2 == 0 ? .decision : .question, targetId: "t\($0)", nodeId: "save",
                text: "Note \($0)", detail: $0 % 2 == 0 ? "More detail" : nil)
        }
        #expect(image(behavior, annotations: notes, mode: .delta, selected: nil) != nil)
    }

    @Test func subflowUncertainAndEveryBoundaryKindRender() {
        let kinds: [BoundaryKind] = [
            .application, .process, .service, .datastore, .external, .trust, .network, .asyncBoundary,
        ]
        let boundaries = kinds.enumerated().map {
            FlowBoundary(id: "b\($0.offset)", label: "B\($0.offset)", kind: $0.element)
        }
        let nodes = [
            FlowBehaviorNode(id: "a", label: "Start", kind: .trigger, boundaryId: "b0"),
            FlowBehaviorNode(id: "b", label: "Shared flow", kind: .subflow, subflowId: "sub", boundaryId: "b1"),
            FlowBehaviorNode(id: "c", label: "Maybe", boundaryId: "b5", provenance: .interpretation, confidence: .low),
            FlowBehaviorNode(id: "d", label: "Store", kind: .datastore, boundaryId: "b3"),
        ]
        let edges = [
            FlowBehaviorEdge(fromId: "a", toId: "b"),
            FlowBehaviorEdge(fromId: "b", toId: "c", label: "go", flow: .async),
            FlowBehaviorEdge(fromId: "c", toId: "d", change: .removed),
        ]
        let behavior = FlowBehavior(nodes: nodes, edges: edges, boundaries: boundaries)
        #expect(image(behavior, annotations: [], mode: .delta, selected: "b") != nil)
    }

    @Test func lozengeFillsItsRectAndInsetsUniformly() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        #expect(Lozenge().path(in: rect).boundingRect == rect)
        #expect(Lozenge().path(in: CGRect(x: 0, y: 0, width: 100, height: 20)).boundingRect.height == 20)
        #expect(Lozenge().inset(by: 5).path(in: rect).boundingRect == rect.insetBy(dx: 5, dy: 5))
    }
}
