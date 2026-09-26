import Foundation

// MARK: - The architecture drawing at one zoom level (§4.3)
//
// Architecture is drawn one level at a time: the system's top-level parts, or the parts
// inside one of them. Parts and relationships in the graph can sit at any depth, so a level
// is a projection — every node and edge is represented by its visible ancestor, edges that
// end up inside one box disappear, and parallel edges collapse into the most important one.
// That lets the model attach an arrow to the sub-part it really enters while the zoomed-out
// drawing still shows a single arrow between the two top-level boxes.

/// Where a review question or decision sits on the drawing.
enum ArchAnchor: Hashable {
    case node(String)
    case edge(String)
}

/// One relationship as drawn at a level: the graph edge it stands for, re-pointed at the
/// visible boxes.
struct ArchLevelEdge: Hashable, Identifiable {
    var edge: ArchitectureEdge
    var fromId: String
    var toId: String
    /// Other graph edges folded into this arrow.
    var mergedIds: [String] = []
    var id: String { edge.id }
}

/// What the Architecture lens draws for one zoom level.
struct ArchLevel {
    /// The part being looked inside, or nil for the whole system.
    var focus: ComponentNode?
    /// Parts drawn at full size: the top-level parts, or the parts inside `focus`.
    var primary: [ComponentNode]
    /// Parts outside `focus` that connect to it, drawn as quiet context.
    var context: [ComponentNode]
    var edges: [ArchLevelEdge]
    var boundaries: [SystemBoundary]

    var nodes: [ComponentNode] { primary + context }
    func contains(_ id: String) -> Bool { nodes.contains { $0.id == id } }
}

extension PRGraph {

    // MARK: Hierarchy

    /// Parts that belong on the drawing: everything above implementation detail.
    var architectureParts: [ComponentNode] {
        components.filter { $0.level != .implementation }
    }

    /// The top-level boxes. A part whose parent doesn't resolve is treated as top-level
    /// rather than lost.
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

    /// Root first, ending with the part itself. Cycles in `parentId` are cut.
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

    /// The part itself plus everything inside it, at any depth, including implementation nodes.
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

    /// The nearest part at or above `id` that can be shown on a drawing — implementation
    /// nodes resolve to the part they implement.
    func drawablePart(for id: String) -> ComponentNode? {
        ancestry(of: id).last { $0.level != .implementation }
            ?? implementationOwner(of: id)
    }

    /// For an implementation node with no parent: the part that names it in `implementedBy`,
    /// or the one it `dependsOnIds` (the older linking scheme).
    private func implementationOwner(of id: String) -> ComponentNode? {
        guard let impl = component(id) else { return nil }
        return architectureParts.first { $0.implementedBy.contains { $0.caseInsensitiveCompare(impl.title) == .orderedSame } }
            ?? impl.dependsOnIds.lazy.compactMap(component).first { $0.level != .implementation }
    }

    /// Implementation nodes and names that realize a part, for the inspector's
    /// Implementation section. Nodes first; then any `implementedBy` names without a node.
    func implementation(of id: String) -> (nodes: [ComponentNode], names: [String]) {
        guard let part = component(id) else { return ([], []) }
        var nodes = components.filter { $0.level == .implementation && $0.parentId == id }
        if nodes.isEmpty { nodes = implementationComponents(for: id).filter { $0.parentId == nil || $0.parentId == id } }
        let named = Set(nodes.map { $0.title.lowercased() })
        return (nodes, part.implementedBy.filter { !named.contains($0.lowercased()) })
    }

    // MARK: Levels

    /// The drawing for `path` — empty for the whole system, otherwise the chain of parts the
    /// reviewer has zoomed into, outermost first.
    func architectureLevel(path: [String]) -> ArchLevel {
        let focus = path.last.flatMap(component)
        let primary = focus.map { parts(inside: $0.id) } ?? topLevelParts
        let primaryIds = Set(primary.map(\.id))
        let pathIds = Set(path)

        // The box that stands for `id` here: the first part down its ancestry that isn't one
        // the reviewer is inside. Nil means the id *is* one of those enclosing parts.
        func representative(_ id: String) -> String? {
            guard let owner = drawablePart(for: id) else { return nil }
            return ancestry(of: owner.id).first { !pathIds.contains($0.id) }?.id
        }

        // An arrow into or out of the focused part itself enters at a part with no incoming
        // arrow inside, and leaves from one with no outgoing arrow inside.
        let innerEdges = resolvedEdges.compactMap { e -> (String, String)? in
            guard let f = representative(e.fromId), let t = representative(e.toId),
                  primaryIds.contains(f), primaryIds.contains(t), f != t else { return nil }
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
            // Zoomed in, only arrows that touch the inside of the focused part matter.
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
        let context = focus == nil ? [] : connected.subtracting(primaryIds).compactMap(component)
            .sorted { (components.firstIndex(of: $0) ?? 0) < (components.firstIndex(of: $1) ?? 0) }

        let visible = primaryIds.union(context.map(\.id))
        let drawnBoundaries: [SystemBoundary]
        if let focus {
            // Inside a part, that part is the container; context stays outside it.
            drawnBoundaries = [SystemBoundary(id: "focus:\(focus.id)", label: focus.title, kind: .application,
                                              componentIds: primary.map(\.id))]
        } else {
            drawnBoundaries = boundaries.compactMap { b in
                let members = unique(b.componentIds.compactMap(representative)).filter(visible.contains)
                return members.isEmpty ? nil : SystemBoundary(id: b.id, label: b.label, kind: b.kind, componentIds: members)
            }
        }
        return ArchLevel(focus: focus, primary: primary, context: context, edges: edges, boundaries: drawnBoundaries)
    }

    /// The zoom path that shows `id` as a box: its enclosing parts.
    func architecturePath(showing id: String) -> [String] {
        guard let part = drawablePart(for: id) else { return [] }
        return ancestry(of: part.id).dropLast().map(\.id)
    }

    // MARK: Cross-links

    /// Flows with a step anywhere inside this part.
    func flows(through id: String) -> [FlowNode] {
        let ids = subtreeIds(of: id)
        return flows.filter { f in f.steps.contains { $0.componentId.map(ids.contains) ?? false } }
    }

    /// Decisions that shape this part or anything inside it — decisions to review first.
    func decisions(within id: String) -> [DecisionNode] {
        let ids = subtreeIds(of: id)
        let hits = decisions.filter { !Set($0.componentIds).isDisjoint(with: ids) }
        let primary = Set(decisionsToReview.map(\.id))
        return hits.filter { primary.contains($0.id) } + hits.filter { !primary.contains($0.id) }
    }

    /// Consequential decisions marked on the drawing, by the box or arrow they explain. Only
    /// decisions to review are placed — whatever their abstraction level; other decisions
    /// stay in the inspector.
    func decisionAnchors(on level: ArchLevel) -> [ArchAnchor: [DecisionNode]] {
        var out: [ArchAnchor: [DecisionNode]] = [:]
        for d in decisionsToReview {
            guard let anchor = anchor(for: d.componentIds, explicitEdges: edgeIds(embodying: d), on: level) else { continue }
            out[anchor, default: []].append(d)
        }
        return out
    }

    /// Overview questions, by the box or arrow where the concern lives.
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

    /// An explicit relationship wins; otherwise an arrow between two of the parts; otherwise
    /// the first part that is drawn.
    private func anchor(for componentIds: [String], explicitEdges: [String], on level: ArchLevel) -> ArchAnchor? {
        for id in explicitEdges {
            if let drawn = level.edges.first(where: { $0.id == id || $0.mergedIds.contains(id) }) { return .edge(drawn.id) }
        }
        let drawn = unique(componentIds.compactMap { id in
            ancestry(of: drawablePart(for: id)?.id ?? id).first { level.contains($0.id) }?.id
        })
        if drawn.count >= 2,
           let edge = level.edges.first(where: { drawn.contains($0.fromId) && drawn.contains($0.toId) }) {
            return .edge(edge.id)
        }
        return drawn.first.map { .node($0) }
    }
}

extension EdgeChange {
    /// Which of several parallel edges represents them on a zoomed-out drawing.
    var priority: Int {
        switch self {
        case .new: return 3
        case .changed: return 2
        case .removed: return 1
        case .existing: return 0
        }
    }
}
