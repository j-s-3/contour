import SwiftUI

/// "What causes this?" — grouped triggers, each a short arrow to the flow/behavior it
/// causes. REST endpoint / method / code location moved to the inspector, not primary
/// text on this screen.
struct EntryPointsView: View {
    let graph: PRGraph
    var onOpenEvidence: (CodeRef) -> Void
    var onOpenFlow: (String) -> Void

    @State private var selected: EntryPointNode?

    var body: some View {
        if graph.entryPoints.isEmpty {
            ContentUnavailableView("No entry points detected", systemImage: "arrow.right.to.line",
                description: Text("This PR didn't add or change anything directly invocable."))
        } else {
            HSplitView {
                triggerList.frame(minWidth: 360)
                InspectorView(content: inspectorContent, onOpenEvidence: onOpenEvidence)
                    .frame(minWidth: 280, idealWidth: 320)
            }
        }
    }

    private var triggerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("What causes this?").font(.title3.weight(.semibold))
                ForEach(groupedByKind.keys.sorted(), id: \.self) { kind in
                    Text(kind.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(groupedByKind[kind] ?? []) { entry in
                        triggerRow(entry)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var groupedByKind: [String: [EntryPointNode]] {
        Dictionary(grouping: graph.entryPoints, by: { $0.kind })
    }

    private func triggerRow(_ entry: EntryPointNode) -> some View {
        Button { selected = entry } label: {
            HStack {
                ChangeKindBadge(kind: entry.changeKind)
                Text(entry.title).font(.callout.weight(.medium))
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Text(entry.triggersLabel ?? entry.flowId.flatMap { graph.flow($0)?.title } ?? "no traced flow")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if let flowId = entry.flowId, graph.flow(flowId) != nil {
                    Image(systemName: "chevron.right.2").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .background(selected?.id == entry.id ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var inspectorContent: InspectorContent? {
        guard let selected else { return nil }
        return InspectorContent(
            title: selected.title,
            kindLabel: selected.kind,
            purpose: nil,
            changedByThisPR: selected.changeKind == .new || selected.changeKind == .changed,
            changeClaim: selected.changeKind.rawValue.capitalized,
            refs: selected.refs,
            onShowImplementation: selected.flowId.flatMap { fid in
                graph.flow(fid) != nil ? { onOpenFlow(fid) } : nil
            }
        )
    }
}
