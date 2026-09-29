import Foundation

struct JiraTracker: IssueTracker {
    let id: TrackerID = .jira

    func reference(in context: RawPRContext) -> IssueRef? {
        Self.ticketKey(in: context).map { IssueRef(id: $0, tracker: .jira) }
    }

    func fetch(_ ref: IssueRef) async -> TicketInfo? {
        await fetchTicket(key: ref.id)
    }

    private static let ticketKeyPattern = try! NSRegularExpression(pattern: #"\b([A-Z][A-Z0-9]{1,9}-[0-9]+)\b"#)

    static func ticketKey(in context: RawPRContext) -> String? {
        let candidates = [context.title, context.body, context.headRefName, context.baseRefName]
            + context.commits.map(\.message)
        for text in candidates {
            if let key = firstMatch(in: text) { return key }
        }
        return nil
    }

    private static func firstMatch(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = ticketKeyPattern.firstMatch(in: text, range: range),
              let matchRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[matchRange])
    }

    func fetchTicket(key: String) async -> TicketInfo? {
        guard let output = try? await Shell.run("acli", ["jira", "workitem", "view", key, "--json"]) else {
            return nil
        }
        guard let fields = Self.parseWorkItemJSON(output) else { return nil }

        let siteHost = await Self.authenticatedSiteHost()
        let url = Self.browseURL(forKey: key, siteHost: siteHost, selfLink: fields.selfLink)

        return TicketInfo(kind: .jira, key: key, summary: fields.summary, description: fields.description, url: url)
    }

    struct ParsedWorkItem: Equatable {
        var summary: String
        var description: String
        var selfLink: String?
    }

    static func parseWorkItemJSON(_ jsonString: String) -> ParsedWorkItem? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = obj["fields"] as? [String: Any],
              let summary = fields["summary"] as? String
        else { return nil }

        let description = (fields["description"] as? [String: Any]).map(Self.flattenADF) ?? ""
        return ParsedWorkItem(summary: summary, description: description, selfLink: obj["self"] as? String)
    }

    static func browseURL(forKey key: String, siteHost: String?, selfLink: String?) -> String {
        if let siteHost {
            return "https://\(siteHost)/browse/\(key)"
        }
        if let selfLink, let url = URL(string: selfLink), let host = url.host {
            return "https://\(host)/browse/\(key)"
        }
        return "https://atlassian.net/browse/\(key)"
    }

    private static func authenticatedSiteHost() async -> String? {
        guard let output = try? await Shell.run("acli", ["jira", "auth", "status"]) else { return nil }
        return Self.parseSiteHost(fromAuthStatusOutput: output)
    }

    static func parseSiteHost(fromAuthStatusOutput output: String) -> String? {
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Site:") {
                return trimmed.replacingOccurrences(of: "Site:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func flattenADF(_ node: [String: Any]) -> String {
        var lines: [String] = []
        walk(node, into: &lines, listPrefix: nil)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func walk(_ node: [String: Any], into lines: inout [String], listPrefix: String?) {
        let type = node["type"] as? String
        let content = node["content"] as? [[String: Any]] ?? []

        switch type {
        case "text":
            if let text = node["text"] as? String {
                if lines.isEmpty || lines[lines.count - 1].hasSuffix("\n") {
                    lines.append((listPrefix ?? "") + text)
                } else {
                    lines[lines.count - 1] += text
                }
            }
        case "paragraph", "heading":
            lines.append("")
            for child in content { walk(child, into: &lines, listPrefix: listPrefix) }
        case "listItem":
            for child in content { walk(child, into: &lines, listPrefix: "- ") }
        case "hardBreak":
            lines.append("")
        default:
            for child in content { walk(child, into: &lines, listPrefix: listPrefix) }
        }
    }
}
