import Foundation

/// Finds the GitHub issue a PR closes, and fetches it through whichever `PRSource` is
/// already in use — so it inherits the same auth story as the PR fetch itself and needs
/// nothing extra installed.
struct GitHubIssueTracker: IssueTracker {
    let id: TrackerID = .github
    let source: any PRSource

    /// `fixes owner/repo#123`, `closes #45`, `resolves GH-7`. GitHub's own closing
    /// keywords, which is what actually links a PR to an issue.
    ///
    /// Case-insensitive, and the repo qualifier is optional so same-repo references work.
    private static let closingPattern = try! NSRegularExpression(
        pattern: #"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\b\s*:?\s+(?:([\w.-]+)/([\w.-]+))?(?:#|GH-)(\d+)"#,
        options: [.caseInsensitive]
    )

    /// A bare `#123` or `owner/repo#123` with no keyword. Weaker evidence, so it is only
    /// consulted after every closing-keyword match has been tried.
    private static let barePattern = try! NSRegularExpression(
        pattern: #"(?:^|[\s(\[])(?:([\w.-]+)/([\w.-]+))?#(\d+)\b"#
    )

    /// A ticket id embedded in a branch name, e.g. `feature/123-add-retry` or
    /// `jstephens/gh-482/fix`. Branch names can't contain `#`, so they need their own shape.
    private static let branchPattern = try! NSRegularExpression(
        pattern: #"(?:^|[/_-])(?:gh-|issue-|#)?(\d{1,6})(?:[/_-]|$)"#,
        options: [.caseInsensitive]
    )

    func reference(in context: RawPRContext) -> IssueRef? {
        // Closing keywords first, wherever they appear: they state intent explicitly.
        // The PR body is checked before the title because that's where GitHub's own UI
        // puts the "Closes #N" line.
        let prose = [context.body, context.title] + context.commits.map(\.message)
        for text in prose {
            if let ref = Self.match(Self.closingPattern, in: text, context: context) { return ref }
        }
        // Then bare references in the same places.
        for text in prose {
            if let ref = Self.match(Self.barePattern, in: text, context: context) { return ref }
        }
        // Branch name last: a number in a branch is the weakest signal of the three, and
        // only the head branch is considered (the base branch is almost never the issue).
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
        // The number is always the last capture group in all three patterns.
        guard let number = group(m.numberOfRanges - 1), !number.isEmpty else { return nil }

        let owner = group(1)
        let repo = group(2)
        // Only record owner/repo when it differs from the PR's own repo, so the common
        // same-repo case produces a clean "#123".
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
            // Already markdown — no rich-text flattening needed, unlike Jira's ADF.
            description: issue.body,
            url: issue.url
        )
    }

    /// Set by the pipeline before `fetch`, so a same-repo `#123` knows which repo it means.
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

/// The subset of an issue Contour needs.
struct RawIssue: Sendable {
    var title: String
    var body: String
    var url: String
}
