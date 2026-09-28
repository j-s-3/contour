import SwiftUI
import AppKit

/// The window shell from §4.1: sidebar of lenses + files, main pane driven by the
/// semantic navigation stack, inspector-free for MVP (cross-links live inline instead).
struct ContentView: View {
    @State private var store = GraphStore()
    @State private var showPalette = false
    @State private var confirmApprove = false
    @State private var composingChangeRequest = false
    /// Mirrors the persisted flag so finishing the wizard swaps the view immediately.
    @State private var needsOnboarding = !Preferences.shared.hasCompletedOnboarding
    /// Explicit, not `.automatic`: entering real fullscreen — at launch when the user has
    /// opted in (`WindowAccessor`), or at any time via the green button — is a known
    /// trigger for `NavigationSplitView` silently collapsing its sidebar column (the
    /// automatic width-based visibility heuristic gets a bad reading mid-transition and
    /// never reconsiders). Owning the binding — and reasserting it once fullscreen
    /// actually completes — is what keeps the sidebar from vanishing.
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    /// Carries the Contour mark from the welcome screen into the analysis screen.
    @Namespace private var markNamespace
    /// Bumped by Open Pull Request… so the start screen's URL field takes focus even when
    /// the start screen is already showing.
    @State private var urlFieldFocusRequest = 0

    var body: some View {
        Group {            if needsOnboarding {
                WelcomeWizard { firstURL in
                    needsOnboarding = false
                    if let firstURL { store.load(prURL: firstURL) }
                }
            } else {
                mainBody
            }
        }
        .sheet(isPresented: $showPalette) {
            CommandPaletteView(store: store, isPresented: $showPalette)
        }
        .background(
            Button("") { showPalette = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
        )
        // Full screen only on opt-in; otherwise the window reopens at its last frame.
        .background(WindowAccessor(entersFullScreen: Preferences.shared.opensInFullScreen))
        .focusedSceneValue(\.reviewStore, store.phase == .review ? store : nil)
        // File ▸ Open / Close Pull Request. Not published during first-run setup, which has
        // no PR to leave and its own way to open the first one.
        .focusedSceneValue(\.prSession, needsOnboarding ? nil : sessionActions)
        .onAppear {
            // Manual-testing hook alongside CONTOUR_MOCK_ANALYSIS: open straight into a PR
            // rather than pasting a URL on every launch.
            if !needsOnboarding, case .idle = store.phase,
               let url = ProcessInfo.processInfo.environment["CONTOUR_OPEN_PR_URL"], !url.isEmpty {
                store.load(prURL: url)
            }
        }
        .onChange(of: store.phase) { _, phase in
            // Companion to CONTOUR_OPEN_PR_URL: land on a specific lens once the PR opens.
            guard phase == .review,
                  let lens = ProcessInfo.processInfo.environment["CONTOUR_OPEN_LENS"] else { return }
            switch lens {
            case "architecture": store.navigate(to: .architecture)
            case "flows": store.navigate(to: .flows)
            case "decisions": store.navigate(to: .decisions)
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            sidebarVisibility = .all
        }
        // `contour://…` and GitHub PR links handed to the app by the system. Only live once
        // Contour runs from a bundle whose Info.plist declares the scheme; a bare SwiftPM
        // executable is never sent them.
        .onOpenURL { url in
            guard !needsOnboarding, let prURL = PRLink.pullRequestURL(from: url) else { return }
            store.load(prURL: prURL)
        }
        // Route incoming links to this window rather than opening a second one.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }

    private var sessionActions: PRSessionActions {
        PRSessionActions(
            hasOpenPR: store.hasOpenPR,
            pullRequestURL: store.pullRequestURL,
            openDifferent: openDifferentPR,
            close: { store.close() }
        )
    }

    /// Back to the start screen, ready to paste the next URL.
    private func openDifferentPR() {
        store.close()
        urlFieldFocusRequest += 1
    }

    @ViewBuilder
    private var mainBody: some View {
        Group {
            switch store.phase {
            case .idle:
                OnboardingView(initialURL: store.lastPRURL, markNamespace: markNamespace,
                               focusRequest: urlFieldFocusRequest) { url in store.load(prURL: url) }
            case .opening:
                // Only the fetch happens here now; the review opens as soon as the PR has
                // been read, and the mark carries on resolving in the toolbar.
                AnalyzingView(stage: .fetching, log: store.progressLog, markNamespace: markNamespace)
            case .failed(let message):
                FailedView(message: message, onRetry: { store.reopen() }, onOpenDifferent: { store.close() })
            case .review:
                if let graph = store.graph {
                    readyBody(graph)
                } else {
                    OnboardingView(initialURL: store.lastPRURL, markNamespace: markNamespace,
                                   focusRequest: urlFieldFocusRequest) { url in store.load(prURL: url) }
                }
            }
        }
        // Screen changes crossfade (and the mark glides from welcome into opening).
        .animation(.easeInOut(duration: 0.45), value: screen)
        // A PR link dropped on the start screen or an open review opens that PR; one PR
        // per window, so a review in progress is replaced.
        .opensDroppedPullRequests { url in store.load(prURL: url) }
    }

    /// Which screen `mainBody` shows. Analysis progress inside the review never swaps the
    /// screen, so it never animates here.
    private var screen: Int { Self.screen(for: store.phase) }

    nonisolated static func screen(for phase: SessionPhase) -> Int {
        switch phase {
        case .idle: return 0
        case .opening: return 1
        case .failed: return 2
        case .review: return 3
        }
    }

    @ViewBuilder
    private func readyBody(_ graph: PRGraph) -> some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar(graph)
        } detail: {
            VStack(spacing: 0) {
                if let head = store.analysis.revalidatingFrom {
                    RevalidationBanner(head: head, updating: store.analysis.canStop)
                }
                detailContent(graph)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
                // The chat is an inspector on the detail column rather than a sheet or a
                // pane inside a lens: it persists across navigation, so following a code
                // citation keeps the thread beside the code instead of replacing it.
                .inspector(isPresented: Binding(
                    get: { store.conversations.isPresented },
                    set: { store.conversations.isPresented = $0 }
                )) {
                    ContextualChatView(store: store, graph: graph)
                        .inspectorColumnWidth(min: 340, ideal: 420, max: 580)
                }
        }
        .environment(\.reviewActions, ReviewActions(
            graph: graph,
            prURL: store.lastPRURL,
            ask: { subject in withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { store.ask(about: subject) } },
            askQuestion: { question, subject in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { store.ask(question, about: subject) }
            },
            navigate: { store.navigate(to: $0) },
            focus: { store.focusedSubject = $0 }
        ))
        .background(
            Button("") {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { store.ask(about: store.subjectForCurrentLocation) }
            }
            .keyboardShortcut(AskShortcut.key, modifiers: AskShortcut.modifiers)
            .opacity(0)
        )
        // `Text(verbatim:)`, not a bare string literal: the `navigationTitle` overload that
        // takes a literal binds it as a `LocalizedStringKey`, which formats an interpolated
        // Int for the current locale — so PR #14039 rendered as "#14,039". A PR number is
        // an identifier, not a quantity, and must never be group-separated.
        .navigationTitle(Text(verbatim: "\(graph.pr.repo) #\(graph.pr.number)"))
        // The PR name in the title bar is the PR's own menu — the visible way to leave it.
        .toolbarTitleMenu {
            let session = sessionActions
            Button("Open on GitHub") { session.openOnGitHub() }
                .disabled(session.pullRequestURL == nil)
            Button("Copy Link") { session.copyLink() }
                .disabled(session.pullRequestURL == nil)
            Divider()
            Button("Open a Different Pull Request…") { session.openDifferent() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { store.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!store.canGoBack)
                Button { store.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!store.canGoForward)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                AnalysisIndicator(state: store.analysis, log: store.progressLog, metrics: store.metrics,
                                  refCheck: graph.refCheckTotal, onStop: { store.stopAnalysis() }) {
                    store.retry($0)
                }
                Button { showPalette = true } label: { Image(systemName: "magnifyingglass") }
                    .help("Command palette (⌘K)")
                // The ways out once the PR is understood: back to GitHub, or with the
                // reviewer's judgment ready to paste into a review comment there.
                Button { store.copyReviewSummary() } label: { Image(systemName: "doc.on.clipboard") }
                    .help("Copy review summary as Markdown")
                Button { store.openOnGitHub() } label: { Image(systemName: "arrow.up.forward.square") }
                    .help("Open on GitHub (⌘⇧O)")
                    .disabled(store.pullRequestWebURL == nil)
                approveButton(graph)
                requestChangesButton(graph)
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        if store.conversations.isPresented {
                            store.conversations.close()
                        } else if store.conversations.active != nil {
                            store.conversations.isPresented = true
                        } else {
                            store.ask(about: store.subjectForCurrentLocation)
                        }
                    }
                } label: {
                    Image(systemName: store.conversations.isPresented ? "bubble.left.and.text.bubble.right.fill" : "bubble.left.and.text.bubble.right")
                }
                .help("Conversations — ask about what you're looking at (⌘⇧A)")
            }
        }
    }

    /// GitHub's +1: submits an approving review as the reviewer, after a confirmation —
    /// it's public and can't be taken back from here.
    private func approveButton(_ graph: PRGraph) -> some View {
        Button { confirmApprove = true } label: {
            reviewButtonLabel(.approve, symbol: "hand.thumbsup", submittedColor: .green)
        }
        .help(store.reviewUnavailableReason(.approve) ?? "Approve this pull request on GitHub")
        .disabled(!store.canSubmitReview(.approve))
        .confirmationDialog(
            Text(verbatim: "Approve \(graph.pr.repo) #\(graph.pr.number)?"),
            isPresented: $confirmApprove
        ) {
            Button("Approve") { store.submitReview(.approve) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This submits an approving review on GitHub as you, through gh.")
        }
        // One alert for both verdicts: only one review is ever in flight.
        .alert(
            reviewFailureTitle,
            isPresented: Binding(
                get: { if case .failed = store.review { true } else { false } },
                set: { if !$0 { store.dismissReviewFailure() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if case .failed(_, let message) = store.review { Text(message) }
        }
    }

    /// Approve's counterpart: GitHub needs the reviewer to say what to change, so this asks
    /// for a comment rather than a bare confirmation.
    private func requestChangesButton(_ graph: PRGraph) -> some View {
        Button { composingChangeRequest = true } label: {
            reviewButtonLabel(.requestChanges, symbol: "hand.thumbsdown", submittedColor: .red)
        }
        .help(store.reviewUnavailableReason(.requestChanges) ?? "Request changes on GitHub")
        .disabled(!store.canSubmitReview(.requestChanges))
        .sheet(isPresented: $composingChangeRequest) {
            RequestChangesSheet(title: "Request changes on \(graph.pr.repo) #\(graph.pr.number)") { comment in
                store.submitReview(.requestChanges, comment: comment)
            }
        }
    }

    /// A spinner while this verdict is in flight, filled once it's submitted.
    @ViewBuilder
    private func reviewButtonLabel(_ verdict: PRReview.Verdict, symbol: String, submittedColor: Color) -> some View {
        switch store.review {
        case .submitting(verdict):
            ProgressView().controlSize(.small)
        case .submitted(verdict):
            Image(systemName: symbol + ".fill").foregroundStyle(submittedColor)
        default:
            Image(systemName: symbol)
        }
    }

    private var reviewFailureTitle: String { Self.reviewFailureTitle(for: store.review) }

    nonisolated static func reviewFailureTitle(for review: PRReview.State) -> String {
        if case .failed(.requestChanges, _) = review { return "Couldn't request changes" }
        return "Couldn't approve the pull request"
    }

    /// Every destination is always open, whatever its analysis state; the row just says how
    /// far along it is, and a finished section simply stops saying anything.
    private func sidebar(_ graph: PRGraph) -> some View {
        let analysis = store.analysis
        return List {
            Section("Overview") {
                sidebarRow("Overview", "house", .summary, status: analysis.sectionStatus(.whatChanged), section: .whatChanged)
            }
            Section("System") {
                sidebarRow("Architecture", "square.stack.3d.up", .architecture,
                           status: analysis.status(.architecture), section: .architecture)
                let flowsStatus = analysis.status(.flows)
                sidebarRow(flowsStatus == .done ? "Flows (\(graph.flows.count))" : "Flows", "arrow.triangle.branch", .flows,
                           status: flowsStatus, section: .flows)
            }
            Section("Review") {
                // Review progress is the Overview's things to think about, resolved — the
                // same n of m the Overview shows — and sits on the row where judgments are
                // recorded.
                let p = graph.reviewProgress(discussed: store.conversations.discussedConsiderationIds)
                let decisionsStatus = analysis.status(.decisions)
                let done = decisionsStatus == .done && analysis.status(.judgment) == .done
                    && p.total > 0 && p.reviewed == p.total
                sidebarRow("Decisions", "checklist", .decisions, status: decisionsStatus, section: .decisions) {
                    if p.total > 0 {
                        HStack(spacing: 4) {
                            if done {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            Text(verbatim: "\(p.reviewed)/\(p.total)")
                                .monospacedDigit()
                                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                        }
                        .font(.callout)
                    }
                }
                .help("Things to think about you've resolved: \(p.reviewed) of \(p.total)")
            }
            Section("Code") {
                sidebarRow("Raw diff", "doc.text", .diff, status: store.diffText == nil ? .pending : .done, section: nil)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }

    private func sidebarRow(_ title: String, _ symbol: String, _ target: NavigationTarget,
                            status: StageStatus, section: ReviewSection?) -> some View {
        sidebarRow(title, symbol, target, status: status, section: section) { EmptyView() }
    }

    private func sidebarRow<Trailing: View>(_ title: String, _ symbol: String, _ target: NavigationTarget,
                                            status: StageStatus, section: ReviewSection?,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        Button { store.navigate(to: target) } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Label(title, systemImage: symbol)
                    if let subtitle = Self.sidebarSubtitle(status, section) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.leading, 27)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 6)
                trailing()
                if status != .done {
                    StageStatusGlyph(status: status)
                }
            }
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.25), value: status)
        }
        .buttonStyle(.plain)
        .listRowBackground(isActive(target) ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    nonisolated static func sidebarSubtitle(_ status: StageStatus, _ section: ReviewSection?) -> String? {
        guard let section else { return nil }
        switch status {
        case .running(let detail): return detail ?? section.workingLabel
        case .failed: return "Couldn't be generated"
        case .stale: return "Previous revision"
        case .stopped: return "Stopped"
        case .pending: return "Waiting…"
        case .done: return nil
        }
    }

    private func isActive(_ target: NavigationTarget) -> Bool { Self.isActive(target, given: store.current) }

    nonisolated static func isActive(_ target: NavigationTarget, given current: NavigationTarget) -> Bool {
        switch (current, target) {
        case (.summary, .summary), (.architecture, .architecture), (.decisions, .decisions),
             (.flows, .flows), (.diff, .diff), (.diffLocation(_), .diff):
            return true
        case (.componentDetail(_), .architecture), (.edgeDetail(_), .architecture), (.decisionDetail(_), .decisions),
             (.consideration(_), .decisions), (.flowDetail(_), .flows),
             (.flowNodeDetail(_, _), .flows):
            return true
        default:
            return false
        }
    }

    /// The node or edge a navigation target asks Architecture to select, if any.
    private var architectureFocus: ArchAnchor? { Self.architectureFocus(for: store.current) }

    nonisolated static func architectureFocus(for current: NavigationTarget) -> ArchAnchor? {
        switch current {
        case .componentDetail(let id): return .node(id)
        case .edgeDetail(let id): return .edge(id)
        default: return nil
        }
    }

    /// The flow, and stage, a navigation target asks Flows to show.
    private var flowsFocus: FlowsView.Focus? { Self.flowsFocus(for: store.current) }

    nonisolated static func flowsFocus(for current: NavigationTarget) -> FlowsView.Focus? {
        switch current {
        case .flowDetail(let id): return .init(flowId: id)
        case .flowNodeDetail(let flowId, let nodeId): return .init(flowId: flowId, nodeId: nodeId)
        default: return nil
        }
    }

    /// The code reference a navigation target asks the raw diff to land on.
    private var diffFocus: CodeRef? { Self.diffFocus(for: store.current) }

    nonisolated static func diffFocus(for current: NavigationTarget) -> CodeRef? {
        if case .diffLocation(let ref) = current { return ref }
        return nil
    }

    /// The decision a navigation target asks Decisions to open, and the Overview question
    /// that brought the reviewer there, if any.
    private func decisionsFocus(_ graph: PRGraph) -> DecisionsView.Focus? {
        Self.decisionsFocus(for: store.current, graph: graph)
    }

    nonisolated static func decisionsFocus(for current: NavigationTarget, graph: PRGraph) -> DecisionsView.Focus? {
        switch current {
        case .decisionDetail(let id):
            return .init(decisionId: id)
        case .consideration(let id):
            guard let item = graph.thingsToThinkAbout.first(where: { $0.id == id }),
                  let decisionId = graph.reviewDecisionId(for: item) else { return nil }
            return .init(decisionId: decisionId, considerationId: id)
        default:
            return nil
        }
    }

    /// A lens that may still be analyzing. With nothing yet it shows what's known and what's
    /// being worked on (or, if it failed, a retry); with something, the lens itself, plus a
    /// floating note while more is still arriving. Never a disabled or blank destination.
    @ViewBuilder
    private func sectionContent<Content: View>(
        _ section: ReviewSection, stage: PipelineStage, hasContent: Bool, ask: String,
        known: String? = nil, progress: String? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        let status = store.analysis.status(stage)
        if hasContent {
            content()
                .overlay(alignment: .bottom) {
                    if status.isRunning, let progress {
                        SectionProgressPill(text: progress)
                    } else if status == .stopped {
                        SectionStoppedPill { store.retry(stage) }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: status.isRunning)
                .animation(.easeInOut(duration: 0.3), value: status == .stopped)
        } else if let message = status.failure {
            SectionFailedView(section: section, message: message, onRetry: { store.retry(stage) }) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { store.ask(ask, about: .pullRequest) }
            }
        } else if status == .stopped {
            SectionStoppedView(section: section) { store.retry(stage) }
        } else if status == .done {
            content()
        } else {
            SectionPendingView(section: section, status: status, known: known)
        }
    }

    @ViewBuilder
    private func detailContent(_ graph: PRGraph) -> some View {
        let analysis = store.analysis
        switch store.current {
        case .summary:
            SummaryView(graph: graph, analysis: analysis, discussed: store.conversations.discussedConsiderationIds,
                        onRetry: { store.retry($0) }) { store.navigate(to: $0) }
        case .architecture, .componentDetail(_), .edgeDetail(_):
            sectionContent(.architecture, stage: .architecture, hasContent: !graph.components.isEmpty,
                           ask: "What part of the system does this change sit in, and how does it change it?",
                           known: graph.dominantBehaviorChange.map { $0.after.map(\.label).joined(separator: " → ") }) {
                ArchitectureView(graph: graph, focus: architectureFocus, mode: $store.diagramMode)
            }
        case .decisions, .decisionDetail(_), .consideration(_):
            sectionContent(.decisions, stage: .decisions, hasContent: !graph.decisions.isEmpty,
                           ask: "What are the consequential design decisions in this PR?",
                           progress: "\(graph.decisions.count) found so far · looking for other consequential choices…") {
                DecisionsView(
                    graph: graph,
                    focus: decisionsFocus(graph),
                    discussed: store.conversations.discussedConsiderationIds,
                    onSetState: { store.setReviewerState($1, forDecision: $0) },
                    onSetNote: { store.setReviewerNote($1, forDecision: $0) },
                    onSetToReview: { store.setToReview($1, forDecision: $0) }
                )
            }
        case .flows, .flowDetail(_), .flowNodeDetail(_, _):
            sectionContent(.flows, stage: .flows, hasContent: !graph.flows.isEmpty,
                           ask: "What happens at runtime when this changed behavior is triggered?",
                           progress: "\(graph.flows.count) traced so far · tracing others…") {
                FlowsView(
                    graph: graph,
                    focus: flowsFocus,
                    mode: $store.diagramMode,
                    onOpenEvidence: { store.navigate(to: .evidence($0)) }
                )
            }
        case .files:
            ContentUnavailableView("No file view", systemImage: "doc.text")
        case .diff, .diffLocation(_):
            if store.diffText != nil {
                DiffView(files: store.diffFiles, graph: graph, focus: diffFocus)
            } else {
                ContentUnavailableView("No diff available", systemImage: "doc.text")
            }
        case .evidence(let ref):
            CodeViewerView(ref: ref, checkout: store.checkout) { store.goBack() }
        }
    }
}
