import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The core workflow's entry point (§2): "the user pastes a GitHub pull request URL."
/// No repo picker, no auth flow, since `gh` is already authenticated.
///
/// Under the URL field, the PRs a review session most often starts from, so the reviewer
/// doesn't have to go and find a URL first: PRs awaiting their review (when `gh` can say)
/// and the ones they opened recently (instant to reopen, from the analysis cache). The URL
/// field stays for everything else.
///
/// The raw Contour mark, not the app icon: the rounded-square tile belongs to the Dock
/// and Finder. Inside the app the mark is the brand, and the same mark resolves while a
/// PR is analyzed, so it is matched across the two screens.
struct OnboardingView: View {
    @State private var urlText: String
    @FocusState private var urlFieldFocused: Bool
    /// A pull request link waiting on the clipboard, offered inline so the reviewer
    /// doesn't have to paste it (see `ClipboardOffer`).
    @State private var clipboardOffer: ClipboardOffer?
    /// The clipboard contents the reviewer already declined, by change count, so the same
    /// link isn't offered again every time the window is activated.
    @State private var declinedChangeCount: Int?
    @State private var recents: [AnalysisCache.RecentPR] = []
    /// Nil until `gh` has answered, or when it can't be asked.
    @State private var reviewRequests: [ReviewRequest]?
    var markNamespace: Namespace.ID
    /// Changes whenever File ▸ Open Pull Request… asks for the URL field.
    var focusRequest: Int
    var onSubmit: (String) -> Void

    /// Rows per list: enough to cover a working week's PRs without pushing the welcome
    /// off-centre.
    static let rowsShown = 5

    /// `initialURL` pre-fills the field — the PR the reviewer last tried, when they come
    /// back here from a failure — so a corrected or repeated attempt needs no re-paste.
    init(initialURL: String? = nil, markNamespace: Namespace.ID, focusRequest: Int = 0,
         onSubmit: @escaping (String) -> Void) {
        _urlText = State(initialValue: initialURL ?? "")
        self.markNamespace = markNamespace
        self.focusRequest = focusRequest
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
                    .focused($urlFieldFocused)
                    .onSubmit(submit)
                    // ⌘V occasionally doesn't route through the standard responder chain
                    // in a bare SPM executable (no .app bundle/Edit menu wiring) — this is
                    // SwiftUI's own paste hook, independent of that plumbing.
                    .onPasteCommand(of: [.text, .url]) { providers in
                        guard let provider = providers.first else { return }
                        Task {
                            // `loadObject`'s completion handler is `@Sendable`; bridging it
                            // through a continuation keeps `urlText` (an `@State`, not
                            // `Sendable`) out of that closure entirely.
                            guard let text = await withCheckedContinuation({ continuation in
                                _ = provider.loadObject(ofClass: String.self) { text, _ in
                                    continuation.resume(returning: text)
                                }
                            }) else { return }
                            urlText = OnboardingViewLogic.resolvedPasteText(text)
                        }
                    }
                // Fallback that never depends on keyboard-shortcut routing at all.
                Button {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        urlText = OnboardingViewLogic.resolvedPasteText(clip)
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

            pullRequestLists
                .padding(.top, 32)
            Spacer()
            // The optical centre sits a little above the geometric one.
            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The start screen exists to take a URL, so it arrives ready for one.
        .onAppear { urlFieldFocused = true }
        .onChange(of: focusRequest) { urlFieldFocused = true }
        .animation(.easeInOut(duration: 0.2), value: clipboardOffer)
        // Re-read on every appearance, so closing a PR lists it at the top straight away.
        .task {
            recents = AnalysisCache().recentPRs(limit: Self.rowsShown)
            await checkClipboard()
            let requests = await ReviewRequests.fetch(access: Preferences.shared.resolvedGitHubAccess)
            // `gh search` takes a second or two; fade the list in rather than jolting the layout.
            withAnimation(.easeInOut(duration: 0.25)) { reviewRequests = requests }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await checkClipboard() }
        }
    }

    /// Side by side rather than stacked, so both lists fit under the field without pushing
    /// the mark off the top of a default-sized window.
    @ViewBuilder
    private var pullRequestLists: some View {
        let requests = OnboardingViewLogic.visibleRequests(reviewRequests, limit: Self.rowsShown)
        if OnboardingViewLogic.shouldShowLists(requests: requests, recents: recents) {
            HStack(alignment: .top, spacing: 28) {
                if !requests.isEmpty {
                    PullRequestList(title: "Awaiting your review", systemImage: "person.crop.circle.badge.questionmark") {
                        ForEach(requests) { request in
                            PullRequestRow(
                                title: request.title, repo: request.repo, number: request.number,
                                detail: request.isDraft ? "\(request.author) · draft" : request.author,
                                date: request.updatedAt, dateVerb: "updated", url: request.url, onOpen: onSubmit
                            )
                        }
                    }
                }
                if !recents.isEmpty {
                    PullRequestList(title: "Recently opened", systemImage: "clock.arrow.circlepath") {
                        ForEach(recents) { recent in
                            PullRequestRow(
                                title: recent.title, repo: recent.repo, number: recent.number,
                                detail: nil, date: recent.lastOpened, dateVerb: "opened", url: recent.url, onOpen: onSubmit
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 24)
            .transition(.opacity)
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
        guard !OnboardingViewLogic.isDeclined(changeCount: changeCount, declinedChangeCount: declinedChangeCount) else {
            clipboardOffer = nil
            return
        }
        // Before 15.4 there is no alert, so the clipboard can simply be read.
        if #available(macOS 15.4, *), pasteboard.accessBehavior != .alwaysAllow {
            let patterns = pasteboard.accessBehavior == .alwaysDeny ? []
                : (try? await pasteboard.detectedPatterns(for: [\.probableWebURL])) ?? []
            clipboardOffer = OnboardingViewLogic.offer(
                detectedProbableWebURL: patterns.contains(\.probableWebURL), changeCount: changeCount
            )
            return
        }
        clipboardOffer = OnboardingViewLogic.offer(fromReadableClipboardText: pasteboard.string(forType: .string))
    }

    /// The reviewer asked for the clipboard, so read it now. A link that isn't a PR goes
    /// into the field rather than vanishing, so they can see why it didn't open.
    private func openUnreadClipboard(_ changeCount: Int) {
        clipboardOffer = nil
        declinedChangeCount = changeCount
        switch OnboardingViewLogic.resolveClipboardRead(NSPasteboard.general.string(forType: .string)) {
        case .open(let url): onSubmit(url)
        case .fillField(let text): urlText = text
        case .doNothing: break
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

/// The row-formatting, clipboard-decision and list-visibility logic CLAUDE.md calls out
/// for this file, pulled out of the view so it's directly testable without a view
/// instance. `checkClipboard`, `openUnreadClipboard` and `pullRequestLists` each forward
/// to one of these rather than deciding inline.
enum OnboardingViewLogic {
    /// A PR row's second line: repo and number always, then whatever else is known —
    /// author or draft state, and when it happened, in that order.
    static func subtitle(repo: String, number: Int, detail: String?, date: Date?, dateVerb: String) -> String {
        var parts = ["\(repo) #\(number)"]
        if let detail { parts.append(detail) }
        if let date { parts.append("\(dateVerb) \(date.formatted(.relative(presentation: .named)))") }
        return parts.joined(separator: " · ")
    }

    /// Whether the clipboard hasn't changed since the reviewer last dismissed its offer —
    /// in which case it should stay hidden rather than reappear every time the window is
    /// activated.
    static func isDeclined(changeCount: Int, declinedChangeCount: Int?) -> Bool {
        changeCount == declinedChangeCount
    }

    /// The offer once the clipboard's own text can be read directly — before macOS 15.4,
    /// or once the reviewer has already granted clipboard access: a recognized PR link is
    /// offered by name, anything else isn't offered at all.
    static func offer(fromReadableClipboardText text: String?) -> ClipboardOffer? {
        text.flatMap(PRLink.extract(from:)).map(ClipboardOffer.pullRequest)
    }

    /// The offer once only pattern detection is available (macOS 15.4+, before the
    /// reviewer has granted clipboard access): a generic "unread link" offer when a
    /// probable web URL was detected, since the contents themselves haven't been read.
    static func offer(detectedProbableWebURL: Bool, changeCount: Int) -> ClipboardOffer? {
        detectedProbableWebURL ? .unreadLink(changeCount: changeCount) : nil
    }

    /// What happens once the reviewer asks to open the clipboard's unread link.
    enum ClipboardReadAction: Equatable {
        /// A recognized PR link — open it directly.
        case open(String)
        /// Something else — put it in the URL field so the reviewer can see why it
        /// didn't open, rather than have it vanish silently.
        case fillField(String)
        /// Nothing was on the clipboard to act on.
        case doNothing
    }

    /// Resolves the clipboard's actual contents, read only once the reviewer asked for
    /// them.
    static func resolveClipboardRead(_ clip: String?) -> ClipboardReadAction {
        guard let clip else { return .doNothing }
        if let url = PRLink.extract(from: clip) { return .open(url) }
        return .fillField(clip)
    }

    /// What pasted (or clipboard-button) text becomes in the URL field: a recognized PR
    /// link is canonicalized, anything else is left as typed so the reviewer can see and
    /// correct it.
    static func resolvedPasteText(_ text: String) -> String {
        PRLink.extract(from: text) ?? text
    }

    /// The review-requested PRs to show, capped at the number of rows the start screen has
    /// room for.
    static func visibleRequests(_ requests: [ReviewRequest]?, limit: Int) -> [ReviewRequest] {
        Array((requests ?? []).prefix(limit))
    }

    /// Whether either PR list has anything to show — the section collapses entirely when
    /// both are empty, rather than displaying two empty headings.
    static func shouldShowLists(requests: [ReviewRequest], recents: [AnalysisCache.RecentPR]) -> Bool {
        !requests.isEmpty || !recents.isEmpty
    }
}

/// One of the start screen's PR lists: a quiet heading over its rows.
private struct PullRequestList<Rows: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            rows
        }
        .frame(maxWidth: 360, alignment: .leading)
    }
}

/// A PR the reviewer can open with one click: its title, then where it lives and when.
private struct PullRequestRow: View {
    let title: String
    let repo: String
    let number: Int
    /// Anything else worth a glance, such as who opened it.
    let detail: String?
    let date: Date?
    /// What `date` records: "updated" for a review request, "opened" for a recent PR.
    let dateVerb: String
    let url: String
    var onOpen: (String) -> Void

    @State private var hovering = false

    var body: some View {
        Button { onOpen(url) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
        OnboardingViewLogic.subtitle(repo: repo, number: number, detail: detail, date: date, dateVerb: dateVerb)
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
    nonisolated static func headline(_ stage: PipelineStage) -> String {
        switch stage {
        case .fetching, .checkingOut, .cacheCheck: return "Opening the pull request…"
        case .ticket, .behaviorChange, .understanding: return "Understanding the change…"
        case .architecture: return "Analyzing architecture…"
        case .decisions: return "Finding the decisions it makes…"
        case .flows: return "Tracing the flows it touches…"
        case .judgment: return "Deciding what needs your judgment…"
        }
    }

    private var latestDetail: String { Self.latestDetail(log: log, stage: stage) }

    /// The console's most recent line, condensed for the one-line status under the mark:
    /// the stage name alone once a step starts, or the stage name and its detail once the
    /// harness reports one.
    nonisolated static func latestDetail(log: [PipelineProgressEntry], stage: PipelineStage) -> String {
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
