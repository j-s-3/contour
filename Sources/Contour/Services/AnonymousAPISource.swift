import Foundation

struct AnonymousAPISource: PRSource {
    var describesItself: String { "GitHub REST API (anonymous)" }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private static let api = URL(string: "https://api.github.com")!

    func fetchContext(prURL: String) async throws -> RawPRContext {
        guard GitHubService.normalize(prURL) != nil else {
            throw GitHubServiceError.badURL(prURL)
        }
        let (owner, repo, number) = try GitHubService.parse(prURL: prURL)
        let base = "/repos/\(owner)/\(repo)/pulls/\(number)"

        let pr = try await getJSONObject(base, owner: owner, repo: repo)
        let diff = try await getRaw(base, accept: "application/vnd.github.v3.diff", owner: owner, repo: repo)

        guard
            let title = pr["title"] as? String,
            let state = pr["state"] as? String,
            let head = pr["head"] as? [String: Any],
            let baseRef = pr["base"] as? [String: Any],
            let headSha = head["sha"] as? String,
            let baseSha = baseRef["sha"] as? String,
            let headRefName = head["ref"] as? String,
            let baseRefName = baseRef["ref"] as? String
        else { throw GitHubServiceError.malformedResponse("\(pr)") }

        let author = ((pr["user"] as? [String: Any])?["login"] as? String) ?? "unknown"
        let body = (pr["body"] as? String) ?? ""

        let isMerged = (pr["merged"] as? Bool) ?? (pr["merged_at"] is String)
        let normalizedState = isMerged ? "MERGED" : state.uppercased()

        let headRepoObj = head["repo"] as? [String: Any]
        let headOwner = ((headRepoObj?["owner"] as? [String: Any])?["login"] as? String) ?? owner
        let headRepoName = (headRepoObj?["name"] as? String) ?? repo
        let isCross = headOwner != owner || headRepoName != repo

        let files = try await getJSONArray("\(base)/files", owner: owner, repo: repo, paginated: true)
            .compactMap { $0["filename"] as? String }

        let commits: [CommitInfo] = try await getJSONArray("\(base)/commits", owner: owner, repo: repo, paginated: true)
            .compactMap { c in
                guard let sha = c["sha"] as? String else { return nil }
                let message = ((c["commit"] as? [String: Any])?["message"] as? String) ?? ""
                let login = (c["author"] as? [String: Any])?["login"] as? String
                let commitAuthor = ((c["commit"] as? [String: Any])?["author"] as? [String: Any])?["name"] as? String
                return CommitInfo(sha: sha, message: message, author: login ?? commitAuthor ?? "unknown")
            }

        let comments: [String] = try await getJSONArray(
            "/repos/\(owner)/\(repo)/issues/\(number)/comments", owner: owner, repo: repo, paginated: true
        ).compactMap { c in
            guard let b = c["body"] as? String, !b.isEmpty else { return nil }
            let who = (c["user"] as? [String: Any])?["login"] as? String ?? "someone"
            return "\(who): \(b)"
        }

        let rawReviews = try await getJSONArray("\(base)/reviews", owner: owner, repo: repo, paginated: true)
        let reviews: [String] =
            rawReviews
            .compactMap { r in
                guard let b = r["body"] as? String, !b.isEmpty else { return nil }
                let who = (r["user"] as? [String: Any])?["login"] as? String ?? "someone"
                return "\(who): \(b)"
            }

        let tally = PRGlance.tallyReviews(
            rawReviews.compactMap { r in
                guard let who = (r["user"] as? [String: Any])?["login"] as? String,
                    let state = r["state"] as? String
                else { return nil }
                return (who, state)
            })
        let glance = PRGlance(
            checks: await checks(owner: owner, repo: repo, sha: headSha),
            approvals: tally.approvals,
            changesRequested: tally.changesRequested,
            unresolvedThreads: nil,
            createdAt: PRGlance.date(iso8601: pr["created_at"] as? String)
        )

        return RawPRContext(
            url: (pr["html_url"] as? String) ?? prURL,
            owner: owner, repo: repo, number: number, title: title, body: body,
            author: author, state: normalizedState,
            headRefName: headRefName, baseRefName: baseRefName,
            headSha: headSha, baseSha: baseSha, isCrossRepository: isCross,
            headCloneURL: "https://github.com/\(headOwner)/\(headRepoName).git",
            additions: (pr["additions"] as? Int) ?? 0,
            deletions: (pr["deletions"] as? Int) ?? 0,
            changedFiles: (pr["changed_files"] as? Int) ?? 0,
            files: files, commits: commits, comments: comments, reviews: reviews, diff: diff,
            glance: glance
        )
    }

    private func checks(owner: String, repo: String, sha: String) async -> PRGlance.Checks? {
        let commit = "/repos/\(owner)/\(repo)/commits/\(sha)"
        let runs =
            (try? await getJSONObject("\(commit)/check-runs?per_page=100", owner: owner, repo: repo))?["check_runs"]
            as? [[String: Any]] ?? []
        let statuses =
            (try? await getJSONObject("\(commit)/status", owner: owner, repo: repo))?["statuses"]
            as? [[String: Any]] ?? []
        let outcomes =
            runs.map {
                PRGlance.checkOutcome(
                    status: $0["status"] as? String, conclusion: $0["conclusion"] as? String, state: nil)
            }
            + statuses.map {
                PRGlance.checkOutcome(status: nil, conclusion: nil, state: $0["state"] as? String)
            }
        return PRGlance.rollUp(outcomes)
    }

    func fetchIssue(owner: String, repo: String, number: String) async -> RawIssue? {
        guard
            let obj = try? await getJSONObject(
                "/repos/\(owner)/\(repo)/issues/\(number)",
                owner: owner, repo: repo),
            let title = obj["title"] as? String
        else { return nil }
        return RawIssue(
            title: title,
            body: (obj["body"] as? String) ?? "",
            url: (obj["html_url"] as? String) ?? "https://github.com/\(owner)/\(repo)/issues/\(number)"
        )
    }

    func openPullRequests(owner: String, repo: String, limit: Int) async throws -> Data {
        let path = "/repos/\(owner)/\(repo)/pulls?state=open&sort=created&direction=desc&per_page=\(limit)"
        let (data, _) = try await send(
            request(path, accept: "application/vnd.github+json"), owner: owner, repo: repo)
        return data
    }

    func pullRequests(owner: String, repo: String, query: String) async throws -> Data {
        let (data, _) = try await send(
            request("/repos/\(owner)/\(repo)/pulls?\(query)", accept: "application/vnd.github+json"),
            owner: owner, repo: repo)
        return data
    }

    private func request(_ path: String, accept: String) -> URLRequest {
        var req = URLRequest(url: URL(string: path, relativeTo: Self.api)!)
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Contour", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func send(_ req: URLRequest, owner: String, repo: String) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubServiceError.malformedResponse("non-HTTP response")
        }
        switch http.statusCode {
        case 200...299:
            return (data, http)
        case 403, 429:
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset")
                    .flatMap(Double.init)
                    .map { Date(timeIntervalSince1970: $0) }
                throw GitHubServiceError.rateLimited(resetAt: reset)
            }
            throw GitHubServiceError.privateRepository(owner: owner, repo: repo)
        case 404:
            throw GitHubServiceError.privateRepository(owner: owner, repo: repo)
        default:
            throw GitHubServiceError.malformedResponse(
                "HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")"
            )
        }
    }

    private func getJSONObject(_ path: String, owner: String, repo: String) async throws -> [String: Any] {
        let (data, _) = try await send(request(path, accept: "application/vnd.github+json"), owner: owner, repo: repo)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubServiceError.malformedResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return obj
    }

    private func getRaw(_ path: String, accept: String, owner: String, repo: String) async throws -> String {
        let (data, _) = try await send(request(path, accept: accept), owner: owner, repo: repo)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func getJSONArray(
        _ path: String, owner: String, repo: String,
        paginated: Bool = false
    ) async throws -> [[String: Any]] {
        let perPage = 100
        let maxPages = paginated ? 5 : 1
        var all: [[String: Any]] = []
        for page in 1...maxPages {
            let sep = path.contains("?") ? "&" : "?"
            let paged = "\(path)\(sep)per_page=\(perPage)&page=\(page)"
            let (data, _) = try await send(
                request(paged, accept: "application/vnd.github+json"),
                owner: owner, repo: repo)
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw GitHubServiceError.malformedResponse(String(data: data, encoding: .utf8) ?? "")
            }
            all += arr
            if arr.count < perPage { break }
        }
        return all
    }
}
