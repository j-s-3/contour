import SwiftUI

/// Layout for the redesigned architecture diagram (§4.3): a deliberately laid-out,
/// left-to-right "direction of travel" diagram, not a force-directed blob. Nodes are
/// layered by how far along the labeled edges they sit (sources on the left, sinks on the
/// right), members of the same boundary are kept vertically contiguous, and boundaries are
/// resolved to container rectangles drawn behind their members. Native Canvas + overlay
/// hit-targets, never an embedded web renderer.
struct ArchDiagramLayout {
    struct PlacedNode: Identifiable {
        var component: ComponentNode
        var frame: CGRect
        var id: String { component.id }
    }
    /// A resolved edge with concrete geometry. `labelPoint` is where the relationship verb
    /// is drawn; `from`/`to` are the anchor points the connector runs between.
    struct PlacedEdge: Identifiable {
        var edge: ArchitectureEdge
        var from: CGPoint
        var to: CGPoint
        var labelPoint: CGPoint
        var id: String { edge.id }
    }
    struct PlacedBoundary: Identifiable {
        var boundary: SystemBoundary
        var frame: CGRect
        var id: String { boundary.id }
    }
    var nodes: [PlacedNode]
    var edges: [PlacedEdge]
    var boundaries: [PlacedBoundary]
    var size: CGSize
}

enum GraphLayoutEngine {
    static let boxWidth: CGFloat = 208
    static let boxHeight: CGFloat = 66
    static let hGap: CGFloat = 116        // wide enough that an edge label fits between columns
    static let vGap: CGFloat = 34
    static let margin: CGFloat = 40
    static let boundaryPad: CGFloat = 18
    static let boundaryLabelH: CGFloat = 22

    /// Lay out `components` along the direction of travel of `edges` (from → to reads
    /// left-to-right), with `boundaries` resolved to container rects behind their members.
    /// The caller passes only the nodes/edges that should currently be visible (filtered by
    /// zoom + Before/After/Delta mode); this engine is otherwise mode-agnostic.
    static func layout(components: [ComponentNode],
                       edges: [ArchitectureEdge],
                       boundaries: [SystemBoundary]) -> ArchDiagramLayout {
        guard !components.isEmpty else {
            return ArchDiagramLayout(nodes: [], edges: [], boundaries: [], size: CGSize(width: 420, height: 220))
        }

        var byId: [String: ComponentNode] = [:]
        for c in components { byId[c.id] = c }

        // Incoming edges per node (only edges whose endpoints are both visible count).
        let liveEdges = edges.filter { byId[$0.fromId] != nil && byId[$0.toId] != nil }
        var incoming: [String: [String]] = [:]
        for e in liveEdges { incoming[e.toId, default: []].append(e.fromId) }

        // Layer = longest path from a source, following edge direction. `visiting` guards
        // against cycles (a back-edge just doesn't deepen the layer).
        var memo: [String: Int] = [:]
        func layer(_ id: String, visiting: Set<String> = []) -> Int {
            if let cached = memo[id] { return cached }
            guard !visiting.contains(id) else { return 0 }
            let ins = (incoming[id] ?? []).filter { byId[$0] != nil }
            guard !ins.isEmpty else { memo[id] = 0; return 0 }
            let l = 1 + (ins.map { layer($0, visiting: visiting.union([id])) }.max() ?? 0)
            memo[id] = l
            return l
        }

        // Keep members of the same boundary adjacent within a column so the container rect
        // stays tight. boundaryRank orders columns' rows by first-owning-boundary.
        var boundaryRank: [String: Int] = [:]
        for (i, b) in boundaries.enumerated() {
            for cid in b.componentIds where boundaryRank[cid] == nil { boundaryRank[cid] = i }
        }
        let originalIndex: [String: Int] = Dictionary(uniqueKeysWithValues: components.enumerated().map { ($1.id, $0) })

        var layers: [Int: [ComponentNode]] = [:]
        for c in components { layers[layer(c.id), default: []].append(c) }
        for key in layers.keys {
            layers[key]?.sort {
                let ra = boundaryRank[$0.id] ?? Int.max, rb = boundaryRank[$1.id] ?? Int.max
                if ra != rb { return ra < rb }
                return (originalIndex[$0.id] ?? 0) < (originalIndex[$1.id] ?? 0)
            }
        }

        var frameById: [String: CGRect] = [:]
        var placed: [ArchDiagramLayout.PlacedNode] = []
        let sortedKeys = layers.keys.sorted()
        var maxBottom: CGFloat = 0
        let topInset = margin + boundaryLabelH

        for key in sortedKeys {
            let column = layers[key] ?? []
            let x = margin + CGFloat(key) * (boxWidth + hGap)
            var y = topInset
            for node in column {
                let frame = CGRect(x: x, y: y, width: boxWidth, height: boxHeight)
                placed.append(.init(component: node, frame: frame))
                frameById[node.id] = frame
                y += boxHeight + vGap
            }
            maxBottom = max(maxBottom, y)
        }

        // Resolve boundary rectangles from member frames.
        var placedBoundaries: [ArchDiagramLayout.PlacedBoundary] = []
        for b in boundaries {
            let memberFrames = b.componentIds.compactMap { frameById[$0] }
            guard !memberFrames.isEmpty else { continue }
            let minX = memberFrames.map(\.minX).min()! - boundaryPad
            let minY = memberFrames.map(\.minY).min()! - boundaryPad - boundaryLabelH
            let maxX = memberFrames.map(\.maxX).max()! + boundaryPad
            let maxY = memberFrames.map(\.maxY).max()! + boundaryPad
            placedBoundaries.append(.init(boundary: b, frame: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)))
        }

        // Resolve edge geometry. Anchor on the side that faces the target so arrows read
        // as travel; a backward/same-column edge still connects sensibly center-to-center.
        var placedEdges: [ArchDiagramLayout.PlacedEdge] = []
        for e in liveEdges {
            guard let f = frameById[e.fromId], let t = frameById[e.toId] else { continue }
            let from: CGPoint, to: CGPoint
            if t.minX >= f.maxX - 1 {                 // target is to the right
                from = CGPoint(x: f.maxX, y: f.midY)
                to = CGPoint(x: t.minX, y: t.midY)
            } else if f.minX >= t.maxX - 1 {          // target is to the left (back-edge)
                from = CGPoint(x: f.minX, y: f.midY)
                to = CGPoint(x: t.maxX, y: t.midY)
            } else {                                  // same column: connect vertically
                let goingDown = t.midY >= f.midY
                from = CGPoint(x: f.midX, y: goingDown ? f.maxY : f.minY)
                to = CGPoint(x: t.midX, y: goingDown ? t.minY : t.maxY)
            }
            let labelPoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 - 9)
            placedEdges.append(.init(edge: e, from: from, to: to, labelPoint: labelPoint))
        }

        let width = margin * 2 + CGFloat(sortedKeys.count) * boxWidth + CGFloat(max(sortedKeys.count - 1, 0)) * hGap
        let size = CGSize(width: max(width, 460), height: max(maxBottom + margin, 260))
        return ArchDiagramLayout(nodes: placed, edges: placedEdges, boundaries: placedBoundaries, size: size)
    }
}
