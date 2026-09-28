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

    /// What "CHANGED BY THIS PR" says: the author's own claim if there is one (even for an
    /// unchanged node — "Untouched; listed for context" — since a claim always outranks the
    /// plain yes/no), otherwise a plain yes/no from whether this node changed at all.
    var changedByThisPRText: String { changeClaim ?? (changedByThisPR ? "Yes" : "No") }

    /// The header's kind eyebrow, upper-cased the way it renders.
    var kindLabelDisplay: String { kindLabel.uppercased() }

    /// Whether the "USED BY" field has anything to show — the field is hidden entirely
    /// rather than rendered empty.
    var showsUsedBy: Bool { !usedBy.isEmpty }

    /// Whether the "IMPLEMENTATION" field has anything to show.
    var showsImplementedBy: Bool { !implementedBy.isEmpty }

    /// Whether the "EVIDENCE" field has anything to show. "Show diff" reuses `primaryRef`,
    /// so it hides under the same condition.
    var showsEvidence: Bool { !refs.isEmpty }

    /// The ref "Show diff" opens: the first piece of evidence, if there is one.
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

    /// The "CHANGED BY THIS PR" icon: a filled checkmark when it did, a plain minus when
    /// it didn't.
    nonisolated static func changedIconName(_ changed: Bool) -> String {
        changed ? "checkmark.circle.fill" : "minus.circle"
    }

    /// The icon's tint, matching `changedIconName`.
    nonisolated static func changedIconTint(_ changed: Bool) -> Color {
        changed ? .green : .secondary
    }
}
