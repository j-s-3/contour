import AppKit
import SwiftUI

struct ReviewActions {
    var graph: PRGraph?
    var prURL: String?
    var ask: (ReviewSubject) -> Void = { _ in }
    var askQuestion: (String, ReviewSubject) -> Void = { _, _ in }
    var navigate: (NavigationTarget) -> Void = { _ in }
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

extension GraphStore {
    var pullRequestWebURL: URL? {
        ReviewActions(graph: graph, prURL: lastPRURL).pullRequestURL
    }

    func openOnGitHub() {
        if let url = pullRequestWebURL { NSWorkspace.shared.open(url) }
    }

    func copyReviewSummary() {
        guard let graph else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(graph.reviewSummaryMarkdown, forType: .string)
    }

    static let ghAvailable = Shell.which("gh") != nil

    func canSubmitReview(_ verdict: PRReview.Verdict) -> Bool {
        guard let graph, pullRequestWebURL != nil, review != .submitted(verdict) else { return false }
        if case .submitting = review { return false }
        return PRReview.canReview(prState: graph.pr.state, ghAvailable: canUseGitHubCLI)
    }

    func reviewUnavailableReason(_ verdict: PRReview.Verdict) -> String? {
        if review == .submitted(verdict) { return verdict == .approve ? "Approved" : "Changes requested" }
        guard let graph else { return "No pull request is open" }
        if !canUseGitHubCLI { return "Reviewing needs the GitHub CLI — install gh and run `gh auth login`" }
        if graph.pr.state.uppercased() != "OPEN" { return "Only an open pull request can be reviewed" }
        return nil
    }
}

extension FocusedValues {
    @Entry var reviewStore: GraphStore?
}

enum OpenOnGitHubShortcut {
    static let key: KeyEquivalent = "o"
    static let modifiers: EventModifiers = [.command, .shift]
}

extension View {
    func reviewContextMenu(_ subject: ReviewSubject) -> some View {
        modifier(ReviewContextMenuModifier(subject: subject, extra: EmptyView()))
    }

    func reviewContextMenu<Extra: View>(_ subject: ReviewSubject, @ViewBuilder extra: () -> Extra) -> some View {
        modifier(ReviewContextMenuModifier(subject: subject, extra: extra()))
    }
}

enum AskShortcut {
    static let key: KeyEquivalent = "a"
    static let modifiers: EventModifiers = [.command, .shift]
}

enum ReviewContextMenuLogic {
    static func architectureParts(for resolved: ResolvedSubject, in graph: PRGraph) -> [ComponentNode] {
        guard ![.component, .relationship, .pullRequest].contains(resolved.kind) else { return [] }
        return unique(resolved.componentIds.compactMap(graph.drawablePart(for:)))
    }

    static func relatedDecisions(for resolved: ResolvedSubject, in graph: PRGraph) -> [DecisionNode] {
        guard ![.decision, .tradeoff].contains(resolved.kind) else { return [] }
        return resolved.decisionIds.compactMap(graph.decision)
    }

    static func relatedFlows(for resolved: ResolvedSubject, in graph: PRGraph) -> [FlowNode] {
        guard ![.flow, .flowStep].contains(resolved.kind) else { return [] }
        return resolved.flowIds.compactMap(graph.flow)
    }

    static func githubURL(for resolved: ResolvedSubject, actions: ReviewActions) -> URL? {
        if let ref = resolved.refs.first, let url = actions.githubURL(for: ref) { return url }
        return actions.pullRequestURL
    }

    static func showsTradeoffQuestion(for kind: SubjectKind) -> Bool {
        kind == .tradeoff
    }

    static func detailButton(for resolved: ResolvedSubject) -> (label: String, target: NavigationTarget)? {
        guard resolved.kind != .tradeoff, let target = resolved.detailTarget else { return nil }
        return (resolved.kind == .code ? "Show in code" : "Open details", target)
    }

    static func diffRef(for resolved: ResolvedSubject, subject: ReviewSubject) -> CodeRef? {
        guard resolved.kind == .code, case .codeRef(let ref) = subject else { return nil }
        return ref
    }

    static func showInCodeTitle(for kind: SubjectKind) -> String {
        kind == .tradeoff ? "Show Evidence" : "Show in Code"
    }

    static func codeRefMenuItems(for resolved: ResolvedSubject) -> [CodeRef] {
        Array(resolved.refs.prefix(12))
    }
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
            Button {
                actions.ask(subject)
            } label: {
                Label("Ask about this…", systemImage: "sparkles")
            }
            .keyboardShortcut(AskShortcut.key, modifiers: AskShortcut.modifiers)
            if ReviewContextMenuLogic.showsTradeoffQuestion(for: resolved.kind) {
                Button("Why did the PR choose this side?") {
                    actions.askQuestion("Why did the PR choose this side of the tradeoff?", subject)
                }
            }

            Divider()

            extra

            if let (label, target) = ReviewContextMenuLogic.detailButton(for: resolved) {
                Button(label) { actions.navigate(target) }
            }
            if let ref = ReviewContextMenuLogic.diffRef(for: resolved, subject: subject) {
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

    @ViewBuilder
    private func showInArchitecture(_ resolved: ResolvedSubject, _ graph: PRGraph) -> some View {
        let parts = ReviewContextMenuLogic.architectureParts(for: resolved, in: graph)
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
        let decisions = ReviewContextMenuLogic.relatedDecisions(for: resolved, in: graph)
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
        let flows = ReviewContextMenuLogic.relatedFlows(for: resolved, in: graph)
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
        let title = ReviewContextMenuLogic.showInCodeTitle(for: resolved.kind)
        if resolved.refs.count == 1, let ref = resolved.refs.first {
            Button(title) { actions.navigate(.evidence(ref)) }
        } else if resolved.refs.count > 1 {
            Menu(title) {
                ForEach(ReviewContextMenuLogic.codeRefMenuItems(for: resolved)) { ref in
                    Button(ref.display) { actions.navigate(.evidence(ref)) }
                }
            }
        }
    }

    private func githubURL(_ resolved: ResolvedSubject) -> URL? {
        ReviewContextMenuLogic.githubURL(for: resolved, actions: actions)
    }
}
