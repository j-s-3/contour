import Foundation

enum GitHubServiceError: LocalizedError {
    case badURL(String)
    case malformedResponse(String)
    case privateRepository(owner: String, repo: String)
    case rateLimited(resetAt: Date?)
    case ghUnavailable

    var errorDescription: String? {
        switch self {
        case .badURL(let u):
            return "Not a recognizable GitHub PR URL: \(u)"
        case .malformedResponse(let d):
            return "Unexpected response from GitHub: \(d.prefix(300))"
        case .privateRepository(let owner, let repo):
            return """
            \(owner)/\(repo) isn't readable anonymously, so it's private or doesn't exist. \
            Install the GitHub CLI and run `gh auth login` to review private pull requests.
            """
        case .rateLimited(let resetAt):
            let when = resetAt.map {
                " Try again after \(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short))."
            } ?? ""
            return """
            GitHub's anonymous rate limit (60 requests/hour) is exhausted.\(when) \
            Authenticating with `gh auth login` raises it to 5000/hour.
            """
        case .ghUnavailable:
            return "Settings require the GitHub CLI, but `gh` isn't installed or isn't authenticated."
        }
    }
}

protocol PRSource: Sendable {
    var describesItself: String { get }
    func fetchContext(prURL: String) async throws -> RawPRContext
    func fetchIssue(owner: String, repo: String, number: String) async -> RawIssue?
}

struct GitHubService: Sendable {
    let mode: GitHubAccessMode
    private let ghAvailable: Bool

    init(mode: GitHubAccessMode = .auto, ghAvailable: Bool? = nil) {
        self.mode = mode
        self.ghAvailable = ghAvailable ?? (Shell.which("gh") != nil)
    }

    func source() throws -> any PRSource {
        switch mode {
        case .gh:
            guard ghAvailable else { throw GitHubServiceError.ghUnavailable }
            return GHCLISource()
        case .anonymous:
            return AnonymousAPISource()
        case .auto:
            return ghAvailable ? GHCLISource() : AnonymousAPISource()
        }
    }

    func fetchContext(prURL: String) async throws -> RawPRContext {
        try await source().fetchContext(prURL: prURL)
    }

    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("github.com"), trimmed.contains("/pull/") else { return nil }
        return trimmed
    }

    static func ownerRepo(fromCanonicalURL url: String) throws -> (String, String) {
        guard let u = URL(string: url) else { throw GitHubServiceError.badURL(url) }
        let parts = u.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { throw GitHubServiceError.badURL(url) }
        return (parts[0], parts[1])
    }

    static func parse(prURL: String) throws -> (owner: String, repo: String, number: Int) {
        guard let u = URL(string: prURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw GitHubServiceError.badURL(prURL)
        }
        let parts = u.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4, parts[2] == "pull", let number = Int(parts[3]) else {
            throw GitHubServiceError.badURL(prURL)
        }
        return (parts[0], parts[1], number)
    }
}
