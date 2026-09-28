import Testing
import Foundation
@testable import Contour

/// `AnalyzingView.headline(_:)` was already a plain static function; `PullRequestRow`'s
/// subtitle formatting and `AnalyzingView`'s console-summary formatting were pulled out
/// into `OnboardingViewLogic` / `AnalyzingView.latestDetail(log:stage:)` per CLAUDE.md's
/// guidance for this file, so both are directly testable without a view instance.
/// `checkClipboard` and `openUnreadClipboard`'s decision logic (declined-clipboard
/// suppression, the readable-text vs. detected-pattern offer paths, and what an "open the
/// unread link" click resolves to) and `pullRequestLists`' row-capping/empty-state logic
/// were pulled out the same way, so `OnboardingView` itself only calls `NSPasteboard` and
/// forwards the answer. The rest — the URL field, the actual clipboard offer row, PR list
/// rendering, the analyzing console — is view rendering and live `NSPasteboard`
/// interaction with no UI-testing infrastructure in this suite.
struct OnboardingViewTests {

    // MARK: - OnboardingViewLogic.subtitle

    @Test func subtitleAlwaysStartsWithRepoAndNumber() {
        #expect(OnboardingViewLogic.subtitle(repo: "acme/shop", number: 42, detail: nil, date: nil, dateVerb: "opened") == "acme/shop #42")
    }

    @Test func subtitleAppendsDetailWhenPresent() {
        #expect(OnboardingViewLogic.subtitle(repo: "acme/shop", number: 42, detail: "jdoe", date: nil, dateVerb: "opened") == "acme/shop #42 · jdoe")
    }

    @Test func subtitleAppendsDateVerbAndRelativeDateWhenPresent() {
        let date = Date(timeIntervalSince1970: 0)
        let subtitle = OnboardingViewLogic.subtitle(repo: "acme/shop", number: 42, detail: nil, date: date, dateVerb: "updated")
        #expect(subtitle.hasPrefix("acme/shop #42 · updated "))
    }

    @Test func subtitleJoinsAllPartsInOrderWhenBothArePresent() {
        let date = Date(timeIntervalSince1970: 0)
        let subtitle = OnboardingViewLogic.subtitle(repo: "acme/shop", number: 7, detail: "jdoe · draft", date: date, dateVerb: "updated")
        #expect(subtitle.hasPrefix("acme/shop #7 · jdoe · draft · updated "))
    }

    // MARK: - AnalyzingView.headline

    @Test func everyPipelineStageHasAReviewerFacingHeadline() {
        #expect(AnalyzingView.headline(.fetching) == "Opening the pull request…")
        #expect(AnalyzingView.headline(.checkingOut) == "Opening the pull request…")
        #expect(AnalyzingView.headline(.cacheCheck) == "Opening the pull request…")
        #expect(AnalyzingView.headline(.ticket) == "Understanding the change…")
        #expect(AnalyzingView.headline(.behaviorChange) == "Understanding the change…")
        #expect(AnalyzingView.headline(.understanding) == "Understanding the change…")
        #expect(AnalyzingView.headline(.architecture) == "Analyzing architecture…")
        #expect(AnalyzingView.headline(.decisions) == "Finding the decisions it makes…")
        #expect(AnalyzingView.headline(.flows) == "Tracing the flows it touches…")
        #expect(AnalyzingView.headline(.judgment) == "Deciding what needs your judgment…")
    }

    // MARK: - AnalyzingView.latestDetail

    @Test func latestDetailFallsBackToTheStageNameWithNoLogYet() {
        #expect(AnalyzingView.latestDetail(log: [], stage: .architecture) == PipelineStage.architecture.rawValue)
    }

    @Test func latestDetailShowsOnlyTheStageWhenTheLastEntryHasNoDetail() {
        let log = [PipelineProgressEntry(stage: "Analyzing architecture", detail: "")]
        #expect(AnalyzingView.latestDetail(log: log, stage: .architecture) == "Analyzing architecture")
    }

    @Test func latestDetailCombinesStageAndDetailWhenBothArePresent() {
        let log = [
            PipelineProgressEntry(stage: "Analyzing architecture", detail: ""),
            PipelineProgressEntry(stage: "Analyzing architecture", detail: "Reading GraphStore.swift"),
        ]
        #expect(AnalyzingView.latestDetail(log: log, stage: .architecture) == "Analyzing architecture — Reading GraphStore.swift")
    }

    // MARK: - OnboardingViewLogic.isDeclined

    /// Pins that a clipboard offer is suppressed exactly when the change count matches the
    /// one the reviewer already dismissed — the mechanism `checkClipboard` relies on to not
    /// re-offer the same link every time the window is activated.
    @Test func isDeclinedMatchesOnlyTheExactChangeCountTheReviewerDismissed() {
        #expect(OnboardingViewLogic.isDeclined(changeCount: 3, declinedChangeCount: 3))
        #expect(!OnboardingViewLogic.isDeclined(changeCount: 4, declinedChangeCount: 3))
    }

    @Test func isDeclinedIsFalseWhenNothingHasBeenDeclinedYet() {
        #expect(!OnboardingViewLogic.isDeclined(changeCount: 1, declinedChangeCount: nil))
    }

    // MARK: - OnboardingViewLogic.offer(fromReadableClipboardText:)

    /// The pre-15.4 / already-granted-access path: a recognized PR link becomes a
    /// `.pullRequest` offer carrying the canonicalized URL, not the raw clipboard text.
    @Test func offerFromReadableTextRecognizesAPullRequestLink() {
        let offer = OnboardingViewLogic.offer(fromReadableClipboardText: "check out https://github.com/acme/shop/pull/42 please")
        #expect(offer == .pullRequest("https://github.com/acme/shop/pull/42"))
    }

    @Test func offerFromReadableTextIsNilForNonPRTextOrNoClipboard() {
        #expect(OnboardingViewLogic.offer(fromReadableClipboardText: "just some notes") == nil)
        #expect(OnboardingViewLogic.offer(fromReadableClipboardText: nil) == nil)
    }

    // MARK: - OnboardingViewLogic.offer(detectedProbableWebURL:changeCount:)

    /// The macOS 15.4+ pre-access path: pattern detection alone can only produce a generic
    /// "unread link" offer, carrying the change count so it can later be marked declined.
    @Test func offerFromDetectedPatternsOffersAnUnreadLinkWhenAWebURLWasDetected() {
        #expect(OnboardingViewLogic.offer(detectedProbableWebURL: true, changeCount: 7) == .unreadLink(changeCount: 7))
    }

    @Test func offerFromDetectedPatternsIsNilWhenNothingWasDetected() {
        #expect(OnboardingViewLogic.offer(detectedProbableWebURL: false, changeCount: 7) == nil)
    }

    // MARK: - OnboardingViewLogic.resolveClipboardRead

    /// Once the reviewer asks to open the unread link, a recognized PR link resolves to
    /// opening it directly.
    @Test func resolveClipboardReadOpensARecognizedPullRequestLink() {
        let action = OnboardingViewLogic.resolveClipboardRead("https://github.com/acme/shop/pull/9")
        #expect(action == .open("https://github.com/acme/shop/pull/9"))
    }

    /// Non-PR clipboard text lands in the URL field instead of vanishing, so the reviewer
    /// can see why it didn't open.
    @Test func resolveClipboardReadFillsTheFieldForNonPRText() {
        let action = OnboardingViewLogic.resolveClipboardRead("https://example.com/not-a-pr")
        #expect(action == .fillField("https://example.com/not-a-pr"))
    }

    @Test func resolveClipboardReadDoesNothingForAnEmptyClipboard() {
        #expect(OnboardingViewLogic.resolveClipboardRead(nil) == .doNothing)
    }

    // MARK: - OnboardingViewLogic.visibleRequests

    /// The review-requested list is capped at the row limit the start screen has room for,
    /// even when `gh` returns more.
    @Test func visibleRequestsCapsAtTheLimit() {
        let requests = (0..<8).map { ReviewRequest(url: "u\($0)", repo: "acme/shop", number: $0, title: "t\($0)", author: "a", isDraft: false, updatedAt: nil) }
        #expect(OnboardingViewLogic.visibleRequests(requests, limit: 5).count == 5)
        #expect(OnboardingViewLogic.visibleRequests(requests, limit: 5).map(\.number) == [0, 1, 2, 3, 4])
    }

    @Test func visibleRequestsIsEmptyWhenGHHasNotAnsweredYet() {
        #expect(OnboardingViewLogic.visibleRequests(nil, limit: 5).isEmpty)
    }

    // MARK: - OnboardingViewLogic.shouldShowLists

    /// The PR-lists section collapses entirely when both lists are empty, rather than
    /// showing two empty headings.
    @Test func shouldShowListsIsFalseOnlyWhenBothListsAreEmpty() {
        #expect(!OnboardingViewLogic.shouldShowLists(requests: [], recents: []))

        let request = ReviewRequest(url: "u", repo: "acme/shop", number: 1, title: "t", author: "a", isDraft: false, updatedAt: nil)
        #expect(OnboardingViewLogic.shouldShowLists(requests: [request], recents: []))

        let recent = AnalysisCache.RecentPR(url: "u", repo: "acme/shop", number: 1, title: "t", lastOpened: Date())
        #expect(OnboardingViewLogic.shouldShowLists(requests: [], recents: [recent]))
    }
}
