import Foundation

enum ArchAnchor: Hashable {
    case node(String)
    case edge(String)
}

struct ArchLevelEdge: Hashable, Identifiable {
    var edge: ArchitectureEdge
    var fromId: String
    var toId: String
    var mergedIds: [String] = []
    var id: String { edge.id }
}

struct ArchLevel {
    var focus: ComponentNode?
    var primary: [ComponentNode]
    var context: [ComponentNode]
    var edges: [ArchLevelEdge]
    var boundaries: [SystemBoundary]

    var nodes: [ComponentNode] { primary + context }
    func contains(_ id: String) -> Bool { nodes.contains { $0.id == id } }
}

extension PRGraph {
    var architectureParts: [ComponentNode] {
        components.filter { $0.level != .implementation }
    }

    var topLevelParts: [ComponentNode] {
        let ids = Set(architectureParts.map(\.id))
        return architectureParts.filter { c in
            guard let parent = c.parentId else { return true }
            return !ids.contains(parent)
        }
    }

    func parts(inside id: String) -> [ComponentNode] {
        architectureParts.filter { $0.parentId == id }
    }

    func ancestry(of id: String) -> [ComponentNode] {
        var chain: [ComponentNode] = []
        var seen = Set<String>()
        var current = component(id)
        while let c = current, seen.insert(c.id).inserted {
            chain.insert(c, at: 0)
            current = c.parentId.flatMap(component)
        }
        return chain
    }

    func subtreeIds(of id: String) -> Set<String> {
        var out: Set<String> = [id]
        var frontier = [id]
        while let next = frontier.popLast() {
            for child in components where child.parentId == next && out.insert(child.id).inserted {
                frontier.append(child.id)
            }
        }
        return out
    }

    func drawablePart(for id: String) -> ComponentNode? {
        ancestry(of: id).last { $0.level != .implementation }
            ?? implementationOwner(of: id)
    }

    private func implementationOwner(of id: String) -> ComponentNode? {
        guard let impl = component(id) else { return nil }
        return architectureParts.first {
            $0.implementedBy.contains { $0.caseInsensitiveCompare(impl.title) == .orderedSame }
        }
            ?? impl.dependsOnIds.lazy.compactMap(component).first { $0.level != .implementation }
    }

    func implementation(of id: String) -> (nodes: [ComponentNode], names: [String]) {
        guard let part = component(id) else { return ([], []) }
        var nodes = components.filter { $0.level == .implementation && $0.parentId == id }
        if nodes.isEmpty {
            nodes = implementationComponents(for: id).filter { $0.parentId == nil || $0.parentId == id }
        }
        let named = Set(nodes.map { $0.title.lowercased() })
        return (nodes, part.implementedBy.filter { !named.contains($0.lowercased()) })
    }

    func architectureLevel(path: [String]) -> ArchLevel {
        let focus = path.last.flatMap(component)
        let primary = focus.map { parts(inside: $0.id) } ?? topLevelParts
        let primaryIds = Set(primary.map(\.id))
        let pathIds = Set(path)

        func representative(_ id: String) -> String? {
            guard let owner = drawablePart(for: id) else { return nil }
            return ancestry(of: owner.id).first { !pathIds.contains($0.id) }?.id
        }

        let innerEdges = resolvedEdges.compactMap { e -> (String, String)? in
            guard let f = representative(e.fromId), let t = representative(e.toId),
                primaryIds.contains(f), primaryIds.contains(t), f != t
            else { return nil }
            return (f, t)
        }
        let entry = primary.first { p in !innerEdges.contains { $0.1 == p.id } }?.id ?? primary.first?.id
        let exit = primary.last { p in !innerEdges.contains { $0.0 == p.id } }?.id ?? primary.last?.id

        var byPair: [String: ArchLevelEdge] = [:]
        var order: [String] = []
        for e in resolvedEdges {
            var from = representative(e.fromId)
            var to = representative(e.toId)
            if focus != nil {
                if from == nil, e.fromId == focus?.id { from = exit }
                if to == nil, e.toId == focus?.id { to = entry }
            }
            guard let f = from, let t = to, f != t else { continue }
            if focus != nil, !primaryIds.contains(f), !primaryIds.contains(t) { continue }
            let key = "\(f)→\(t)"
            if var existing = byPair[key] {
                existing.mergedIds.append(e.id)
                if e.change.priority > existing.edge.change.priority {
                    existing.mergedIds.append(existing.edge.id)
                    existing.mergedIds.removeAll { $0 == e.id }
                    existing.edge = e
                }
                byPair[key] = existing
            } else {
                byPair[key] = ArchLevelEdge(edge: e, fromId: f, toId: t)
                order.append(key)
            }
        }
        let edges = order.compactMap { byPair[$0] }

        let connected = Set(edges.flatMap { [$0.fromId, $0.toId] })
        let context =
            focus == nil
            ? []
            : connected.subtracting(primaryIds).compactMap(component)
                .sorted { (components.firstIndex(of: $0) ?? 0) < (components.firstIndex(of: $1) ?? 0) }

        let visible = primaryIds.union(context.map(\.id))
        let drawnBoundaries: [SystemBoundary]
        if let focus {
            drawnBoundaries = [
                SystemBoundary(
                    id: "focus:\(focus.id)", label: focus.title, kind: .application,
                    componentIds: primary.map(\.id))
            ]
        } else {
            drawnBoundaries = boundaries.compactMap { b in
                let members = unique(b.componentIds.compactMap(representative)).filter(visible.contains)
                return members.isEmpty
                    ? nil : SystemBoundary(id: b.id, label: b.label, kind: b.kind, componentIds: members)
            }
        }
        return ArchLevel(focus: focus, primary: primary, context: context, edges: edges, boundaries: drawnBoundaries)
    }

    func architecturePath(showing id: String) -> [String] {
        guard let part = drawablePart(for: id) else { return [] }
        return ancestry(of: part.id).dropLast().map(\.id)
    }

    func flows(through id: String) -> [FlowNode] {
        let ids = subtreeIds(of: id)
        return flows.filter { f in f.steps.contains { $0.componentId.map(ids.contains) ?? false } }
    }

    func decisions(within id: String) -> [DecisionNode] {
        let ids = subtreeIds(of: id)
        let hits = decisions.filter { !Set($0.componentIds).isDisjoint(with: ids) }
        let primary = Set(decisionsToReview.map(\.id))
        return hits.filter { primary.contains($0.id) } + hits.filter { !primary.contains($0.id) }
    }

    func decisionAnchors(on level: ArchLevel) -> [ArchAnchor: [DecisionNode]] {
        var out: [ArchAnchor: [DecisionNode]] = [:]
        for d in decisionsToReview {
            guard let anchor = anchor(for: d.componentIds, explicitEdges: edgeIds(embodying: d), on: level) else {
                continue
            }
            out[anchor, default: []].append(d)
        }
        return out
    }

    func questionAnchors(on level: ArchLevel) -> [ArchAnchor: [Consideration]] {
        var out: [ArchAnchor: [Consideration]] = [:]
        for item in thingsToThinkAbout {
            let decisionParts = item.relatedIds.compactMap(decision).flatMap(\.componentIds)
            let parts = item.relatedIds.filter { component($0) != nil } + decisionParts
            let edges = item.relatedIds.filter { id in resolvedEdges.contains { $0.id == id } }
            guard let anchor = anchor(for: parts, explicitEdges: edges, on: level) else { continue }
            out[anchor, default: []].append(item)
        }
        return out
    }

    private func edgeIds(embodying d: DecisionNode) -> [String] {
        resolvedEdges.filter { $0.decisionIds.contains(d.id) }.map(\.id)
    }

    private func anchor(for componentIds: [String], explicitEdges: [String], on level: ArchLevel) -> ArchAnchor? {
        for id in explicitEdges {
            if let drawn = level.edges.first(where: { $0.id == id || $0.mergedIds.contains(id) }) {
                return .edge(drawn.id)
            }
        }
        let drawn = unique(
            componentIds.compactMap { id in
                ancestry(of: drawablePart(for: id)?.id ?? id).first { level.contains($0.id) }?.id
            })
        if drawn.count >= 2,
            let edge = level.edges.first(where: { drawn.contains($0.fromId) && drawn.contains($0.toId) })
        {
            return .edge(edge.id)
        }
        return drawn.first.map { .node($0) }
    }
}

extension EdgeChange {
    var priority: Int {
        switch self {
        case .new: return 3
        case .changed: return 2
        case .removed: return 1
        case .existing: return 0
        }
    }
}
