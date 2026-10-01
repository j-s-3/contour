import Foundation
import os

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

enum WatchedFailure: Error, Equatable, Sendable {
    case notFound
    case rateLimited(resetAt: Date?)
    case unavailable
}

private let watchedLogger = Logger(subsystem: "Contour", category: "WatchedPullRequests")

struct WatchedPullRequests: Sendable {
    struct Candidate: Equatable, Sendable {
        var pullRequest: WatchedPullRequest
        var isBot: Bool
    }

    enum Transport: Equatable, Sendable {
        case gh
        case rest
    }

    var ghAvailable: @Sendable () -> Bool = { Shell.which("gh") != nil }
    var runGH: @Sendable ([String]) async throws -> String = { try await Shell.run("gh", $0) }
    var anonymous = AnonymousAPISource()
    var now: @Sendable () -> Date = { Date() }

    func fetch(
        _ repository: WatchedRepository, access: GitHubAccessMode
    ) async -> Result<WatchedPullRequestList, WatchedFailure> {
        guard let transport = Self.transport(access: access, ghAvailable: ghAvailable()) else {
            return .failure(.unavailable)
        }
        do {
            let candidates: [Candidate]?
            switch transport {
            case .gh:
                candidates = Self.parseGH(Data(try await runGH(Self.arguments(for: repository)).utf8))
            case .rest:
                candidates = Self.parseREST(
                    try await anonymous.openPullRequests(
                        owner: repository.owner, repo: repository.name, limit: Self.fetchLimit))
            }
            guard let candidates else {
                watchedLogger.error("Unreadable pull request list for \(repository.id, privacy: .public)")
                return .failure(.unavailable)
            }
            return .success(Self.list(from: candidates, fetchedAt: now()))
        } catch {
            watchedLogger.error(
                "Listing \(repository.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return .failure(Self.failure(from: error))
        }
    }

    func viewerLogin(access: GitHubAccessMode) async -> String? {
        guard Self.transport(access: access, ghAvailable: ghAvailable()) == .gh,
            let output = try? await runGH(["api", "user", "--jq", ".login"])
        else { return nil }
        let login = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty ? nil : login
    }

    static func transport(access: GitHubAccessMode, ghAvailable: Bool) -> Transport? {
        switch access {
        case .anonymous: return .rest
        case .gh: return ghAvailable ? .gh : nil
        case .auto: return ghAvailable ? .gh : .rest
        }
    }

    static func arguments(for repository: WatchedRepository) -> [String] {
        [
            "pr", "list", "-R", repository.id, "--state", "open", "--limit", String(fetchLimit),
            "--json", "number,title,url,author,isDraft,createdAt",
        ]
    }

    static func failure(from error: any Error) -> WatchedFailure {
        switch error {
        case let process as ProcessError:
            if process.stderr.contains("Could not resolve to a Repository") { return .notFound }
            if process.stderr.localizedCaseInsensitiveContains("rate limit") { return .rateLimited(resetAt: nil) }
            return .unavailable
        case GitHubServiceError.privateRepository:
            return .notFound
        case GitHubServiceError.rateLimited(let resetAt):
            return .rateLimited(resetAt: resetAt)
        default:
            return .unavailable
        }
    }

    static func message(for failure: WatchedFailure, repository: String, anonymous: Bool) -> String {
        let lead = "Couldn't list pull requests for \(repository)."
        switch failure {
        case .notFound:
            let signIn = anonymous ? " Sign in with the GitHub CLI to watch private repositories." : ""
            return "\(lead) It's private or doesn't exist.\(signIn)"
        case .rateLimited(let resetAt):
            let limit = anonymous ? "GitHub's anonymous limit is used up." : "GitHub's rate limit is used up."
            let when =
                resetAt.map {
                    " Try again after \(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short))."
                } ?? ""
            return "\(lead) \(limit)\(when)"
        case .unavailable:
            return lead
        }
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
