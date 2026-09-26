import Testing
import Foundation
@testable import Contour

/// The Overview's facts line: CI rolled up from either kind of check in either source's
/// spelling, reviews counted once per reviewer, and a line that omits what wasn't known.
struct PRGlanceTests {

    // MARK: - Checks

    @Test func checkRunsAndCommitStatusesInEitherSpelling() {
        #expect(PRGlance.checkOutcome(status: "COMPLETED", conclusion: "SUCCESS", state: nil) == .passed)
        #expect(PRGlance.checkOutcome(status: "completed", conclusion: "failure", state: nil) == .failed)
        #expect(PRGlance.checkOutcome(status: "completed", conclusion: "cancelled", state: nil) == .failed)
        #expect(PRGlance.checkOutcome(status: "completed", conclusion: "skipped", state: nil) == .ignored)
        #expect(PRGlance.checkOutcome(status: "IN_PROGRESS", conclusion: nil, state: nil) == .pending)
        #expect(PRGlance.checkOutcome(status: "queued", conclusion: nil, state: nil) == .pending)
        #expect(PRGlance.checkOutcome(status: nil, conclusion: nil, state: "SUCCESS") == .passed)
        #expect(PRGlance.checkOutcome(status: nil, conclusion: nil, state: "error") == .failed)
        #expect(PRGlance.checkOutcome(status: nil, conclusion: nil, state: "pending") == .pending)
    }

    @Test func anyFailureFailsAndAnythingUnfinishedIsPending() {
        #expect(PRGlance.rollUp([.passed, .failed, .pending]) == .failing)
        #expect(PRGlance.rollUp([.passed, .pending, .ignored]) == .pending)
        #expect(PRGlance.rollUp([.passed, .ignored]) == .passing)
    }

    @Test func noChecksOrOnlySkippedOnesIsNoCI() {
        #expect(PRGlance.rollUp([]) == nil)
        #expect(PRGlance.rollUp([.ignored]) == nil)
    }

    // MARK: - Reviews

    @Test func eachReviewerCountsOnceByTheirLatestStance() {
        let tally = PRGlance.tallyReviews([
            ("ana", "CHANGES_REQUESTED"), ("ana", "APPROVED"),   // changed their mind
            ("bo", "APPROVED"), ("bo", "COMMENTED"),              // a comment doesn't withdraw it
            ("cy", "APPROVED"), ("cy", "DISMISSED"),              // a dismissal does
            ("di", "changes_requested")
        ])
        #expect(tally.approvals == 2)
        #expect(tally.changesRequested == 1)
    }

    @Test func commentOnlyReviewsCountForNothing() {
        let tally = PRGlance.tallyReviews([("ana", "COMMENTED")])
        #expect(tally.approvals == 0 && tally.changesRequested == 0)
    }

    // MARK: - The line

    private func summary(_ glance: PRGlance?) -> PRSummary {
        var pr = ContourSampleData.publishTriggeredReindex.pr
        pr.filesChanged = 12
        pr.additions = 148
        pr.deletions = 37
        pr.glance = glance
        return pr
    }

    @Test func sizeIsAlwaysShownEvenForGraphsSavedBeforeGlanceFacts() {
        #expect(summary(nil).glanceFacts().map(\.text) == ["12 files", "+148 \u{2212}37"])
    }

    @Test func fullLineReadsInOrder() {
        let now = Date()
        let facts = summary(PRGlance(
            checks: .passing, approvals: 2, changesRequested: 0, unresolvedThreads: 3,
            createdAt: now.addingTimeInterval(-2 * 86_400)
        )).glanceFacts(now: now)
        #expect(facts.prefix(5).map(\.text) == ["12 files", "+148 \u{2212}37", "CI passing", "2 approvals", "3 unresolved threads"])
        #expect(facts.last?.text.hasPrefix("opened ") == true)
        #expect(facts[2].tone == .good)
        #expect(facts[4].tone == .caution)
    }

    @Test func unknownFactsAreOmittedRatherThanGuessed() {
        // The anonymous source can't see thread resolution, and this PR has no CI.
        let texts = summary(PRGlance(approvals: 1, changesRequested: 0)).glanceFacts().map(\.text)
        #expect(texts == ["12 files", "+148 \u{2212}37", "1 approval"])
    }

    @Test func failingCIAndRequestedChangesStandOut() {
        let facts = summary(PRGlance(checks: .failing, approvals: 0, changesRequested: 1, unresolvedThreads: 0)).glanceFacts()
        #expect(facts.map(\.text) == ["12 files", "+148 \u{2212}37", "CI failing", "changes requested"])
        #expect(facts[2].tone == .bad)
        #expect(facts[3].tone == .caution)
    }

    @Test func noReviewsSaysSo() {
        let texts = summary(PRGlance(checks: .pending, approvals: 0, changesRequested: 0)).glanceFacts().map(\.text)
        #expect(texts.suffix(2) == ["CI running", "no approvals"])
    }

    @Test func singleFileIsSingular() {
        var pr = summary(nil)
        pr.filesChanged = 1
        #expect(pr.glanceFacts().first?.text == "1 file")
    }

    // MARK: - Assembly and caching

    @Test func refreshingACachedGraphPicksUpCurrentGlanceFacts() {
        var graph = ContourSampleData.publishTriggeredReindex
        #expect(graph.pr.glance == nil)
        var ctx = RawPRContext(
            url: "https://github.com/acme/docs-site/pull/4821", owner: "acme", repo: "docs-site", number: 4821,
            title: "t", body: "", author: "a", state: "OPEN", headRefName: "h", baseRefName: "main",
            headSha: "x", baseSha: "y", isCrossRepository: false, headCloneURL: "", additions: 1,
            deletions: 1, changedFiles: 1, files: [], commits: [], comments: [], reviews: [], diff: ""
        )
        ctx.glance = PRGlance(checks: .failing, approvals: 1, changesRequested: 0)
        graph.refreshMetadata(from: ctx)
        #expect(graph.pr.glance?.checks == .failing)
    }

    @Test func graphsSavedWithoutGlanceStillDecode() throws {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.glance = nil
        let data = try JSONEncoder().encode(graph)
        #expect(!String(decoding: data, as: UTF8.self).contains("\"glance\""))
        let decoded = try JSONDecoder().decode(PRGraph.self, from: data)
        #expect(decoded.pr.glance == nil)
    }
}
