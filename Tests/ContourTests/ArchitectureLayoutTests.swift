import CoreGraphics
import Testing

@testable import Contour

struct ArchitectureLayoutTests {
    private func node(_ id: String, _ height: CGFloat = 90) -> GraphLayoutEngine.NodeSpec {
        .init(id: id, size: CGSize(width: 224, height: height))
    }
    private func edge(_ from: String, _ to: String, label: CGFloat = 80) -> GraphLayoutEngine.EdgeSpec {
        .init(id: "\(from)->\(to)", fromId: from, toId: to, labelSize: CGSize(width: label, height: 20))
    }

    private var bat:
        (
            nodes: [GraphLayoutEngine.NodeSpec], edges: [GraphLayoutEngine.EdgeSpec],
            groups: [GraphLayoutEngine.GroupSpec]
        )
    {
        (
            [node("source"), node("reader", 110), node("inspection", 140), node("printer"), node("terminal", 60)],
            [
                edge("source", "reader"), edge("reader", "inspection", label: 170), edge("inspection", "printer"),
                edge("reader", "printer"), edge("printer", "terminal"),
            ],
            [
                .init(id: "bat", memberIds: ["reader", "inspection", "printer"]),
                .init(id: "external", memberIds: ["source", "terminal"]),
            ]
        )
    }

    @Test(arguments: [false, true])
    func batDrawsCleanly(vertical: Bool) {
        let (nodes, edges, groups) = bat
        let layout = GraphLayoutEngine.layout(nodes: nodes, edges: edges, groups: groups, vertical: vertical)
        assertClean(layout, groups: groups)
        let frames = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.frame) })
        let order = ["source", "reader", "inspection", "printer", "terminal"].map {
            vertical ? frames[$0]!.minY : frames[$0]!.minX
        }
        #expect(order == order.sorted())
        #expect(layout.boundaries.map(\.id).sorted() == ["bat", "external#0", "external#1"])
    }

    @Test(arguments: [false, true])
    func overlappingBoundariesStack(vertical: Bool) {
        let nodes = [node("api"), node("queue"), node("worker"), node("db"), node("cache")]
        let edges = [
            edge("api", "queue"), edge("queue", "worker"), edge("api", "cache"), edge("worker", "db"),
            edge("api", "db"), edge("db", "api"),
        ]
        let groups: [GraphLayoutEngine.GroupSpec] = [
            .init(id: "service", memberIds: ["api", "worker"]),
            .init(id: "infra", memberIds: ["queue", "db", "cache"]),
        ]
        let layout = GraphLayoutEngine.layout(nodes: nodes, edges: edges, groups: groups, vertical: vertical)
        assertClean(layout, groups: groups)
        #expect(layout.edges.count == edges.count)
    }

    @Test func labelsGetTheRoomTheyNeed() {
        let wide = GraphLayoutEngine.layout(
            nodes: [node("a"), node("b")], edges: [edge("a", "b", label: 240)], groups: [])
        let frames = Dictionary(uniqueKeysWithValues: wide.nodes.map { ($0.id, $0.frame) })
        #expect(frames["b"]!.minX - frames["a"]!.maxX >= 240)
    }

    private func assertClean(_ layout: ArchDiagramLayout, groups: [GraphLayoutEngine.GroupSpec]) {
        let frames = layout.nodes
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] {
                #expect(!a.frame.intersects(b.frame), "\(a.id) overlaps \(b.id)")
            }
        }
        for boundary in layout.boundaries {
            let base = String(boundary.id.split(separator: "#").first!)
            let members = Set(groups.first { $0.id == base }?.memberIds ?? [])
            for n in frames where !members.contains(n.id) {
                #expect(!boundary.frame.intersects(n.frame), "\(n.id) is inside boundary \(boundary.id)")
            }
        }
        for e in layout.edges {
            let ends = e.id.components(separatedBy: "->")
            for n in frames where !ends.contains(n.id) {
                let box = n.frame.insetBy(dx: 1, dy: 1)
                for (p, q) in zip(e.points, e.points.dropFirst()) {
                    let segment = CGRect(
                        x: min(p.x, q.x), y: min(p.y, q.y), width: abs(p.x - q.x), height: abs(p.y - q.y))
                    #expect(!box.intersects(segment.insetBy(dx: -0.5, dy: -0.5)), "\(e.id) crosses \(n.id)")
                }
            }
            for (p, q) in zip(e.points, e.points.dropFirst()) {
                #expect(abs(p.x - q.x) < 0.5 || abs(p.y - q.y) < 0.5, "\(e.id) has a diagonal segment")
            }
        }
        for n in frames {
            #expect(
                n.frame.minX >= 0 && n.frame.minY >= 0 && n.frame.maxX <= layout.size.width
                    && n.frame.maxY <= layout.size.height)
        }
    }
}
