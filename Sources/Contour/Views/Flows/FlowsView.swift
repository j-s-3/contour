import SwiftUI

/// The Flows lens (§4.6): "show me what happens when…". Each flow is a scenario ("Open a
/// file", "Pipe data into bat") drawn as runtime behavior — trigger, stages, branches,
/// outcomes, and the boundaries it crosses — with what this PR changed emphasized and the
/// decisions and review questions pinned where they matter.
///
/// The diagram owns the screen. Scenarios are tabs across the top ([ and ] step through
/// them); an inspector opens beside the diagram only once a stage is selected, and walks down
/// the abstraction ladder — behavior, steps, implementation, code — rather than leading with
/// the call trace.
struct FlowsView: View {
    let graph: PRGraph
    /// A flow, and optionally a stage in it, that navigation asked for.
    var focus: Focus? = nil
    /// Before this PR / after it / what it changed — shared with Architecture.
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
                // Clicking a stage takes focus back from the chat, so B / A / D work again.
                keyboardFocused = true
                publishFocus()
            }
            .onDisappear { actions.focus(nil) }
        }
    }

    // MARK: - State

    private var currentFlow: FlowNode? { graph.flow(selectedFlowId) ?? graph.flows.first }
    private var currentBehavior: FlowBehavior? { currentFlow.map { graph.behavior(for: $0) } }
    private var selectedNode: FlowBehaviorNode? { currentBehavior?.node(selectedNodeId) }

    private func apply(_ focus: Focus?) {
        guard let focus, graph.flow(focus.flowId) != nil else { return }
        selectedFlowId = focus.flowId
        selectedNodeId = focus.nodeId
        level = .behavior
    }

    private func openFlow(_ id: String) {
        guard graph.flow(id) != nil else { return }
        selectedFlowId = id
        selectedNodeId = nil
        keyboardFocused = true
    }

    private func select(_ node: FlowBehaviorNode?) {
        if node?.id != selectedNodeId { level = .behavior }
        selectedNodeId = node?.id
        keyboardFocused = true
    }

    /// [ and ] cycle scenarios, like the Decisions lens's J and K. Shortcuts with a modifier
    /// aren't ours.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard graph.flows.count > 1,
              press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        let offset: Int
        switch press.characters {
        case "[": offset = -1
        case "]": offset = 1
        default: return .ignored
        }
        if let next = graph.scenario(offset, from: currentFlow?.id) { openFlow(next.id) }
        return .handled
    }

    /// Double-click: step one rung down the ladder.
    private func drill(_ node: FlowBehaviorNode) {
        guard let flow = currentFlow else { return }
        let available = FlowDrillLevel.available(for: node, in: flow, graph: graph)
        if selectedNodeId != node.id {
            selectedNodeId = node.id
            level = available.first { $0 > .behavior } ?? .behavior
        } else {
            level = available.first { $0 > level } ?? level
        }
    }

    private func showImplementation(_ node: FlowBehaviorNode) {
        selectedNodeId = node.id
        level = .implementation
    }

    /// Tells the window what "this" is for ⌘⇧A.
    private func publishFocus() {
        guard let flow = currentFlow else { return actions.focus(nil) }
        if let node = selectedNode {
            actions.focus(.flowNode(flowId: flow.id, nodeId: node.id))
        } else {
            actions.focus(.flow(flow.id))
        }
    }

    // MARK: - Header

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
            // Last in the header, so it sits on the edge of the drawing it filters.
            DiagramModeControl(mode: $mode, subject: "flow")
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    /// Which scenarios can I explore? A labeled row of tabs, the selected one underlined.
    /// Whether the PR changes a scenario is part of its name ("· changed"), not a dot that
    /// reads as selection.
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

    /// The ten-second version: what happens, and what this PR changed about it. With several
    /// scenarios the selected tab already names the flow, so the story leads instead.
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

    /// Older analyses carry no change sentence; name the stages that changed instead.
    private func condensedChangeSummary(_ behavior: FlowBehavior) -> String? {
        let changed = behavior.nodes.filter { $0.change != .existing && $0.kind != .trigger }
        guard !changed.isEmpty else { return nil }
        return "Changes " + changed.prefix(3).map { "“\($0.label)”" }.joined(separator: ", ")
            + (changed.count > 3 ? ", and \(changed.count - 3) more" : "") + "."
    }

    /// Several triggers converging on this flow, or this flow handing off to a shared one.
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

    // MARK: - Diagram

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
