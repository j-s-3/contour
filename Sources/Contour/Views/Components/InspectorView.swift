import SwiftUI

/// The one place code-level detail concentrates: paths, line numbers, class names.
/// Every lens (Architecture, Decisions, Flows, Entry points) can hand this a selected
/// node's projection and get Purpose / Used by / Implementation / Changed-by-this-PR /
/// "Show implementation" / "Show diff" for free, instead of scattering that detail
/// across every screen.
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
                            Image(systemName: content.changedByThisPR ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(content.changedByThisPR ? .green : .secondary)
                            Text(content.changeClaim ?? (content.changedByThisPR ? "Yes" : "No"))
                                .font(.callout)
                        }
                    }
                    if !content.usedBy.isEmpty {
                        field("USED BY") {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(content.usedBy, id: \.self) { Text($0).font(.callout) }
                            }
                        }
                    }
                    if !content.implementedBy.isEmpty {
                        field("IMPLEMENTATION") {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(content.implementedBy, id: \.self) { name in
                                    Text(name).font(.system(.callout, design: .monospaced))
                                }
                            }
                        }
                    }
                    if !content.refs.isEmpty {
                        field("EVIDENCE") {
                            WrapChips(content.refs) { ref in CodeRefChip(ref: ref) { onOpenEvidence(ref) } }
                        }
                    }
                    HStack(spacing: 10) {
                        if let showImpl = content.onShowImplementation {
                            Button("Show implementation") { showImpl() }.buttonStyle(.bordered)
                        }
                        if let ref = content.refs.first {
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
            Text(content.kindLabel.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(content.title).font(.title3.weight(.semibold))
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.5)
            content()
        }
    }
}
