import Foundation
import os

private let stackLogger = Logger(subsystem: "Contour", category: "StackDiscovery")

struct StackDiscovery: Sendable {
    enum Filter: Equatable, Sendable {
        case head(String)
        case base(String)
    }

    var ghAvailable: @Sendable () -> Bool = { Shell.which("gh") != nil }
    var runGH: @Sendable ([String]) async throws -> String = { try await Shell.run("gh", $0) }
    var anonymous = AnonymousAPISource()

    static let ghFields =
        "number,url,title,author,isDraft,headRefName,baseRefName,headRefOid,baseRefOid,"
        + "additions,deletions,changedFiles,isCrossRepository"
    static let pageSize = 10

    func discover(ctx: RawPRContext, access: GitHubAccessMode) async -> PRStack? {
        guard let transport = WatchedPullRequests.transport(access: access, ghAvailable: ghAvailable()) else {
            return nil
        }
        do {
            return try await Self.walk(
                current: Self.layer(from: ctx),
                parent: { base in try await self.list(.head(base), ctx: ctx, transport: transport).first },
                children: { head in try await self.list(.base(head), ctx: ctx, transport: transport) })
        } catch {
            stackLogger.error(
                "Stack discovery for \(ctx.owner, privacy: .public)/\(ctx.repo, privacy: .public) #\(ctx.number) failed: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    private func list(
        _ filter: Filter, ctx: RawPRContext, transport: WatchedPullRequests.Transport
    ) async throws -> [StackLayer] {
        let repository = "\(ctx.owner)/\(ctx.repo)"
        let layers: [StackLayer]?
        switch transport {
        case .gh:
            layers = Self.parseGH(Data(try await runGH(Self.arguments(repository: repository, filter: filter)).utf8))
        case .rest:
            layers = Self.parseREST(
                try await anonymous.pullRequests(
                    owner: ctx.owner, repo: ctx.repo, query: Self.restQuery(owner: ctx.owner, filter: filter)),
                repository: repository)
        }
        guard let layers else { throw GitHubServiceError.malformedResponse("pull request list") }
        return layers
    }

    static func walk(
        current: StackLayer,
        parent: (String) async throws -> StackLayer?,
        children: (String) async throws -> [StackLayer]
    ) async throws -> PRStack? {
        var seen: Set<String> = [current.headRefName]
        var below: [StackLayer] = []
        var cursor = current
        while below.count + 1 < PRStack.maximumLayers, PRStack.isValidBranchName(cursor.baseRefName),
            !seen.contains(cursor.baseRefName), let next = try await parent(cursor.baseRefName)
        {
            seen.insert(next.headRefName)
            below.insert(next, at: 0)
            cursor = next
        }
        var above: [StackLayer] = []
        cursor = current
        while below.count + 1 + above.count < PRStack.maximumLayers, PRStack.isValidBranchName(cursor.headRefName) {
            let candidates = try await children(cursor.headRefName)
            guard candidates.count == 1, let next = candidates.first, !seen.contains(next.headRefName) else { break }
            seen.insert(next.headRefName)
            above.append(next)
            cursor = next
        }
        guard !below.isEmpty || !above.isEmpty else { return nil }
        return PRStack(layers: below + [current] + above, currentIndex: below.count)
    }

    static func layer(from ctx: RawPRContext) -> StackLayer {
        StackLayer(
            url: ctx.url, number: ctx.number, title: ctx.title, author: ctx.author, isDraft: false,
            headRefName: ctx.headRefName, baseRefName: ctx.baseRefName, headSha: ctx.headSha,
            baseSha: ctx.baseSha,
            size: StackLayer.Size(additions: ctx.additions, deletions: ctx.deletions, changedFiles: ctx.changedFiles))
    }

    static func arguments(repository: String, filter: Filter) -> [String] {
        var arguments = ["pr", "list", "-R", repository, "--state", "open", "--limit", String(pageSize)]
        switch filter {
        case .head(let branch): arguments += ["--head", branch]
        case .base(let branch): arguments += ["--base", branch]
        }
        return arguments + ["--json", ghFields]
    }

    static func restQuery(owner: String, filter: Filter) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._/~"))
        func encoded(_ branch: String) -> String {
            branch.addingPercentEncoding(withAllowedCharacters: allowed) ?? branch
        }
        switch filter {
        case .head(let branch): return "state=open&per_page=\(pageSize)&head=\(owner):\(encoded(branch))"
        case .base(let branch): return "state=open&per_page=\(pageSize)&base=\(encoded(branch))"
        }
    }

    static func parseGH(_ data: Data) -> [StackLayer]? {
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard (row["isCrossRepository"] as? Bool) != true,
                let url = row["url"] as? String, let number = row["number"] as? Int,
                let title = row["title"] as? String,
                let head = row["headRefName"] as? String, let base = row["baseRefName"] as? String,
                let headSha = row["headRefOid"] as? String, let baseSha = row["baseRefOid"] as? String
            else { return nil }
            return StackLayer(
                url: url, number: number, title: title,
                author: ((row["author"] as? [String: Any])?["login"] as? String) ?? "unknown",
                isDraft: (row["isDraft"] as? Bool) ?? false,
                headRefName: head, baseRefName: base, headSha: headSha, baseSha: baseSha,
                size: size(additions: row["additions"], deletions: row["deletions"], files: row["changedFiles"]))
        }
    }

    static func parseREST(_ data: Data, repository: String) -> [StackLayer]? {
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard let url = row["html_url"] as? String, let number = row["number"] as? Int,
                let title = row["title"] as? String,
                let head = row["head"] as? [String: Any], let base = row["base"] as? [String: Any],
                let headRef = head["ref"] as? String, let baseRef = base["ref"] as? String,
                let headSha = head["sha"] as? String, let baseSha = base["sha"] as? String,
                ((head["repo"] as? [String: Any])?["full_name"] as? String) == repository
            else { return nil }
            return StackLayer(
                url: url, number: number, title: title,
                author: ((row["user"] as? [String: Any])?["login"] as? String) ?? "unknown",
                isDraft: (row["draft"] as? Bool) ?? false,
                headRefName: headRef, baseRefName: baseRef, headSha: headSha, baseSha: baseSha,
                size: size(additions: row["additions"], deletions: row["deletions"], files: row["changed_files"]))
        }
    }

    private static func size(additions: Any?, deletions: Any?, files: Any?) -> StackLayer.Size? {
        guard let additions = additions as? Int, let deletions = deletions as? Int, let files = files as? Int else {
            return nil
        }
        return StackLayer.Size(additions: additions, deletions: deletions, changedFiles: files)
    }
}
