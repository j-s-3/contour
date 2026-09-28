import Foundation

/// Best-effort Jira lookup via `acli` (the same "shell out to an already-authenticated
/// CLI" pattern as `gh` and `pi` — no separate Jira credential handling in this app).
/// Detects a ticket key referenced by the PR (title, description, branch name, or commit
/// messages) and pulls its summary/description to ground the "Problem to be solved" ELI5
/// statement in what was actually asked for, not just what the diff appears to do.
///
/// Opt-in: only offered when `acli` is on PATH, and only used when the user selects it.
/// Entirely best-effort, like every tracker — if `acli` isn't installed, isn't
/// authenticated, no ticket key is found, or the lookup fails for any reason, this
/// returns `nil` and the pipeline continues without it. A missing ticket must never fail
/// PR analysis.
struct JiraTracker: IssueTracker {
    let id: TrackerID = .jira

    func reference(in context: RawPRContext) -> IssueRef? {
        Self.ticketKey(in: context).map { IssueRef(id: $0, tracker: .jira) }
    }

    func fetch(_ ref: IssueRef) async -> TicketInfo? {
        await fetchTicket(key: ref.id)
    }

    /// Matches keys like `PROJ-40000`, `ABC-1234` — an uppercase project prefix (2+
    /// letters, optionally with digits) followed by a dash and a number.
    private static let ticketKeyPattern = try! NSRegularExpression(pattern: #"\b([A-Z][A-Z0-9]{1,9}-[0-9]+)\b"#)

    /// Searches, in order, the PR title, body, head/base branch names, and commit
    /// messages. Returns the first match — PR authors conventionally put the ticket key
    /// in the title or branch name, so that's checked first.
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

    /// Fetches ticket summary/description via `acli jira workitem view <key> --json`.
    /// Returns `nil` on any failure (not installed, not authed, ticket not found, ADF
    /// parse failure) rather than throwing, per this service's best-effort contract.
    func fetchTicket(key: String) async -> TicketInfo? {
        guard let output = try? await Shell.run("acli", ["jira", "workitem", "view", key, "--json"]) else {
            return nil
        }
        guard let data = output.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = obj["fields"] as? [String: Any],
              let summary = fields["summary"] as? String
        else { return nil }

        let description = (fields["description"] as? [String: Any]).map(Self.flattenADF) ?? ""
        let url = await Self.browseURL(forKey: key, selfLink: obj["self"] as? String)

        return TicketInfo(kind: .jira, key: key, summary: summary, description: description, url: url)
    }

    /// Derives a human-facing `/browse/<key>` URL. Prefers the public site host from
    /// `acli jira auth status` (e.g. "your-org.atlassian.net") — the REST API's own
    /// `self` link points at an internal backend host (e.g.
    /// `jira-prod-us-28-1.prod.atl-paas.net`) that isn't guaranteed to resolve for a
    /// human clicking the link, even though it's a perfectly valid API endpoint.
    private static func browseURL(forKey key: String, selfLink: String?) async -> String {
        if let site = await authenticatedSiteHost() {
            return "https://\(site)/browse/\(key)"
        }
        if let selfLink, let url = URL(string: selfLink), let host = url.host {
            return "https://\(host)/browse/\(key)"
        }
        // No site host discoverable; the key alone is still useful in the UI even though
        // this URL won't resolve.
        return "https://atlassian.net/browse/\(key)"
    }

    /// Parses the "Site: <host>" line from `acli jira auth status`'s plain-text output.
    private static func authenticatedSiteHost() async -> String? {
        guard let output = try? await Shell.run("acli", ["jira", "auth", "status"]) else { return nil }
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Site:") {
                return trimmed.replacingOccurrences(of: "Site:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Flattens Atlassian Document Format (rich-text) JSON into plain text good enough
    /// for an LLM prompt: paragraph/heading boundaries become newlines, list items get a
    /// leading dash, inline marks are dropped (bold/italic don't matter for grounding).
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
