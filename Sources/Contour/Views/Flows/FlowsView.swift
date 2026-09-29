import SwiftUI

struct FlowsView: View {
    let graph: PRGraph
    var focus: Focus? = nil
    @Binding var mode: DiagramMode
    var onOpenEvidence: (CodeRef) -> Void

    struct Focus: Equatable {
        var flowId: String
        var nodeId: String? = nil
    }

    @Environment(\.reviewActions) private var actions
    @State private var selectedFlowId: String?
    @State private var selectedNodeId: String?
    @State private var level: FlowDrillLevel = .behavior
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        if graph.flows.isEmpty {
            ContentUnavailableView("No flows traced", systemImage: "arrow.triangle.branch",
                description: Text("No entry point in this PR had an execution path worth tracing end to end."))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                HStack(spacing: 0) {
                    diagram
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let flow = currentFlow, let node = selectedNode {
                        Divider()
                        FlowStageInspector(
                            graph: graph, flow: flow, node: node, level: $level,
                            onSelectNode: { select($0) },
                            onOpenEvidence: onOpenEvidence,
                            onOpenFlow: { openFlow($0) },
                            onClose: { select(nil) }
                        )
                        .frame(width: 360)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: selectedNodeId)
            }
            .background(
                Button("") { select(nil) }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .disabled(selectedNodeId == nil)
            )
            .focusable()
            .focusEffectDisabled()
            .focused($keyboardFocused)
            .diagramModeKeys($mode)
            .onKeyPress(phases: .down) { press in handleKey(press) }
            .onAppear {
                keyboardFocused = true
                apply(focus)
                if selectedFlowId == nil { selectedFlowId = graph.flows.first?.id }
                publishFocus()
            }
            .onChange(of: focus) { _, new in apply(new) }
            .onChange(of: selectedFlowId) { _, _ in publishFocus() }
            .onChange(of: selectedNodeId) { _, _ in
                keyboardFocused = true
                publishFocus()
            }
            .onDisappear { actions.focus(nil) }
        }
    }

    private var currentFlow: FlowNode? { FlowsViewLogic.currentFlow(in: graph, selectedFlowId: selectedFlowId) }
    private var currentBehavior: FlowBehavior? { currentFlow.map { graph.behavior(for: $0) } }
    private var selectedNode: FlowBehaviorNode? { currentBehavior?.node(selectedNodeId) }

    private func apply(_ focus: Focus?) {
        guard let result = FlowsViewLogic.applying(focus, to: graph) else { return }
        selectedFlowId = result.selectedFlowId
        selectedNodeId = result.selectedNodeId
        level = result.level
    }

    private func openFlow(_ id: String) {
        guard let result = FlowsViewLogic.opening(id, in: graph) else { return }
        selectedFlowId = result.selectedFlowId
        selectedNodeId = result.selectedNodeId
        keyboardFocused = true
    }

    private func select(_ node: FlowBehaviorNode?) {
        let result = FlowsViewLogic.selecting(node, currentSelectedNodeId: selectedNodeId)
        if let newLevel = result.level { level = newLevel }
        selectedNodeId = result.nodeId
        keyboardFocused = true
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard FlowsViewLogic.recognizesScenarioKey(press.characters, modifiers: press.modifiers, flowCount: graph.flows.count),
              let offset = FlowsViewLogic.scenarioOffset(for: press.characters) else { return .ignored }
        if let next = graph.scenario(offset, from: currentFlow?.id) { openFlow(next.id) }
        return .handled
    }

    private func drill(_ node: FlowBehaviorNode) {
        guard let flow = currentFlow else { return }
        let available = FlowDrillLevel.available(for: node, in: flow, graph: graph)
        let result = FlowsViewLogic.drilling(node, currentSelectedNodeId: selectedNodeId, currentLevel: level, available: available)
        selectedNodeId = result.nodeId
        level = result.level
    }

    private func showImplementation(_ node: FlowBehaviorNode) {
        selectedNodeId = node.id
        level = .implementation
    }

    private func publishFocus() {
        guard let subject = FlowsViewLogic.focusToPublish(flow: currentFlow, node: selectedNode) else {
            return actions.focus(nil)
        }
        actions.focus(subject)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                if graph.flows.count > 1 { scenarioTabs } else { Spacer(minLength: 0) }
                Spacer(minLength: 12)
                if let flow = currentFlow {
                    Button { actions.ask(.flow(flow.id)) } label: {
                        Label("Ask", systemImage: "sparkles").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Ask about this flow… (⌘⇧A)")
                }
            }
            if let flow = currentFlow, let behavior = currentBehavior {
                story(flow, behavior)
            }
            DiagramModeControl(mode: $mode, subject: "flow")
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var scenarioTabs: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("What happens when… · \(graph.flows.count) scenarios")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("[ ] to switch")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(graph.flows) { flow in
                        scenarioTab(flow, selected: flow.id == currentFlow?.id)
                    }
                }
            }
        }
    }

    private func scenarioTab(_ flow: FlowNode, selected: Bool) -> some View {
        let changed = graph.behavior(for: flow).hasChange
        return Button { openFlow(flow.id) } label: {
            (Text(graph.scenarioTitle(for: flow))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
             + Text(changed ? " · changed" : "")
                .font(.callout)
                .foregroundStyle(Color.blue))
                .lineLimit(1)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selected ? Color.accentColor : .clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(changed ? "This PR changes this flow" : "Unchanged by this PR — shown for context")
        .reviewContextMenu(.flow(flow.id))
    }

    @ViewBuilder
    private func story(_ flow: FlowNode, _ behavior: FlowBehavior) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if graph.flows.count <= 1 {
                Text(graph.scenarioTitle(for: flow))
                    .font(.system(size: 22, weight: .semibold))
                    .reviewContextMenu(.flow(flow.id))
            }
            if let summary = behavior.summary {
                Text(summary)
                    .font(graph.flows.count > 1 ? .title3 : .body)
                    .foregroundStyle(graph.flows.count > 1 ? .primary : .secondary)
                    .lineLimit(3)
                    .frame(maxWidth: 760, alignment: .leading)
            }
            changeLine(behavior)
            convergence(flow)
        }
    }

    @ViewBuilder
    private func changeLine(_ behavior: FlowBehavior) -> some View {
        let text = behavior.changeSummary ?? condensedChangeSummary(behavior)
        if let text {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("THIS PR")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.blue)
                Text(text)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
            }
            .frame(maxWidth: 760, alignment: .leading)
        } else if !behavior.hasChange {
            Text("This PR doesn't change this flow — it's shown for context.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func condensedChangeSummary(_ behavior: FlowBehavior) -> String? {
        FlowsViewLogic.condensedChangeSummary(behavior)
    }

    @ViewBuilder
    private func convergence(_ flow: FlowNode) -> some View {
        let sources = graph.flowsConverging(into: flow.id)
        if !sources.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.merge").font(.caption).foregroundStyle(.secondary)
                Text("Also reached from").font(.caption).foregroundStyle(.secondary)
                ForEach(sources) { source in
                    Button(graph.scenarioTitle(for: source)) { openFlow(source.id) }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var diagram: some View {
        if let flow = currentFlow, let behavior = currentBehavior {
            let visible = behavior.visible(in: mode)
            let ids = Set(visible.nodes.map(\.id))
            BehaviorDiagramView(
                flowId: flow.id,
                behavior: visible,
                annotations: graph.annotations(for: flow).filter { ids.contains($0.nodeId) },
                mode: mode,
                selectedNodeId: selectedNodeId,
                onSelect: { node in select(selectedNodeId == node.id ? nil : node) },
                onDrill: drill,
                onShowImplementation: showImplementation,
                onOpenAnnotation: { note in
                    switch note.kind {
                    case .decision: actions.navigate(.decisionDetail(note.targetId))
                    case .question: actions.navigate(.consideration(note.targetId))
                    }
                },
                onOpenSubflow: openFlow,
                subflowTitle: { id in graph.flow(id).map { graph.scenarioTitle(for: $0) } }
            )
            .id("\(flow.id)-\(mode.rawValue)")
            .background(.background)
            .onChange(of: mode) { _, new in
                if let node = selectedNode, !node.change.isVisible(in: new) { select(nil) }
            }
        }
    }
}

enum FlowsViewLogic {
    static func scenarioOffset(for characters: String) -> Int? {
        switch characters {
        case "[": return -1
        case "]": return 1
        default: return nil
        }
    }

    static func recognizesScenarioKey(_ characters: String, modifiers: EventModifiers, flowCount: Int) -> Bool {
        flowCount > 1
            && modifiers.isDisjoint(with: [.command, .control, .option])
            && scenarioOffset(for: characters) != nil
    }

    static func nextLevel(after level: FlowDrillLevel, available: [FlowDrillLevel]) -> FlowDrillLevel {
        available.first { $0 > level } ?? level
    }

    static func condensedChangeSummary(_ behavior: FlowBehavior) -> String? {
        let changed = behavior.nodes.filter { $0.change != .existing && $0.kind != .trigger }
        guard !changed.isEmpty else { return nil }
        return "Changes " + changed.prefix(3).map { "“\($0.label)”" }.joined(separator: ", ")
            + (changed.count > 3 ? ", and \(changed.count - 3) more" : "") + "."
    }

    static func currentFlow(in graph: PRGraph, selectedFlowId: String?) -> FlowNode? {
        graph.flow(selectedFlowId) ?? graph.flows.first
    }

    static func applying(_ focus: FlowsView.Focus?, to graph: PRGraph)
        -> (selectedFlowId: String, selectedNodeId: String?, level: FlowDrillLevel)? {
        guard let focus, graph.flow(focus.flowId) != nil else { return nil }
        return (focus.flowId, focus.nodeId, .behavior)
    }

    static func opening(_ id: String, in graph: PRGraph) -> (selectedFlowId: String, selectedNodeId: String?)? {
        guard graph.flow(id) != nil else { return nil }
        return (id, nil)
    }

    static func selecting(_ node: FlowBehaviorNode?, currentSelectedNodeId: String?)
        -> (nodeId: String?, level: FlowDrillLevel?) {
        let changesSelection = node?.id != currentSelectedNodeId
        let resetLevel: FlowDrillLevel? = changesSelection ? .behavior : nil
        return (node?.id, resetLevel)
    }

    static func drilling(_ node: FlowBehaviorNode, currentSelectedNodeId: String?, currentLevel: FlowDrillLevel,
                          available: [FlowDrillLevel]) -> (nodeId: String, level: FlowDrillLevel) {
        if currentSelectedNodeId != node.id {
            return (node.id, nextLevel(after: .behavior, available: available))
        }
        return (node.id, nextLevel(after: currentLevel, available: available))
    }

    static func focusToPublish(flow: FlowNode?, node: FlowBehaviorNode?) -> ReviewSubject? {
        guard let flow else { return nil }
        if let node { return .flowNode(flowId: flow.id, nodeId: node.id) }
        return .flow(flow.id)
    }
}
