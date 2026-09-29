import Foundation

enum PRLink {
    private static let pattern = try! NSRegularExpression(
        pattern:
            #"(?<![\w.-])(?:https?://)?(?:www\.)?github\.com/([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)/([A-Za-z0-9._-]+)/pull/([0-9]+)(?![0-9])"#,
        options: [.caseInsensitive]
    )

    static func extract(from text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
            let owner = Range(match.range(at: 1), in: text).map({ text[$0] }),
            let repo = Range(match.range(at: 2), in: text).map({ text[$0] }),
            let number = Range(match.range(at: 3), in: text).flatMap({ Int(text[$0]) })
        else {
            return nil
        }
        return "https://github.com/\(owner)/\(repo)/pull/\(number)"
    }

    static func pullRequestURL(from url: URL) -> String? {
        if url.scheme?.lowercased() == "contour",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            if let target = components.queryItems?.first(where: { $0.name == "url" })?.value {
                return extract(from: target)
            }
            if let host = components.host, host.lowercased() != "github.com" {
                return extract(from: "github.com/\(host)\(components.path)")
            }
        }
        return extract(from: url.absoluteString.removingPercentEncoding ?? url.absoluteString)
    }

    static func label(for prURL: String) -> String? {
        guard let parts = try? GitHubService.parse(prURL: prURL) else { return nil }
        return "\(parts.owner)/\(parts.repo) #\(parts.number)"
    }
}
