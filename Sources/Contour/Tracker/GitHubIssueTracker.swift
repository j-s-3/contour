import Foundation

struct GitHubIssueTracker: IssueTracker {
    let id: TrackerID = .github
    let source: any PRSource

    private static let closingPattern = try! NSRegularExpression(
        pattern: #"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\b\s*:?\s+(?:([\w.-]+)/([\w.-]+))?(?:#|GH-)(\d+)"#,
        options: [.caseInsensitive]
    )

    private static let barePattern = try! NSRegularExpression(
        pattern: #"(?:^|[\s(\[])(?:([\w.-]+)/([\w.-]+))?#(\d+)\b"#
    )

    private static let branchPattern = try! NSRegularExpression(
        pattern: #"(?:^|[/_-])(?:gh-|issue-|#)?(\d{1,6})(?:[/_-]|$)"#,
        options: [.caseInsensitive]
    )

    func reference(in context: RawPRContext) -> IssueRef? {
        let prose = [context.body, context.title] + context.commits.map(\.message)
        for text in prose {
            if let ref = Self.match(Self.closingPattern, in: text, context: context) { return ref }
        }
        for text in prose {
            if let ref = Self.match(Self.barePattern, in: text, context: context) { return ref }
        }
        if let ref = Self.match(Self.branchPattern, in: context.headRefName, context: context) {
            return ref
        }
        return nil
    }

    private static func match(_ regex: NSRegularExpression, in text: String, context: RawPRContext) -> IssueRef? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range) else { return nil }

        func group(_ i: Int) -> String? {
            guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: text) else { return nil }
            return String(text[r])
        }
        guard let number = group(m.numberOfRanges - 1), !number.isEmpty else { return nil }

        let owner = group(1)
        let repo = group(2)
        let isCrossRepo = owner != nil && repo != nil && !(owner == context.owner && repo == context.repo)
        return IssueRef(
            id: number,
            tracker: .github,
            owner: isCrossRepo ? owner : nil,
            repo: isCrossRepo ? repo : nil
        )
    }

    func fetch(_ ref: IssueRef) async -> TicketInfo? {
        let owner = ref.owner ?? currentOwner
        let repo = ref.repo ?? currentRepo
        guard let owner, let repo else { return nil }
        guard let issue = await source.fetchIssue(owner: owner, repo: repo, number: ref.id) else {
            return nil
        }
        return TicketInfo(
            kind: .github,
            key: ref.displayKey,
            summary: issue.title,
            description: issue.body,
            url: issue.url
        )
    }

    var currentOwner: String?
    var currentRepo: String?

    init(source: any PRSource, currentOwner: String? = nil, currentRepo: String? = nil) {
        self.source = source
        self.currentOwner = currentOwner
        self.currentRepo = currentRepo
    }

    func scoped(to context: RawPRContext) -> GitHubIssueTracker {
        GitHubIssueTracker(source: source, currentOwner: context.owner, currentRepo: context.repo)
    }
}

struct RawIssue: Sendable {
    var title: String
    var body: String
    var url: String
}
