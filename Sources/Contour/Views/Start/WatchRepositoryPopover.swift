import SwiftUI

struct WatchRepositoryPopover: View {
    let suggestions: [String]
    var onWatch: (String) -> Void
    @State private var text: String
    @FocusState private var fieldFocused: Bool

    init(suggestions: [String], initialText: String = "", onWatch: @escaping (String) -> Void) {
        self.suggestions = suggestions
        self.onWatch = onWatch
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("owner/repo or a GitHub URL", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(confirm)
                Button("Watch", action: confirm)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!StartScreenLogic.canWatch(text))
            }
            if !suggestions.isEmpty {
                Text("From your recent pull requests")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onWatch(suggestion)
                    } label: {
                        Text(verbatim: suggestion)
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { fieldFocused = true }
    }

    private func confirm() {
        guard StartScreenLogic.canWatch(text) else { return }
        onWatch(text)
    }
}
