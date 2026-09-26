import Foundation

/// Anything a reviewer can point at and say "wait, why does it do that?" — every boxed
/// element in every lens maps to exactly one of these. It is an address into the review
/// graph, not a copy of it: the graph stays the single source of truth, and a subject is
/// resolved against it whenever context is needed.
enum ReviewSubject: Hashable, Sendable {
    case pullRequest
    case behaviorChange(String)
    case behaviorStage(changeId: String, stageId: String)
    case behaviorWhy(changeId: String)
    case behaviorConsequence(changeId: String)
    case consideration(String)
    case component(String)
    case relationship(String)
    case decision(String)
    case tradeoff(String)
    case flow(String)
    case flowStep(flowId: String, stepId: String)
    case storyStep(flowId: String, index: Int)
    case entryPoint(String)
    case codeRef(CodeRef)
}

/// What kind of thing a subject is, for the chat header glyph and for picking suggestions.
enum SubjectKind: String, Sendable {
    case pullRequest, behavior, stage, statement, consideration, component, relationship,
         decision, tradeoff, flow, flowStep, entryPoint, code

    var label: String {
        switch self {
        case .pullRequest: return "Pull request"
        case .behavior: return "Behavior change"
        case .stage: return "Behavior step"
        case .statement: return "Summary"
        case .consideration: return "Thing to think about"
        case .component: return "Architecture"
        case .relationship: return "Relationship"
        case .decision: return "Decision"
        case .tradeoff: return "Tradeoff"
        case .flow: return "Flow"
        case .flowStep: return "Flow step"
        case .entryPoint: return "Entry point"
        case .code: return "Code"
        }
    }

    /// SF Symbols, matching the sidebar's glyph for the same lens.
    var symbol: String {
        switch self {
        case .pullRequest: return "arrow.triangle.pull"
        case .behavior, .stage: return "arrow.right.circle"
        case .statement: return "text.alignleft"
        case .consideration: return "exclamationmark.triangle"
        case .component: return "square.stack.3d.up"
        case .relationship: return "arrow.right"
        case .decision: return "checklist"
        case .tradeoff: return "arrow.left.arrow.right"
        case .flow, .flowStep: return "arrow.triangle.branch"
        case .entryPoint: return "door.left.hand.open"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// A subject resolved against the graph: what it is, where it sits in the hierarchy, and
/// which neighbors it touches. The context menu, the chat header, and the harness context
/// document are all built from this one projection, so they can never disagree about what
/// "this" is.
struct ResolvedSubject {
    var subject: ReviewSubject
    var kind: SubjectKind
    var title: String
    /// Ancestors from the PR down, excluding the subject itself — e.g.
    /// ["PR #16678", "Architecture"] for a component.
    var lineage: [String]
    /// Up to four short lines for the "You are discussing" card.
    var summary: [String]
    /// The object itself, in full, as markdown for the harness.
    var detail: String
    var componentIds: [String] = []
    var decisionIds: [String] = []
    var tradeoffIds: [String] = []
    var flowIds: [String] = []
    var edgeIds: [String] = []
    var refs: [CodeRef] = []
    /// Where "Open details" goes.
    var detailTarget: NavigationTarget?
}

extension PRGraph {

    // MARK: - Resolution

    func resolve(_ subject: ReviewSubject) -> ResolvedSubject? {
        let prLine = "PR #\(pr.number): \(pr.title)"
        switch subject {
        case .pullRequest:
            return ResolvedSubject(
                subject: subject, kind: .pullRequest, title: pr.title, lineage: [],
                summary: [pr.intent.text].compactMap(Self.oneLine),
                detail: "Pull request \(pr.repo) #\(pr.number): \(pr.title)\n\nIntent: \(pr.intent.text)",
                componentIds: components.filter { $0.level <= .system }.map(\.id),
                decisionIds: decisions.map(\.id),
                flowIds: flows.map(\.id),
                detailTarget: .summary
            )

        case .behaviorChange(let id):
            guard let change = behaviorChanges.first(where: { $0.id == id }) else { return nil }
            let stages = change.before + change.after
            let componentIds = unique(stages.flatMap(\.componentIds))
            var summary = [change.title]
            if let why = change.why { summary.append("Why: \(why.text)") }
            if let consequence = change.consequence { summary.append("Consequence: \(consequence.text)") }
            return ResolvedSubject(
                subject: subject, kind: .behavior, title: change.title,
                lineage: [prLine, "What changed"],
                summary: summary.compactMap(Self.oneLine),
                detail: Self.describe(change),
                componentIds: componentIds,
                decisionIds: decisionIds(affectingAny: componentIds),
                flowIds: unique(stages.compactMap(\.flowId) + componentIds.flatMap { flows(traversing: $0).map(\.id) }),
                refs: unique(stages.flatMap(\.refs)),
                detailTarget: .summary
            )

        case .behaviorStage(let changeId, let stageId):
            guard let change = behaviorChanges.first(where: { $0.id == changeId }),
                  let stage = (change.before + change.after).first(where: { $0.id == stageId })
            else { return nil }
            let phase: String
            switch stage.tag {
            case .beforeOnly: phase = "Only before this PR"
            case .afterOnly: phase = "New in this PR"
            case .both: phase = "Before and after this PR"
            }
            let componentTitles = stage.componentIds.compactMap { component($0)?.title }
            var summary = [stage.label, "\(phase) · \(change.title)"]
            if !componentTitles.isEmpty { summary.append("Part of \(componentTitles.joined(separator: ", "))") }
            let decisionIds = decisionIds(affectingAny: stage.componentIds)
            if let first = decisionIds.first.flatMap(decision) { summary.append("Related decision: \(first.title)") }
            let before = change.before.map(\.label).joined(separator: " → ")
            let after = change.after.map(\.label).joined(separator: " → ")
            return ResolvedSubject(
                subject: subject, kind: .stage, title: stage.label,
                lineage: [prLine, "What changed", change.title],
                summary: summary.compactMap(Self.oneLine),
                detail: """
                Behavior step "\(stage.label)" (\(phase.lowercased())\(stage.outcome.map { ", outcome: \($0.rawValue)" } ?? "")).
                It belongs to the behavior change "\(change.title)":
                - Before: \(before)
                - After: \(after)
                """,
                componentIds: stage.componentIds,
                decisionIds: decisionIds,
                flowIds: unique([stage.flowId].compactMap { $0 } + stage.componentIds.flatMap { flows(traversing: $0).map(\.id) }),
                refs: stage.refs,
                detailTarget: stage.componentIds.first.map { .componentDetail($0) } ?? stage.flowId.map { .flowDetail($0) }
            )

        case .behaviorWhy(let changeId), .behaviorConsequence(let changeId):
            guard let change = behaviorChanges.first(where: { $0.id == changeId }) else { return nil }
            let isWhy: Bool = { if case .behaviorWhy = subject { return true } else { return false } }()
            guard let statement = isWhy ? change.why : change.consequence else { return nil }
            let label = isWhy ? "Why" : "Consequence"
            let base = resolve(.behaviorChange(changeId))
            return ResolvedSubject(
                subject: subject, kind: .statement, title: "\(label): \(statement.text)",
                lineage: [prLine, "What changed", change.title],
                summary: ["\(label) — \(change.title)", statement.text].compactMap(Self.oneLine),
                detail: "\(label) of the behavior change \"\(change.title)\": \(Self.describe(statement))\n\n\(Self.describe(change))",
                componentIds: base?.componentIds ?? [],
                decisionIds: base?.decisionIds ?? [],
                flowIds: base?.flowIds ?? [],
                refs: base?.refs ?? [],
                detailTarget: base?.decisionIds.first.map { .decisionDetail($0) }
            )

        case .consideration(let id):
            guard let item = thingsToThinkAbout.first(where: { $0.id == id }) else { return nil }
            let decisionIds = item.relatedIds.filter { decision($0) != nil }
            let componentIds = item.relatedIds.filter { component($0) != nil }
            let flowIds = item.relatedIds.filter { flow($0) != nil }
            var summary = [item.question, item.detail]
            if let first = decisionIds.first.flatMap(decision) { summary.append("Related decision: \(first.title)") }
            var detail = """
            Something the reviewer was asked to think about (\(item.kind == .question ? "an open question the analysis could not settle" : "a judgment call or risk")):
            Question: \(item.question)
            Why it matters: \(item.detail)
            Provenance: \(Self.provenanceLabel(item.provenance, item.confidence))
            """
            if let explanation = item.explanation { detail += "\nFull reasoning: \(explanation)" }
            return ResolvedSubject(
                subject: subject, kind: .consideration, title: item.question,
                lineage: [prLine, "Things to think about"],
                summary: summary.compactMap(Self.oneLine),
                detail: detail,
                componentIds: componentIds,
                decisionIds: unique(decisionIds + self.decisionIds(affectingAny: componentIds)),
                flowIds: flowIds,
                refs: item.refs,
                detailTarget: decisionIds.first.map { .decisionDetail($0) }
                    ?? componentIds.first.map { .componentDetail($0) }
                    ?? flowIds.first.map { .flowDetail($0) }
            )

        case .component(let id):
            guard let node = component(id) else { return nil }
            let incoming = resolvedEdges.filter { $0.toId == id }
            let outgoing = resolvedEdges.filter { $0.fromId == id }
            let decisions = decisions(affecting: id)
            var summary = [node.title]
            if let s = node.summary { summary.append(s.text) }
            if !incoming.isEmpty {
                summary.append("Triggered by " + incoming.prefix(3).map { component($0.fromId)?.title ?? $0.fromId }.joined(separator: ", "))
            }
            if let d = decisions.first { summary.append("Related decision: \(d.title)") }
            var detail = """
            Architecture element "\(node.title)" (\(node.level.label.lowercased()) level, \(node.changeKind.label.lowercased()) by this PR).
            """
            if let s = node.summary { detail += "\nResponsibility: \(Self.describe(s))" }
            if !node.implementedBy.isEmpty { detail += "\nImplemented by: \(node.implementedBy.joined(separator: ", "))" }
            for e in incoming { detail += "\n- Incoming: \(describeEdge(e))" }
            for e in outgoing { detail += "\n- Outgoing: \(describeEdge(e))" }
            if let boundary = boundaries.first(where: { $0.componentIds.contains(id) }) {
                detail += "\nInside boundary: \(boundary.label) (\(boundary.kind.label))"
            }
            return ResolvedSubject(
                subject: subject, kind: .component, title: node.title,
                lineage: [prLine, "Architecture"],
                summary: summary.compactMap(Self.oneLine),
                detail: detail,
                componentIds: unique([id] + incoming.map(\.fromId) + outgoing.map(\.toId)),
                decisionIds: unique(node.decisionIds + decisions.map(\.id)),
                flowIds: unique(node.flowIds + flows(traversing: id).map(\.id)),
                edgeIds: (incoming + outgoing).map(\.id),
                refs: node.refs,
                detailTarget: .componentDetail(id)
            )

        case .relationship(let id):
            guard let edge = resolvedEdges.first(where: { $0.id == id }) else { return nil }
            let from = component(edge.fromId)?.title ?? edge.fromId
            let to = component(edge.toId)?.title ?? edge.toId
            let decisions = decisions(forEdge: edge)
            var summary = ["\(from) → \(to)", "\(edge.label.isEmpty ? "relates to" : edge.label) · \(edge.flow == .async ? "asynchronous" : "synchronous") · \(Self.edgeChangeLabel(edge.change))"]
            if let d = decisions.first { summary.append("Related decision: \(d.title)") }
            if let note = edge.note { summary.append(note) }
            let bothFlows = flows.filter { f in
                let ids = Set(f.steps.compactMap(\.componentId))
                return ids.contains(edge.fromId) && ids.contains(edge.toId)
            }
            let endpoints = [edge.fromId, edge.toId].compactMap { resolve(.component($0))?.detail }
            return ResolvedSubject(
                subject: subject, kind: .relationship, title: "\(from) → \(to)",
                lineage: [prLine, "Architecture"],
                summary: summary.compactMap(Self.oneLine),
                detail: "Relationship: \(describeEdge(edge))\n\nBoth endpoints:\n\n" + endpoints.joined(separator: "\n\n"),
                componentIds: [edge.fromId, edge.toId],
                decisionIds: decisions.map(\.id),
                flowIds: bothFlows.map(\.id),
                edgeIds: [id],
                refs: unique((component(edge.fromId)?.refs ?? []) + (component(edge.toId)?.refs ?? [])),
                detailTarget: .edgeDetail(id)
            )

        case .decision(let id):
            guard let d = decision(id) else { return nil }
            let tradeoffs = tradeoffs(for: id)
            var summary = [d.title, d.decision.text]
            if let t = tradeoffs.first { summary.append("Tradeoff: \(t.poleA) vs \(t.poleB)") }
            if d.reviewerState != .unreviewed { summary.append("Reviewer marked: \(d.reviewerState.label)") }
            return ResolvedSubject(
                subject: subject, kind: .decision, title: d.title,
                lineage: [prLine, "Decisions"],
                summary: summary.compactMap(Self.oneLine),
                detail: Self.describe(d),
                componentIds: d.componentIds,
                decisionIds: [id],
                tradeoffIds: tradeoffs.map(\.id),
                flowIds: unique(d.componentIds.flatMap { flows(traversing: $0).map(\.id) }),
                refs: d.refs,
                detailTarget: .decisionDetail(id)
            )

        case .tradeoff(let id):
            guard let t = tradeoff(id) else { return nil }
            let owning = t.decisionIds.compactMap(decision)
            var summary = [t.title, "\(t.poleA) ↔ \(t.poleB), landing on \(t.chosen)"]
            if let d = owning.first { summary.append("From decision: \(d.title)") }
            return ResolvedSubject(
                subject: subject, kind: .tradeoff, title: t.title,
                lineage: [prLine, "Decisions"] + owning.prefix(1).map(\.title),
                summary: summary.compactMap(Self.oneLine),
                detail: """
                Tradeoff "\(t.title)": \(t.poleA) versus \(t.poleB). The implementation landed on: \(t.chosen).
                Explanation: \(Self.describe(t.explanation))
                """,
                componentIds: unique(owning.flatMap(\.componentIds)),
                decisionIds: t.decisionIds,
                tradeoffIds: [id],
                refs: t.refs,
                detailTarget: .tradeoffDetail(id)
            )

        case .flow(let id):
            guard let f = flow(id) else { return nil }
            let newSteps = f.steps.filter { $0.changeKind == .new || $0.changeKind == .changed }.count
            var summary = [f.title, "\(f.steps.count) steps, \(newSteps) new or changed"]
            if let entry = entryPoint(f.entryPointId) { summary.append("Starts at \(entry.title)") }
            let componentIds = unique(f.steps.compactMap(\.componentId))
            return ResolvedSubject(
                subject: subject, kind: .flow, title: f.title,
                lineage: [prLine, "Flows"],
                summary: summary.compactMap(Self.oneLine),
                detail: Self.describe(f, graph: self),
                componentIds: componentIds,
                decisionIds: decisionIds(affectingAny: componentIds),
                flowIds: [id],
                refs: unique(f.steps.flatMap(\.refs)),
                detailTarget: .flowDetail(id)
            )

        case .flowStep(let flowId, let stepId):
            guard let f = flow(flowId), let step = f.steps.first(where: { $0.id == stepId }) else { return nil }
            var summary = [step.title, "Step \(step.index) of \(f.title)"]
            if let c = component(step.componentId) { summary.append("In \(c.title)") }
            if let caution = step.caution { summary.append("Caution: \(caution)") }
            return ResolvedSubject(
                subject: subject, kind: .flowStep, title: step.title,
                lineage: [prLine, "Flows", f.title],
                summary: summary.compactMap(Self.oneLine),
                detail: "Flow step: \(Self.describe(step, graph: self))\n\nThe whole flow, for position:\n\(Self.describe(f, graph: self))",
                componentIds: [step.componentId].compactMap { $0 },
                decisionIds: decisionIds(affectingAny: [step.componentId].compactMap { $0 }),
                flowIds: [flowId],
                refs: step.refs,
                detailTarget: .flowDetail(flowId)
            )

        case .storyStep(let flowId, let index):
            guard let f = flow(flowId), f.storySteps.indices.contains(index) else { return nil }
            let story = f.storySteps[index]
            let componentIds = unique(f.steps.compactMap(\.componentId))
            return ResolvedSubject(
                subject: subject, kind: .flowStep, title: story.text,
                lineage: [prLine, "Flows", f.title],
                summary: [story.text, "Step \(index + 1) of \(f.storySteps.count) in \(f.title)"].compactMap(Self.oneLine),
                detail: "Story-level step \(index + 1) of the flow \"\(f.title)\": \(story.text)\n\n\(Self.describe(f, graph: self))",
                componentIds: componentIds,
                decisionIds: decisionIds(affectingAny: componentIds),
                flowIds: [flowId],
                refs: unique(f.steps.flatMap(\.refs)),
                detailTarget: .flowDetail(flowId)
            )

        case .entryPoint(let id):
            guard let e = entryPoint(id) else { return nil }
            let triggered = flow(e.flowId)
            var summary = [e.title, "\(e.kind) · \(e.changeKind.label.lowercased())"]
            if let t = e.triggersLabel ?? triggered?.title { summary.append("Triggers \(t)") }
            return ResolvedSubject(
                subject: subject, kind: .entryPoint, title: e.title,
                lineage: [prLine, "Flows"],
                summary: summary.compactMap(Self.oneLine),
                detail: "Entry point \"\(e.title)\" (\(e.kind), \(e.changeKind.label.lowercased()))" + (triggered.map { "\n\nIt starts this flow:\n\(Self.describe($0, graph: self))" } ?? ""),
                componentIds: unique(triggered?.steps.compactMap(\.componentId) ?? []),
                flowIds: [e.flowId].compactMap { $0 },
                refs: e.refs,
                detailTarget: e.flowId.map { .flowDetail($0) }
            )

        case .codeRef(let ref):
            let owners = owners(of: ref)
            var summary = [ref.display]
            if !owners.isEmpty { summary.append("Supports " + owners.prefix(3).map(\.title).joined(separator: ", ")) }
            if ref.side == .base { summary.append("Base side — the code before this PR") }
            let ownerDetail = owners.prefix(3).compactMap { resolve($0.subject)?.detail }
            return ResolvedSubject(
                subject: subject, kind: .code, title: ref.display,
                lineage: [prLine] + (owners.first.map { [$0.title] } ?? []),
                summary: summary.compactMap(Self.oneLine),
                detail: "Code reference \(ref.display) (\(ref.side == .base ? "base, before this PR" : "head, after this PR")).\n\n"
                    + (ownerDetail.isEmpty
                       ? "No review-model object cites this exact range."
                       : "The concepts this code supports:\n\n" + ownerDetail.joined(separator: "\n\n")),
                componentIds: unique(owners.flatMap { resolve($0.subject)?.componentIds ?? [] }),
                decisionIds: unique(owners.flatMap { resolve($0.subject)?.decisionIds ?? [] }),
                flowIds: unique(owners.flatMap { resolve($0.subject)?.flowIds ?? [] }),
                refs: [ref],
                detailTarget: .evidence(ref)
            )
        }
    }

    /// The conceptual objects that cite a code reference — the answer to "what is this
    /// line *for*?" Exact range matches first, then anything citing an overlapping range
    /// in the same file.
    func owners(of ref: CodeRef) -> [(subject: ReviewSubject, title: String)] {
        func cites(_ refs: [CodeRef]) -> Bool {
            refs.contains { $0.path == ref.path && $0.startLine <= ref.endLine && ref.startLine <= $0.endLine }
        }
        var out: [(ReviewSubject, String)] = []
        for d in decisions where cites(d.refs) { out.append((.decision(d.id), d.title)) }
        for c in components where cites(c.refs) { out.append((.component(c.id), c.title)) }
        for f in flows {
            for s in f.steps where cites(s.refs) { out.append((.flowStep(flowId: f.id, stepId: s.id), s.title)) }
        }
        for t in tradeoffs where cites(t.refs) { out.append((.tradeoff(t.id), t.title)) }
        return out
    }

    // MARK: - Neighborhood queries used by the context menu

    func decisionIds(affectingAny componentIds: [String]) -> [String] {
        unique(componentIds.flatMap { decisions(affecting: $0).map(\.id) })
    }

    // MARK: - Describers (markdown for the harness)

    func describeEdge(_ e: ArchitectureEdge) -> String {
        let from = component(e.fromId)?.title ?? e.fromId
        let to = component(e.toId)?.title ?? e.toId
        var s = "\(from) —\(e.label.isEmpty ? "relates to" : e.label)→ \(to) [\(e.flow == .async ? "async" : "sync"), \(Self.edgeChangeLabel(e.change))"
        if e.onCriticalPath { s += ", on a critical path" }
        if e.isTrustBoundary { s += ", crosses a trust boundary" }
        s += "]"
        if let note = e.note { s += " — \(note)" }
        return s
    }

    static func describe(_ change: BehaviorChange) -> String {
        var s = "Behavior change \"\(change.title)\"\n"
        s += "- Before: " + change.before.map(stageLabel).joined(separator: " → ") + "\n"
        s += "- After: " + change.after.map(stageLabel).joined(separator: " → ")
        if let why = change.why { s += "\n- Why: \(describe(why))" }
        if let c = change.consequence { s += "\n- Consequence: \(describe(c))" }
        if let q = change.humanQuestion { s += "\n- Open question: \(describe(q))" }
        return s
    }

    private static func stageLabel(_ stage: BehaviorStage) -> String {
        switch stage.outcome {
        case .failure: return "\(stage.label) (fails)"
        case .success: return "\(stage.label) (succeeds)"
        case nil: return stage.label
        }
    }

    static func describe(_ d: DecisionNode) -> String {
        var s = "Decision \"\(d.title)\" (\(d.level.label.lowercased()) level, confidence \(d.confidence.rawValue))\n"
        s += "- Decision: \(describe(d.decision))"
        for r in d.rationale { s += "\n- Rationale: \(describe(r))" }
        for a in d.alternatives { s += "\n- Alternative: \(describe(a))" }
        for c in d.consequences { s += "\n- Consequence: \(describe(c))" }
        if d.reviewerState != .unreviewed { s += "\n- Reviewer marked it: \(d.reviewerState.label)" }
        if !d.reviewerNote.isEmpty { s += "\n- Reviewer note: \(d.reviewerNote)" }
        return s
    }

    static func describe(_ f: FlowNode, graph: PRGraph) -> String {
        var s = "Flow \"\(f.title)\""
        if !f.storySteps.isEmpty {
            s += "\nStory: " + f.storySteps.map(\.text).joined(separator: " → ")
        }
        for step in f.steps { s += "\n\(describe(step, graph: graph))" }
        return s
    }

    static func describe(_ step: FlowStep, graph: PRGraph) -> String {
        var s = "\(step.index). \(step.title) [\(step.changeKind.label.lowercased())"
        if let c = graph.component(step.componentId) { s += ", in \(c.title)" }
        s += "]"
        if let d = step.stateDelta { s += " state: \(d)" }
        if !step.branches.isEmpty { s += " branches: \(step.branches.joined(separator: "; "))" }
        if !step.externalCalls.isEmpty { s += " calls: \(step.externalCalls.joined(separator: "; "))" }
        if !step.errorPaths.isEmpty { s += " errors: \(step.errorPaths.joined(separator: "; "))" }
        if step.isAsyncBoundaryAfter { s += " (async boundary after this step)" }
        if let c = step.caution { s += " CAUTION: \(c)" }
        return s
    }

    static func describe(_ statement: Statement) -> String {
        var s = statement.text + " (" + provenanceLabel(statement.provenance, statement.confidence) + ")"
        if let source = statement.source, !source.isEmpty { s += " [source: \(source)]" }
        return s
    }

    static func provenanceLabel(_ p: Provenance, _ c: Confidence?) -> String {
        switch p {
        case .fact: return "observed fact"
        case .claim: return "author's claim"
        case .interpretation: return "AI inference" + (c.map { ", \($0.rawValue) confidence" } ?? "")
        }
    }

    static func edgeChangeLabel(_ change: EdgeChange) -> String {
        switch change {
        case .new: return "new in this PR"
        case .changed: return "changed by this PR"
        case .existing: return "existing"
        case .removed: return "removed by this PR"
        }
    }

    /// Trims to the first line; drops empties. The "You are discussing" card is a glance,
    /// not a report.
    static func oneLine(_ text: String) -> String? {
        let first = text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? nil : first
    }
}

/// Order-preserving de-duplication.
func unique<T: Hashable>(_ items: [T]) -> [T] {
    var seen = Set<T>()
    return items.filter { seen.insert($0).inserted }
}
