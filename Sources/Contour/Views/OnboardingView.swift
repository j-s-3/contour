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
    @State private var urlText: String = ""
    @State private var recents: [AnalysisCache.RecentPR] = []
    /// Nil until `gh` has answered, or when it can't be asked.
    @State private var reviewRequests: [ReviewRequest]?
    var markNamespace: Namespace.ID
    var onSubmit: (String) -> Void

    /// Rows per list: enough to cover a working week's PRs without pushing the welcome
    /// off-centre.
    static let rowsShown = 5

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

            pullRequestLists
                .padding(.top, 32)
            Spacer()
            // The optical centre sits a little above the geometric one.
            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Re-read on every appearance, so closing a PR lists it at the top straight away.
        .task {
            recents = AnalysisCache().recentPRs(limit: Self.rowsShown)
            let requests = await ReviewRequests.fetch(access: Preferences.shared.resolvedGitHubAccess)
            // `gh search` takes a second or two; fade the list in rather than jolting the layout.
            withAnimation(.easeInOut(duration: 0.25)) { reviewRequests = requests }
        }
    }

    /// Side by side rather than stacked, so both lists fit under the field without pushing
    /// the mark off the top of a default-sized window.
    @ViewBuilder
    private var pullRequestLists: some View {
        let requests = Array((reviewRequests ?? []).prefix(Self.rowsShown))
        if !requests.isEmpty || !recents.isEmpty {
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
        var parts = ["\(repo) #\(number)"]
        if let detail { parts.append(detail) }
        if let date { parts.append("\(dateVerb) \(date.formatted(.relative(presentation: .named)))") }
        return parts.joined(separator: " · ")
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
