import Foundation

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
    case decisionOption(decisionId: String, index: Int)
    case tradeoff(decisionId: String, index: Int)
    case flow(String)
    case flowStep(flowId: String, stepId: String)
    case storyStep(flowId: String, index: Int)
    case flowNode(flowId: String, nodeId: String)
    case entryPoint(String)
    case codeRef(CodeRef)
}

enum SubjectKind: String, Sendable {
    case pullRequest, behavior, stage, statement, consideration, component, relationship,
        decision, option, tradeoff, flow, flowStep, entryPoint, code

    var label: String {
        switch self {
        case .pullRequest: return "Pull request"
        case .behavior: return "Behavior change"
        case .stage: return "Behavior step"
        case .statement: return "Summary"
        case .consideration: return "Area needing judgment"
        case .component: return "Architecture"
        case .relationship: return "Relationship"
        case .decision: return "Decision"
        case .option: return "Decision option"
        case .tradeoff: return "Tradeoff"
        case .flow: return "Flow"
        case .flowStep: return "Flow step"
        case .entryPoint: return "Entry point"
        case .code: return "Code"
        }
    }

    var symbol: String {
        switch self {
        case .pullRequest: return "arrow.triangle.pull"
        case .behavior, .stage: return "arrow.right.circle"
        case .statement: return "text.alignleft"
        case .consideration: return "exclamationmark.triangle"
        case .component: return "square.stack.3d.up"
        case .relationship: return "arrow.right"
        case .decision: return "checklist"
        case .option: return "circle.circle"
        case .tradeoff: return "arrow.left.arrow.right"
        case .flow, .flowStep: return "arrow.triangle.branch"
        case .entryPoint: return "door.left.hand.open"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct ResolvedSubject {
    var subject: ReviewSubject
    var kind: SubjectKind
    var title: String
    var lineage: [String]
    var summary: [String]
    var detail: String
    var componentIds: [String] = []
    var decisionIds: [String] = []
    var flowIds: [String] = []
    var edgeIds: [String] = []
    var refs: [CodeRef] = []
    var detailTarget: NavigationTarget?
}

extension PRGraph {
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
                flowIds: unique(
                    [stage.flowId].compactMap { $0 } + stage.componentIds.flatMap { flows(traversing: $0).map(\.id) }),
                refs: stage.refs,
                detailTarget: stage.componentIds.first.map { .componentDetail($0) }
                    ?? stage.flowId.map { .flowDetail($0) }
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
                detail:
                    "\(label) of the behavior change \"\(change.title)\": \(Self.describe(statement))\n\n\(Self.describe(change))",
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
            var summary = [item.headline, item.impact] + [item.decision.map { "Decision: \($0)" }].compactMap { $0 }
            if let first = decisionIds.first.flatMap(decision) { summary.append("Related decision: \(first.title)") }
            var detail = """
                Something the reviewer was asked to judge (\(item.kind == .question ? "an open question the analysis could not settle" : "a judgment call or risk")):
                Observation: \(item.headline)
                Why it matters: \(item.impact)
                Provenance: \(Self.provenanceLabel(item.provenance, item.confidence))
                """
            if let category = item.category { detail += "\nCategory: \(category.label)" }
            if let decision = item.decision { detail += "\nDecision asked of the reviewer: \(decision)" }
            if let evidence = item.evidence { detail += "\nTechnical evidence: \(evidence)" }
            return ResolvedSubject(
                subject: subject, kind: .consideration, title: item.headline,
                lineage: [prLine, "Areas needing judgment"],
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
            let decisions = decisions(within: id)
            let flows = flows(through: id)
            let ancestors = ancestry(of: id).dropLast().map(\.title)
            let inside = parts(inside: id)
            let impl = implementation(of: id)
            let questions = architectureQuestions(touching: [id], edges: (incoming + outgoing).map(\.id))
            var summary = [node.title]
            if let s = node.summary { summary.append(s.text) }
            if let before = node.delta?.before, let after = node.delta?.after {
                summary.append("This PR: \(before) → \(after)")
            } else if !incoming.isEmpty {
                summary.append(
                    "Receives "
                        + incoming.prefix(3).map { "\($0.label) from \(component($0.fromId)?.title ?? $0.fromId)" }
                        .joined(separator: ", "))
            }
            if let d = decisions.first { summary.append("Related decision: \(brief(for: d).question)") }
            var detail = """
                Architecture part "\(node.title)" (\(node.level.label.lowercased()) level, \(node.changeKind.label.lowercased()) by this PR).
                """
            if !ancestors.isEmpty { detail += "\nPart of: \(ancestors.joined(separator: " › "))" }
            if let s = node.summary { detail += "\nResponsibility: \(Self.describe(s))" }
            if let delta = node.delta {
                if let before = delta.before, let after = delta.after {
                    detail += "\nWhat this PR changed about it: \(before) → \(after)"
                }
                if let summary = delta.summary { detail += "\nThis PR: \(Self.describe(summary))" }
            }
            if !inside.isEmpty { detail += "\nParts inside it: \(inside.map(\.title).joined(separator: ", "))" }
            let implNames = impl.nodes.map(\.title) + impl.names
            if !implNames.isEmpty { detail += "\nImplemented by: \(implNames.joined(separator: ", "))" }
            for e in incoming { detail += "\n- Incoming: \(describeEdge(e))" }
            for e in outgoing { detail += "\n- Outgoing: \(describeEdge(e))" }
            if let boundary = boundaries.first(where: { $0.componentIds.contains(id) }) {
                detail += "\nInside boundary: \(boundary.label) (\(boundary.kind.label))"
            }
            if let assessment = architecture {
                detail +=
                    "\nThe PR's overall architectural impact: \(assessment.impact.label.lowercased()) — \(assessment.headline)"
            }
            for q in questions { detail += "\n- Overview question about this part: \(q.briefing)" }
            return ResolvedSubject(
                subject: subject, kind: .component, title: node.title,
                lineage: [prLine, "Architecture"] + ancestors,
                summary: summary.compactMap(Self.oneLine),
                detail: detail,
                componentIds: unique([id] + inside.map(\.id) + incoming.map(\.fromId) + outgoing.map(\.toId)),
                decisionIds: unique(node.decisionIds + decisions.map(\.id)),
                flowIds: unique(node.flowIds + flows.map(\.id)),
                edgeIds: (incoming + outgoing).map(\.id),
                refs: unique(node.refs + impl.nodes.flatMap(\.refs)),
                detailTarget: .componentDetail(id)
            )

        case .relationship(let id):
            guard let edge = resolvedEdges.first(where: { $0.id == id }) else { return nil }
            let from = component(edge.fromId)?.title ?? edge.fromId
            let to = component(edge.toId)?.title ?? edge.toId
            let decisions = decisions(forEdge: edge)
            let crossing =
                edge.previousLabel.map { "\($0) → \(edge.label)" } ?? (edge.label.isEmpty ? "relates to" : edge.label)
            var summary = [
                "\(from) → \(to)",
                "\(crossing) · \(edge.flow == .async ? "asynchronous" : "synchronous") · \(Self.edgeChangeLabel(edge.change))",
            ]
            if let d = decisions.first { summary.append("Related decision: \(d.title)") }
            if let note = edge.note { summary.append(note) }
            let fromFlows = Set(flows(through: edge.fromId).map(\.id))
            let bothFlows = flows(through: edge.toId).filter { fromFlows.contains($0.id) }
            let questions = architectureQuestions(touching: [edge.fromId, edge.toId], edges: [id])
            let endpoints = [edge.fromId, edge.toId].compactMap { resolve(.component($0))?.detail }
            var detail = "Relationship: \(describeEdge(edge))"
            for q in questions { detail += "\n- Overview question about this relationship: \(q.briefing)" }
            return ResolvedSubject(
                subject: subject, kind: .relationship, title: "\(from) → \(to)",
                lineage: [prLine, "Architecture"],
                summary: summary.compactMap(Self.oneLine),
                detail: detail + "\n\nBoth endpoints:\n\n" + endpoints.joined(separator: "\n\n"),
                componentIds: [edge.fromId, edge.toId],
                decisionIds: decisions.map(\.id),
                flowIds: bothFlows.map(\.id),
                edgeIds: [id],
                refs: unique((component(edge.fromId)?.refs ?? []) + (component(edge.toId)?.refs ?? [])),
                detailTarget: .edgeDetail(id)
            )

        case .decision(let id):
            guard let d = decision(id) else { return nil }
            let brief = brief(for: d)
            let affects = affects(d)
            var summary = [brief.question]
            if let chosen = brief.chosen {
                let others = brief.options.filter { !$0.chosen }.map(\.label)
                summary.append(
                    "Chose \(chosen.label)" + (others.isEmpty ? "" : " over \(others.joined(separator: ", "))"))
            } else {
                summary.append(d.decision.text)
            }
            if let t = d.primaryTradeoff { summary.append("Trading \(t.dimensionA) against \(t.dimensionB)") }
            if d.reviewerState != .unreviewed { summary.append("Reviewer marked: \(d.reviewerState.label)") }
            var detail = Self.describe(d)
            let placement = isToReview(d) ? "Decisions to Review" : "Other Decisions"
            let who = d.reviewerPlacement == nil ? "the analysis placed it" : "the reviewer moved it there"
            detail += "\n- Shown under \(placement) (\(who)): \(attentionReason(for: d))"
            for q in overviewQuestions(reviewedOn: id) {
                detail += "\n- Overview question reviewed on this decision: \(q.briefing)"
            }
            return ResolvedSubject(
                subject: subject, kind: .decision, title: brief.question,
                lineage: [prLine, "Decisions"],
                summary: summary.compactMap(Self.oneLine),
                detail: detail,
                componentIds: d.componentIds,
                decisionIds: [id],
                flowIds: affects.flows.map(\.id),
                edgeIds: affects.edges.map(\.id),
                refs: d.allRefs,
                detailTarget: .decisionDetail(id)
            )

        case .decisionOption(let decisionId, let index):
            guard let d = decision(decisionId), let base = resolve(.decision(decisionId)) else { return nil }
            let brief = brief(for: d)
            guard brief.options.indices.contains(index) else { return nil }
            let option = brief.options[index]
            let others = brief.options.enumerated().filter { $0.offset != index }.map(\.element)
            var summary = [
                option.label, option.chosen ? "The option this PR chose" : "An option this PR did not choose",
                brief.question,
            ]
            if let detail = option.detail { summary.insert(detail, at: 1) }
            return ResolvedSubject(
                subject: subject, kind: .option, title: option.label,
                lineage: [prLine, "Decisions", brief.question],
                summary: summary.compactMap(Self.oneLine),
                detail: """
                    Option "\(option.label)"\(option.detail.map { " (\($0))" } ?? "") — \(option.chosen ? "the option this PR chose" : "an option this PR did NOT choose").
                    The other options were: \(others.map { "\($0.label)\($0.chosen ? " (chosen)" : "")" }.joined(separator: "; ")).

                    \(base.detail)
                    """,
                componentIds: base.componentIds,
                decisionIds: [decisionId],
                flowIds: base.flowIds,
                edgeIds: base.edgeIds,
                refs: d.refs,
                detailTarget: .decisionDetail(decisionId)
            )

        case .tradeoff(let decisionId, let index):
            guard let d = decision(decisionId), d.tradeoffs.indices.contains(index),
                let base = resolve(.decision(decisionId))
            else { return nil }
            let t = d.tradeoffs[index]
            let question = brief(for: d).question
            var summary = ["\(t.dimensionA) ↔ \(t.dimensionB)", "Leans toward \(t.chosenDimension)", question]
            if let e = t.explanation { summary.insert(e.text, at: 2) }
            return ResolvedSubject(
                subject: subject, kind: .tradeoff, title: "\(t.dimensionA) vs. \(t.dimensionB)",
                lineage: [prLine, "Decisions", question],
                summary: summary.compactMap(Self.oneLine),
                detail: """
                    A tradeoff made by one decision (\(t.prominence == .primary ? "the tension that makes the decision worth reviewing" : "a secondary tradeoff of the decision")): \(Self.describe(t)).
                    The reviewer is weighing this as part of the decision below, not as a separate item.

                    \(base.detail)
                    """,
                componentIds: base.componentIds,
                decisionIds: [decisionId],
                flowIds: base.flowIds,
                edgeIds: base.edgeIds,
                refs: t.refs.isEmpty ? d.refs : t.refs,
                detailTarget: .decisionDetail(decisionId)
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
                detail:
                    "Flow step: \(Self.describe(step, graph: self))\n\nThe whole flow, for position:\n\(Self.describe(f, graph: self))",
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
                summary: [story.text, "Step \(index + 1) of \(f.storySteps.count) in \(f.title)"].compactMap(
                    Self.oneLine),
                detail:
                    "Story-level step \(index + 1) of the flow \"\(f.title)\": \(story.text)\n\n\(Self.describe(f, graph: self))",
                componentIds: componentIds,
                decisionIds: decisionIds(affectingAny: componentIds),
                flowIds: [flowId],
                refs: unique(f.steps.flatMap(\.refs)),
                detailTarget: .flowDetail(flowId)
            )

        case .flowNode(let flowId, let nodeId):
            guard let f = flow(flowId) else { return nil }
            let behavior = behavior(for: f)
            guard let node = behavior.node(nodeId) else { return nil }
            let notes = annotations(for: f).filter { $0.nodeId == nodeId }
            let pinned = notes.filter { $0.kind == .decision }.map(\.targetId)
            let steps = implementationSteps(for: node, in: f)
            let componentIds = unique([node.componentId].compactMap { $0 } + steps.compactMap(\.componentId))
            let scenario = scenarioTitle(for: f)
            var summary = [node.label, "\(Self.flowChangeLabel(node.change)) · \(scenario)"]
            if let before = node.before, let after = node.after {
                summary.append("Before: \(before) · After: \(after)")
            }
            if let d = pinned.first.flatMap(decision) { summary.append("Related decision: \(brief(for: d).question)") }
            let related =
                pinned.isEmpty
                ? decisionIds(affectingAny: componentIds).filter { id in decisionsToReview.contains { $0.id == id } }
                : pinned
            return ResolvedSubject(
                subject: subject, kind: .flowStep, title: node.label,
                lineage: [prLine, "Flows", scenario],
                summary: summary.compactMap(Self.oneLine),
                detail: describe(node, in: f),
                componentIds: componentIds,
                decisionIds: related,
                flowIds: unique([flowId] + [node.subflowId].compactMap { $0 }),
                refs: unique(node.refs + steps.flatMap(\.refs)),
                detailTarget: .flowNodeDetail(flowId: flowId, nodeId: nodeId)
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
                detail: "Entry point \"\(e.title)\" (\(e.kind), \(e.changeKind.label.lowercased()))"
                    + (triggered.map { "\n\nIt starts this flow:\n\(Self.describe($0, graph: self))" } ?? ""),
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
                detail:
                    "Code reference \(ref.display) (\(ref.side == .base ? "base, before this PR" : "head, after this PR")).\n\n"
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

    func owners(of ref: CodeRef) -> [(subject: ReviewSubject, title: String)] {
        func cites(_ refs: [CodeRef]) -> Bool {
            refs.contains { $0.path == ref.path && $0.startLine <= ref.endLine && ref.startLine <= $0.endLine }
        }
        var out: [(ReviewSubject, String)] = []
        for d in decisions {
            if cites(d.refs) { out.append((.decision(d.id), brief(for: d).question)) }
            for (i, t) in d.tradeoffs.enumerated() where cites(t.refs) {
                out.append((.tradeoff(decisionId: d.id, index: i), "\(t.dimensionA) vs. \(t.dimensionB)"))
            }
        }
        for c in components where cites(c.refs) { out.append((.component(c.id), c.title)) }
        for f in flows {
            for s in f.steps where cites(s.refs) { out.append((.flowStep(flowId: f.id, stepId: s.id), s.title)) }
        }
        return out
    }

    func architectureQuestions(touching componentIds: [String], edges edgeIds: [String]) -> [Consideration] {
        let parts = componentIds.reduce(into: Set<String>()) { $0.formUnion(subtreeIds(of: $1)) }
        return thingsToThinkAbout.filter { item in
            let related = Set(item.relatedIds)
            if !related.isDisjoint(with: edgeIds) { return true }
            if !related.isDisjoint(with: parts) { return true }
            return item.relatedIds.compactMap(decision).contains { !parts.isDisjoint(with: $0.componentIds) }
        }
    }

    func decisionIds(affectingAny componentIds: [String]) -> [String] {
        unique(componentIds.flatMap { decisions(affecting: $0).map(\.id) })
    }

    func describeEdge(_ e: ArchitectureEdge) -> String {
        let from = component(e.fromId)?.title ?? e.fromId
        let to = component(e.toId)?.title ?? e.toId
        var s =
            "\(from) —\(e.label.isEmpty ? "relates to" : e.label)→ \(to) [\(e.flow == .async ? "async" : "sync"), \(Self.edgeChangeLabel(e.change))"
        if let previous = e.previousLabel { s += ", previously carried: \(previous)" }
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
        if let significance = d.significance {
            s += "- Review significance: \(significance.rawValue)"
            if !d.impacts.isEmpty { s += "; impacts \(d.impacts.map(\.label).joined(separator: ", "))" }
            s += d.significanceReason.map { " — \($0)" } ?? ""
            s += "\n"
        }
        if let question = d.question { s += "- Question it answers: \(question)\n" }
        for option in d.options {
            s +=
                "- Option: \(option.label)\(option.detail.map { " (\($0))" } ?? "")\(option.chosen ? " ← chosen" : "")\n"
        }
        if let why = d.why { s += "- Why (short): \(describe(why))\n" }
        for t in d.tradeoffs {
            s += "- \(t.prominence == .primary ? "Tradeoff" : "Secondary tradeoff"): \(describe(t))\n"
        }
        s += "- Decision: \(describe(d.decision))"
        for r in d.rationale { s += "\n- Rationale: \(describe(r))" }
        for a in d.alternatives { s += "\n- Alternative: \(describe(a))" }
        for c in d.consequences { s += "\n- Consequence: \(describe(c))" }
        if d.reviewerState != .unreviewed { s += "\n- Reviewer marked it: \(d.reviewerState.label)" }
        if !d.reviewerNote.isEmpty { s += "\n- Reviewer note: \(d.reviewerNote)" }
        return s
    }

    static func describe(_ t: DecisionTradeoff) -> String {
        let lean = abs(t.chosenPosition - 0.5) < 0.1 ? "roughly balanced" : "leaning toward \(t.chosenDimension)"
        var s =
            "\(t.dimensionA) versus \(t.dimensionB), \(lean) (position \(String(format: "%.2f", t.chosenPosition)) from \(t.dimensionA) = 0 to \(t.dimensionB) = 1)"
        if let e = t.explanation { s += " — \(describe(e))" }
        if !t.refs.isEmpty { s += " [evidence: \(t.refs.map(\.display).joined(separator: ", "))]" }
        return s
    }

    static func describe(_ f: FlowNode, graph: PRGraph) -> String {
        var s = "Flow \"\(graph.scenarioTitle(for: f))\""
        let behavior = graph.behavior(for: f)
        if let summary = behavior.summary { s += "\nWhat happens: \(summary)" }
        if let change = behavior.changeSummary { s += "\nHow this PR changed it: \(change)" }
        s += "\nBehavior (stages and where each leads):"
        for node in behavior.nodes { s += "\n- " + graph.describeStage(node, in: behavior) }
        if !f.steps.isEmpty { s += "\nImplementation trace underneath:" }
        for step in f.steps { s += "\n\(describe(step, graph: graph))" }
        return s
    }

    func describeStage(_ node: FlowBehaviorNode, in behavior: FlowBehavior) -> String {
        var s = "\(node.label) (\(node.kind.rawValue), \(Self.flowChangeLabel(node.change).lowercased())"
        if node.isUncertain { s += ", inferred rather than traced" }
        s += ")"
        if let before = node.before { s += " before: \(before);" }
        if let after = node.after { s += " after: \(after);" }
        let next = behavior.outgoing(node.id).map { e in
            (behavior.node(e.toId)?.label ?? e.toId) + (e.label.map { " when \($0)" } ?? "")
                + (e.flow == .async ? " (async)" : "")
        }
        if !next.isEmpty { s += " → " + next.joined(separator: "; ") }
        if let sub = node.subflowId, let f = flow(sub) {
            s += " (continues in the shared flow \"\(scenarioTitle(for: f))\")"
        }
        return s
    }

    func describe(_ node: FlowBehaviorNode, in f: FlowNode) -> String {
        let behavior = behavior(for: f)
        var s =
            "Flow stage \"\(node.label)\" in the flow \"\(scenarioTitle(for: f))\" — \(Self.flowChangeLabel(node.change).lowercased())."
        if let detail = node.detail { s += "\nWhat happens here: \(detail)" }
        if let before = node.before { s += "\nBefore this PR: \(before)" }
        if let after = node.after { s += "\nAfter this PR: \(after)" }
        if node.isUncertain { s += "\nThis stage is inferred, not traced in the code." }
        let previous = behavior.incoming(node.id).compactMap { behavior.node($0.fromId)?.label }
        if !previous.isEmpty { s += "\nComes after: \(previous.joined(separator: ", "))" }
        let next = behavior.outgoing(node.id).map { e in
            (behavior.node(e.toId)?.label ?? e.toId) + (e.label.map { " (when \($0))" } ?? "")
        }
        if !next.isEmpty { s += "\nLeads to: \(next.joined(separator: ", "))" }
        if !node.substeps.isEmpty { s += "\nSub-steps: \(node.substeps.joined(separator: " → "))" }
        for note in annotations(for: f) where note.nodeId == node.id {
            switch note.kind {
            case .decision: s += "\nDecision that shapes this point: \(note.detail ?? note.text) — chose \(note.text)"
            case .question: s += "\nReview question raised here: \(note.text)\(note.detail.map { " \($0)" } ?? "")"
            }
        }
        if let c = component(node.componentId) { s += "\nPart of: \(c.title)" }
        let steps = implementationSteps(for: node, in: f)
        if !steps.isEmpty {
            s += "\nImplementation steps underneath:"
            for step in steps { s += "\n\(Self.describe(step, graph: self))" }
        }
        s += "\n\nThe whole flow, for position:\n\(Self.describe(f, graph: self))"
        return s
    }

    static func flowChangeLabel(_ change: FlowChange) -> String {
        switch change {
        case .new: return "New in this PR"
        case .changed: return "Changed by this PR"
        case .existing: return "Unchanged"
        case .removed: return "Removed by this PR"
        }
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

    static func oneLine(_ text: String) -> String? {
        let first = text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? nil : first
    }
}

func unique<T: Hashable>(_ items: [T]) -> [T] {
    var seen = Set<T>()
    return items.filter { seen.insert($0).inserted }
}
