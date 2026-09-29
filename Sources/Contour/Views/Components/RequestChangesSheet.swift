import SwiftUI

struct RequestChangesSheet: View {
    let title: String
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var comment = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title).font(.headline)
            Text("This submits a review requesting changes on GitHub as you, through gh.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $comment)
                .font(.body)
                .focused($editorFocused)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if Self.showsPlaceholder(comment: comment) {
                        Text("What should change?")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .accessibilityLabel("What should change")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Request Changes") {
                    Self.submit(comment: comment, onSubmit: onSubmit) { dismiss() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!PRReview.isReady(.requestChanges, comment: comment))
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { editorFocused = true }
    }

    static func submit(comment: String, onSubmit: (String) -> Void, dismiss: () -> Void) {
        onSubmit(comment)
        dismiss()
    }

    static func showsPlaceholder(comment: String) -> Bool {
        comment.isEmpty
    }
}
