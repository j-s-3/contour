import Foundation

/// Raw material pulled from GitHub for one PR, before any analysis. Corresponds to
/// design doc §9 "Repository-context acquisition", tier 1.
struct RawPRContext: Sendable {
    var url: String
    var owner: String
    var repo: String
    var number: Int
    var title: String
    var body: String
    var author: String
    var state: String
    var headRefName: String
    var baseRefName: String
    var headSha: String
    var baseSha: String
    var isCrossRepository: Bool
    var headCloneURL: String       // where to fetch the head ref from (fork-aware)
    var additions: Int
    var deletions: Int
    var changedFiles: Int
    var files: [String]            // changed file paths
    var commits: [CommitInfo]
    var comments: [String]         // issue-thread comments, author + body flattened
    var reviews: [String]          // review bodies, for author-stated rationale extraction
    var diff: String
}

struct CommitInfo: Sendable {
    var sha: String
    var message: String
    var author: String
}
