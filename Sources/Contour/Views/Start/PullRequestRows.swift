import SwiftUI

struct ClipboardOfferRow: View {
    let offer: ClipboardOffer
    var onOpen: (String) -> Void
    var onOpenUnread: (Int) -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.secondary)
            switch offer {
            case .pullRequest(let url):
                Button {
                    onOpen(url)
                } label: {
                    Text(verbatim: "Open \(PRLink.label(for: url) ?? url) from clipboard?")
                }
                .buttonStyle(.link)
                .help(url)
            case .unreadLink(let changeCount):
                Button("Open the link on your clipboard?") { onOpenUnread(changeCount) }
                    .buttonStyle(.link)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Dismiss")
        }
        .font(.callout)
    }
}

struct StartListHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

extension StartListHeader where Trailing == EmptyView {
    init(title: String, systemImage: String) {
        self.init(title: title, systemImage: systemImage) { EmptyView() }
    }
}

struct PullRequestRow: View {
    let title: String
    let repo: String?
    let number: Int
    let detail: String?
    let date: Date?
    let dateVerb: String
    let url: String
    var labels: [String] = []
    var onOpen: (String) -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            onOpen(url)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ForEach(labels, id: \.self) { label in
                        PullRequestLabel(text: label)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url)
    }

    private var subtitle: String {
        StartScreenLogic.subtitle(repo: repo, number: number, detail: detail, date: date, dateVerb: dateVerb)
    }
}

struct PullRequestLabel: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18)))
    }
}
