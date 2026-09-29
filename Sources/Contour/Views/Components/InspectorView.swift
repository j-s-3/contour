import SwiftUI

struct InspectorContent {
    var title: String
    var kindLabel: String
    var purpose: Statement?
    var usedBy: [String] = []
    var implementedBy: [String] = []
    var changedByThisPR: Bool
    var changeClaim: String?
    var refs: [CodeRef] = []
    var onShowImplementation: (() -> Void)?

    var changedByThisPRText: String { changeClaim ?? (changedByThisPR ? "Yes" : "No") }

    var kindLabelDisplay: String { kindLabel.uppercased() }

    var showsUsedBy: Bool { !usedBy.isEmpty }

    var showsImplementedBy: Bool { !implementedBy.isEmpty }

    var showsEvidence: Bool { !refs.isEmpty }

    var primaryRef: CodeRef? { refs.first }
}

struct InspectorView: View {
    let content: InspectorContent?
    var onOpenEvidence: (CodeRef) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let content {
                    header(content)
                    if let purpose = content.purpose {
                        field("PURPOSE") { StatementView(statement: purpose) }
                    }
                    field("CHANGED BY THIS PR") {
                        HStack(spacing: 6) {
                            Image(systemName: Self.changedIconName(content.changedByThisPR))
                                .foregroundStyle(Self.changedIconTint(content.changedByThisPR))
                            Text(content.changedByThisPRText)
                                .font(.callout)
                        }
                    }
                    if content.showsUsedBy {
                        field("USED BY") {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(content.usedBy, id: \.self) { Text($0).font(.callout) }
                            }
                        }
                    }
                    if content.showsImplementedBy {
                        field("IMPLEMENTATION") {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(content.implementedBy, id: \.self) { name in
                                    Text(name).font(.system(.callout, design: .monospaced))
                                }
                            }
                        }
                    }
                    if content.showsEvidence {
                        field("EVIDENCE") {
                            WrapChips(content.refs) { ref in CodeRefChip(ref: ref) { onOpenEvidence(ref) } }
                        }
                    }
                    HStack(spacing: 10) {
                        if let showImpl = content.onShowImplementation {
                            Button("Show implementation") { showImpl() }.buttonStyle(.bordered)
                        }
                        if let ref = content.primaryRef {
                            Button("Show diff") { onOpenEvidence(ref) }.buttonStyle(.bordered)
                        }
                    }
                } else {
                    Text("Select a node to inspect it.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ content: InspectorContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.kindLabelDisplay).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(content.title).font(.title3.weight(.semibold))
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.5)
            content()
        }
    }

    nonisolated static func changedIconName(_ changed: Bool) -> String {
        changed ? "checkmark.circle.fill" : "minus.circle"
    }

    nonisolated static func changedIconTint(_ changed: Bool) -> Color {
        changed ? .green : .secondary
    }
}
