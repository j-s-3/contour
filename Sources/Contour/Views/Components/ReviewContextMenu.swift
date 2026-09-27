import SwiftUI
import AppKit

/// What a boxed element can do with itself, injected once at the window shell so every
/// lens gets the same right-click menu without threading closures through each view.
struct ReviewActions {
    var graph: PRGraph?
    /// The URL the PR was opened from; the base for GitHub links (keeps GitHub Enterprise
    /// hosts intact rather than assuming github.com).
    var prURL: String?
    var ask: (ReviewSubject) -> Void = { _ in }
    /// Opens the subject's conversation and asks this question in it.
    var askQuestion: (String, ReviewSubject) -> Void = { _, _ in }
    var navigate: (NavigationTarget) -> Void = { _ in }
    /// A lens publishes its current selection so ⌘⇧A knows what "this" is.
    var focus: (ReviewSubject?) -> Void = { _ in }

    var repoWebBase: String? {
        if let prURL, let range = prURL.range(of: "/pull/") { return String(prURL[..<range.lowerBound]) }
        return graph.map { "https://github.com/\($0.pr.repo)" }
    }

    func githubURL(for ref: CodeRef) -> URL? {
        guard let base = repoWebBase, let graph else { return nil }
        let sha = ref.side == .base ? graph.pr.baseSha : graph.pr.headSha
        let lines = ref.startLine == ref.endLine ? "L\(ref.startLine)" : "L\(ref.startLine)-L\(ref.endLine)"
        return URL(string: "\(base)/blob/\(sha)/\(ref.path)#\(lines)")
    }

    var pullRequestURL: URL? {
        if let prURL, let url = URL(string: prURL) { return url }
        guard let base = repoWebBase, let graph else { return nil }
        return URL(string: "\(base)/pull/\(graph.pr.number)")
    }
}

extension EnvironmentValues {
    @Entry var reviewActions = ReviewActions()
}

/// The ways out of a review, shared by the toolbar, the File menu and the command palette.
extension GraphStore {
    var pullRequestWebURL: URL? {
        ReviewActions(graph: graph, prURL: lastPRURL).pullRequestURL
    }

    func openOnGitHub() {
        if let url = pullRequestWebURL { NSWorkspace.shared.open(url) }
    }

    /// Puts the reviewer's marks and notes on the pasteboard as Markdown for a GitHub review
    /// comment (`PRGraph.reviewSummaryMarkdown`).
    func copyReviewSummary() {
        guard let graph else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(graph.reviewSummaryMarkdown, forType: .string)
    }

    /// Read once: `gh` appearing mid-session is rare enough to need a relaunch.
    static let ghAvailable = Shell.which("gh") != nil

    /// One review at a time, and not the same verdict twice. The other verdict stays open:
    /// on GitHub a reviewer's latest review stands, so they can change their mind.
    func canSubmitReview(_ verdict: PRReview.Verdict) -> Bool {
        guard let graph, pullRequestWebURL != nil, review != .submitted(verdict) else { return false }
        if case .submitting = review { return false }
        return PRReview.canReview(prState: graph.pr.state, ghAvailable: Self.ghAvailable)
    }

    /// Why a verdict is unavailable, for its button's help text; nil when it's available.
    func reviewUnavailableReason(_ verdict: PRReview.Verdict) -> String? {
        if review == .submitted(verdict) { return verdict == .approve ? "Approved" : "Changes requested" }
        guard let graph else { return "No pull request is open" }
        if !Self.ghAvailable { return "Reviewing needs the GitHub CLI — install gh and run `gh auth login`" }
        if graph.pr.state.uppercased() != "OPEN" { return "Only an open pull request can be reviewed" }
        return nil
    }
}

/// The open review, published to the menu bar so File-menu commands act on the key window's
/// PR and disable themselves when there is none.
extension FocusedValues {
    @Entry var reviewStore: GraphStore?
}

/// ⌘⇧O — bound on the File menu's "Open on GitHub" and named in the toolbar button's help.
enum OpenOnGitHubShortcut {
    static let key: KeyEquivalent = "o"
    static let modifiers: EventModifiers = [.command, .shift]
}

extension View {
    /// The standard right-click menu for any review artifact: "Ask about this…" first, then
    /// a handful of ways to go deeper, then copy. Kept short on purpose.
    func reviewContextMenu(_ subject: ReviewSubject) -> some View {
        modifier(ReviewContextMenuModifier(subject: subject, extra: EmptyView()))
    }

    /// The standard menu plus items only the calling view can perform (e.g. expanding the
    /// card it sits on), placed right after "Ask about this…" and its follow-ups.
    func reviewContextMenu<Extra: View>(_ subject: ReviewSubject, @ViewBuilder extra: () -> Extra) -> some View {
        modifier(ReviewContextMenuModifier(subject: subject, extra: extra()))
    }
}

/// ⌘⇧A — shown beside "Ask about this…" and bound for real at the window shell.
enum AskShortcut {
    static let key: KeyEquivalent = "a"
    static let modifiers: EventModifiers = [.command, .shift]
}

private struct ReviewContextMenuModifier<Extra: View>: ViewModifier {
    @Environment(\.reviewActions) private var actions
    let subject: ReviewSubject
    let extra: Extra

    func body(content: Content) -> some View {
        content.contextMenu { menu }
    }

    @ViewBuilder
    private var menu: some View {
        if let graph = actions.graph, let resolved = graph.resolve(subject) {
            Button { actions.ask(subject) } label: {
                Label("Ask about this…", systemImage: "sparkles")
            }
            .keyboardShortcut(AskShortcut.key, modifiers: AskShortcut.modifiers)
            if resolved.kind == .tradeoff {
                Button("Why did the PR choose this side?") {
                    actions.askQuestion("Why did the PR choose this side of the tradeoff?", subject)
                }
            }

            Divider()

            extra

            if let target = resolved.detailTarget, resolved.kind != .tradeoff {
                Button(resolved.kind == .code ? "Show in code" : "Open details") { actions.navigate(target) }
            }
            if resolved.kind == .code, case .codeRef(let ref) = subject {
                Button("Show in Diff") { actions.navigate(.diffLocation(ref)) }
            }
            showInArchitecture(resolved, graph)
            relatedDecisions(resolved, graph)
            relatedFlows(resolved, graph)
            if resolved.kind != .code { showInCode(resolved) }
            if let url = githubURL(resolved) {
                Button("Open on GitHub") { NSWorkspace.shared.open(url) }
            }

            Divider()

            if let url = githubURL(resolved) {
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        }
    }

    /// From anything that happens in a part — a flow step, a decision, a behavior stage —
    /// to that part on the architecture drawing.
    @ViewBuilder
    private func showInArchitecture(_ resolved: ResolvedSubject, _ graph: PRGraph) -> some View {
        let parts = [.component, .relationship, .pullRequest].contains(resolved.kind) ? []
            : unique(resolved.componentIds.compactMap { graph.drawablePart(for: $0) })
        if parts.count == 1, let part = parts.first {
            Button("Show in Architecture") { actions.navigate(.componentDetail(part.id)) }
        } else if parts.count > 1 {
            Menu("Show in Architecture") {
                ForEach(parts) { part in Button(part.title) { actions.navigate(.componentDetail(part.id)) } }
            }
        }
    }

    @ViewBuilder
    private func relatedDecisions(_ resolved: ResolvedSubject, _ graph: PRGraph) -> some View {
        let decisions = [.decision, .tradeoff].contains(resolved.kind) ? [] : resolved.decisionIds.compactMap(graph.decision)
        if decisions.count == 1, let d = decisions.first {
            Button("Show Related Decision") { actions.navigate(.decisionDetail(d.id)) }
        } else if decisions.count > 1 {
            Menu("Show Related Decisions") {
                ForEach(decisions) { d in Button(d.title) { actions.navigate(.decisionDetail(d.id)) } }
            }
        }
    }

    @ViewBuilder
    private func relatedFlows(_ resolved: ResolvedSubject, _ graph: PRGraph) -> some View {
        let flows = [.flow, .flowStep].contains(resolved.kind) ? [] : resolved.flowIds.compactMap(graph.flow)
        if flows.count == 1, let f = flows.first {
            Button("Show Related Flow") { actions.navigate(.flowDetail(f.id)) }
        } else if flows.count > 1 {
            Menu("Show Related Flows") {
                ForEach(flows) { f in Button(f.title) { actions.navigate(.flowDetail(f.id)) } }
            }
        }
    }

    @ViewBuilder
    private func showInCode(_ resolved: ResolvedSubject) -> some View {
        let title = resolved.kind == .tradeoff ? "Show Evidence" : "Show in Code"
        if resolved.refs.count == 1, let ref = resolved.refs.first {
            Button(title) { actions.navigate(.evidence(ref)) }
        } else if resolved.refs.count > 1 {
            Menu(title) {
                ForEach(resolved.refs.prefix(12)) { ref in Button(ref.display) { actions.navigate(.evidence(ref)) } }
            }
        }
    }

    /// Code gets a line permalink; anything else links to its first cited range when it
    /// has one, else to the pull request itself.
    private func githubURL(_ resolved: ResolvedSubject) -> URL? {
        if let ref = resolved.refs.first, let url = actions.githubURL(for: ref) { return url }
        return actions.pullRequestURL
    }
}
