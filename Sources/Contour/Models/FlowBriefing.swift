import Foundation

/// A decision or review question pinned to the point in a flow where it matters.
struct FlowAnnotation: Hashable, Identifiable {
    enum Kind: Hashable { case decision, question }

    var kind: Kind
    /// The decision id, or the consideration id.
    var targetId: String
    /// The stage whose outgoing connection the annotation sits on.
    var nodeId: String
    /// A few words: the chosen option for a decision, the question for a review question.
    var text: String
    /// One sentence more, for the tooltip.
    var detail: String?

    var id: String { "\(kind)-\(targetId)-\(nodeId)" }
}

/// The Flows model, resolved from whatever the graph has.
///
/// New analyses carry `FlowNode.behavior` from the flows stage, decisions pinned to stages by
/// `decisionIds`, and review questions pinned by `Consideration.flowAnchors`. Older cached
/// graphs (and the captured mock fixtures) only have story steps and a call trace, so a
/// linear behavior is condensed from those instead — the same approach as
/// `thingsToThinkAbout` and `brief(for:)`.
extension PRGraph {

    // MARK: - Scenario

    /// The flow's name as a scenario ("Open a file"). Older flows were titled as a call
    /// chain ("bat <file> -> content type detection -> …"); only the trigger half is kept.
    func scenarioTitle(for flow: FlowNode) -> String {
        guard flow.behavior == nil else { return flow.title }
        let separators = ["->", "→", "=>"]
        var head = flow.title
        for sep in separators {
            if let range = head.range(of: sep) { head = String(head[..<range.lowerBound]) }
        }
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? flow.title : trimmed
    }

    /// "Open a file: bat samples the input and classifies it" — one line for outlines.
    func flowOutline(_ flow: FlowNode) -> String {
        let behavior = behavior(for: flow)
        let story = behavior.summary
            ?? behavior.nodes.filter { $0.kind != .trigger }.map(\.label).joined(separator: " → ")
        return story.isEmpty ? scenarioTitle(for: flow) : "\(scenarioTitle(for: flow)): \(story)"
    }

    // MARK: - Behavior

    /// The behavior diagram for a flow: the analysis's own model when it has one, else one
    /// condensed from the story steps.
    func behavior(for flow: FlowNode) -> FlowBehavior {
        if let behavior = flow.behavior, !behavior.nodes.isEmpty { return behavior }
        return condensedBehavior(for: flow)
    }

    /// A linear behavior from an older flow: a trigger, then one stage per story step, each
    /// classified by the implementation steps it most plausibly summarizes. Honest about what
    /// it doesn't know — no branches, no before/after wording, no boundaries.
    func condensedBehavior(for flow: FlowNode) -> FlowBehavior {
        let labels: [String] = flow.storySteps.isEmpty
            ? flow.steps.prefix(8).map(\.title)
            : flow.storySteps.map(\.text)
        let buckets: [[FlowStep]] = flow.storySteps.isEmpty
            ? flow.steps.prefix(8).map { [$0] }
            : Self.align(flow.steps, to: labels)

        var nodes: [FlowBehaviorNode] = []
        var edges: [FlowBehaviorEdge] = []
        let entry = entryPoint(flow.entryPointId)
        let triggerId = "trigger"
        nodes.append(FlowBehaviorNode(
            id: triggerId, label: scenarioTitle(for: flow), kind: .trigger,
            detail: entry.map { "\($0.title) (\($0.kind))" },
            componentId: nil, refs: entry?.refs ?? []
        ))

        var previous = triggerId
        var asyncAfterPrevious = false
        for (index, label) in labels.enumerated() {
            let steps = buckets.indices.contains(index) ? buckets[index] : []
            let story = flow.storySteps.indices.contains(index) ? flow.storySteps[index] : nil
            let change = Self.condensedChange(steps.map(\.changeKind))
            let lead = steps.first { $0.changeKind == .new || $0.changeKind == .changed } ?? steps.first
            let id = "stage-\(index)"
            nodes.append(FlowBehaviorNode(
                id: id, label: label,
                kind: index == labels.count - 1 ? .outcome : .step,
                detail: lead?.stateDelta,
                change: change,
                stepIds: steps.map(\.id),
                componentId: lead?.componentId,
                refs: unique(steps.flatMap(\.refs)),
                provenance: story?.provenance == .interpretation ? .interpretation : .fact,
                confidence: story?.confidence
            ))
            edges.append(FlowBehaviorEdge(fromId: previous, toId: id, flow: asyncAfterPrevious ? .async : .sync))
            previous = id
            asyncAfterPrevious = steps.last?.isAsyncBoundaryAfter ?? false
        }
        return FlowBehavior(nodes: nodes, edges: edges)
    }

    /// A story step is new when everything under it is new, changed when anything under it
    /// is new or changed, and otherwise existing context.
    static func condensedChange(_ kinds: [ChangeKind]) -> FlowChange {
        guard !kinds.isEmpty else { return .existing }
        if kinds.allSatisfy({ $0 == .new }) { return .new }
        if kinds.contains(where: { $0 == .new || $0 == .changed }) { return .changed }
        return .existing
    }

    /// Assigns each implementation step to a story step, in order, by shared words — story
    /// steps and implementation steps are written in the same order but at different
    /// granularity, and older graphs never linked them.
    ///
    /// Solved as a monotonic alignment maximizing total overlap, so one stray shared word
    /// can't drag every later step to the end; ties lean toward the proportional position.
    static func align(_ steps: [FlowStep], to labels: [String]) -> [[FlowStep]] {
        let m = labels.count, n = steps.count
        guard m > 0 else { return [] }
        var buckets = Array(repeating: [FlowStep](), count: m)
        guard n > 0 else { return buckets }
        let labelWords = labels.map(keywords)
        let score: [[Double]] = steps.enumerated().map { i, step in
            let words = keywords(step.title + " " + (step.stateDelta ?? ""))
            let expected = Double(i) * Double(m) / Double(n)
            return (0..<m).map { j in Double(labelWords[j].intersection(words).count) - 0.01 * abs(Double(j) - expected) }
        }
        // best[i][j]: the best total for steps 0...i with step i under label j.
        var best = [score[0]]
        var from = [[Int]](repeating: Array(repeating: 0, count: m), count: n)
        for i in 1..<n {
            var row = Array(repeating: 0.0, count: m)
            var runningMax = -Double.infinity, runningArg = 0
            for j in 0..<m {
                if best[i - 1][j] > runningMax { runningMax = best[i - 1][j]; runningArg = j }
                row[j] = score[i][j] + runningMax
                from[i][j] = runningArg
            }
            best.append(row)
        }
        var j = best[n - 1].indices.max { best[n - 1][$0] < best[n - 1][$1] }!
        for i in stride(from: n - 1, through: 0, by: -1) {
            buckets[j].insert(steps[i], at: 0)
            j = from[i][j]
        }
        return buckets
    }

    /// Content words, crudely stemmed to five letters so "printer" meets "print" and
    /// "buffered" meets "buffer".
    static func keywords(_ text: String) -> Set<String> {
        let stop: Set<String> = ["the", "and", "for", "with", "via", "into", "from", "that", "this",
                                 "only", "then", "when", "than", "its", "out", "whether", "any", "all"]
        let tokens = text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "-" }
        return Set(tokens.map(String.init).filter { $0.count >= 3 && !stop.contains($0) }.map { String($0.prefix(5)) })
    }

    // MARK: - Decisions and questions in the flow

    /// Decisions and review questions pinned to the stages of a flow.
    func annotations(for flow: FlowNode) -> [FlowAnnotation] {
        let behavior = behavior(for: flow)
        var out: [FlowAnnotation] = []

        // Decisions: where the analysis pinned them, else — for condensed flows — on the
        // first changed stage inside a component the decision shapes.
        var decisionNode: [String: String] = [:]
        let explicit = behavior.nodes.contains { !$0.decisionIds.isEmpty }
        if explicit {
            for node in behavior.nodes {
                for id in node.decisionIds where decision(id) != nil && decisionNode[id] == nil {
                    decisionNode[id] = node.id
                }
            }
        } else if flow.behavior == nil {
            let changed = behavior.nodes.filter { $0.change != .existing && $0.componentId != nil }
            for d in primaryDecisions {
                if let node = changed.first(where: { d.componentIds.contains($0.componentId!) }) {
                    decisionNode[d.id] = node.id
                }
            }
        }
        for d in decisions where decisionNode[d.id] != nil {
            let brief = brief(for: d)
            out.append(FlowAnnotation(
                kind: .decision, targetId: d.id, nodeId: decisionNode[d.id]!,
                text: brief.chosen?.label ?? Self.firstSentence(d.decision.text),
                detail: brief.question
            ))
        }

        // Review questions: where the judgment stage anchored them, else next to the
        // decision they're reviewed on, else on the first changed stage of a flow they name.
        let flowIds = Set(flows.map(\.id))
        for item in thingsToThinkAbout {
            let nodeId: String?
            if !item.flowAnchors.isEmpty {
                nodeId = item.flowAnchors.first { $0.flowId == flow.id && behavior.node($0.nodeId) != nil }?.nodeId
            } else {
                let namedFlows = item.relatedIds.filter { flowIds.contains($0) }
                if !namedFlows.isEmpty && !namedFlows.contains(flow.id) {
                    nodeId = nil
                } else if let viaDecision = item.relatedIds.lazy.compactMap({ decisionNode[$0] }).first {
                    nodeId = viaDecision
                } else if namedFlows.contains(flow.id) {
                    nodeId = (behavior.nodes.first { $0.change != .existing && $0.kind != .trigger }
                              ?? behavior.nodes.first { $0.kind != .trigger })?.id
                } else {
                    nodeId = nil
                }
            }
            if let nodeId {
                out.append(FlowAnnotation(kind: .question, targetId: item.id, nodeId: nodeId,
                                          text: item.question, detail: item.detail.isEmpty ? nil : item.detail))
            }
        }
        return out
    }

    /// Where a decision shows up in the runtime behavior, for "Appears in" on the decision.
    func flowAppearances(ofDecision decisionId: String) -> [(flow: FlowNode, nodeId: String)] {
        flows.compactMap { flow in
            annotations(for: flow).first { $0.kind == .decision && $0.targetId == decisionId }
                .map { (flow, $0.nodeId) }
        }
    }

    // MARK: - Convergence

    /// Flows that hand off into this one through a shared stage — "Upload asset" and
    /// "Delete asset" both reaching "Reconcile repository".
    func flowsConverging(into flowId: String) -> [FlowNode] {
        flows.filter { f in f.id != flowId && behavior(for: f).nodes.contains { $0.subflowId == flowId } }
    }

    /// The implementation steps a stage summarizes, in trace order.
    func implementationSteps(for node: FlowBehaviorNode, in flow: FlowNode) -> [FlowStep] {
        let ids = Set(node.stepIds)
        return flow.steps.filter { ids.contains($0.id) }
    }
}
