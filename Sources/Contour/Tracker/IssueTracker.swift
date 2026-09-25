import Foundation

/// Where a PR's originating issue lives.
enum TrackerID: String, Codable, CaseIterable, Sendable {
    /// GitHub issues. The default: needs nothing installed, and the PR is already there.
    case github
    /// Jira via `acli`. Opt-in, and only offered when `acli` is present.
    case jira
    /// Skip the lookup entirely.
    case none

    var displayName: String {
        switch self {
        case .github: return "GitHub Issues"
        case .jira: return "Jira"
        case .none: return "None"
        }
    }
}

/// A detected reference to an issue, before it has been fetched.
struct IssueRef: Hashable, Sendable {
    /// `"123"` for GitHub, `"PROJ-123"` for Jira.
    var id: String
    var tracker: TrackerID
    /// Set when a GitHub reference names a repo other than the PR's own
    /// (`owner/repo#123`), so cross-repo references resolve correctly.
    var owner: String?
    var repo: String?

    /// How the reference is written in prose, for progress lines and chips.
    var displayKey: String {
        switch tracker {
        case .github:
            if let owner, let repo { return "\(owner)/\(repo)#\(id)" }
            return "#\(id)"
        case .jira, .none:
            return id
        }
    }
}

/// A fetched issue, used to ground the "Problem to be solved" summary in what was
/// actually asked for rather than in what the diff appears to do.
struct TicketInfo: Codable, Hashable, Sendable {
    var kind: TrackerID
    var key: String
    var summary: String
    var description: String
    var url: String
}

/// Finds and fetches the issue a PR came from.
///
/// The contract is best-effort and load-bearing: no missing, unreachable, or unparseable
/// issue may ever fail PR analysis. `fetch` returns nil instead of throwing, and callers
/// continue without it.
protocol IssueTracker: Sendable {
    var id: TrackerID { get }
    func reference(in context: RawPRContext) -> IssueRef?
    func fetch(_ ref: IssueRef) async -> TicketInfo?
}

/// The tracker used when lookup is switched off. Keeps the pipeline free of `if tracker
/// != nil` branches.
struct NoTracker: IssueTracker {
    let id: TrackerID = .none
    func reference(in context: RawPRContext) -> IssueRef? { nil }
    func fetch(_ ref: IssueRef) async -> TicketInfo? { nil }
}

enum IssueTrackerFactory {
    static func make(_ id: TrackerID, source: any PRSource) -> any IssueTracker {
        switch id {
        case .github: return GitHubIssueTracker(source: source)
        case .jira: return JiraTracker()
        case .none: return NoTracker()
        }
    }
}
