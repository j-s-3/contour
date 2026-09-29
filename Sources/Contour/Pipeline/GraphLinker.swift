enum GraphLinker {
    static func linkDecisions(_ decisions: [DecisionNode], to components: [ComponentNode]) -> [DecisionNode] {
        let parts = components.filter { $0.level != .implementation }
        guard !parts.isEmpty else { return decisions }
        return decisions.map { decision in
            guard decision.componentIds.isEmpty else { return decision }
            var linked = decision
            linked.componentIds = componentIds(citing: decision.refs + decision.tradeoffs.flatMap(\.refs), in: parts)
            return linked
        }
    }

    static func pinDecisions(_ decisions: [DecisionNode], to flows: [FlowNode]) -> [FlowNode] {
        guard !decisions.isEmpty else { return flows }
        return flows.map { flow in
            guard var behavior = flow.behavior, !behavior.nodes.isEmpty,
                behavior.nodes.allSatisfy({ $0.decisionIds.isEmpty })
            else { return flow }
            let stepRefs = Dictionary(flow.steps.map { ($0.id, $0.refs) }, uniquingKeysWith: { a, _ in a })
            let nodeRefs = behavior.nodes.map { node in node.refs + node.stepIds.flatMap { stepRefs[$0] ?? [] } }

            for decision in decisions {
                let refs = decision.refs + decision.tradeoffs.flatMap(\.refs)
                let scores = nodeRefs.map { evidence(refs, against: $0) }
                guard let best = scores.max(), !best.isEmpty else { continue }
                let winners = scores.indices.filter { scores[$0] == best }
                guard winners.count == 1 else { continue }
                behavior.nodes[winners[0]].decisionIds.append(decision.id)
            }
            var pinned = flow
            pinned.behavior = behavior
            return pinned
        }
    }

    struct Evidence: Comparable {
        var overlaps = 0
        var sameFile = 0

        var isEmpty: Bool { overlaps == 0 && sameFile == 0 }

        static func < (a: Evidence, b: Evidence) -> Bool {
            (a.overlaps, a.sameFile) < (b.overlaps, b.sameFile)
        }
    }

    static func evidence(_ refs: [CodeRef], against targets: [CodeRef]) -> Evidence {
        var result = Evidence()
        for ref in refs {
            let sameFile = targets.filter { $0.path == ref.path }
            if sameFile.contains(where: { ref.startLine <= $0.endLine && $0.startLine <= ref.endLine }) {
                result.overlaps += 1
            } else if !sameFile.isEmpty {
                result.sameFile += 1
            }
        }
        return result
    }

    private static func componentIds(citing refs: [CodeRef], in parts: [ComponentNode]) -> [String] {
        let scored = parts.enumerated()
            .map { (offset: $0.offset, part: $0.element, evidence: evidence(refs, against: $0.element.refs)) }
            .filter { !$0.evidence.isEmpty }
        guard !scored.isEmpty else { return [] }
        let anyOverlap = scored.contains { $0.evidence.overlaps > 0 }
        let candidates = anyOverlap ? scored.filter { $0.evidence.overlaps > 0 } : scored
        let byId = Dictionary(parts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ancestors: Set<String> = Set(
            candidates.flatMap { candidate -> [String] in
                var chain: [String] = []
                var parent = candidate.part.parentId
                while let id = parent, !chain.contains(id) {
                    chain.append(id)
                    parent = byId[id]?.parentId
                }
                return chain
            })
        return
            candidates
            .filter { !ancestors.contains($0.part.id) }
            .sorted { $0.evidence != $1.evidence ? $0.evidence > $1.evidence : $0.offset < $1.offset }
            .map(\.part.id)
    }
}
