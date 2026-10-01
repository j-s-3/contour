import Foundation

struct WatchedPullRequest: Equatable, Identifiable, Sendable {
    var url: String
    var number: Int
    var title: String
    var author: String
    var isDraft: Bool
    var createdAt: Date?

    var id: String { url }
}

struct WatchedPullRequestList: Equatable, Sendable {
    var pullRequests: [WatchedPullRequest]
    var hasMore: Bool
    var fetchedAt: Date
}

struct WatchedPullRequests: Sendable {
    struct Candidate: Equatable, Sendable {
        var pullRequest: WatchedPullRequest
        var isBot: Bool
    }

    static let fetchLimit = 30
    static let listLimit = 10

    static func isBot(login: String, flagged: Bool) -> Bool {
        flagged || login.hasPrefix("app/") || login.hasSuffix("[bot]")
    }

    static func parseGH(_ data: Data) -> [Candidate]? {
        parse(data, url: "url", draft: "isDraft", createdAt: "createdAt", author: "author") { author in
            (author["is_bot"] as? Bool) ?? false
        }
    }

    static func parseREST(_ data: Data) -> [Candidate]? {
        parse(data, url: "html_url", draft: "draft", createdAt: "created_at", author: "user") { author in
            (author["type"] as? String) == "Bot"
        }
    }

    static func list(from candidates: [Candidate], fetchedAt: Date) -> WatchedPullRequestList {
        let people = candidates.filter { !$0.isBot }.map(\.pullRequest)
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        return WatchedPullRequestList(
            pullRequests: Array(people.prefix(listLimit)),
            hasMore: people.count > listLimit || candidates.count >= fetchLimit,
            fetchedAt: fetchedAt)
    }

    private static func parse(
        _ data: Data, url: String, draft: String, createdAt: String, author: String,
        flagged: ([String: Any]) -> Bool
    ) -> [Candidate]? {
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        let dates = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let link = row[url] as? String,
                let number = row["number"] as? Int,
                let title = row["title"] as? String
            else { return nil }
            let person = (row[author] as? [String: Any]) ?? [:]
            let login = (person["login"] as? String) ?? "unknown"
            return Candidate(
                pullRequest: WatchedPullRequest(
                    url: link, number: number, title: title, author: login,
                    isDraft: (row[draft] as? Bool) ?? false,
                    createdAt: (row[createdAt] as? String).flatMap(dates.date(from:))),
                isBot: isBot(login: login, flagged: flagged(person)))
        }
    }
}
