import Foundation

/// Finds a GitHub pull request link wherever one arrives from — the clipboard, a drag from
/// Slack or a browser, a `contour://` link — and reduces it to the canonical
/// `https://github.com/{owner}/{repo}/pull/{number}` the rest of the app opens.
///
/// A link rarely arrives bare: Slack wraps it in a sentence, a browser tab is usually on
/// `/files` or a `#discussion_r…` anchor. So this searches rather than validates, and
/// drops everything after the number.
enum PRLink {
    /// `owner`, `repo` and `number` as GitHub allows them. The look-behind keeps
    /// `notgithub.com/…` from matching; the scheme is optional so `github.com/…` pasted
    /// without one still counts.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<![\w.-])(?:https?://)?(?:www\.)?github\.com/([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)/([A-Za-z0-9._-]+)/pull/([0-9]+)(?![0-9])"#,
        options: [.caseInsensitive]
    )

    /// The first pull request link in `text`, canonicalized, or nil if there isn't one.
    static func extract(from text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              let owner = Range(match.range(at: 1), in: text).map({ text[$0] }),
              let repo = Range(match.range(at: 2), in: text).map({ text[$0] }),
              let number = Range(match.range(at: 3), in: text).flatMap({ Int(text[$0]) }) else {
            return nil
        }
        return "https://github.com/\(owner)/\(repo)/pull/\(number)"
    }

    /// The pull request an incoming URL points at. Accepts a plain GitHub PR URL and the
    /// `contour://` forms:
    /// - `contour://open?url=https%3A%2F%2Fgithub.com%2F…%2Fpull%2F3877`
    /// - `contour://github.com/sharkdp/bat/pull/3877`
    /// - `contour://sharkdp/bat/pull/3877`
    static func pullRequestURL(from url: URL) -> String? {
        if url.scheme?.lowercased() == "contour",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let target = components.queryItems?.first(where: { $0.name == "url" })?.value {
                return extract(from: target)
            }
            // Host-relative form: the host is the owner rather than github.com.
            if let host = components.host, host.lowercased() != "github.com" {
                return extract(from: "github.com/\(host)\(components.path)")
            }
        }
        return extract(from: url.absoluteString.removingPercentEncoding ?? url.absoluteString)
    }

    /// How a PR is named to the reviewer: `sharkdp/bat #3877`.
    static func label(for prURL: String) -> String? {
        guard let parts = try? GitHubService.parse(prURL: prURL) else { return nil }
        return "\(parts.owner)/\(parts.repo) #\(parts.number)"
    }
}
