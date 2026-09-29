import SwiftUI

enum FlowDrillLevel: Int, CaseIterable, Comparable, Identifiable {
    case behavior, steps, implementation, code

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .behavior: return "Behavior"
        case .steps: return "Steps"
        case .implementation: return "Implementation"
        case .code: return "Code"
        }
    }
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    static func available(for node: FlowBehaviorNode, in flow: FlowNode, graph: PRGraph) -> [FlowDrillLevel] {
        let steps = graph.implementationSteps(for: node, in: flow)
        var out: [FlowDrillLevel] = [.behavior]
        if !node.substeps.isEmpty { out.append(.steps) }
        if !steps.isEmpty || node.componentId != nil { out.append(.implementation) }
        if !(node.refs + steps.flatMap(\.refs)).isEmpty { out.append(.code) }
        return out
    }
}

enum FlowStageInspectorLogic {
    static func refs(node: FlowBehaviorNode, steps: [FlowStep]) -> [CodeRef] {
        unique(node.refs + steps.flatMap(\.refs))
    }

    static func notes(_ all: [FlowAnnotation], forNodeId nodeId: String) -> [FlowAnnotation] {
        all.filter { $0.nodeId == nodeId }
    }

    static func notes(_ notes: [FlowAnnotation], kind: FlowAnnotation.Kind) -> [FlowAnnotation] {
        notes.filter { $0.kind == kind }
    }

    static func neighbors(
        of nodeId: String, in behavior: FlowBehavior
    ) -> (previous: [FlowBehaviorNode], next: [(edge: FlowBehaviorEdge, node: FlowBehaviorNode)]) {
        let previous = behavior.incoming(nodeId).compactMap { behavior.node($0.fromId) }
        let next = behavior.outgoing(nodeId).compactMap { edge in
            behavior.node(edge.toId).map { (edge: edge, node: $0) }
        }
        return (previous, next)
    }

    static func levelAfterNodeChange(current: FlowDrillLevel, available: [FlowDrillLevel]) -> FlowDrillLevel {
        available.contains(current) ? current : .behavior
    }
}

struct FlowStageInspector: View {
    let graph: PRGraph
    let flow: FlowNode
    let node: FlowBehaviorNode
    @Binding var level: FlowDrillLevel
    var onSelectNode: (FlowBehaviorNode) -> Void
    var onOpenEvidence: (CodeRef) -> Void
    var onOpenFlow: (String) -> Void
    var onClose: () -> Void

    @Environment(\.reviewActions) private var actions

    private var behavior: FlowBehavior { graph.behavior(for: flow) }
    private var steps: [FlowStep] { graph.implementationSteps(for: node, in: flow) }
    private var refs: [CodeRef] { FlowStageInspectorLogic.refs(node: node, steps: steps) }
    private var available: [FlowDrillLevel] { FlowDrillLevel.available(for: node, in: flow, graph: graph) }
    private var notes: [FlowAnnotation] { FlowStageInspectorLogic.notes(graph.annotations(for: flow), forNodeId: node.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            ladder
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch level {
                    case .behavior: behaviorRung
                    case .steps: stepsRung
                    case .implementation: implementationRung
                    case .code: codeRung
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            actionsBar
        }
        .background(.background.secondary)
        .onChange(of: node.id) { _, _ in level = FlowStageInspectorLogic.levelAfterNodeChange(current: level, available: available) }
    }

    private var titleBar: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kindLabel.uppercased())
                    .font(.caption2.weight(.semibold)).tracking(0.5)
                    .foregroundStyle(.secondary)
                Text(node.label)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .reviewContextMenu(.flowNode(flowId: flow.id, nodeId: node.id))
                if node.change != .existing {
                    Text(PRGraph.flowChangeLabel(node.change))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(node.change.color)
                }
            }
            Spacer(minLength: 0)
            Button(action: onClose) { Image(systemName: "xmark").font(.caption.weight(.semibold)) }
                .buttonStyle(.borderless)
                .help("Close (esc)")
        }
        .padding(16)
    }

    private var ladder: some View {
        HStack(spacing: 2) {
            ForEach(FlowDrillLevel.allCases) { rung in
                let enabled = available.contains(rung)
                Button { level = rung } label: {
                    Text(rung.label)
                        .font(.caption.weight(level == rung ? .semibold : .regular))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(level == rung ? Color.accentColor.opacity(0.15) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(enabled ? (level == rung ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary)) : AnyShapeStyle(.tertiary))
                .disabled(!enabled)
                if rung != .code {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var actionsBar: some View {
        HStack(spacing: 14) {
            if available.contains(.implementation) && level != .implementation {
                Button("Show implementation") { level = .implementation }
            }
            if available.contains(.code) && level != .code {
                Button("Show code") { level = .code }
            }
            Spacer(minLength: 0)
            Button { actions.ask(.flowNode(flowId: flow.id, nodeId: node.id)) } label: {
                Label("Ask about this…", systemImage: "sparkles")
            }
        }
        .buttonStyle(.link)
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var kindLabel: String { Self.kindLabel(for: node.kind) }

    nonisolated static func kindLabel(for kind: FlowNodeKind) -> String {
        switch kind {
        case .trigger: return "Trigger"
        case .step: return "Stage"
        case .decision: return "Branch point"
        case .outcome: return "Outcome"
        case .external: return "External system"
        case .datastore: return "Storage"
        case .subflow: return "Shared flow"
        }
    }

    @ViewBuilder
    private var behaviorRung: some View {
        if let detail = node.detail {
            Text(detail).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        if node.isUncertain {
            Label("Inferred, not traced in the code", systemImage: "questionmark.circle")
                .font(.caption).foregroundStyle(.orange)
        }
        if node.change == .changed, node.before != nil || node.after != nil {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                if let before = node.before {
                    GridRow { fieldLabel("Before"); Text(before).foregroundStyle(.secondary) }
                }
                if let after = node.after {
                    GridRow { fieldLabel("After"); Text(after).fontWeight(.semibold) }
                }
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }

        let (previous, next) = FlowStageInspectorLogic.neighbors(of: node.id, in: behavior)
        if !previous.isEmpty || !next.isEmpty {
            field("In the flow") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(previous) { p in neighbor(p, prefix: "After", condition: nil, async: false) }
                    ForEach(next, id: \.edge.id) { e, n in neighbor(n, prefix: "Then", condition: e.label, async: e.flow == .async) }
                }
            }
        }

        if let sub = node.subflowId, let target = graph.flow(sub) {
            Button { onOpenFlow(sub) } label: {
                Label("Open the shared flow “\(graph.scenarioTitle(for: target))”", systemImage: "arrow.triangle.merge")
            }
            .buttonStyle(.link).font(.callout)
        }

        let decisions = FlowStageInspectorLogic.notes(notes, kind: .decision)
        if !decisions.isEmpty {
            field("Decision") { noteLinks(decisions) }
        }
        let questions = FlowStageInspectorLogic.notes(notes, kind: .question)
        if !questions.isEmpty {
            field("Review question") { noteLinks(questions) }
        }
    }

    private func neighbor(_ n: FlowBehaviorNode, prefix: String, condition: String?, async: Bool) -> some View {
        Button { onSelectNode(n) } label: {
            HStack(spacing: 5) {
                Text(prefix).foregroundStyle(.secondary)
                if let condition { Text(condition.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
                Text(n.label).fontWeight(n.change == .existing ? .regular : .semibold)
                if async { Image(systemName: "clock.arrow.circlepath").font(.caption2).foregroundStyle(.secondary).help("Asynchronous") }
            }
            .font(.callout)
        }
        .buttonStyle(.plain)
    }

    private func noteLinks(_ notes: [FlowAnnotation]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(notes) { note in
                Button {
                    switch note.kind {
                    case .decision: actions.navigate(.decisionDetail(note.targetId))
                    case .question: actions.navigate(.consideration(note.targetId))
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: note.kind.symbol).font(.caption).foregroundStyle(note.kind.color)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.text).font(.callout.weight(.medium))
                            if let detail = note.detail {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .reviewContextMenu(note.kind == .decision ? .decision(note.targetId) : .consideration(note.targetId))
            }
        }
    }

    @ViewBuilder
    private var stepsRung: some View {
        field(node.label) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(node.substeps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 0) {
                            Circle().fill(Color.accentColor.opacity(0.8)).frame(width: 7, height: 7).padding(.top, 5)
                            if i < node.substeps.count - 1 {
                                Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1.2).frame(minHeight: 18)
                            }
                        }
                        Text(step).font(.callout).fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, i < node.substeps.count - 1 ? 8 : 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var implementationRung: some View {
        if let c = node.componentId.flatMap(graph.drawablePart(for:)) {
            field("Part of") {
                Button { actions.navigate(.componentDetail(c.id)) } label: {
                    Label(c.title, systemImage: "square.stack.3d.up").font(.callout)
                }
                .buttonStyle(.link)
                .reviewContextMenu(.component(c.id))
                if !c.implementedBy.isEmpty {
                    Text(c.implementedBy.joined(separator: ", "))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        if !steps.isEmpty {
            field("Traced steps") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(steps) { step in implementationStep(step) }
                }
            }
        }
    }

    private func implementationStep(_ step: FlowStep) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(step.title).font(.callout.weight(.medium))
                if step.changeKind == .new || step.changeKind == .changed {
                    Text(step.changeKind.label.uppercased()).font(.system(size: 9, weight: .heavy)).foregroundStyle(step.changeKind.color)
                }
                Spacer(minLength: 8)
                if let part = graph.drawablePart(for: step.componentId ?? "") {
                    Button { actions.navigate(.componentDetail(part.id)) } label: {
                        Label(part.title, systemImage: "square.stack.3d.up").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Show in Architecture")
                }
            }
            if let delta = step.stateDelta {
                Text(delta).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(step.branches, id: \.self) { detailLine("arrow.triangle.branch", $0) }
            ForEach(step.externalCalls, id: \.self) { detailLine("arrow.up.right", $0, mono: true) }
            ForEach(step.errorPaths, id: \.self) { detailLine("exclamationmark.octagon", $0) }
            if let caution = step.caution {
                Label(caution, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if !step.refs.isEmpty {
                WrapChips(step.refs) { ref in CodeRefChip(ref: ref) { onOpenEvidence(ref) } }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .reviewContextMenu(.flowStep(flowId: flow.id, stepId: step.id))
    }

    private func detailLine(_ symbol: String, _ text: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol).font(.caption2).foregroundStyle(.tertiary)
            Text(text).font(mono ? .system(.caption, design: .monospaced) : .caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var codeRung: some View {
        field("Evidence") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(refs) { ref in
                    CodeRefChip(ref: ref) { onOpenEvidence(ref) }
                }
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            content()
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption2.weight(.bold)).tracking(0.5).foregroundStyle(.secondary)
    }
}
