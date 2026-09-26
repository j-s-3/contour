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
            Section("Decisions") {
                sidebarRow("Decisions (\(graph.decisions.count))", "checklist", .decisions)
                sidebarRow("Tradeoffs (\(graph.tradeoffs.count))", "arrow.left.arrow.right", .tradeoffs)
            }
            Section("Code") {
                sidebarRow("Raw diff", "doc.text", .diff)
            }
            Section("Progress") {
                // Review progress is status, not PR understanding, so it lives here — compact
                // and always visible — rather than as a card on the Overview.
                let p = graph.reviewProgress
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(verbatim: "\(p.reviewed) / \(p.total) reviewed").monospacedDigit()
                    } icon: {
                        Image(systemName: p.total > 0 && p.reviewed == p.total ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundStyle(p.total > 0 && p.reviewed == p.total ? .green : .secondary)
                    }
                    .font(.callout)
                    ProgressView(value: p.total == 0 ? 0 : Double(p.reviewed), total: Double(max(p.total, 1)))
                        .controlSize(.small)
                }
                .padding(.vertical, 2)
                .help("Decisions you've accepted, questioned, or marked for discussion")
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }

    private func sidebarRow(_ title: String, _ symbol: String, _ target: NavigationTarget) -> some View {
        Button { store.navigate(to: target) } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.plain)
        .listRowBackground(isActive(target) ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    private func isActive(_ target: NavigationTarget) -> Bool {
        switch (store.current, target) {
        case (.summary, .summary), (.architecture, .architecture), (.decisions, .decisions),
             (.tradeoffs, .tradeoffs), (.flows, .flows), (.diff, .diff):
            return true
        case (.componentDetail(_), .architecture), (.edgeDetail(_), .architecture), (.decisionDetail(_), .decisions),
             (.tradeoffDetail(_), .tradeoffs), (.flowDetail(_), .flows):
            return true
        default:
            return false
        }
    }

    /// The node or edge a navigation target asks Architecture to select, if any.
    private var architectureFocus: ArchitectureView.Selection? {
        switch store.current {
        case .componentDetail(let id): return .node(id)
        case .edgeDetail(let id): return .edge(id)
        default: return nil
        }
    }

    @ViewBuilder
    private func detailContent(_ graph: PRGraph) -> some View {
        switch store.current {
        case .summary:
            SummaryView(graph: graph) { store.navigate(to: $0) }
        case .architecture, .componentDetail(_), .edgeDetail(_):
            ArchitectureView(
                graph: graph,
                focus: architectureFocus,
                onOpenEvidence: { store.navigate(to: .evidence($0)) },
                onOpenDecision: { store.navigate(to: .decisionDetail($0)) }
            )
        case .decisions, .decisionDetail(_):
            DecisionsView(
                graph: graph,
                focusDecisionId: { if case .decisionDetail(let id) = store.current { return id } else { return nil } }(),
                onSetState: { store.setReviewerState($1, forDecision: $0) },
                onOpenEvidence: { store.navigate(to: .evidence($0)) },
                onOpenTradeoff: { store.navigate(to: .tradeoffDetail($0)) }
            )
        case .tradeoffs, .tradeoffDetail(_):
            TradeoffsView(
                graph: graph,
                onOpenEvidence: { store.navigate(to: .evidence($0)) },
                onOpenDecision: { store.navigate(to: .decisionDetail($0)) }
            )
        case .flows, .flowDetail(_):
            FlowsView(
                graph: graph,
                focusFlowId: { if case .flowDetail(let id) = store.current { return id } else { return nil } }(),
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
