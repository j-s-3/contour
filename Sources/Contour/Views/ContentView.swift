import SwiftUI
import AppKit

/// The window shell from §4.1: sidebar of lenses + files, main pane driven by the
/// semantic navigation stack, inspector-free for MVP (cross-links live inline instead).
struct ContentView: View {
    @State private var store = GraphStore()
    @State private var showPalette = false
    /// Mirrors the persisted flag so finishing the wizard swaps the view immediately.
    @State private var needsOnboarding = !Preferences.shared.hasCompletedOnboarding
    /// Explicit, not `.automatic`: `WindowAccessor` force-enters real fullscreen ~0.2s
    /// after launch, and that AppKit transition is a known trigger for
    /// `NavigationSplitView` silently collapsing its sidebar column (the automatic
    /// width-based visibility heuristic gets a bad reading mid-transition and never
    /// reconsiders). Owning the binding — and reasserting it once fullscreen actually
    /// completes — is what keeps the sidebar from vanishing.
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if needsOnboarding {
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
        .background(WindowAccessor()) // enters full screen shortly after launch, see §1/2 request
        .onAppear {
            // Manual-testing hook alongside CONTOUR_MOCK_ANALYSIS: open straight into a PR
            // rather than pasting a URL on every launch.
            if !needsOnboarding, case .idle = store.phase,
               let url = ProcessInfo.processInfo.environment["CONTOUR_OPEN_PR_URL"], !url.isEmpty {
                store.load(prURL: url)
            }
        }
        .onChange(of: store.phase) { _, phase in
            // Companion to CONTOUR_OPEN_PR_URL: land on a specific lens once the PR is ready.
            guard phase == .ready,
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
    }

    @ViewBuilder
    private var mainBody: some View {
        Group {
            switch store.phase {
            case .idle:
                OnboardingView { url in store.load(prURL: url) }
            case .running(let stage):
                AnalyzingView(stage: stage, log: store.progressLog)
            case .failed(let message):
                FailedView(message: message) { store.phase = .idle }
            case .ready:
                if let graph = store.graph {
                    readyBody(graph)
                } else {
                    OnboardingView { url in store.load(prURL: url) }
                }
            }
        }
    }

    @ViewBuilder
    private func readyBody(_ graph: PRGraph) -> some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar(graph)
        } detail: {
            detailContent(graph)
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
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { store.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!store.canGoBack)
                Button { store.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!store.canGoForward)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showPalette = true } label: { Image(systemName: "magnifyingglass") }
                    .help("Command palette (⌘K)")
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

    private func sidebar(_ graph: PRGraph) -> some View {
        List {
            Section("Overview") {
                sidebarRow("Overview", "house", .summary)
            }
            Section("System") {
                sidebarRow("Architecture", "square.stack.3d.up", .architecture)
                sidebarRow("Flows (\(graph.flows.count))", "arrow.triangle.branch", .flows)
            }
            Section("Review") {
                // Review progress means "I have consciously judged n of the consequential
                // decisions this PR made", so it sits on the row where that judgment happens.
                let p = graph.reviewProgress
                let done = p.total > 0 && p.reviewed == p.total
                sidebarRow("Decisions", "checklist", .decisions) {
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
                .help("Design decisions you've consciously reviewed: \(p.reviewed) of \(p.total)")
            }
            Section("Code") {
                sidebarRow("Raw diff", "doc.text", .diff)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }

    private func sidebarRow(_ title: String, _ symbol: String, _ target: NavigationTarget) -> some View {
        sidebarRow(title, symbol, target) { EmptyView() }
    }

    private func sidebarRow<Trailing: View>(_ title: String, _ symbol: String, _ target: NavigationTarget,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        Button { store.navigate(to: target) } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer(minLength: 6)
                trailing()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isActive(target) ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    private func isActive(_ target: NavigationTarget) -> Bool {
        switch (store.current, target) {
        case (.summary, .summary), (.architecture, .architecture), (.decisions, .decisions),
             (.flows, .flows), (.diff, .diff):
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
    private var architectureFocus: ArchAnchor? {
        switch store.current {
        case .componentDetail(let id): return .node(id)
        case .edgeDetail(let id): return .edge(id)
        default: return nil
        }
    }

    /// The flow, and stage, a navigation target asks Flows to show.
    private var flowsFocus: FlowsView.Focus? {
        switch store.current {
        case .flowDetail(let id): return .init(flowId: id)
        case .flowNodeDetail(let flowId, let nodeId): return .init(flowId: flowId, nodeId: nodeId)
        default: return nil
        }
    }

    /// The decision a navigation target asks Decisions to open, and the Overview question
    /// that brought the reviewer there, if any.
    private func decisionsFocus(_ graph: PRGraph) -> DecisionsView.Focus? {
        switch store.current {
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

    @ViewBuilder
    private func detailContent(_ graph: PRGraph) -> some View {
        switch store.current {
        case .summary:
            SummaryView(graph: graph) { store.navigate(to: $0) }
        case .architecture, .componentDetail(_), .edgeDetail(_):
            ArchitectureView(graph: graph, focus: architectureFocus)
        case .decisions, .decisionDetail(_), .consideration(_):
            DecisionsView(
                graph: graph,
                focus: decisionsFocus(graph),
                onSetState: { store.setReviewerState($1, forDecision: $0) },
                onSetNote: { store.setReviewerNote($1, forDecision: $0) }
            )
        case .flows, .flowDetail(_), .flowNodeDetail(_, _):
            FlowsView(
                graph: graph,
                focus: flowsFocus,
                onOpenEvidence: { store.navigate(to: .evidence($0)) }
            )
        case .files:
            ContentUnavailableView("No file view", systemImage: "doc.text")
        case .diff:
            if let diff = store.diffText {
                DiffView(diff: diff)
            } else {
                ContentUnavailableView("No diff available", systemImage: "doc.text")
            }
        case .evidence(let ref):
            CodeViewerView(ref: ref, checkout: store.checkout) { store.goBack() }
        }
    }
}
