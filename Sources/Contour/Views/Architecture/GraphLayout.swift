import CoreGraphics

struct ArchDiagramLayout {
    struct PlacedNode: Identifiable {
        var id: String
        var frame: CGRect
    }
    struct PlacedEdge: Identifiable {
        var id: String
        var points: [CGPoint]
        var labelCenter: CGPoint
    }
    struct PlacedBoundary: Identifiable {
        var id: String
        var frame: CGRect
    }
    var nodes: [PlacedNode]
    var edges: [PlacedEdge]
    var boundaries: [PlacedBoundary]
    var size: CGSize

    func node(_ id: String) -> PlacedNode? { nodes.first { $0.id == id } }
}

enum GraphLayoutEngine {
    struct NodeSpec {
        var id: String
        var size: CGSize
    }
    struct EdgeSpec {
        var id: String
        var fromId: String
        var toId: String
        var labelSize: CGSize
    }
    struct GroupSpec {
        var id: String
        var memberIds: [String]
    }

    static let margin: CGFloat = 36
    static let minGap: CGFloat = 104
    static let maxGap: CGFloat = 280
    static let rowGap: CGFloat = 40
    static let bandGap: CGFloat = 36
    static let boundaryPad: CGFloat = 20
    static let boundaryLabelHeight: CGFloat = 26
    static let laneSpacing: CGFloat = 26

    static func layout(nodes: [NodeSpec], edges: [EdgeSpec], groups: [GroupSpec], vertical: Bool) -> ArchDiagramLayout {
        guard vertical else { return layout(nodes: nodes, edges: edges, groups: groups) }
        func flip(_ s: CGSize) -> CGSize { CGSize(width: s.height, height: s.width) }
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.y, y: p.x) }
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minY, y: r.minX, width: r.height, height: r.width) }
        let turned = layout(
            nodes: nodes.map { NodeSpec(id: $0.id, size: flip($0.size)) },
            edges: edges.map { EdgeSpec(id: $0.id, fromId: $0.fromId, toId: $0.toId, labelSize: flip($0.labelSize)) },
            groups: groups
        )
        return ArchDiagramLayout(
            nodes: turned.nodes.map { .init(id: $0.id, frame: flip($0.frame)) },
            edges: turned.edges.map {
                .init(id: $0.id, points: $0.points.map(flip), labelCenter: flip($0.labelCenter))
            },
            boundaries: turned.boundaries.map { b in
                var frame = flip(b.frame)
                frame.origin.y -= boundaryLabelHeight - 8
                frame.size.height += boundaryLabelHeight - 8
                return .init(id: b.id, frame: frame)
            },
            size: flip(turned.size)
        )
    }

    static func bestFit(nodes: [NodeSpec], edges: [EdgeSpec], groups: [GroupSpec], available: CGSize) -> (
        ArchDiagramLayout, CGFloat
    ) {
        func fit(_ l: ArchDiagramLayout) -> CGFloat {
            min(1, available.width / max(l.size.width, 1), available.height / max(l.size.height, 1))
        }
        let across = layout(nodes: nodes, edges: edges, groups: groups, vertical: false)
        guard fit(across) < 1 else { return (across, 1) }
        let down = layout(nodes: nodes, edges: edges, groups: groups, vertical: true)
        return fit(down) > fit(across) * 1.15 ? (down, fit(down)) : (across, fit(across))
    }

    static func layout(nodes: [NodeSpec], edges: [EdgeSpec], groups: [GroupSpec]) -> ArchDiagramLayout {
        guard !nodes.isEmpty else { return ArchDiagramLayout(nodes: [], edges: [], boundaries: [], size: .zero) }
        let index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        let sizes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.size) })
        let live = edges.filter { index[$0.fromId] != nil && index[$0.toId] != nil && $0.fromId != $0.toId }

        var outgoing: [String: [String]] = [:]
        for e in live { outgoing[e.fromId, default: []].append(e.toId) }
        var state: [String: Int] = [:]
        var backEdges = Set<String>()
        func visit(_ id: String) {
            state[id] = 1
            for next in outgoing[id] ?? [] {
                if state[next] == 1 { backEdges.insert("\(id)→\(next)") } else if state[next] == nil { visit(next) }
            }
            state[id] = 2
        }
        for n in nodes where state[n.id] == nil { visit(n.id) }
        let forward = live.filter { !backEdges.contains("\($0.fromId)→\($0.toId)") }
        var layer: [String: Int] = [:]
        func column(_ id: String) -> Int {
            if let l = layer[id] { return l }
            let preds = forward.filter { $0.toId == id }.map(\.fromId)
            let l = preds.isEmpty ? 0 : (preds.map(column).max() ?? 0) + 1
            layer[id] = l
            return l
        }
        for n in nodes { _ = column(n.id) }
        let columnCount = (layer.values.max() ?? 0) + 1

        var groupOf: [String: Int] = [:]
        var blocks: [(id: String?, members: [String])] = []
        for g in groups {
            let members = g.memberIds.filter { index[$0] != nil && groupOf[$0] == nil }
            var runs: [[String]] = []
            for m in members.sorted(by: { (layer[$0] ?? 0, index[$0]!) < (layer[$1] ?? 0, index[$1]!) }) {
                if let last = runs.last?.last, (layer[m] ?? 0) - (layer[last] ?? 0) <= 1 {
                    runs[runs.count - 1].append(m)
                } else {
                    runs.append([m])
                }
            }
            for (i, run) in runs.enumerated() {
                for m in run { groupOf[m] = blocks.count }
                blocks.append((runs.count == 1 ? g.id : "\(g.id)#\(i)", run))
            }
        }
        for n in nodes where groupOf[n.id] == nil {
            groupOf[n.id] = blocks.count
            blocks.append((nil, [n.id]))
        }
        let spans = blocks.map { b -> ClosedRange<Int> in
            let ls = b.members.map { layer[$0] ?? 0 }
            return ls.min()!...ls.max()!
        }

        let blockOrder = blocks.indices.sorted {
            if spans[$0].lowerBound != spans[$1].lowerBound { return spans[$0].lowerBound < spans[$1].lowerBound }
            let a = blocks[$0].members.compactMap { index[$0] }.min() ?? 0
            let b = blocks[$1].members.compactMap { index[$0] }.min() ?? 0
            return a < b
        }
        var bands: [[Int]] = []
        for b in blockOrder {
            if let i = bands.firstIndex(where: { band in band.allSatisfy { !spans[$0].overlaps(spans[b]) } }) {
                bands[i].append(b)
            } else {
                bands.append([b])
            }
        }
        var bandOf: [Int: Int] = [:]
        for (i, band) in bands.enumerated() { for b in band { bandOf[b] = i } }

        var row: [String: Int] = [:]
        for block in blocks {
            var byColumn: [Int: [String]] = [:]
            for m in block.members { byColumn[layer[m] ?? 0, default: []].append(m) }
            for l in byColumn.keys.sorted() {
                var members = byColumn[l]!.sorted { index[$0]! < index[$1]! }
                if l > 0 {
                    func barycenter(_ id: String) -> Double {
                        let rows = live.filter { $0.toId == id }.compactMap { row[$0.fromId] }
                        return rows.isEmpty ? Double(index[id]!) / 1000 : Double(rows.reduce(0, +)) / Double(rows.count)
                    }
                    members.sort { barycenter($0) < barycenter($1) }
                }
                for (r, m) in members.enumerated() { row[m] = r }
            }
        }

        var gapWidth = [CGFloat](repeating: minGap, count: max(columnCount - 1, 0))
        for e in live {
            let a = layer[e.fromId] ?? 0
            let b = layer[e.toId] ?? 0
            if b == a + 1 {
                gapWidth[a] = min(maxGap, max(gapWidth[a], e.labelSize.width + 36))
            }
        }
        var columnWidth = [CGFloat](repeating: 0, count: columnCount)
        for n in nodes { columnWidth[layer[n.id] ?? 0] = max(columnWidth[layer[n.id] ?? 0], n.size.width) }
        var columnX = [CGFloat](repeating: margin + boundaryPad, count: columnCount)
        for l in 1..<max(columnCount, 1) where l < columnCount {
            columnX[l] = columnX[l - 1] + columnWidth[l - 1] + gapWidth[l - 1]
        }

        enum Route {
            case straight, elbow, vertical
            case channel(band: Int, lane: Int)
        }
        var routes: [String: Route] = [:]
        var lanesPerBand: [Int: Int] = [:]
        var elbowsPerGap: [Int: [String]] = [:]
        for e in live {
            let a = layer[e.fromId] ?? 0
            let b = layer[e.toId] ?? 0
            let bandA = bandOf[groupOf[e.fromId]!]!
            let bandB = bandOf[groupOf[e.toId]!]!
            if b == a + 1 {
                let sameRow = bandA == bandB && row[e.fromId] == row[e.toId]
                routes[e.id] = sameRow ? .straight : .elbow
                if !sameRow { elbowsPerGap[a, default: []].append(e.id) }
            } else if a == b, groupOf[e.fromId] == groupOf[e.toId] {
                routes[e.id] = .vertical
            } else {
                let band = max(bandA, bandB)
                let lane = lanesPerBand[band, default: 0]
                lanesPerBand[band] = lane + 1
                routes[e.id] = .channel(band: band, lane: lane)
            }
        }

        var frames: [String: CGRect] = [:]
        var bandBottom: [CGFloat] = []
        var y = margin
        for (i, band) in bands.enumerated() {
            let framed = band.contains { blocks[$0].id != nil }
            let top = y + (framed ? boundaryPad + boundaryLabelHeight : 0)
            let rowCount = band.map { b in blocks[b].members.map { (row[$0] ?? 0) + 1 }.max() ?? 1 }.max() ?? 1
            var rowHeight = [CGFloat](repeating: 0, count: rowCount)
            for b in band {
                for m in blocks[b].members { rowHeight[row[m] ?? 0] = max(rowHeight[row[m] ?? 0], sizes[m]!.height) }
            }
            var rowY = [CGFloat](repeating: top, count: rowCount)
            for r in 1..<max(rowCount, 1) where r < rowCount { rowY[r] = rowY[r - 1] + rowHeight[r - 1] + rowGap }
            for b in band {
                for m in blocks[b].members {
                    let l = layer[m] ?? 0
                    let r = row[m] ?? 0
                    let width = sizes[m]!.width
                    let x = columnX[l] + (columnWidth[l] - width) / 2
                    frames[m] = CGRect(x: x, y: rowY[r], width: width, height: rowHeight[r])
                }
            }
            let bottom = rowY[rowCount - 1] + rowHeight[rowCount - 1] + (framed ? boundaryPad : 0)
            bandBottom.append(bottom)
            let lanes = lanesPerBand[i, default: 0]
            y = bottom + (lanes > 0 ? CGFloat(lanes) * laneSpacing + 12 : 0) + bandGap
        }

        var placedBoundaries: [ArchDiagramLayout.PlacedBoundary] = []
        for block in blocks {
            guard let id = block.id else { continue }
            let rects = block.members.compactMap { frames[$0] }
            let minX = rects.map(\.minX).min()! - boundaryPad
            let maxX = rects.map(\.maxX).max()! + boundaryPad
            let minY = rects.map(\.minY).min()! - boundaryPad - boundaryLabelHeight
            let maxY = rects.map(\.maxY).max()! + boundaryPad
            placedBoundaries.append(
                .init(id: id, frame: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)))
        }

        var placedEdges: [ArchDiagramLayout.PlacedEdge] = []
        for e in live {
            guard let f = frames[e.fromId], let t = frames[e.toId], let route = routes[e.id] else { continue }
            let a = layer[e.fromId] ?? 0
            switch route {
            case .straight:
                let yMid = (f.midY + t.midY) / 2
                let start = CGPoint(x: f.maxX, y: yMid)
                let end = CGPoint(x: t.minX, y: yMid)
                placedEdges.append(
                    .init(
                        id: e.id, points: [start, end],
                        labelCenter: CGPoint(x: (start.x + end.x) / 2, y: yMid)))
            case .elbow:
                let siblings = elbowsPerGap[a] ?? [e.id]
                let k = CGFloat(siblings.firstIndex(of: e.id) ?? 0)
                let gapMid = columnX[a] + columnWidth[a] + gapWidth[a] / 2
                let x = gapMid + (k - CGFloat(siblings.count - 1) / 2) * 14
                let points = [
                    CGPoint(x: f.maxX, y: f.midY), CGPoint(x: x, y: f.midY),
                    CGPoint(x: x, y: t.midY), CGPoint(x: t.minX, y: t.midY),
                ]
                placedEdges.append(
                    .init(id: e.id, points: points, labelCenter: CGPoint(x: x, y: (f.midY + t.midY) / 2)))
            case .vertical:
                let down = t.midY > f.midY
                let start = CGPoint(x: f.midX, y: down ? f.maxY : f.minY)
                let end = CGPoint(x: t.midX, y: down ? t.minY : t.maxY)
                placedEdges.append(
                    .init(
                        id: e.id, points: [start, end],
                        labelCenter: CGPoint(x: start.x, y: (start.y + end.y) / 2)))
            case .channel(let band, let lane):
                let b = layer[e.toId] ?? 0
                let offset = CGFloat(lane) * 8
                let exitX = columnX[a] + columnWidth[a] + 16 + offset
                let entryX = columnX[b] - 16 - offset
                let channelY = bandBottom[band] + 16 + CGFloat(lane) * laneSpacing
                let points = [
                    CGPoint(x: f.maxX, y: f.midY), CGPoint(x: exitX, y: f.midY),
                    CGPoint(x: exitX, y: channelY), CGPoint(x: entryX, y: channelY),
                    CGPoint(x: entryX, y: t.midY), CGPoint(x: t.minX, y: t.midY),
                ]
                placedEdges.append(
                    .init(
                        id: e.id, points: points,
                        labelCenter: CGPoint(x: (exitX + entryX) / 2, y: channelY)))
            }
        }

        let placedNodes = nodes.compactMap { n in frames[n.id].map { ArchDiagramLayout.PlacedNode(id: n.id, frame: $0) }
        }
        var extent = CGRect.null
        for n in placedNodes { extent = extent.union(n.frame) }
        for b in placedBoundaries { extent = extent.union(b.frame) }
        for e in placedEdges {
            for p in e.points { extent = extent.union(CGRect(origin: p, size: .zero)) }
        }
        let size = CGSize(width: extent.maxX + margin, height: extent.maxY + margin)
        return ArchDiagramLayout(nodes: placedNodes, edges: placedEdges, boundaries: placedBoundaries, size: size)
    }
}
