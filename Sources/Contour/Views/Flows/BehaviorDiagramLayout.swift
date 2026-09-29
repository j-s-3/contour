import CoreGraphics
import Foundation

struct BehaviorDiagramLayout {
    struct PlacedNode: Identifiable {
        var node: FlowBehaviorNode
        var frame: CGRect
        var id: String { node.id }
    }
    struct PlacedEdge: Identifiable {
        var edge: FlowBehaviorEdge
        var points: [CGPoint]
        var labelPoint: CGPoint?
        var id: String { edge.id }
    }
    struct PlacedAnnotation: Identifiable {
        var annotation: FlowAnnotation
        var frame: CGRect
        var id: String { annotation.id }
    }
    struct PlacedOverflow: Identifiable {
        var nodeId: String
        var count: Int
        var frame: CGRect
        var id: String { nodeId }
    }
    struct PlacedBoundary: Identifiable {
        var boundary: FlowBoundary
        var frame: CGRect
        var id: String { boundary.id }
    }

    var nodes: [PlacedNode] = []
    var edges: [PlacedEdge] = []
    var annotations: [PlacedAnnotation] = []
    var overflow: [PlacedOverflow] = []
    var boundaries: [PlacedBoundary] = []
    var size: CGSize = .zero

    func node(_ id: String) -> PlacedNode? { nodes.first { $0.id == id } }
}

enum BehaviorDiagramLayoutEngine {
    static let nodeWidth: CGFloat = 232
    static let columnGap: CGFloat = 56
    static var columnWidth: CGFloat { nodeWidth + columnGap }
    static let noteInset: CGFloat = 34
    static let annotationWidth: CGFloat = columnWidth - noteInset
    static let maxAnnotationWidth: CGFloat = 420
    static let margin: CGFloat = 28
    static let labelBand: CGFloat = 30
    static let minLayerGap: CGFloat = 60
    static let maxNotesPerStage = 3
    static let roomyWidth: CGFloat = 1200
    static let overflowHeight: CGFloat = 20

    static func layout(
        _ behavior: FlowBehavior, mode: DiagramMode, annotations: [FlowAnnotation],
        availableWidth: CGFloat? = nil
    ) -> BehaviorDiagramLayout {
        let nodes = behavior.nodes
        guard !nodes.isEmpty else { return BehaviorDiagramLayout() }
        let index = Dictionary(nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let forward = forwardEdges(behavior)
        let layer = layers(nodes, forward: forward)
        let layerCount = (layer.values.max() ?? 0) + 1

        var rows: [[String]] = Array(repeating: [], count: layerCount)
        for n in nodes { rows[layer[n.id]!].append(n.id) }
        var column: [String: CGFloat] = [:]
        for (l, row) in rows.enumerated() {
            if l == 0 {
                for (i, id) in row.enumerated() { column[id] = CGFloat(i) }
                continue
            }
            let desired: [(String, CGFloat)] = row.map { id in
                let parents = forward.filter { $0.toId == id }.compactMap { column[$0.fromId] }
                let x = parents.isEmpty ? (column.values.max() ?? 0) + 1 : parents.reduce(0, +) / CGFloat(parents.count)
                return (id, x)
            }
            .sorted { $0.1 == $1.1 ? index[$0.0]! < index[$1.0]! : $0.1 < $1.1 }
            var placed: [CGFloat] = []
            for (_, x) in desired { placed.append(placed.last.map { max(x, $0 + 1) } ?? x) }
            let shift = (desired.map(\.1).reduce(0, +) - placed.reduce(0, +)) / CGFloat(placed.count)
            for (i, (id, _)) in desired.enumerated() { column[id] = placed[i] + shift }
            rows[l] = desired.map(\.0)
        }
        let hasBackEdges = behavior.edges.count > forward.count
        let leftGutter: CGFloat = hasBackEdges ? 40 : 0
        let minColumn = column.values.min() ?? 0
        let span = (column.values.max() ?? 0) - minColumn

        let grouped = Dictionary(grouping: annotations, by: \.nodeId)
        let cap = (availableWidth ?? 0) >= roomyWidth ? Int.max : maxNotesPerStage
        let byNode = grouped.mapValues { Array($0.prefix(cap)) }
        let hidden = grouped.mapValues { max(0, $0.count - cap) }

        var noteWidth = annotationWidth
        if let availableWidth, !annotations.isEmpty {
            let fixed = 2 * margin + leftGutter + nodeWidth / 2 + 14 - noteInset
            let fitted = (availableWidth - fixed) / (span + 1) - noteInset
            noteWidth = min(maxAnnotationWidth, max(annotationWidth, fitted))
        }
        let pitch = noteWidth + noteInset
        let heights = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, height(of: $0, mode: mode)) })

        var tops: [CGFloat] = []
        var y = margin
        for row in rows {
            tops.append(y)
            let rowHeight = row.map { heights[$0]! }.max() ?? 0
            let notes =
                row.map {
                    stackHeight(byNode[$0] ?? [], width: noteWidth)
                        + (hidden[$0, default: 0] > 0 ? overflowHeight + 6 : 0)
                }.max() ?? 0
            let gap = max(minLayerGap, notes > 0 ? 12 + notes + 10 + labelBand : 0)
            y += rowHeight + gap
        }

        var out = BehaviorDiagramLayout()
        var frames: [String: CGRect] = [:]
        for n in nodes {
            let l = layer[n.id]!
            let x = margin + leftGutter + (column[n.id]! - minColumn) * pitch
            let frame = CGRect(x: x, y: tops[l], width: nodeWidth, height: heights[n.id]!)
            frames[n.id] = frame
            out.nodes.append(.init(node: n, frame: frame))
        }

        for n in nodes {
            guard let notes = byNode[n.id], let frame = frames[n.id] else { continue }
            var noteY = frame.maxY + 12
            for note in notes {
                let h = height(of: note, width: noteWidth)
                out.annotations.append(
                    .init(
                        annotation: note,
                        frame: CGRect(x: frame.midX + 14, y: noteY, width: noteWidth, height: h)))
                noteY += h + 6
            }
            if let count = hidden[n.id], count > 0 {
                out.overflow.append(
                    .init(
                        nodeId: n.id, count: count,
                        frame: CGRect(x: frame.midX + 14, y: noteY, width: noteWidth, height: overflowHeight)))
            }
        }

        let forwardIds = Set(forward.map(\.id))
        let leftLane = margin + leftGutter / 2
        for edge in behavior.edges {
            guard let a = frames[edge.fromId], let b = frames[edge.toId] else { continue }
            var points: [CGPoint]
            if forwardIds.contains(edge.id) {
                let bar = b.minY - labelBand
                let between = out.nodes.filter {
                    let l = layer[$0.id]!
                    return l > layer[edge.fromId]! && l < layer[edge.toId]! && $0.frame.minX - 8 < a.midX
                        && a.midX < $0.frame.maxX + 8
                }
                if between.isEmpty {
                    points = [
                        CGPoint(x: a.midX, y: a.maxY), CGPoint(x: a.midX, y: bar),
                        CGPoint(x: b.midX, y: bar), CGPoint(x: b.midX, y: b.minY),
                    ]
                } else {
                    let exit = a.maxY + 6
                    let obstacles =
                        out.nodes.filter { $0.id != edge.fromId && $0.id != edge.toId }.map(\.frame)
                        + out.annotations.map(\.frame) + out.overflow.map(\.frame)
                    let lane = detourLane(from: a.midX, exit: exit, bar: bar, to: b.midX, avoiding: obstacles)
                    points = [
                        CGPoint(x: a.midX, y: a.maxY), CGPoint(x: a.midX, y: exit), CGPoint(x: lane, y: exit),
                        CGPoint(x: lane, y: bar), CGPoint(x: b.midX, y: bar), CGPoint(x: b.midX, y: b.minY),
                    ]
                }
            } else {
                points = [
                    CGPoint(x: a.minX, y: a.midY), CGPoint(x: leftLane, y: a.midY),
                    CGPoint(x: leftLane, y: b.midY), CGPoint(x: b.minX, y: b.midY),
                ]
            }
            points = simplified(points)
            let label = edge.label.map { _ in CGPoint(x: b.midX, y: b.minY - labelBand / 2) }
            out.edges.append(.init(edge: edge, points: points, labelPoint: forwardIds.contains(edge.id) ? label : nil))
        }

        for boundary in behavior.boundaries {
            let members = nodes.filter { $0.boundaryId == boundary.id }.compactMap { frames[$0.id] }
            guard let first = members.first else { continue }
            let union = members.dropFirst().reduce(first) { $0.union($1) }
            out.boundaries.append(
                .init(
                    boundary: boundary,
                    frame: CGRect(
                        x: union.minX - 16, y: union.minY - 30,
                        width: union.width + 32, height: union.height + 46)))
        }

        let extents = out.nodes.map(\.frame) + out.annotations.map(\.frame) + out.boundaries.map(\.frame)
        let maxX = max(extents.map(\.maxX).max() ?? 0, out.edges.flatMap(\.points).map(\.x).max() ?? 0)
        let maxY = extents.map(\.maxY).max() ?? 0
        out.size = CGSize(width: maxX + margin, height: maxY + margin)
        return out
    }

    private static func forwardEdges(_ behavior: FlowBehavior) -> [FlowBehaviorEdge] {
        var state: [String: Int] = [:]
        var back: Set<String> = []
        func visit(_ id: String) {
            state[id] = 1
            for e in behavior.outgoing(id) {
                switch state[e.toId] {
                case 1: back.insert(e.id)
                case nil: visit(e.toId)
                default: break
                }
            }
            state[id] = 2
        }
        let targets = Set(behavior.edges.map(\.toId))
        for n in behavior.nodes where !targets.contains(n.id) && state[n.id] == nil { visit(n.id) }
        for n in behavior.nodes where state[n.id] == nil { visit(n.id) }
        return behavior.edges.filter { !back.contains($0.id) }
    }

    private static func layers(_ nodes: [FlowBehaviorNode], forward: [FlowBehaviorEdge])
        -> [String: Int]
    {
        var layer: [String: Int] = [:]
        var indegree = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, 0) })
        for e in forward { indegree[e.toId, default: 0] += 1 }
        var queue = nodes.filter { indegree[$0.id] == 0 }.map(\.id)
        for id in queue { layer[id] = 0 }
        while !queue.isEmpty {
            let id = queue.removeFirst()
            for e in forward where e.fromId == id {
                layer[e.toId] = max(layer[e.toId] ?? 0, layer[id]! + 1)
                indegree[e.toId]! -= 1
                if indegree[e.toId] == 0 { queue.append(e.toId) }
            }
        }
        for n in nodes where layer[n.id] == nil { layer[n.id] = 0 }
        return layer
    }

    private static func detourLane(
        from start: CGFloat, exit: CGFloat, bar: CGFloat, to end: CGFloat,
        avoiding obstacles: [CGRect]
    ) -> CGFloat {
        let clearance: CGFloat = 32
        let padded = obstacles.map { $0.insetBy(dx: -clearance / 2, dy: -3) }
        func blocked(_ lane: CGFloat) -> [CGRect] {
            let segments = [
                CGRect(x: min(start, lane), y: exit, width: abs(start - lane), height: 0),
                CGRect(x: lane, y: exit, width: 0, height: bar - exit),
                CGRect(x: min(lane, end), y: bar, width: abs(lane - end), height: 0),
            ]
            return padded.filter { r in segments.contains { $0.insetBy(dx: -0.5, dy: -0.5).intersects(r) } }
        }
        func search(_ direction: CGFloat) -> CGFloat? {
            var lane = start
            for _ in 0..<(obstacles.count + 1) {
                let hits = blocked(lane)
                if hits.isEmpty { return lane }
                let next = direction > 0 ? hits.map(\.maxX).max()! + 1 : hits.map(\.minX).min()! - 1
                guard direction > 0 ? next > lane : next < lane else { return nil }
                lane = next
            }
            return nil
        }
        let left = search(-1).flatMap { $0 >= margin / 2 ? $0 : nil }
        let right = search(1)
        switch (left, right) {
        case (let l?, let r?): return start - l <= r - start ? l : r
        case (let l?, nil): return l
        case (nil, let r?): return r
        case (nil, nil):
            return (obstacles.map(\.maxX).max() ?? start) + clearance
        }
    }

    private static func simplified(_ points: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for p in points {
            if let last = out.last, abs(last.x - p.x) < 0.5, abs(last.y - p.y) < 0.5 { continue }
            if out.count >= 2 {
                let a = out[out.count - 2]
                let b = out[out.count - 1]
                let collinear =
                    (abs(a.x - b.x) < 0.5 && abs(b.x - p.x) < 0.5) || (abs(a.y - b.y) < 0.5 && abs(b.y - p.y) < 0.5)
                if collinear {
                    out[out.count - 1] = p
                    continue
                }
            }
            out.append(p)
        }
        return out
    }

    static func lines(_ text: String, perLine: Int, max cap: Int) -> Int {
        min(cap, max(1, Int((Double(text.count) / Double(perLine)).rounded(.up))))
    }

    static func height(of node: FlowBehaviorNode, mode: DiagramMode) -> CGFloat {
        if node.kind == .trigger { return 26 + CGFloat(lines(node.label, perLine: 22, max: 2)) * 18 }
        var h: CGFloat = 22 + CGFloat(lines(node.label, perLine: 28, max: 3)) * 19
        if [.external, .datastore, .subflow].contains(node.kind) { h += 16 }
        if node.change == .changed {
            switch mode {
            case .delta where node.before != nil || node.after != nil: h += 44
            case .before where node.before != nil: h += 18
            case .after where node.after != nil: h += 18
            default: break
            }
        }
        if mode == .delta && node.change != .existing { h += 4 }
        return h
    }

    static func height(of note: FlowAnnotation, width: CGFloat = annotationWidth) -> CGFloat {
        20 + CGFloat(lines(note.text, perLine: max(20, Int((width - 16) / 6)), max: 3)) * 16
    }

    static func stackHeight(_ notes: [FlowAnnotation], width: CGFloat = annotationWidth) -> CGFloat {
        guard !notes.isEmpty else { return 0 }
        return notes.map { height(of: $0, width: width) }.reduce(0, +) + CGFloat(notes.count - 1) * 6
    }
}
