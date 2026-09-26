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
