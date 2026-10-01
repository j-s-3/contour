import Foundation
import Testing

@testable import Contour

struct StartScreenLogicTests {
    @Test func subtitleAlwaysStartsWithRepoAndNumber() {
        #expect(
            StartScreenLogic.subtitle(repo: "acme/shop", number: 42, detail: nil, date: nil, dateVerb: "opened")
                == "acme/shop #42")
    }

    @Test func subtitleAppendsDetailWhenPresent() {
        #expect(
            StartScreenLogic.subtitle(repo: "acme/shop", number: 42, detail: "jdoe", date: nil, dateVerb: "opened")
                == "acme/shop #42 · jdoe")
    }

    @Test func subtitleAppendsDateVerbAndRelativeDateWhenPresent() {
        let date = Date(timeIntervalSince1970: 0)
        let subtitle = StartScreenLogic.subtitle(
            repo: "acme/shop", number: 42, detail: nil, date: date, dateVerb: "updated")
        #expect(subtitle.hasPrefix("acme/shop #42 · updated "))
    }

    @Test func subtitleJoinsAllPartsInOrderWhenBothArePresent() {
        let date = Date(timeIntervalSince1970: 0)
        let subtitle = StartScreenLogic.subtitle(
            repo: "acme/shop", number: 7, detail: "jdoe · draft", date: date, dateVerb: "updated")
        #expect(subtitle.hasPrefix("acme/shop #7 · jdoe · draft · updated "))
    }

    @Test func isDeclinedMatchesOnlyTheExactChangeCountTheReviewerDismissed() {
        #expect(StartScreenLogic.isDeclined(changeCount: 3, declinedChangeCount: 3))
        #expect(!StartScreenLogic.isDeclined(changeCount: 4, declinedChangeCount: 3))
    }

    @Test func isDeclinedIsFalseWhenNothingHasBeenDeclinedYet() {
        #expect(!StartScreenLogic.isDeclined(changeCount: 1, declinedChangeCount: nil))
    }

    @Test func offerFromReadableTextRecognizesAPullRequestLink() {
        let offer = StartScreenLogic.offer(
            fromReadableClipboardText: "check out https://github.com/acme/shop/pull/42 please")
        #expect(offer == .pullRequest("https://github.com/acme/shop/pull/42"))
    }

    @Test func offerFromReadableTextIsNilForNonPRTextOrNoClipboard() {
        #expect(StartScreenLogic.offer(fromReadableClipboardText: "just some notes") == nil)
        #expect(StartScreenLogic.offer(fromReadableClipboardText: nil) == nil)
    }

    @Test func offerFromDetectedPatternsOffersAnUnreadLinkWhenAWebURLWasDetected() {
        #expect(StartScreenLogic.offer(detectedProbableWebURL: true, changeCount: 7) == .unreadLink(changeCount: 7))
    }

    @Test func offerFromDetectedPatternsIsNilWhenNothingWasDetected() {
        #expect(StartScreenLogic.offer(detectedProbableWebURL: false, changeCount: 7) == nil)
    }

    @Test func resolveClipboardReadOpensARecognizedPullRequestLink() {
        let action = StartScreenLogic.resolveClipboardRead("https://github.com/acme/shop/pull/9")
        #expect(action == .open("https://github.com/acme/shop/pull/9"))
    }

    @Test func resolveClipboardReadFillsTheFieldForNonPRText() {
        let action = StartScreenLogic.resolveClipboardRead("https://example.com/not-a-pr")
        #expect(action == .fillField("https://example.com/not-a-pr"))
    }

    @Test func resolveClipboardReadDoesNothingForAnEmptyClipboard() {
        #expect(StartScreenLogic.resolveClipboardRead(nil) == .doNothing)
    }

    @Test func resolvedPasteTextCanonicalizesARecognizedPullRequestLink() {
        #expect(
            StartScreenLogic.resolvedPasteText("see github.com/acme/shop/pull/3 for details")
                == "https://github.com/acme/shop/pull/3")
    }

    @Test func resolvedPasteTextLeavesNonPRTextUnchanged() {
        #expect(StartScreenLogic.resolvedPasteText("not a link") == "not a link")
    }

    @Test func visibleRequestsCapsAtTheLimit() {
        let requests = (0..<8).map {
            ReviewRequest(
                url: "u\($0)", repo: "acme/shop", number: $0, title: "t\($0)", author: "a", isDraft: false,
                updatedAt: nil)
        }
        #expect(StartScreenLogic.visibleRequests(requests, limit: 5).count == 5)
        #expect(StartScreenLogic.visibleRequests(requests, limit: 5).map(\.number) == [0, 1, 2, 3, 4])
    }

    @Test func visibleRequestsIsEmptyWhenGHHasNotAnsweredYet() {
        #expect(StartScreenLogic.visibleRequests(nil, limit: 5).isEmpty)
    }

    private func request(_ number: Int) -> ReviewRequest {
        ReviewRequest(
            url: "https://github.com/acme/shop/pull/\(number)", repo: "acme/shop", number: number,
            title: "t\(number)", author: "a", isDraft: false, updatedAt: nil)
    }

    private func recent(_ number: Int) -> AnalysisCache.RecentPR {
        AnalysisCache.RecentPR(
            url: "https://github.com/acme/shop/pull/\(number)", repo: "acme/shop", number: number,
            title: "t\(number)", lastOpened: Date(timeIntervalSince1970: TimeInterval(number)))
    }

    @Test func sourcesListReviewRequestsOnlyWhenGHAnswered() {
        #expect(StartScreenLogic.sources(reviewRequestsAvailable: false, watched: []) == [.recents])
        #expect(
            StartScreenLogic.sources(reviewRequestsAvailable: true, watched: []) == [.reviewRequests, .recents])
    }

    @Test func sourcesListWatchedRepositoriesLastInTheOrderGiven() {
        #expect(
            StartScreenLogic.sources(reviewRequestsAvailable: true, watched: ["acme/web", "acme/api"])
                == [.reviewRequests, .recents, .watched("acme/web"), .watched("acme/api")])
    }

    @Test func aRememberedSourceThatStillExistsIsSelected() {
        let sources: [StartSource] = [.reviewRequests, .recents, .watched("acme/api")]
        #expect(
            StartScreenLogic.resolvedSelection(remembered: .watched("acme/api"), sources: sources)
                == .watched("acme/api"))
    }

    @Test func withNothingRememberedTheFirstSourceIsSelected() {
        #expect(
            StartScreenLogic.resolvedSelection(remembered: nil, sources: [.reviewRequests, .recents])
                == .reviewRequests)
        #expect(StartScreenLogic.resolvedSelection(remembered: nil, sources: [.recents]) == .recents)
    }

    @Test func aRememberedSourceThatIsGoneFallsBackToTheFirstSource() {
        #expect(
            StartScreenLogic.resolvedSelection(remembered: .watched("acme/gone"), sources: [.reviewRequests, .recents])
                == .reviewRequests)
    }

    @Test func selectionFallsBackToRecentsWhenThereAreNoSourcesAtAll() {
        #expect(StartScreenLogic.resolvedSelection(remembered: nil, sources: []) == .recents)
    }

    @Test func welcomeShowsOnlyWhenNothingIsListedAndNothingIsWatched() {
        #expect(StartScreenLogic.showsWelcome(requests: [], recents: [], watchedCount: 0))
        #expect(!StartScreenLogic.showsWelcome(requests: [request(1)], recents: [], watchedCount: 0))
        #expect(!StartScreenLogic.showsWelcome(requests: [], recents: [recent(1)], watchedCount: 0))
        #expect(!StartScreenLogic.showsWelcome(requests: [], recents: [], watchedCount: 1))
    }

    @Test func everySourceHasATitleASymbolAndAnEmptyMessage() {
        #expect(StartScreenLogic.title(for: .reviewRequests) == "Awaiting your review")
        #expect(StartScreenLogic.title(for: .recents) == "Recently opened")
        #expect(StartScreenLogic.title(for: .watched("acme/api")) == "acme/api")
        #expect(StartScreenLogic.symbol(for: .reviewRequests) == "person.crop.circle.badge.questionmark")
        #expect(StartScreenLogic.symbol(for: .recents) == "clock.arrow.circlepath")
        #expect(StartScreenLogic.symbol(for: .watched("acme/api")) == "eye")
        #expect(StartScreenLogic.emptyMessage(for: .reviewRequests) == "Nothing is waiting for your review.")
        #expect(StartScreenLogic.emptyMessage(for: .recents) == "Pull requests you open will appear here.")
        #expect(StartScreenLogic.emptyMessage(for: .watched("acme/api")) == "No open pull requests.")
    }

    @Test func aCountIsShownOnlyWhenThereAreRows() {
        #expect(StartScreenLogic.count(rows: 0) == nil)
        #expect(StartScreenLogic.count(rows: 3) == "3")
    }

    @Test func listsShowTenRows() {
        #expect(StartScreenLogic.rowsShown == 10)
    }
}
