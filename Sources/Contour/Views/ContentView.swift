import AppKit
import SwiftUI

struct ContentView: View {
    @State private var store: GraphStore
    @State private var showPalette = false
    @State private var confirmApprove = false
    @State private var composingChangeRequest = false
    @State private var needsOnboarding: Bool
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @Namespace private var markNamespace
    @State private var urlFieldFocusRequest = 0

    init(store: GraphStore = GraphStore(), needsOnboarding: Bool? = nil) {
        _store = State(initialValue: store)
        _needsOnboarding = State(initialValue: needsOnboarding ?? !Preferences.shared.hasCompletedOnboarding)
    }

    var body: some View {
        Group {
            if needsOnboarding {
                WelcomeWizard { firstURL in
                    needsOnboarding = false
                    Self.openFirstPR(firstURL) { store.load(prURL: $0) }
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
        .background(WindowAccessor(entersFullScreen: Preferences.shared.opensInFullScreen))
        .focusedSceneValue(\.reviewStore, store.phase == .review ? store : nil)
        .focusedSceneValue(\.prSession, needsOnboarding ? nil : sessionActions)
        .onAppear {
            if !needsOnboarding, case .idle = store.phase {
                Self.openFirstPR(ProcessInfo.processInfo.environment["CONTOUR_OPEN_PR_URL"]) { store.load(prURL: $0) }
            }
        }
        .onChange(of: store.phase) { _, phase in
            guard phase == .review,
                let target = Self.lensTarget(named: ProcessInfo.processInfo.environment["CONTOUR_OPEN_LENS"])
            else { return }
            store.navigate(to: target)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            sidebarVisibility = .all
        }
        .onOpenURL { url in Self.openLink(url, needsOnboarding: needsOnboarding) { store.load(prURL: $0) } }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }

    nonisolated static func openFirstPR(_ url: String?, load: (String) -> Void) {
        if let url, !url.isEmpty { load(url) }
    }

    nonisolated static func openLink(_ url: URL, needsOnboarding: Bool, load: (String) -> Void) {
        guard !needsOnboarding, let prURL = PRLink.pullRequestURL(from: url) else { return }
        load(prURL)
    }

    static func reviewActions(graph: PRGraph, store: GraphStore) -> ReviewActions {
        ReviewActions(
            graph: graph,
            prURL: store.lastPRURL,
            ask: { subject in withAnimation(spring) { store.ask(about: subject) } },
            askQuestion: { question, subject in withAnimation(spring) { store.ask(question, about: subject) } },
            navigate: { store.navigate(to: $0) },
            focus: { store.focusedSubject = $0 }
        )
    }

    nonisolated static func lensTarget(named name: String?) -> NavigationTarget? {
        switch name {
        case "architecture": return .architecture
        case "flows": return .flows
        case "decisions": return .decisions
        default: return nil
        }
    }

    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.86)

    private var sessionActions: PRSessionActions {
        PRSessionActions(
            hasOpenPR: store.hasOpenPR,
            pullRequestURL: store.pullRequestURL,
            openDifferent: openDifferentPR,
            close: { store.close() }
        )
    }

    private func openDifferentPR() {
        store.close()
        urlFieldFocusRequest += 1
    }

    @ViewBuilder
    private var mainBody: some View {
        Group {
            switch store.phase {
            case .idle:
                OnboardingView(
                    initialURL: store.lastPRURL, markNamespace: markNamespace,
                    focusRequest: urlFieldFocusRequest
                ) { url in store.load(prURL: url) }
            case .opening:
                AnalyzingView(stage: .fetching, log: store.progressLog, markNamespace: markNamespace)
            case .failed(let message):
                FailedView(message: message, onRetry: { store.reopen() }, onOpenDifferent: { store.close() })
            case .review:
                if let graph = store.graph {
                    readyBody(graph)
                } else {
                    OnboardingView(
                        initialURL: store.lastPRURL, markNamespace: markNamespace,
                        focusRequest: urlFieldFocusRequest
                    ) { url in store.load(prURL: url) }
                }
            }
        }
        .animation(.easeInOut(duration: 0.45), value: screen)
        .opensDroppedPullRequests { url in store.load(prURL: url) }
    }

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
            .inspector(
                isPresented: Binding(
                    get: { store.conversations.isPresented },
                    set: { store.conversations.isPresented = $0 }
                )
            ) {
                ContextualChatView(store: store, graph: graph)
                    .inspectorColumnWidth(min: 340, ideal: 420, max: 580)
            }
        }
        .environment(\.reviewActions, Self.reviewActions(graph: graph, store: store))
        .background(
            Button("") { withAnimation(Self.spring) { store.ask(about: store.subjectForCurrentLocation) } }
                .keyboardShortcut(AskShortcut.key, modifiers: AskShortcut.modifiers)
                .opacity(0)
        )
        .navigationTitle(Text(verbatim: "\(graph.pr.repo) #\(graph.pr.number)"))
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
                Button {
                    store.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!store.canGoBack)
                Button {
                    store.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!store.canGoForward)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                AnalysisIndicator(
                    state: store.analysis, log: store.progressLog, metrics: store.metrics,
                    refCheck: graph.refCheckTotal, onStop: { store.stopAnalysis() }, onRetry: { store.retry($0) })
                Button {
                    showPalette = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Command palette (⌘K)")
                Button {
                    store.copyReviewSummary()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("Copy review summary as Markdown")
                Button {
                    store.openOnGitHub()
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .help("Open on GitHub (⌘⇧O)")
                .disabled(store.pullRequestWebURL == nil)
                approveButton(graph)
                requestChangesButton(graph)
                Button {
                    withAnimation(Self.spring) { store.toggleConversations() }
                } label: {
                    Image(
                        systemName: store.conversations.isPresented
                            ? "bubble.left.and.text.bubble.right.fill" : "bubble.left.and.text.bubble.right")
                }
                .help("Conversations — ask about what you're looking at (⌘⇧A)")
            }
        }
    }

    private func approveButton(_ graph: PRGraph) -> some View {
        Button {
            confirmApprove = true
        } label: {
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

    private func requestChangesButton(_ graph: PRGraph) -> some View {
        Button {
            composingChangeRequest = true
        } label: {
            reviewButtonLabel(.requestChanges, symbol: "hand.thumbsdown", submittedColor: .red)
        }
        .help(store.reviewUnavailableReason(.requestChanges) ?? "Request changes on GitHub")
        .disabled(!store.canSubmitReview(.requestChanges))
        .sheet(isPresented: $composingChangeRequest) {
            RequestChangesSheet(title: "Request changes on \(graph.pr.repo) #\(graph.pr.number)") {
                store.submitReview(.requestChanges, comment: $0)
            }
        }
    }

    @ViewBuilder
    private func reviewButtonLabel(_ verdict: PRReview.Verdict, symbol: String, submittedColor: Color) -> some View {
        switch Self.reviewButtonPhase(for: store.review, verdict: verdict) {
        case .submitting:
            ProgressView().controlSize(.small)
        case .submitted:
            Image(systemName: symbol + ".fill").foregroundStyle(submittedColor)
        case .idle:
            Image(systemName: symbol)
        }
    }

    enum ReviewButtonPhase: Equatable {
        case idle
        case submitting
        case submitted
    }

    nonisolated static func reviewButtonPhase(for review: PRReview.State, verdict: PRReview.Verdict)
        -> ReviewButtonPhase
    {
        switch review {
        case .submitting(verdict): return .submitting
        case .submitted(verdict): return .submitted
        default: return .idle
        }
    }

    private var reviewFailureTitle: String { Self.reviewFailureTitle(for: store.review) }

    nonisolated static func reviewFailureTitle(for review: PRReview.State) -> String {
        if case .failed(.requestChanges, _) = review { return "Couldn't request changes" }
        return "Couldn't approve the pull request"
    }

    private func sidebar(_ graph: PRGraph) -> some View {
        let analysis = store.analysis
        return List {
            Section("Overview") {
                sidebarRow(
                    "Overview", "house", .summary, status: analysis.sectionStatus(.whatChanged), section: .whatChanged)
            }
            Section("System") {
                sidebarRow(
                    "Architecture", "square.stack.3d.up", .architecture,
                    status: analysis.status(.architecture), section: .architecture)
                let flowsStatus = analysis.status(.flows)
                sidebarRow(
                    Self.flowsRowTitle(status: flowsStatus, count: graph.flows.count), "arrow.triangle.branch", .flows,
                    status: flowsStatus, section: .flows)
            }
            Section("Review") {
                let p = graph.reviewProgress(discussed: store.conversations.discussedConsiderationIds)
                let decisionsStatus = analysis.status(.decisions)
                let done = Self.decisionsRowIsFullyReviewed(
                    decisionsStatus: decisionsStatus, judgmentStatus: analysis.status(.judgment), progress: p)
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
                sidebarRow(
                    "Raw diff", "doc.text", .diff, status: Self.diffRowStatus(diffText: store.diffText), section: nil)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }

    nonisolated static func flowsRowTitle(status: StageStatus, count: Int) -> String {
        status == .done ? "Flows (\(count))" : "Flows"
    }

    nonisolated static func decisionsRowIsFullyReviewed(
        decisionsStatus: StageStatus, judgmentStatus: StageStatus, progress: (reviewed: Int, total: Int)
    ) -> Bool {
        decisionsStatus == .done && judgmentStatus == .done && progress.total > 0 && progress.reviewed == progress.total
    }

    nonisolated static func diffRowStatus(diffText: String?) -> StageStatus {
        diffText == nil ? .pending : .done
    }

    private func sidebarRow(
        _ title: String, _ symbol: String, _ target: NavigationTarget,
        status: StageStatus, section: ReviewSection?
    ) -> some View {
        sidebarRow(title, symbol, target, status: status, section: section) { EmptyView() }
    }

    private func sidebarRow<Trailing: View>(
        _ title: String, _ symbol: String, _ target: NavigationTarget,
        status: StageStatus, section: ReviewSection?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Button {
            store.navigate(to: target)
        } label: {
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

    private var architectureFocus: ArchAnchor? { Self.architectureFocus(for: store.current) }

    nonisolated static func architectureFocus(for current: NavigationTarget) -> ArchAnchor? {
        switch current {
        case .componentDetail(let id): return .node(id)
        case .edgeDetail(let id): return .edge(id)
        default: return nil
        }
    }

    private var flowsFocus: FlowsView.Focus? { Self.flowsFocus(for: store.current) }

    nonisolated static func flowsFocus(for current: NavigationTarget) -> FlowsView.Focus? {
        switch current {
        case .flowDetail(let id): return .init(flowId: id)
        case .flowNodeDetail(let flowId, let nodeId): return .init(flowId: flowId, nodeId: nodeId)
        default: return nil
        }
    }

    private var diffFocus: CodeRef? { Self.diffFocus(for: store.current) }

    nonisolated static func diffFocus(for current: NavigationTarget) -> CodeRef? {
        if case .diffLocation(let ref) = current { return ref }
        return nil
    }

    private func decisionsFocus(_ graph: PRGraph) -> DecisionsView.Focus? {
        Self.decisionsFocus(for: store.current, graph: graph)
    }

    nonisolated static func decisionsFocus(for current: NavigationTarget, graph: PRGraph) -> DecisionsView.Focus? {
        switch current {
        case .decisionDetail(let id):
            return .init(decisionId: id)
        case .consideration(let id):
            guard let item = graph.thingsToThinkAbout.first(where: { $0.id == id }),
                let decisionId = graph.reviewDecisionId(for: item)
            else { return nil }
            return .init(decisionId: decisionId, considerationId: id)
        default:
            return nil
        }
    }

    enum SectionBranch: Equatable {
        case content(showsOverlay: Bool)
        case failed(String)
        case stopped
        case pending
    }

    nonisolated static func sectionBranch(hasContent: Bool, status: StageStatus) -> SectionBranch {
        if hasContent { return .content(showsOverlay: true) }
        if let message = status.failure { return .failed(message) }
        if status == .stopped { return .stopped }
        if status == .done { return .content(showsOverlay: false) }
        return .pending
    }

    enum SectionOverlay: Equatable {
        case none
        case progress(String)
        case stopped
    }

    nonisolated static func sectionOverlay(status: StageStatus, progress: String?) -> SectionOverlay {
        if status.isRunning, let progress { return .progress(progress) }
        if status == .stopped { return .stopped }
        return .none
    }

    @ViewBuilder
    private func sectionContent<Content: View>(
        _ section: ReviewSection, stage: PipelineStage, hasContent: Bool, ask: String,
        known: String? = nil, progress: String? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        let status = store.analysis.status(stage)
        switch Self.sectionBranch(hasContent: hasContent, status: status) {
        case .content(showsOverlay: true):
            content()
                .overlay(alignment: .bottom) {
                    switch Self.sectionOverlay(status: status, progress: progress) {
                    case .progress(let text):
                        SectionProgressPill(text: text)
                    case .stopped:
                        SectionStoppedPill { store.retry(stage) }
                    case .none:
                        EmptyView()
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: status.isRunning)
                .animation(.easeInOut(duration: 0.3), value: status == .stopped)
        case .content(showsOverlay: false):
            content()
        case .failed(let message):
            SectionFailedView(
                section: section, message: message, onRetry: { store.retry(stage) },
                onAsk: { withAnimation(Self.spring) { store.ask(ask, about: .pullRequest) } })
        case .stopped:
            SectionStoppedView(section: section) { store.retry(stage) }
        case .pending:
            SectionPendingView(section: section, status: status, known: known)
        }
    }

    @ViewBuilder
    private func detailContent(_ graph: PRGraph) -> some View {
        let analysis = store.analysis
        switch store.current {
        case .summary:
            SummaryView(
                graph: graph, analysis: analysis, discussed: store.conversations.discussedConsiderationIds,
                onRetry: { store.retry($0) }, navigate: { store.navigate(to: $0) }
            )
        case .architecture, .componentDetail(_), .edgeDetail(_):
            sectionContent(
                .architecture, stage: .architecture, hasContent: !graph.components.isEmpty,
                ask: "What part of the system does this change sit in, and how does it change it?",
                known: graph.dominantBehaviorChange.map { $0.after.map(\.label).joined(separator: " → ") }
            ) {
                ArchitectureView(graph: graph, focus: architectureFocus, mode: $store.diagramMode)
            }
        case .decisions, .decisionDetail(_), .consideration(_):
            sectionContent(
                .decisions, stage: .decisions, hasContent: !graph.decisions.isEmpty,
                ask: "What are the consequential design decisions in this PR?",
                progress: "\(graph.decisions.count) found so far · looking for other consequential choices…"
            ) {
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
            sectionContent(
                .flows, stage: .flows, hasContent: !graph.flows.isEmpty,
                ask: "What happens at runtime when this changed behavior is triggered?",
                progress: "\(graph.flows.count) traced so far · tracing others…"
            ) {
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
