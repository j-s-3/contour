import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @State private var urlText: String
    @FocusState private var urlFieldFocused: Bool
    @State private var clipboardOffer: ClipboardOffer?
    @State private var declinedChangeCount: Int?
    @State private var recents: [AnalysisCache.RecentPR] = []
    @State private var reviewRequests: [ReviewRequest]?
    var markNamespace: Namespace.ID
    var focusRequest: Int
    var onSubmit: (String) -> Void
    nonisolated(unsafe) private let pasteboard: NSPasteboard
    private let loadRecents: () -> [AnalysisCache.RecentPR]
    private let loadReviewRequests: @MainActor () async -> [ReviewRequest]?

    static let rowsShown = 5

    init(
        initialURL: String? = nil, markNamespace: Namespace.ID, focusRequest: Int = 0,
        pasteboard: NSPasteboard = .general,
        loadRecents: @escaping () -> [AnalysisCache.RecentPR] = {
            AnalysisCache().recentPRs(limit: OnboardingView.rowsShown)
        },
        loadReviewRequests: @escaping @MainActor () async -> [ReviewRequest]? = {
            await ReviewRequests.fetch(access: Preferences.shared.resolvedGitHubAccess)
        },
        onSubmit: @escaping (String) -> Void
    ) {
        self.pasteboard = pasteboard
        self.loadRecents = loadRecents
        self.loadReviewRequests = loadReviewRequests
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
                    .onPasteCommand(of: [.text, .url]) { providers in
                        Self.loadPastedText(from: providers) { urlText = $0 }
                    }
                Button {
                    if let clip = pasteboard.string(forType: .string) {
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
            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { urlFieldFocused = true }
        .onChange(of: focusRequest) { urlFieldFocused = true }
        .animation(.easeInOut(duration: 0.2), value: clipboardOffer)
        .task {
            recents = loadRecents()
            await checkClipboard()
            let requests = await loadReviewRequests()
            withAnimation(.easeInOut(duration: 0.25)) { reviewRequests = requests }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await checkClipboard() }
        }
    }

    private var pullRequestLists: some View {
        PullRequestLists(
            requests: OnboardingViewLogic.visibleRequests(reviewRequests, limit: Self.rowsShown),
            recents: recents, onOpen: onSubmit
        )
    }

    static func loadPastedText(from providers: [NSItemProvider], apply: @escaping @MainActor (String) -> Void) {
        guard let provider = providers.first else { return }
        Task { @MainActor in
            guard
                let text = await withCheckedContinuation({ continuation in
                    _ = provider.loadObject(ofClass: String.self) { text, _ in
                        continuation.resume(returning: text)
                    }
                })
            else { return }
            apply(OnboardingViewLogic.resolvedPasteText(text))
        }
    }

    private func submit() {
        guard GitHubService.normalize(urlText) != nil else { return }
        onSubmit(urlText)
    }

    private func clipboardOfferRow(_ offer: ClipboardOffer) -> some View {
        ClipboardOfferRow(
            offer: offer, onOpen: onSubmit, onOpenUnread: openUnreadClipboard,
            onDismiss: {
                declinedChangeCount = pasteboard.changeCount
                clipboardOffer = nil
            }
        )
    }

    private func checkClipboard() async {
        let changeCount = pasteboard.changeCount
        guard !OnboardingViewLogic.isDeclined(changeCount: changeCount, declinedChangeCount: declinedChangeCount) else {
            clipboardOffer = nil
            return
        }
        if #available(macOS 15.4, *), pasteboard.accessBehavior != .alwaysAllow {
            let patterns =
                pasteboard.accessBehavior == .alwaysDeny
                ? []
                : (try? await pasteboard.detectedPatterns(for: [\.probableWebURL])) ?? []
            clipboardOffer = OnboardingViewLogic.offer(
                detectedProbableWebURL: patterns.contains(\.probableWebURL), changeCount: changeCount
            )
            return
        }
        clipboardOffer = OnboardingViewLogic.offer(fromReadableClipboardText: pasteboard.string(forType: .string))
    }

    private func openUnreadClipboard(_ changeCount: Int) {
        clipboardOffer = nil
        declinedChangeCount = changeCount
        OnboardingViewLogic.perform(
            OnboardingViewLogic.resolveClipboardRead(pasteboard.string(forType: .string)),
            open: onSubmit, fillField: { urlText = $0 }
        )
    }
}

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

struct PullRequestLists: View {
    let requests: [ReviewRequest]
    let recents: [AnalysisCache.RecentPR]
    var onOpen: (String) -> Void

    var body: some View {
        if OnboardingViewLogic.shouldShowLists(requests: requests, recents: recents) {
            HStack(alignment: .top, spacing: 28) {
                if !requests.isEmpty {
                    PullRequestList(title: "Awaiting your review", systemImage: "person.crop.circle.badge.questionmark")
                    {
                        ForEach(requests) { request in
                            PullRequestRow(
                                title: request.title, repo: request.repo, number: request.number,
                                detail: request.isDraft ? "\(request.author) · draft" : request.author,
                                date: request.updatedAt, dateVerb: "updated", url: request.url, onOpen: onOpen
                            )
                        }
                    }
                }
                if !recents.isEmpty {
                    PullRequestList(title: "Recently opened", systemImage: "clock.arrow.circlepath") {
                        ForEach(recents) { recent in
                            PullRequestRow(
                                title: recent.title, repo: recent.repo, number: recent.number,
                                detail: nil, date: recent.lastOpened, dateVerb: "opened", url: recent.url,
                                onOpen: onOpen
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
}

enum ClipboardOffer: Equatable {
    case pullRequest(String)
    case unreadLink(changeCount: Int)
}

enum OnboardingViewLogic {
    static func subtitle(repo: String, number: Int, detail: String?, date: Date?, dateVerb: String) -> String {
        var parts = ["\(repo) #\(number)"]
        if let detail { parts.append(detail) }
        if let date { parts.append("\(dateVerb) \(date.formatted(.relative(presentation: .named)))") }
        return parts.joined(separator: " · ")
    }

    static func isDeclined(changeCount: Int, declinedChangeCount: Int?) -> Bool {
        changeCount == declinedChangeCount
    }

    static func offer(fromReadableClipboardText text: String?) -> ClipboardOffer? {
        text.flatMap(PRLink.extract(from:)).map(ClipboardOffer.pullRequest)
    }

    static func offer(detectedProbableWebURL: Bool, changeCount: Int) -> ClipboardOffer? {
        detectedProbableWebURL ? .unreadLink(changeCount: changeCount) : nil
    }

    enum ClipboardReadAction: Equatable {
        case open(String)
        case fillField(String)
        case doNothing
    }

    static func resolveClipboardRead(_ clip: String?) -> ClipboardReadAction {
        guard let clip else { return .doNothing }
        if let url = PRLink.extract(from: clip) { return .open(url) }
        return .fillField(clip)
    }

    static func perform(_ action: ClipboardReadAction, open: (String) -> Void, fillField: (String) -> Void) {
        switch action {
        case .open(let url): open(url)
        case .fillField(let text): fillField(text)
        case .doNothing: break
        }
    }

    static func resolvedPasteText(_ text: String) -> String {
        PRLink.extract(from: text) ?? text
    }

    static func visibleRequests(_ requests: [ReviewRequest]?, limit: Int) -> [ReviewRequest] {
        Array((requests ?? []).prefix(limit))
    }

    static func shouldShowLists(requests: [ReviewRequest], recents: [AnalysisCache.RecentPR]) -> Bool {
        !requests.isEmpty || !recents.isEmpty
    }
}

struct PullRequestList<Rows: View>: View {
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

struct PullRequestRow: View {
    let title: String
    let repo: String
    let number: Int
    let detail: String?
    let date: Date?
    let dateVerb: String
    let url: String
    var onOpen: (String) -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            onOpen(url)
        } label: {
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
