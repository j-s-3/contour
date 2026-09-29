import Foundation

struct PRGlance: Codable, Hashable, Sendable {
    enum Checks: String, Codable, Sendable {
        case passing, failing, pending
    }

    var checks: Checks?
    var approvals: Int?
    var changesRequested: Int?
    var unresolvedThreads: Int?
    var createdAt: Date?

    enum CheckOutcome: Equatable {
        case passed, failed, pending, ignored
    }

    static func checkOutcome(status: String?, conclusion: String?, state: String?) -> CheckOutcome {
        if let state {
            switch state.uppercased() {
            case "SUCCESS": return .passed
            case "FAILURE", "ERROR": return .failed
            default: return .pending
            }
        }
        if let status, status.uppercased() != "COMPLETED" { return .pending }
        switch conclusion?.uppercased() {
        case "SUCCESS": return .passed
        case "NEUTRAL", "SKIPPED", "STALE": return .ignored
        case nil: return .pending
        default: return .failed
        }
    }

    static func rollUp(_ outcomes: [CheckOutcome]) -> Checks? {
        if outcomes.contains(.failed) { return .failing }
        if outcomes.contains(.pending) { return .pending }
        if outcomes.contains(.passed) { return .passing }
        return nil
    }

    static func tallyReviews(_ reviews: [(author: String, state: String)]) -> (approvals: Int, changesRequested: Int) {
        var stance: [String: String] = [:]
        for review in reviews {
            let state = review.state.uppercased()
            guard ["APPROVED", "CHANGES_REQUESTED", "DISMISSED"].contains(state) else { continue }
            stance[review.author] = state
        }
        return (stance.values.filter { $0 == "APPROVED" }.count,
                stance.values.filter { $0 == "CHANGES_REQUESTED" }.count)
    }

    static func date(iso8601: String?) -> Date? {
        iso8601.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

struct GlanceFact: Hashable, Sendable {
    enum Tone: Sendable { case plain, good, caution, bad }
    var text: String
    var tone: Tone = .plain
}

extension PRSummary {
    func glanceFacts(now: Date = Date()) -> [GlanceFact] {
        var facts = [
            GlanceFact(text: Self.count(filesChanged, "file", "files")),
            GlanceFact(text: "+\(additions) \u{2212}\(deletions)")
        ]
        guard let glance else { return facts }

        switch glance.checks {
        case .passing: facts.append(GlanceFact(text: "CI passing", tone: .good))
        case .failing: facts.append(GlanceFact(text: "CI failing", tone: .bad))
        case .pending: facts.append(GlanceFact(text: "CI running", tone: .caution))
        case nil: break
        }

        if let changes = glance.changesRequested, changes > 0 {
            facts.append(GlanceFact(text: "changes requested", tone: .caution))
        }
        if let approvals = glance.approvals {
            if approvals > 0 {
                facts.append(GlanceFact(text: Self.count(approvals, "approval", "approvals")))
            } else if (glance.changesRequested ?? 0) == 0 {
                facts.append(GlanceFact(text: "no approvals"))
            }
        }

        if let open = glance.unresolvedThreads, open > 0 {
            facts.append(GlanceFact(text: Self.count(open, "unresolved thread", "unresolved threads"), tone: .caution))
        }

        if let created = glance.createdAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            facts.append(GlanceFact(text: "opened " + formatter.localizedString(for: min(created, now), relativeTo: now)))
        }
        return facts
    }

    private static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }
}
