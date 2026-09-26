import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The core workflow's entry point (§2): "the user pastes a GitHub pull request URL."
/// Nothing else — no repo picker, no auth flow, since `gh` is already authenticated.
struct OnboardingView: View {
    @State private var urlText: String = ""
    var onSubmit: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if let icon = AppDelegate.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)
            }
            Text("Contour").font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("Paste a GitHub pull request URL to build its review model.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("https://github.com/owner/repo/pull/123", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 420)
                    .onSubmit(submit)
                    // ⌘V occasionally doesn't route through the standard responder chain
                    // in a bare SPM executable (no .app bundle/Edit menu wiring) — this is
                    // SwiftUI's own paste hook, independent of that plumbing.
                    .onPasteCommand(of: [.text, .url]) { providers in
                        guard let provider = providers.first else { return }
                        _ = provider.loadObject(ofClass: String.self) { text, _ in
                            guard let text else { return }
                            DispatchQueue.main.async { urlText = text }
                        }
                    }
                // Fallback that never depends on keyboard-shortcut routing at all.
                Button {
                    if let clip = NSPasteboard.general.string(forType: .string) { urlText = clip }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("Paste from clipboard")
                Button("Open", action: submit)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(GitHubService.normalize(urlText) == nil)
            }

            // Mock mode only: the canned analysis matches exactly one PR, so offer it
            // directly rather than making the tester remember its URL.
            if MockAnalysisFixtures.isEnabled {
                Button {
                    onSubmit(MockAnalysisFixtures.sourcePRURL)
                } label: {
                    Label("Load test data", systemImage: "testtube.2")
                }
                .help(MockAnalysisFixtures.sourcePRURL)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        guard GitHubService.normalize(urlText) != nil else { return }
        onSubmit(urlText)
    }
}

struct FailedView: View {
    let message: String
    var onRetry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Couldn't open this PR", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: onRetry)
        }
    }
}
