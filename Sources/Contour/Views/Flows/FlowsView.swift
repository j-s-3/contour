import SwiftUI

/// Default rendering shows `storySteps` — a short labeled vertical arrow chain, one flow
/// per user/system scenario. Selecting a story step expands to the implementation-level
/// `steps` detail beneath it, progressive disclosure rather than a wall of text.
struct FlowsView: View {
    let graph: PRGraph
    /// A flow the navigation target asked for.
    var focusFlowId: String? = nil
    var onOpenEvidence: (CodeRef) -> Void

    @Environment(\.reviewActions) private var actions
    @State private var selectedFlowId: String?
    @State private var expandedStoryIndex: Int?

    var body: some View {
        if graph.flows.isEmpty {
            ContentUnavailableView("No flows traced", systemImage: "arrow.triangle.branch",
                description: Text("No entry point in this PR had a execution path worth tracing end to end."))
        } else {
            HSplitView {
                flowPicker.frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
                storyPane.frame(minWidth: 340)
            }
            .onAppear {
                if let focusFlowId { selectedFlowId = focusFlowId }
                if selectedFlowId == nil { selectedFlowId = graph.flows.first?.id }
                actions.focus(selectedFlowId.map { .flow($0) })
            }
            .onChange(of: focusFlowId) { _, new in if let new { selectedFlowId = new; expandedStoryIndex = nil } }
            .onChange(of: selectedFlowId) { _, new in actions.focus(new.map { .flow($0) }) }
            .onDisappear { actions.focus(nil) }
        }
    }

    private var currentFlow: FlowNode? { graph.flow(selectedFlowId) }

    private var flowPicker: some View {
        List(graph.flows, selection: Binding(get: { selectedFlowId }, set: { selectedFlowId = $0; expandedStoryIndex = nil })) { flow in
            Text(flow.title).tag(flow.id as String?)
                .reviewContextMenu(.flow(flow.id))
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var storyPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let flow = currentFlow {
                    HStack(alignment: .firstTextBaseline) {
                        Text(flow.title).font(.title3.weight(.semibold))
                        Spacer()
                        Button { actions.ask(.flow(flow.id)) } label: {
                            Label("Ask", systemImage: "sparkles").font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Ask about this flow… (⌘⇧A)")
                    }
                    .padding(.bottom, 6)
                    .reviewContextMenu(.flow(flow.id))
                    if flow.storySteps.isEmpty {
                        Text("No story-level steps recorded — see implementation steps below.")
                            .font(.callout).foregroundStyle(.secondary)
                        implementationSteps(flow.steps, flowId: flow.id)
                    } else {
                        ForEach(Array(flow.storySteps.enumerated()), id: \.offset) { index, story in
                            storyRow(index: index, story: story, isLast: index == flow.storySteps.count - 1, flow: flow)
                        }
                    }
                } else {
                    Text("Select a flow.").foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func storyRow(index: Int, story: Statement, isLast: Bool, flow: FlowNode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expandedStoryIndex = (expandedStoryIndex == index) ? nil : index
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                        if !isLast {
                            Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1.4).frame(minHeight: 26)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            ProvenanceBadge(provenance: story.provenance, confidence: story.confidence)
                            Text(story.text).font(.callout.weight(.medium))
                            Image(systemName: expandedStoryIndex == index ? "chevron.down" : "chevron.right")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.bottom, isLast ? 0 : 14)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .reviewContextMenu(.storyStep(flowId: flow.id, index: index))

            if expandedStoryIndex == index {
                let relatedSteps = matchingSteps(for: index, in: flow)
                if !relatedSteps.isEmpty {
                    implementationSteps(relatedSteps, flowId: flow.id)
                        .padding(.leading, 18)
                        .padding(.bottom, 10)
                }
            }
        }
    }

    /// Naive alignment of implementation steps to a story step: proportional bucketing by
    /// index, since the AI doesn't currently link story steps to implementation steps by
    /// ID. Good enough for progressive disclosure without inventing a new schema field.
    private func matchingSteps(for storyIndex: Int, in flow: FlowNode) -> [FlowStep] {
        guard !flow.steps.isEmpty, !flow.storySteps.isEmpty else { return flow.steps }
        let bucketSize = max(1, flow.steps.count / flow.storySteps.count)
        let start = storyIndex * bucketSize
        let end = (storyIndex == flow.storySteps.count - 1) ? flow.steps.count : min(flow.steps.count, start + bucketSize)
        guard start < end else { return [] }
        return Array(flow.steps[start..<end])
    }

    private func implementationSteps(_ steps: [FlowStep], flowId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(steps) { step in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(step.title).font(.callout)
                        ChangeKindBadge(kind: step.changeKind)
                        if step.caution != nil {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption2)
                        }
                    }
                    if let stateDelta = step.stateDelta {
                        Text(stateDelta).font(.caption).foregroundStyle(.secondary)
                    }
                    if !step.branches.isEmpty || !step.externalCalls.isEmpty || !step.errorPaths.isEmpty {
                        HStack(spacing: 10) {
                            if !step.branches.isEmpty { detailChip("branch", step.branches.count, "arrow.triangle.branch") }
                            if !step.externalCalls.isEmpty { detailChip("call", step.externalCalls.count, "network") }
                            if !step.errorPaths.isEmpty { detailChip("error path", step.errorPaths.count, "exclamationmark.octagon") }
                        }
                    }
                    if let caution = step.caution {
                        Text(caution).font(.caption).foregroundStyle(.orange)
                    }
                    if !step.refs.isEmpty {
                        WrapChips(step.refs) { ref in CodeRefChip(ref: ref) { onOpenEvidence(ref) } }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .reviewContextMenu(.flowStep(flowId: flowId, stepId: step.id))
            }
        }
    }

    private func detailChip(_ label: String, _ count: Int, _ symbol: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.caption2)
            Text("\(count) \(label)\(count == 1 ? "" : "s")").font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}
