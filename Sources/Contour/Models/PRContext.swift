import Foundation

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
    var headCloneURL: String
    var additions: Int
    var deletions: Int
    var changedFiles: Int
    var files: [String]
    var commits: [CommitInfo]
    var comments: [String]
    var reviews: [String]
    var diff: String
    var glance = PRGlance()
}

struct CommitInfo: Sendable {
    var sha: String
    var message: String
    var author: String
}
