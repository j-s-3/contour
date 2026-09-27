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
    @State private var urlText: String
    /// A pull request link waiting on the clipboard, offered inline so the reviewer
    /// doesn't have to paste it (see `ClipboardOffer`).
    @State private var clipboardOffer: ClipboardOffer?
    /// The clipboard contents the reviewer already declined, by change count, so the same
    /// link isn't offered again every time the window is activated.
    @State private var declinedChangeCount: Int?
    var markNamespace: Namespace.ID
    var onSubmit: (String) -> Void

    /// `initialURL` pre-fills the field — the PR the reviewer last tried, when they come
    /// back here from a failure — so a corrected or repeated attempt needs no re-paste.
    init(initialURL: String? = nil, markNamespace: Namespace.ID, onSubmit: @escaping (String) -> Void) {
        _urlText = State(initialValue: initialURL ?? "")
        self.markNamespace = markNamespace
        self.onSubmit = onSubmit
    }

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
                    .onSubmit(submit)
                    // ⌘V occasionally doesn't route through the standard responder chain
                    // in a bare SPM executable (no .app bundle/Edit menu wiring) — this is
                    // SwiftUI's own paste hook, independent of that plumbing.
                    .onPasteCommand(of: [.text, .url]) { providers in
                        guard let provider = providers.first else { return }
                        _ = provider.loadObject(ofClass: String.self) { text, _ in
                            guard let text else { return }
                            DispatchQueue.main.async { urlText = PRLink.extract(from: text) ?? text }
                        }
                    }
                // Fallback that never depends on keyboard-shortcut routing at all.
                Button {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        urlText = PRLink.extract(from: clip) ?? clip
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("Paste from clipboard")
                Button("Open", action: submit)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(GitHubService.normalize(urlText) == nil)
            }
            .padding(.top, 28)

            if let offer = clipboardOffer {
                clipboardOfferRow(offer)
                    .padding(.top, 14)
                    .transition(.opacity)
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
                .padding(.top, 16)
            }
            Spacer()
            // The optical centre sits a little above the geometric one.
            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: clipboardOffer)
        .task { await checkClipboard() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await checkClipboard() }
        }
    }

    private func submit() {
        guard GitHubService.normalize(urlText) != nil else { return }
        onSubmit(urlText)
    }

    private func clipboardOfferRow(_ offer: ClipboardOffer) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.secondary)
            switch offer {
            case .pullRequest(let url):
                Button {
                    onSubmit(url)
                } label: {
                    Text(verbatim: "Open \(PRLink.label(for: url) ?? url) from clipboard?")
                }
                .buttonStyle(.link)
                .help(url)
            case .unreadLink(let changeCount):
                Button("Open the link on your clipboard?") { openUnreadClipboard(changeCount) }
                    .buttonStyle(.link)
            }
            Button {
                declinedChangeCount = NSPasteboard.general.changeCount
                clipboardOffer = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Dismiss")
        }
        .font(.callout)
    }

    /// Looks for a PR link on the clipboard without tripping macOS's paste-access alert:
    /// pattern detection never reads the contents, and the contents are only read up
    /// front once the reviewer has let Contour read the clipboard. Otherwise the offer is
    /// generic and the read waits for their click.
    private func checkClipboard() async {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != declinedChangeCount else {
            clipboardOffer = nil
            return
        }
        // Before 15.4 there is no alert, so the clipboard can simply be read.
        if #available(macOS 15.4, *), pasteboard.accessBehavior != .alwaysAllow {
            let patterns = pasteboard.accessBehavior == .alwaysDeny ? []
                : (try? await pasteboard.detectedPatterns(for: [\.probableWebURL])) ?? []
            clipboardOffer = patterns.contains(\.probableWebURL) ? .unreadLink(changeCount: changeCount) : nil
            return
        }
        clipboardOffer = pasteboard.string(forType: .string)
            .flatMap(PRLink.extract(from:))
            .map(ClipboardOffer.pullRequest)
    }

    /// The reviewer asked for the clipboard, so read it now. A link that isn't a PR goes
    /// into the field rather than vanishing, so they can see why it didn't open.
    private func openUnreadClipboard(_ changeCount: Int) {
        clipboardOffer = nil
        declinedChangeCount = changeCount
        guard let clip = NSPasteboard.general.string(forType: .string) else { return }
        if let url = PRLink.extract(from: clip) {
            onSubmit(url)
        } else {
            urlText = clip
        }
    }
}

/// What the start screen can offer from the clipboard.
enum ClipboardOffer: Equatable {
    /// A PR link, read and recognized.
    case pullRequest(String)
    /// A web link that hasn't been read yet, because reading it would ask the reviewer for
    /// clipboard access before they've asked for anything.
    case unreadLink(changeCount: Int)
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

/// Opening the PR failed. "Try again" retries the same URL; the start screen (pre-filled
/// with that URL) is a separate, secondary way out, for when the URL itself was wrong.
struct FailedView: View {
    let message: String
    var onRetry: () -> Void
    var onOpenDifferent: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Couldn't open this PR", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: onRetry)
                .keyboardShortcut(.defaultAction)
            Button("Open a different PR", action: onOpenDifferent)
        }
    }
}
