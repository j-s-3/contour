enum TrackerID: String, Codable, CaseIterable, Sendable {
    case github
    case jira
    case none

    var displayName: String {
        switch self {
        case .github: return "GitHub Issues"
        case .jira: return "Jira"
        case .none: return "None"
        }
    }
}

struct IssueRef: Hashable, Sendable {
    var id: String
    var tracker: TrackerID
    var owner: String?
    var repo: String?

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

struct TicketInfo: Codable, Hashable, Sendable {
    var kind: TrackerID
    var key: String
    var summary: String
    var description: String
    var url: String
}

protocol IssueTracker: Sendable {
    var id: TrackerID { get }
    func reference(in context: RawPRContext) -> IssueRef?
    func fetch(_ ref: IssueRef) async -> TicketInfo?
}

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
