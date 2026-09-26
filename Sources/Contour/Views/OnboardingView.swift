import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The core workflow's entry point (§2): "the user pastes a GitHub pull request URL."
/// Nothing else — no repo picker, no auth flow, since `gh` is already authenticated.
///
/// The raw Contour mark, not the app icon: the rounded-square tile belongs to the Dock
/// and Finder. Inside the app the mark is the brand, and the same mark resolves while a
/// PR is analyzed, so it is matched across the two screens.
struct OnboardingView: View {
    @State private var urlText: String = ""
    @FocusState private var urlFieldFocused: Bool
    var markNamespace: Namespace.ID
    /// Changes whenever File ▸ Open Pull Request… asks for the URL field.
    var focusRequest: Int = 0
    var onSubmit: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ContourMarkView()
                .matchesContourMark(in: markNamespace)
                .frame(height: ContourMarkView.heroHeight)
            Text("Contour")
                .font(.system(size: 28, weight: .semibold))
                .padding(.top, 22)
            Text("Understand the change, not just the diff.")
                .font(.title3)
                .padding(.top, 10)
            Text("See what changed, how the system works, and which decisions deserve your attention.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(.top, 6)

            HStack {
                TextField("Paste a GitHub pull request URL…", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 420)
                    .focused($urlFieldFocused)
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
            .padding(.top, 28)

            // Mock mode only: the canned analysis matches exactly one PR, so offer it
            // directly rather than making the tester remember its URL.
            if MockAnalysisFixtures.isEnabled {
                Button {
                    onSubmit(MockAnalysisFixtures.sourcePRURL)
                } label: {
                    Label("Load test data", systemImage: "testtube.2")
                }
                .help(MockAnalysisFixtures.sourcePRURL)
                .padding(.top, 16)
            }
            Spacer()
            // The optical centre sits a little above the geometric one.
            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The start screen exists to take a URL, so it arrives ready for one.
        .onAppear { urlFieldFocused = true }
        .onChange(of: focusRequest) { urlFieldFocused = true }
    }

    private func submit() {
        guard GitHubService.normalize(urlText) != nil else { return }
        onSubmit(urlText)
    }
}

/// Shown while the PR itself is fetched — the one wait left before the review opens (the
/// analysis then fills in the open review; see `AnalysisIndicator`). The Contour mark
/// resolving as it goes,
/// what's happening in words, and the latest real substep from the harness — so progress
/// never depends on the mark alone, and never on a bare spinner (§10). The full tool-call
/// log is one click away for anyone who wants to watch the work.
struct AnalyzingView: View {
    let stage: PipelineStage
    let log: [PipelineProgressEntry]
    var markNamespace: Namespace.ID

    @AppStorage("showsAnalysisActivity") private var showsActivity = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()
                AnalyzingMark(stage: stage)
                    .matchesContourMark(in: markNamespace)
                    .frame(height: ContourMarkView.heroHeight)
                Text(Self.headline(stage))
                    .font(.title3)
                    .padding(.top, 28)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: Self.headline(stage))
                Text(latestDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
                    .padding(.top, 6)
                Spacer()
                if !showsActivity { Spacer().frame(height: 60) }
                activityToggle
                    .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsActivity {
                Divider()
                console
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What Contour is working out, in the reviewer's terms rather than the pipeline's.
    static func headline(_ stage: PipelineStage) -> String {
        switch stage {
        case .fetching, .checkingOut, .cacheCheck: return "Opening the pull request…"
        case .ticket, .behaviorChange, .understanding: return "Understanding the change…"
        case .architecture: return "Analyzing architecture…"
        case .decisions: return "Finding the decisions it makes…"
        case .flows: return "Tracing the flows it touches…"
        case .judgment: return "Deciding what needs your judgment…"
        }
    }

    private var latestDetail: String {
        guard let last = log.last else { return stage.rawValue }
        return last.detail.isEmpty ? last.stage : "\(last.stage) — \(last.detail)"
    }

    private var activityToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { showsActivity.toggle() }
        } label: {
            Label(showsActivity ? "Hide activity" : "Show activity",
                  systemImage: showsActivity ? "chevron.down" : "chevron.up")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Every step the harness takes as it reads the repository")
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
            .onAppear { if let last = log.last { proxy.scrollTo(last.id, anchor: .bottom) } }
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
            Label("Couldn't open this PR", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: onRetry)
        }
    }
}
