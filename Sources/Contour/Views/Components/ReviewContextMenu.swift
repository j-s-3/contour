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

    static func navigationItems(
        for resolved: ResolvedSubject, subject: ReviewSubject, in graph: PRGraph
    ) -> [ReviewMenuItem] {
        var items: [ReviewMenuItem] = []
        if let (label, target) = detailButton(for: resolved) {
            items.append(.button(ReviewMenuEntry(title: label, command: .navigate(target))))
        }
        if let ref = diffRef(for: resolved, subject: subject) {
            items.append(.button(ReviewMenuEntry(title: "Show in Diff", command: .navigate(.diffLocation(ref)))))
        }
        items += choice(
            single: "Show in Architecture", multiple: "Show in Architecture",
            entries: architectureParts(for: resolved, in: graph).map {
                ReviewMenuEntry(title: $0.title, command: .navigate(.componentDetail($0.id)))
            })
        items += choice(
            single: "Show Related Decision", multiple: "Show Related Decisions",
            entries: relatedDecisions(for: resolved, in: graph).map {
                ReviewMenuEntry(title: $0.title, command: .navigate(.decisionDetail($0.id)))
            })
        items += choice(
            single: "Show Related Flow", multiple: "Show Related Flows",
            entries: relatedFlows(for: resolved, in: graph).map {
                ReviewMenuEntry(title: $0.title, command: .navigate(.flowDetail($0.id)))
            })
        if resolved.kind != .code {
            let title = showInCodeTitle(for: resolved.kind)
            items += choice(
                single: title, multiple: title,
                entries: codeRefMenuItems(for: resolved).map {
                    ReviewMenuEntry(title: $0.display, command: .navigate(.evidence($0)))
                })
        }
        return items
    }

    static func choice(single: String, multiple: String, entries: [ReviewMenuEntry]) -> [ReviewMenuItem] {
        switch entries.count {
        case 0: []
        case 1: [.button(ReviewMenuEntry(title: single, command: entries[0].command))]
        default: [.submenu(multiple, entries)]
        }
    }
}

struct ReviewMenuEntry: Equatable {
    var title: String
    var command: ReviewMenuCommand
}

enum ReviewMenuItem: Equatable {
    case button(ReviewMenuEntry)
    case submenu(String, [ReviewMenuEntry])
}

enum ReviewMenuCommand: Equatable {
    case ask(ReviewSubject)
    case askTradeoff(ReviewSubject)
    case navigate(NavigationTarget)
    case openURL(URL)
    case copyURL(URL)
}

extension ReviewActions {
    func perform(_ command: ReviewMenuCommand) {
        switch command {
        case .ask(let subject): ask(subject)
        case .askTradeoff(let subject):
            askQuestion("Why did the PR choose this side of the tradeoff?", subject)
        case .navigate(let target): navigate(target)
        case .openURL(let url): NSWorkspace.shared.open(url)
        case .copyURL(let url):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
    }
}

private struct ReviewContextMenuModifier<Extra: View>: ViewModifier {
    let subject: ReviewSubject
    let extra: Extra

    func body(content: Content) -> some View {
        content.contextMenu { ReviewContextMenuContent(subject: subject, extra: extra) }
    }
}

struct ReviewContextMenuContent<Extra: View>: View {
    @Environment(\.reviewActions) private var actions
    let subject: ReviewSubject
    let extra: Extra

    @ViewBuilder
    var body: some View {
        if let graph = actions.graph, let resolved = graph.resolve(subject) {
            Button {
                actions.perform(.ask(subject))
            } label: {
                Label("Ask about this…", systemImage: "sparkles")
            }
            .keyboardShortcut(AskShortcut.key, modifiers: AskShortcut.modifiers)
            if ReviewContextMenuLogic.showsTradeoffQuestion(for: resolved.kind) {
                entryButton(ReviewMenuEntry(title: "Why did the PR choose this side?", command: .askTradeoff(subject)))
            }

            Divider()

            extra

            ForEach(
                Array(ReviewContextMenuLogic.navigationItems(for: resolved, subject: subject, in: graph).enumerated()),
                id: \.offset
            ) { _, item in
                itemView(item)
            }
            if let url = ReviewContextMenuLogic.githubURL(for: resolved, actions: actions) {
                entryButton(ReviewMenuEntry(title: "Open on GitHub", command: .openURL(url)))

                Divider()

                entryButton(ReviewMenuEntry(title: "Copy Link", command: .copyURL(url)))
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: ReviewMenuItem) -> some View {
        switch item {
        case .button(let entry):
            entryButton(entry)
        case .submenu(let title, let entries):
            Menu(title) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in entryButton(entry) }
            }
        }
    }

    private func entryButton(_ entry: ReviewMenuEntry) -> some View {
        Button(entry.title) { actions.perform(entry.command) }
    }
}
