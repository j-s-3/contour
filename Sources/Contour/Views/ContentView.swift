import SwiftUI
import AppKit

/// The window shell from §4.1: sidebar of lenses + files, main pane driven by the
/// semantic navigation stack, inspector-free for MVP (cross-links live inline instead).
struct ContentView: View {
    @State private var store = GraphStore()
    @State private var showPalette = false
    /// Explicit, not `.automatic`: `WindowAccessor` force-enters real fullscreen ~0.2s
    /// after launch, and that AppKit transition is a known trigger for
    /// `NavigationSplitView` silently collapsing its sidebar column (the automatic
    /// width-based visibility heuristic gets a bad reading mid-transition and never
    /// reconsiders). Owning the binding — and reasserting it once fullscreen actually
    /// completes — is what keeps the sidebar from vanishing.
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
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
        .sheet(isPresented: $showPalette) {
            CommandPaletteView(store: store, isPresented: $showPalette)
        }
        .background(
            Button("") { showPalette = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
        )
        .background(WindowAccessor()) // enters full screen shortly after launch, see §1/2 request
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            sidebarVisibility = .all
        }
    }

    @ViewBuilder
    private func readyBody(_ graph: PRGraph) -> some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar(graph)
        } detail: {
            detailContent(graph)
        }
        .navigationTitle("\(graph.pr.repo) #\(graph.pr.number)")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { store.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!store.canGoBack)
                Button { store.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!store.canGoForward)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showPalette = true } label: { Image(systemName: "magnifyingglass") }
                    .help("Command palette (⌘K)")
            }
        }
    }

    private func sidebar(_ graph: PRGraph) -> some View {
        List {
            Section("Overview") {
                sidebarRow("Summary", "house", .summary)
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
                let p = graph.reviewProgress
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: p.total == 0 ? 0 : Double(p.reviewed), total: Double(max(p.total, 1)))
                    Text("\(p.reviewed)/\(p.total) decisions reviewed").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
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
        case (.componentDetail(_), .architecture), (.decisionDetail(_), .decisions),
             (.tradeoffDetail(_), .tradeoffs), (.flowDetail(_), .flows):
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func detailContent(_ graph: PRGraph) -> some View {
        switch store.current {
        case .summary:
            SummaryView(graph: graph) { store.navigate(to: $0) }
        case .architecture, .componentDetail(_):
            ArchitectureView(
                graph: graph,
                onOpenEvidence: { store.navigate(to: .evidence($0)) },
                onOpenDecision: { store.navigate(to: .decisionDetail($0)) }
            )
        case .decisions, .decisionDetail(_):
            DecisionsView(
                graph: graph,
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
            FlowsView(graph: graph, onOpenEvidence: { store.navigate(to: .evidence($0)) })
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
