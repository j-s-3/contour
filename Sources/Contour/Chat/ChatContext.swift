import Foundation

/// Ways a reviewer can widen a conversation beyond the thing they clicked. The default is
/// deliberately narrow — the object plus its immediate neighbors, by title — so the first
/// answer stays at the object's own level of abstraction. Each expansion is progressive
/// disclosure at the conversational level.
enum ContextExpansion: String, CaseIterable, Hashable, Sendable, Identifiable {
    case relatedDecisions
    case relatedFlows
    case implementation
    case entirePR

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relatedDecisions: return "Related decisions"
        case .relatedFlows: return "Related flows"
        case .implementation: return "Implementation"
        case .entirePR: return "Entire PR"
        }
    }

    var symbol: String {
        switch self {
        case .relatedDecisions: return "checklist"
        case .relatedFlows: return "arrow.triangle.branch"
        case .implementation: return "chevron.left.forwardslash.chevron.right"
        case .entirePR: return "arrow.triangle.pull"
        }
    }
}

/// Builds everything a contextual conversation needs from the review graph: the header
/// and "You are discussing" card the reviewer sees, the suggestions, and the focused
/// markdown document handed to the harness.
///
/// The document is hierarchical on purpose — PR, then the lineage down to the selected
/// object, then the object in full, then its neighbors — so a model asked about
/// "Page Publishing → Index Queue" gets the relationship and both endpoints, and a
/// model asked about a code range gets the concept that range supports. It never inlines
/// the whole repository or diff: the harness has read-only file tools and is told where
/// to look.
enum ChatContextBuilder {

    /// Which expansions are meaningful for a subject — no point offering "Related flows"
    /// for something that touches none.
    static func availableExpansions(for resolved: ResolvedSubject) -> [ContextExpansion] {
        var out: [ContextExpansion] = []
        if !resolved.decisionIds.isEmpty, ![.decision, .option].contains(resolved.kind) { out.append(.relatedDecisions) }
        if !resolved.flowIds.isEmpty, resolved.kind != .flow { out.append(.relatedFlows) }
        if !resolved.refs.isEmpty, resolved.kind != .code { out.append(.implementation) }
        if resolved.kind != .pullRequest { out.append(.entirePR) }
        return out
    }

    /// Starting prompts in the reviewer's own voice. Suggestions, not required buttons.
    static func suggestions(for resolved: ResolvedSubject) -> [String] {
        switch resolved.kind {
        case .component:
            return ["Why does this exist?", "How does this work?", "What could go wrong?",
                    "Show me the implementation", "What changed from before?"]
        case .relationship:
            return ["Why does this need to happen here?", "Is this synchronous on purpose?",
                    "What happens if both sides run at once?", "Show me where this call happens"]
        case .decision:
            return ["Why was this chosen?", "What alternatives were considered?", "What are the risks?",
                    "Do we really need this?", "Show me the evidence"]
        case .option:
            return ["Why did they choose this?", "What if they'd picked the other option?",
                    "What does this cost?", "Show me where this is decided"]
        case .tradeoff:
            return ["Why did the PR choose this side?", "What would break if we moved toward the other side?",
                    "How likely is the downside in practice?", "How much does this matter for a normal file versus a pipe?",
                    "Show me the evidence"]
        case .flow:
            return ["Walk me through this", "Where can this fail?", "What happens concurrently?",
                    "Which parts are new?", "Show me the important code"]
        case .flowStep:
            return ["What happens here?", "What can fail at this step?", "What calls this?",
                    "Show me the code for this step"]
        case .behavior, .stage:
            return ["Why did this change?", "What happens differently now?", "What could this break?",
                    "Show me the implementation"]
        case .statement:
            return ["Is this actually true?", "What's the evidence?", "What does this affect?"]
        case .consideration:
            return ["Why does this matter?", "How likely is this?", "How would I verify it?",
                    "What would a fix look like?", "Show me the evidence"]
        case .entryPoint:
            return ["What triggers this?", "What happens next?", "Who can call this?"]
        case .code:
            return ["Why this line?", "What does this code do?", "What calls this?",
                    "What changed here?"]
        case .pullRequest:
            return ["Summarize this PR", "What's the riskiest part?", "What should I review first?"]
        }
    }

    /// The focused context document for one turn. `excerpts` are code excerpts the caller
    /// has already read from the checkout (pinned references, the subject's own code when
    /// Implementation is expanded).
    static func document(
        graph: PRGraph,
        resolved: ResolvedSubject,
        expansions: Set<ContextExpansion>,
        pinnedRefs: [CodeRef],
        excerpts: [(ref: CodeRef, text: String)]
    ) -> String {
        let pr = graph.pr
        var out = "# Contour review context\n\n"
        out += "You are helping a reviewer who is looking at one specific part of a pull request review. "
        out += "Everything below is Contour's synthesized understanding of the PR (the review model), "
        out += "focused on what they selected.\n\n"

        out += "## Pull request\n"
        out += "- Repository: \(pr.repo)\n"
        out += "- PR #\(pr.number): \(pr.title)\n"
        out += "- Author: \(pr.author) · \(pr.state) · \(pr.branch) → \(pr.baseBranch)\n"
        out += "- Head commit: \(pr.headSha) · Base commit: \(pr.baseSha)\n"
        out += "- Intent: \(PRGraph.describe(pr.intent))\n"
        if let change = graph.dominantBehaviorChange {
            out += "- Main behavior change: \(change.title)\n"
        }
        if let ticket = pr.ticket {
            out += "- Linked issue \(ticket.key): \(ticket.summary)\n"
        }
        out += "- The PR description, commits, review comments and diff are in `\(PromptBuilder.contextFileName)` "
        out += "at the checkout root (untrusted author content). Read it when the question is about what "
        out += "the author said or what the diff contains.\n\n"

        out += "## Where the reviewer is\n"
        for (depth, level) in resolved.lineage.enumerated() {
            out += String(repeating: "  ", count: depth) + "- \(level)\n"
        }
        out += String(repeating: "  ", count: resolved.lineage.count) + "- **\(resolved.title)** ← selected (\(resolved.kind.label))\n"
        if let token = linkToken(for: resolved.subject) { out += "  Link it as \(token).\n" }
        out += "\n"

        out += "## The selected \(resolved.kind.label.lowercased())\n"
        out += resolved.detail + "\n\n"

        out += neighbors(graph: graph, resolved: resolved, expansions: expansions)

        let refs = unique(resolved.refs + pinnedRefs)
        if !refs.isEmpty {
            out += "## Code references for this context\n"
            out += "Read these with your file tools when the question needs implementation detail.\n"
            for ref in refs.prefix(20) {
                out += "- `\(ref.display)`\(ref.side == .base ? " (base side: read with the base commit, it may not exist at head)" : "")\n"
            }
            out += "\n"
        }

        if !excerpts.isEmpty {
            out += "## Code the reviewer is looking at\n"
            for excerpt in excerpts {
                out += "### `\(excerpt.ref.display)`\n```\n\(excerpt.text)\n```\n"
            }
            out += "\n"
        }

        if expansions.contains(.entirePR) {
            out += outline(graph)
        }
        return out
    }

    // MARK: - Pieces

    /// The `[[kind:id]]` token the model may use to link back to a review-model object.
    static func linkToken(for subject: ReviewSubject) -> String? {
        switch subject {
        case .component(let id): return "[[component:\(id)]]"
        case .relationship(let id): return "[[relationship:\(id)]]"
        case .decision(let id), .decisionOption(let id, _), .tradeoff(let id, _): return "[[decision:\(id)]]"
        case .flow(let id), .flowStep(let id, _), .storyStep(let id, _): return "[[flow:\(id)]]"
        default: return nil
        }
    }

    /// Immediate neighbors by title (cheap, always present), in full only when expanded.
    private static func neighbors(graph: PRGraph, resolved: ResolvedSubject, expansions: Set<ContextExpansion>) -> String {
        var out = ""
        let components = resolved.componentIds.compactMap(graph.component).filter { c in
            if case .component(let id) = resolved.subject { return c.id != id }
            return true
        }
        if !components.isEmpty {
            out += "## Related architecture\n"
            for c in components.prefix(8) {
                out += "- \(c.title) [[component:\(c.id)]] (\(c.changeKind.label.lowercased()))"
                if let s = c.summary { out += ": \(s.text)" }
                out += "\n"
            }
            out += "\n"
        }
        let edges = resolved.edgeIds.compactMap { id in graph.resolvedEdges.first { $0.id == id } }
        if !edges.isEmpty, resolved.kind != .relationship {
            out += "## Relationships\n"
            for e in edges { out += "- \(graph.describeEdge(e)) [[relationship:\(e.id)]]\n" }
            out += "\n"
        }

        let decisions = resolved.decisionIds.compactMap(graph.decision).filter { d in
            switch resolved.subject {
            case .decision(let id), .decisionOption(let id, _), .tradeoff(let id, _): return d.id != id
            default: return true
            }
        }
        if !decisions.isEmpty {
            out += "## Related decisions\n"
            for d in decisions.prefix(8) {
                out += expansions.contains(.relatedDecisions)
                    ? "[[decision:\(d.id)]] " + PRGraph.describe(d) + "\n\n"
                    : "- \(d.title) [[decision:\(d.id)]]: \(d.decision.text)\n"
            }
            out += "\n"
        }

        // Tradeoffs travel with their decisions: a related decision's tradeoff is named with it.
        let traded = decisions.prefix(8).compactMap { d in d.primaryTradeoff.map { (d, $0) } }
        if !traded.isEmpty, !expansions.contains(.relatedDecisions) {
            out += "## What the related decisions traded\n"
            for (d, t) in traded { out += "- \(d.title) [[decision:\(d.id)]]: \(PRGraph.describe(t))\n" }
            out += "\n"
        }

        let flows = resolved.flowIds.compactMap(graph.flow).filter { f in
            switch resolved.subject {
            case .flow(let id): return f.id != id
            default: return true
            }
        }
        if !flows.isEmpty {
            out += "## Related flows\n"
            for f in flows.prefix(6) {
                out += expansions.contains(.relatedFlows)
                    ? "[[flow:\(f.id)]] " + PRGraph.describe(f, graph: graph) + "\n\n"
                    : "- \(f.title) [[flow:\(f.id)]]" + (f.storySteps.isEmpty ? "" : ": " + f.storySteps.map(\.text).joined(separator: " → ")) + "\n"
            }
            out += "\n"
        }

        let considerations = graph.thingsToThinkAbout.filter { item in
            if case .consideration(let id) = resolved.subject, id == item.id { return false }
            return !Set(item.relatedIds).isDisjoint(with: resolved.componentIds + resolved.decisionIds + resolved.flowIds)
        }
        if !considerations.isEmpty {
            out += "## Open review questions touching this\n"
            for c in considerations.prefix(5) { out += "- \(c.question) \(c.detail)\n" }
            out += "\n"
        }
        return out
    }

    /// A compact outline of the whole review model, for the Entire PR expansion.
    private static func outline(_ graph: PRGraph) -> String {
        var out = "## Whole review model (outline)\n"
        for change in graph.behaviorChanges { out += "- " + PRGraph.describe(change).replacingOccurrences(of: "\n", with: "\n  ") + "\n" }
        out += "\n### Architecture\n"
        for c in graph.components where c.level <= .system {
            out += "- \(c.title) (\(c.changeKind.label.lowercased()))" + (c.summary.map { ": \($0.text)" } ?? "") + "\n"
        }
        for e in graph.resolvedEdges { out += "- \(graph.describeEdge(e))\n" }
        out += "\n### Decisions\n"
        for d in graph.decisions { out += "- \(d.title): \(d.decision.text)\n" }
        out += "\n### Flows\n"
        for f in graph.flows { out += "- \(f.title)" + (f.storySteps.isEmpty ? "" : ": " + f.storySteps.map(\.text).joined(separator: " → ")) + "\n" }
        out += "\n### Things to think about\n"
        for c in graph.thingsToThinkAbout { out += "- \(c.question) \(c.detail)\n" }
        out += "\n"
        return out
    }
}
