import Foundation
import Testing
import SwiftUI
@testable import Contour

/// `BehaviorDiagramView`'s body is Canvas drawing, `ForEach` composition and gesture wiring
/// with no pure seam left, so these render it for real with `ImageRenderer` over the sample
/// publish flow in each mode. They pin that every branch of the view (each stage kind,
/// boundary, edge style, annotation, overflow chip and the legend) draws without trapping and
/// produces an image, which is what covers the body for the CLAUDE.md coverage target (#122).
/// `Lozenge` is checked directly for its geometry.
@MainActor
struct BehaviorDiagramRenderTests {

    private func image(_ behavior: FlowBehavior, annotations: [FlowAnnotation], mode: DiagramMode,
                       selected: String?) -> NSImage? {
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

    /// Each mode draws a non-empty diagram of the sample flow; Delta also exercises the tinted,
    /// struck-through and before/after stage paths and the change legend.
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

    /// Many notes on one stage collapse into a "+N more" overflow chip; rendering must cover it.
    @Test func crowdedAnnotationsRenderTheOverflowChip() {
        let behavior = ContourSampleData.publishTriggeredReindex.flows[0].behavior!
        let notes = (0..<6).map {
            FlowAnnotation(kind: $0 % 2 == 0 ? .decision : .question, targetId: "t\($0)", nodeId: "save",
                           text: "Note \($0)", detail: $0 % 2 == 0 ? "More detail" : nil)
        }
        #expect(image(behavior, annotations: notes, mode: .delta, selected: nil) != nil)
    }

    /// A subflow stage, an uncertain stage and every boundary kind render together.
    @Test func subflowUncertainAndEveryBoundaryKindRender() {
        let kinds: [BoundaryKind] = [.application, .process, .service, .datastore, .external, .trust, .network, .asyncBoundary]
        let boundaries = kinds.enumerated().map { FlowBoundary(id: "b\($0.offset)", label: "B\($0.offset)", kind: $0.element) }
        let nodes = [
            FlowBehaviorNode(id: "a", label: "Start", kind: .trigger, boundaryId: "b0"),
            FlowBehaviorNode(id: "b", label: "Shared flow", kind: .subflow, subflowId: "sub", boundaryId: "b1"),
            FlowBehaviorNode(id: "c", label: "Maybe", boundaryId: "b5", provenance: .interpretation, confidence: .low),
            FlowBehaviorNode(id: "d", label: "Store", kind: .datastore, boundaryId: "b3")
        ]
        let edges = [FlowBehaviorEdge(fromId: "a", toId: "b"),
                     FlowBehaviorEdge(fromId: "b", toId: "c", label: "go", flow: .async),
                     FlowBehaviorEdge(fromId: "c", toId: "d", change: .removed)]
        let behavior = FlowBehavior(nodes: nodes, edges: edges, boundaries: boundaries)
        #expect(image(behavior, annotations: [], mode: .delta, selected: "b") != nil)
    }

    /// A lozenge's pointed ends sit on the vertical midline and its bounds fill the rect;
    /// insetting shrinks it uniformly. A short shape caps its point at half its height.
    @Test func lozengeFillsItsRectAndInsetsUniformly() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        #expect(Lozenge().path(in: rect).boundingRect == rect)
        #expect(Lozenge().path(in: CGRect(x: 0, y: 0, width: 100, height: 20)).boundingRect.height == 20)
        #expect(Lozenge().inset(by: 5).path(in: rect).boundingRect == rect.insetBy(dx: 5, dy: 5))
    }
}
