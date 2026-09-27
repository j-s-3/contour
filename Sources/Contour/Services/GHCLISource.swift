import Foundation

/// Reads PRs through an already-authenticated `gh`. No token handling and no GitHub SDK —
/// every credential and rate limit is inherited from the user's own `gh` (§8, §16). This
/// is the path that covers private repositories.
struct GHCLISource: PRSource {
    var describesItself: String { "gh CLI" }

    func fetchContext(prURL: String) async throws -> RawPRContext {
        guard let normalized = GitHubService.normalize(prURL) else {
            throw GitHubServiceError.badURL(prURL)
        }

        let fields = "url,number,title,body,author,state,headRefName,baseRefName,headRefOid," +
                     "baseRefOid,isCrossRepository,headRepository,headRepositoryOwner," +
                     "additions,deletions,changedFiles,files,commits,comments,reviews," +
                     "createdAt,statusCheckRollup"

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
        let (owner, repo) = try GitHubService.ownerRepo(fromCanonicalURL: url)
        let headRepo = obj["headRepository"] as? [String: Any]
        let headOwnerLogin = (obj["headRepositoryOwner"] as? [String: Any])?["login"] as? String ?? owner
        let headRepoName = (headRepo?["name"] as? String) ?? repo
        let headCloneURL = "https://github.com/\(headOwnerLogin)/\(headRepoName).git"

        async let unresolved = unresolvedThreadCount(prURL: url, owner: owner, repo: repo, number: number)
        let diff = try await Shell.run("gh", ["pr", "diff", normalized])

        let checks = ((obj["statusCheckRollup"] as? [[String: Any]]) ?? []).map {
            PRGlance.checkOutcome(status: $0["status"] as? String,
                                  conclusion: $0["conclusion"] as? String,
                                  state: $0["state"] as? String)
        }
        let tally = PRGlance.tallyReviews(((obj["reviews"] as? [[String: Any]]) ?? []).compactMap { r in
            guard let who = (r["author"] as? [String: Any])?["login"] as? String,
                  let state = r["state"] as? String else { return nil }
            return (who, state)
        })
        let glance = PRGlance(
            checks: PRGlance.rollUp(checks),
            approvals: tally.approvals,
            changesRequested: tally.changesRequested,
            unresolvedThreads: await unresolved,
            createdAt: PRGlance.date(iso8601: obj["createdAt"] as? String)
        )

        return RawPRContext(
            url: url, owner: owner, repo: repo, number: number, title: title, body: body,
            author: author, state: state, headRefName: headRefName, baseRefName: baseRefName,
            headSha: headSha, baseSha: baseSha, isCrossRepository: isCross, headCloneURL: headCloneURL,
            additions: additions, deletions: deletions, changedFiles: changedFiles, files: files,
            commits: commits, comments: comments, reviews: reviews, diff: diff, glance: glance
        )
    }

    /// Thread resolution isn't among `gh pr view`'s fields, so it takes one GraphQL query.
    /// Best effort: a failure costs the facts line one item, never the fetch. Counts the
    /// first 100 threads, which is every thread on all but the most contested PRs.
    private func unresolvedThreadCount(prURL: String, owner: String, repo: String, number: Int) async -> Int? {
        let query = """
        query($owner: String!, $repo: String!, $number: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $number) { reviewThreads(first: 100) { nodes { isResolved } } }
          }
        }
        """
        var args = ["api", "graphql", "-f", "query=\(query)",
                    "-F", "owner=\(owner)", "-F", "repo=\(repo)", "-F", "number=\(number)"]
        // `gh api` defaults to github.com; a GitHub Enterprise PR has to name its host.
        if let host = URL(string: prURL)?.host, host != "github.com" {
            args += ["--hostname", host]
        }
        guard let json = try? await Shell.run("gh", args),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pr = ((obj["data"] as? [String: Any])?["repository"] as? [String: Any])?["pullRequest"] as? [String: Any],
              let nodes = (pr["reviewThreads"] as? [String: Any])?["nodes"] as? [[String: Any]]
        else { return nil }
        return nodes.filter { ($0["isResolved"] as? Bool) == false }.count
    }

    func fetchIssue(owner: String, repo: String, number: String) async -> RawIssue? {
        guard let json = try? await Shell.run("gh", [
            "issue", "view", number, "--repo", "\(owner)/\(repo)", "--json", "title,body,url"
        ]) else { return nil }
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = obj["title"] as? String
        else { return nil }
        return RawIssue(
            title: title,
            body: (obj["body"] as? String) ?? "",
            url: (obj["url"] as? String) ?? "https://github.com/\(owner)/\(repo)/issues/\(number)"
        )
    }
}
