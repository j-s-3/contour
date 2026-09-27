import Foundation

/// A PR someone has asked the user to review, for the start screen.
struct ReviewRequest: Equatable, Identifiable, Sendable {
    var url: String
    /// "owner/repo".
    var repo: String
    var number: Int
    var title: String
    var author: String
    var isDraft: Bool
    var updatedAt: Date?

    var id: String { "\(repo)#\(number)" }
}

/// The open PRs awaiting the user's review, from `gh search prs --review-requested=@me`,
/// so the start screen can be where a review session begins rather than a URL field the
/// reviewer has to go elsewhere to fill.
///
/// Best-effort like every tracker lookup: `gh` missing, not authenticated, offline or rate
/// limited all come back as an empty list, and the start screen simply doesn't show the
/// section. Nothing here needs `gh` to open a PR; it only helps find one.
enum ReviewRequests {

    static let limit = 20

    /// Nil when there is no way to ask (no `gh`, or the user pinned anonymous access);
    /// otherwise whatever GitHub returned, possibly empty.
    static func fetch(access: GitHubAccessMode) async -> [ReviewRequest]? {
        guard access != .anonymous, Shell.which("gh") != nil else { return nil }
        let fields = "number,title,url,repository,author,isDraft,updatedAt"
        guard let json = try? await Shell.run("gh", [
            "search", "prs", "--review-requested=@me", "--state=open",
            "--sort=updated", "--limit", String(limit), "--json", fields,
        ]) else { return nil }
        return parse(json)
    }

    /// Decodes `gh search prs --json` output, newest update first. Rows missing the fields
    /// needed to open them are dropped rather than failing the whole list.
    static func parse(_ json: String) -> [ReviewRequest] {
        guard let data = json.data(using: .utf8),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }
        let dates = ISO8601DateFormatter()
        let requests: [ReviewRequest] = rows.compactMap { row in
            guard let url = row["url"] as? String,
                  let number = row["number"] as? Int,
                  let title = row["title"] as? String,
                  let repo = (row["repository"] as? [String: Any])?["nameWithOwner"] as? String
            else { return nil }
            return ReviewRequest(
                url: url, repo: repo, number: number, title: title,
                author: ((row["author"] as? [String: Any])?["login"] as? String) ?? "unknown",
                isDraft: (row["isDraft"] as? Bool) ?? false,
                updatedAt: (row["updatedAt"] as? String).flatMap(dates.date(from:))
            )
        }
        return requests.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }
}
