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

enum GitHubServiceError: LocalizedError {
    case badURL(String)
    case malformedResponse(String)
    var errorDescription: String? {
        switch self {
        case .badURL(let u): return "Not a recognizable GitHub PR URL: \(u)"
        case .malformedResponse(let d): return "Unexpected response from gh: \(d)"
        }
    }
}

/// Wraps the `gh` CLI. No token handling, no GitHub SDK — every credential and rate limit
/// is inherited from the user's already-authenticated `gh` (§8, §16).
struct GitHubService {

    /// Fetches everything needed to build the PR knowledge graph, in one pass.
    func fetchContext(prURL: String) async throws -> RawPRContext {
        guard let normalized = Self.normalize(prURL) else {
            throw GitHubServiceError.badURL(prURL)
        }

        let fields = "url,number,title,body,author,state,headRefName,baseRefName,headRefOid," +
                     "baseRefOid,isCrossRepository,headRepository,headRepositoryOwner," +
                     "additions,deletions,changedFiles,files,commits,comments,reviews"

        let json = try await Shell.run("gh", ["pr", "view", normalized, "--json", fields])
        guard let data = json.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw GitHubServiceError.malformedResponse(json) }

        guard
            let url = obj["url"] as? String,
            let number = obj["number"] as? Int,
            let title = obj["title"] as? String,
            let author = (obj["author"] as? [String: Any])?["login"] as? String,
            let state = obj["state"] as? String,
            let headRefName = obj["headRefName"] as? String,
            let baseRefName = obj["baseRefName"] as? String,
            let headSha = obj["headRefOid"] as? String,
            let baseSha = obj["baseRefOid"] as? String
        else { throw GitHubServiceError.malformedResponse(json) }

        let body = (obj["body"] as? String) ?? ""
        let isCross = (obj["isCrossRepository"] as? Bool) ?? false
        let additions = (obj["additions"] as? Int) ?? 0
        let deletions = (obj["deletions"] as? Int) ?? 0
        let changedFiles = (obj["changedFiles"] as? Int) ?? 0

        let files = ((obj["files"] as? [[String: Any]]) ?? []).compactMap { $0["path"] as? String }

        let commits: [CommitInfo] = ((obj["commits"] as? [[String: Any]]) ?? []).compactMap { c in
            guard let oid = c["oid"] as? String else { return nil }
            let messageHeadline = (c["messageHeadline"] as? String) ?? ""
            let messageBody = (c["messageBody"] as? String) ?? ""
            let authors = (c["authors"] as? [[String: Any]])?.compactMap { $0["login"] as? String } ?? []
            let msg = messageBody.isEmpty ? messageHeadline : "\(messageHeadline)\n\(messageBody)"
            return CommitInfo(sha: oid, message: msg, author: authors.first ?? "unknown")
        }

        let comments: [String] = ((obj["comments"] as? [[String: Any]]) ?? []).compactMap { c in
            guard let b = c["body"] as? String, !b.isEmpty else { return nil }
            let who = (c["author"] as? [String: Any])?["login"] as? String ?? "someone"
            return "\(who): \(b)"
        }
        let reviews: [String] = ((obj["reviews"] as? [[String: Any]]) ?? []).compactMap { r in
            guard let b = r["body"] as? String, !b.isEmpty else { return nil }
            let who = (r["author"] as? [String: Any])?["login"] as? String ?? "someone"
            return "\(who): \(b)"
        }

        // Extract owner/repo from the canonical url so we can drive the checkout even for forks.
        let (owner, repo) = try Self.ownerRepo(fromCanonicalURL: url)
        let headRepo = obj["headRepository"] as? [String: Any]
        let headOwnerLogin = (obj["headRepositoryOwner"] as? [String: Any])?["login"] as? String ?? owner
        let headRepoName = (headRepo?["name"] as? String) ?? repo
        let headCloneURL = "https://github.com/\(headOwnerLogin)/\(headRepoName).git"

        let diff = try await Shell.run("gh", ["pr", "diff", normalized])

        return RawPRContext(
            url: url, owner: owner, repo: repo, number: number, title: title, body: body,
            author: author, state: state, headRefName: headRefName, baseRefName: baseRefName,
            headSha: headSha, baseSha: baseSha, isCrossRepository: isCross, headCloneURL: headCloneURL,
            additions: additions, deletions: deletions, changedFiles: changedFiles, files: files,
            commits: commits, comments: comments, reviews: reviews, diff: diff
        )
    }

    /// Accepts a full PR URL, `owner/repo#123`, or bare `123` won't resolve without -R; we
    /// require the full URL per the product's core workflow ("paste a GitHub PR URL").
    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("github.com"), trimmed.contains("/pull/") else { return nil }
        return trimmed
    }

    static func ownerRepo(fromCanonicalURL url: String) throws -> (String, String) {
        // https://github.com/{owner}/{repo}/pull/{number}
        guard let u = URL(string: url) else { throw GitHubServiceError.badURL(url) }
        let parts = u.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { throw GitHubServiceError.badURL(url) }
        return (parts[0], parts[1])
    }

    /// Post reviewer-marked decisions back to GitHub as a real PR review. Deferred past MVP
    /// (§17/§18) but the shape is settled now: one line-anchored comment per marked decision,
    /// built from its primary CodeRef.
    func submitReview(prURL: String, body: String, comments: [(path: String, line: Int, body: String)]) async throws {
        // gh pr review <url> --comment/--approve/--request-changes --body "..."
        // Line-anchored comments require the REST review API (`gh api .../pulls/{n}/reviews`)
        // since `gh pr review` only supports a top-level body. Left unimplemented until §18.
        fatalError("submitReview: post-MVP, see design doc §18")
    }
}
