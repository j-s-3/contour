import Foundation

/// The facts a reviewer wants in the first few seconds, before any analysis: is CI green,
/// has anyone reviewed it, are threads still open, and how long has it been up. Raw GitHub
/// state, not interpretation, so the Overview shows it as one quiet line under the title
/// and never as a dashboard.
///
/// Every field is best effort. A source that can't tell leaves it nil and the line simply
/// omits that fact: the anonymous REST API has no thread-resolution state, and a PR with
/// no checks configured has no CI to report.
struct PRGlance: Codable, Hashable, Sendable {
    enum Checks: String, Codable, Sendable {
        case passing, failing, pending
    }

    /// Rolled up across every check run and commit status on the head commit.
    var checks: Checks?
    /// Reviewers whose latest standing review approves.
    var approvals: Int?
    /// Reviewers whose latest standing review requests changes.
    var changesRequested: Int?
    var unresolvedThreads: Int?
    var createdAt: Date?

    // MARK: - Normalizing what the sources return

    /// One check's contribution to the rollup. `ignored` is a check that finished without
    /// a verdict (neutral, skipped, stale), which GitHub doesn't count against the PR.
    enum CheckOutcome: Equatable {
        case passed, failed, pending, ignored
    }

    /// Reads either kind of check GitHub reports, in either spelling: a check run has a
    /// `status` and, once completed, a `conclusion`; a commit status has only a `state`.
    /// `gh` uppercases these and the REST API lowercases them.
    static func checkOutcome(status: String?, conclusion: String?, state: String?) -> CheckOutcome {
        if let state {
            switch state.uppercased() {
            case "SUCCESS": return .passed
            case "FAILURE", "ERROR": return .failed
            default: return .pending          // PENDING, EXPECTED
            }
        }
        if let status, status.uppercased() != "COMPLETED" { return .pending }
        switch conclusion?.uppercased() {
        case "SUCCESS": return .passed
        case "NEUTRAL", "SKIPPED", "STALE": return .ignored
        case nil: return .pending
        default: return .failed               // FAILURE, CANCELLED, TIMED_OUT, ACTION_REQUIRED, …
        }
    }

    /// Any failure makes the PR failing; otherwise anything unfinished makes it pending.
    /// Nil when there's nothing that passed or failed — no CI to speak of.
    static func rollUp(_ outcomes: [CheckOutcome]) -> Checks? {
        if outcomes.contains(.failed) { return .failing }
        if outcomes.contains(.pending) { return .pending }
        if outcomes.contains(.passed) { return .passing }
        return nil
    }

    /// Counts each reviewer once, by their latest review that took a stance. A comment-only
    /// review after an approval doesn't withdraw it; a dismissal does. Reviews must be in
    /// submission order, which is how both sources return them.
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

/// One item on the Overview's facts line. The tone lets the view flag the facts that
/// should stop a reviewer — failing CI, requested changes, open threads — without the
/// line becoming a row of badges.
struct GlanceFact: Hashable, Sendable {
    enum Tone: Sendable { case plain, good, caution, bad }
    var text: String
    var tone: Tone = .plain
}

extension PRSummary {
    /// `12 files · +148 −37 · CI passing · 2 approvals · 3 unresolved threads · opened 2 days ago`.
    /// Size is always known; the rest appears only when the source could tell.
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
            // Clamped so clock skew never reads as "opened in 3 seconds".
            facts.append(GlanceFact(text: "opened " + formatter.localizedString(for: min(created, now), relativeTo: now)))
        }
        return facts
    }

    private static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }
}
