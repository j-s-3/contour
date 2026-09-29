import CoreGraphics
import Testing

@testable import Contour

struct GraphLayoutEngineTests {
    private func node(_ id: String, width: CGFloat = 200, height: CGFloat = 80) -> GraphLayoutEngine.NodeSpec {
        .init(id: id, size: CGSize(width: width, height: height))
    }
    private func edge(
        _ from: String, _ to: String, label: CGFloat = 60, id: String? = nil
    ) -> GraphLayoutEngine.EdgeSpec {
        .init(id: id ?? "\(from)->\(to)", fromId: from, toId: to, labelSize: CGSize(width: label, height: 20))
    }
    private func frames(_ layout: ArchDiagramLayout) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.frame) })
    }

    @Test func emptyGraphLaysOutToNothing() {
        let layout = GraphLayoutEngine.layout(nodes: [], edges: [], groups: [], vertical: true)
        #expect(layout.nodes.isEmpty)
        #expect(layout.edges.isEmpty)
        #expect(layout.boundaries.isEmpty)
        #expect(layout.size == .zero)
    }

    @Test func singleNodeSitsAtTheMargin() {
        let layout = GraphLayoutEngine.layout(nodes: [node("solo")], edges: [], groups: [])
        let frame = frames(layout)["solo"]!
        #expect(frame.minX == GraphLayoutEngine.margin + GraphLayoutEngine.boundaryPad)
        #expect(frame.minY == GraphLayoutEngine.margin)
        #expect(layout.size.width == frame.maxX + GraphLayoutEngine.margin)
        #expect(layout.size.height == frame.maxY + GraphLayoutEngine.margin)
    }

    @Test func selfLoopsAndDanglingEdgesAreDropped() {
        let layout = GraphLayoutEngine.layout(
            nodes: [node("a"), node("b")],
            edges: [edge("a", "a"), edge("a", "ghost"), edge("ghost", "b"), edge("a", "b")],
            groups: [])
        #expect(layout.edges.map(\.id) == ["a->b"])
    }

    @Test func adjacentColumnsInTheSameRowConnectStraight() {
        let layout = GraphLayoutEngine.layout(nodes: [node("a"), node("b")], edges: [edge("a", "b")], groups: [])
        let placed = frames(layout)
        let route = layout.edges[0]
        #expect(route.points.count == 2)
        #expect(route.points[0].x == placed["a"]!.maxX)
        #expect(route.points[1].x == placed["b"]!.minX)
        #expect(route.points[0].y == route.points[1].y)
        #expect(route.labelCenter.x == (route.points[0].x + route.points[1].x) / 2)
    }

    @Test func fanOutBendsTheOffRowEdgeThroughAnElbow() {
        let layout = GraphLayoutEngine.layout(
            nodes: [node("a"), node("b"), node("c")], edges: [edge("a", "b"), edge("a", "c")], groups: [])
        let elbows = layout.edges.filter { $0.points.count == 4 }
        #expect(elbows.count == 1)
        let bend = elbows[0]
        #expect(bend.points[1].x == bend.points[2].x)
        #expect(bend.labelCenter.x == bend.points[1].x)
        let placed = frames(layout)
        #expect(bend.points[1].x > placed["a"]!.maxX)
        #expect(bend.points[2].x < placed["c"]!.minX)
    }

    @Test func severalElbowsInOneGapAreOffsetFromEachOther() {
        let layout = GraphLayoutEngine.layout(
            nodes: [node("a"), node("b"), node("c"), node("d")],
            edges: [edge("a", "c"), edge("b", "c"), edge("a", "d"), edge("b", "d")],
            groups: [])
        let elbows = layout.edges.filter { $0.points.count == 4 }
        #expect(elbows.count >= 2)
        #expect(Set(elbows.map { $0.points[1].x }).count == elbows.count)
    }

    @Test func wideLabelsWidenTheirGapUpToTheMaximum() {
        let wide = GraphLayoutEngine.layout(
            nodes: [node("a"), node("b")], edges: [edge("a", "b", label: 1000)], groups: [])
        let wideFrames = frames(wide)
        #expect(wideFrames["b"]!.minX - wideFrames["a"]!.maxX == GraphLayoutEngine.maxGap)

        let narrow = GraphLayoutEngine.layout(
            nodes: [node("a"), node("b")], edges: [edge("a", "b", label: 1)], groups: [])
        let narrowFrames = frames(narrow)
        #expect(narrowFrames["b"]!.minX - narrowFrames["a"]!.maxX == GraphLayoutEngine.minGap)
    }

    @Test func cyclesAreBrokenSoEveryNodeStillPlaces() {
        let layout = GraphLayoutEngine.layout(
            nodes: [node("a"), node("b"), node("c")],
            edges: [edge("a", "b"), edge("b", "c"), edge("c", "a")],
            groups: [])
        #expect(layout.nodes.count == 3)
        #expect(layout.edges.count == 3)
        let placed = frames(layout)
        #expect(placed["a"]!.minX < placed["b"]!.minX)
        #expect(placed["b"]!.minX < placed["c"]!.minX)
        let back = layout.edges.first { $0.id == "c->a" }!
        #expect(back.points.count == 6)
    }

    @Test func skippingAColumnRoutesEachEdgeThroughItsOwnChannelBelowTheBand() {
        let layout = GraphLayoutEngine.layout(
            nodes: [node("a"), node("b"), node("c")],
            edges: [
                edge("a", "b"), edge("b", "c"), edge("a", "c", id: "skip-1"), edge("a", "c", id: "skip-2"),
            ],
            groups: [])
        let channels = layout.edges.filter { $0.points.count == 6 }
        #expect(channels.count == 2)
        let placed = frames(layout)
        for channel in channels {
            #expect(channel.points[2].y > placed["a"]!.maxY)
        }
        #expect(channels[0].points[2].y != channels[1].points[2].y)
        #expect(channels[0].points[1].x != channels[1].points[1].x)
    }

    @Test func groupsSplitIntoSeparateBoundariesWhenTheirMembersAreNotAdjacent() {
        let nodes = [node("a"), node("b"), node("c"), node("d")]
        let edges = [edge("a", "b"), edge("b", "c"), edge("c", "d")]
        let groups: [GraphLayoutEngine.GroupSpec] = [
            .init(id: "ends", memberIds: ["a", "d"]),
            .init(id: "ghosted", memberIds: ["a", "phantom"]),
        ]
        let layout = GraphLayoutEngine.layout(nodes: nodes, edges: edges, groups: groups)
        #expect(layout.boundaries.map(\.id).sorted() == ["ends#0", "ends#1"])
        for boundary in layout.boundaries {
            #expect(boundary.frame.width > 0 && boundary.frame.height > 0)
        }
    }

    @Test func verticalLayoutTransposesTheHorizontalOne() {
        let nodes = [node("a", width: 200, height: 60), node("b", width: 120, height: 90)]
        let edges = [edge("a", "b")]
        let groups: [GraphLayoutEngine.GroupSpec] = [.init(id: "g", memberIds: ["a"])]
        let across = GraphLayoutEngine.layout(nodes: nodes, edges: edges, groups: groups, vertical: false)
        let down = GraphLayoutEngine.layout(nodes: nodes, edges: edges, groups: groups, vertical: true)
        let acrossFrames = frames(across)
        let downFrames = frames(down)
        #expect(downFrames["a"]!.minY < downFrames["b"]!.minY)
        #expect(downFrames["a"]!.width == 200)
        #expect(downFrames["a"]!.height == 60)
        #expect(acrossFrames["a"]!.minX < acrossFrames["b"]!.minX)
        #expect(down.edges[0].points.count == across.edges[0].points.count)
        #expect(down.boundaries.count == 1)
    }

    @Test func bestFitKeepsTheHorizontalLayoutWhenItFits() {
        let (layout, scale) = GraphLayoutEngine.bestFit(
            nodes: [node("a"), node("b")], edges: [edge("a", "b")], groups: [],
            available: CGSize(width: 5000, height: 5000))
        #expect(scale == 1)
        let placed = frames(layout)
        #expect(placed["a"]!.minX < placed["b"]!.minX)
    }

    @Test func bestFitTurnsALongChainDownWhenTheAreaIsNarrow() {
        let nodes = (0..<6).map { node("n\($0)", width: 200, height: 40) }
        let edges = (0..<5).map { edge("n\($0)", "n\($0 + 1)") }
        let (layout, scale) = GraphLayoutEngine.bestFit(
            nodes: nodes, edges: edges, groups: [], available: CGSize(width: 400, height: 2000))
        let placed = frames(layout)
        #expect(placed["n0"]!.minY < placed["n5"]!.minY)
        #expect(scale > 0 && scale <= 1)
    }

    @Test func bestFitStaysAcrossWhenTurningDownIsNoBetter() {
        let nodes = [node("a", width: 300, height: 300), node("b", width: 300, height: 300)]
        let (layout, scale) = GraphLayoutEngine.bestFit(
            nodes: nodes, edges: [edge("a", "b")], groups: [], available: CGSize(width: 100, height: 100))
        let placed = frames(layout)
        #expect(placed["a"]!.minX < placed["b"]!.minX)
        #expect(scale < 1)
    }
}
