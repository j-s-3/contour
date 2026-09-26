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
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        guard GitHubService.normalize(urlText) != nil else { return }
        onSubmit(urlText)
    }
}

/// Shown while the pipeline runs. Real substeps from the JSONL stream, not a spinner —
/// this is the "progress panel shows real substeps" behavior from the worked example.
/// Fills the whole window: a stage rail across the top so the reviewer can see where
/// they are across every stage, then a full-size scrolling console underneath so the
/// (often long) tool-call log is actually readable instead of squeezed into a small box.
struct AnalyzingView: View {
    let stage: PipelineStage
    let log: [PipelineProgressEntry]

    private static let orderedStages: [PipelineStage] = [
        .fetching, .checkingOut, .cacheCheck, .ticket, .architecture, .intent, .eli5,
        .decisions, .flows, .judgment
    ]

    var body: some View {
        VStack(spacing: 0) {
            stageRail
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            Divider()
            console
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stageRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(stage.rawValue).font(.title2.weight(.semibold))
            }
            HStack(spacing: 6) {
                ForEach(Array(Self.orderedStages.enumerated()), id: \.element) { index, s in
                    stagePill(s)
                    if index < Self.orderedStages.count - 1 {
                        Rectangle()
                            .fill(stageIndex(s) < stageIndex(stage) ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(height: 2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stagePill(_ s: PipelineStage) -> some View {
        let current = stageIndex(s) == stageIndex(stage)
        let done = stageIndex(s) < stageIndex(stage)
        return HStack(spacing: 5) {
            Image(systemName: done ? "checkmark.circle.fill" : (current ? "circle.fill" : "circle"))
                .font(.caption2)
                .foregroundStyle(done ? Color.accentColor : (current ? Color.accentColor : Color.secondary.opacity(0.5)))
            Text(shortLabel(s))
                .font(.caption.weight(current ? .semibold : .regular))
                .foregroundStyle(current ? Color.primary : (done ? Color.secondary : Color.secondary.opacity(0.6)))
        }
        .fixedSize()
    }

    private func stageIndex(_ s: PipelineStage) -> Int { Self.orderedStages.firstIndex(of: s) ?? 0 }

    private func shortLabel(_ s: PipelineStage) -> String {
        switch s {
        case .fetching: return "Fetch"
        case .checkingOut: return "Checkout"
        case .cacheCheck: return "Cache"
        case .ticket: return "Issue"
        case .behaviorChange: return "Behavior"
        case .architecture: return "Architecture"
        case .intent: return "Intent"
        case .eli5: return "Plain-language"
        case .decisions: return "Decisions"
        case .flows: return "Flows"
        case .judgment: return "Judgment"
        case .done: return "Done"
        }
    }

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(log) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(entry.stage)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 160, alignment: .leading)
                                .lineLimit(1)
                            Text(entry.detail)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .id(entry.id)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: log.count) { _, _ in
                if let last = log.last {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

struct FailedView: View {
    let message: String
    var onRetry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Analysis failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: onRetry)
        }
    }
}
