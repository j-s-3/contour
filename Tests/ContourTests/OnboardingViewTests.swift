import Foundation
import Testing

@testable import Contour

struct OnboardingViewTests {
    @Test func subtitleAlwaysStartsWithRepoAndNumber() {
        #expect(
            OnboardingViewLogic.subtitle(repo: "acme/shop", number: 42, detail: nil, date: nil, dateVerb: "opened")
                == "acme/shop #42")
    }

    @Test func subtitleAppendsDetailWhenPresent() {
        #expect(
            OnboardingViewLogic.subtitle(repo: "acme/shop", number: 42, detail: "jdoe", date: nil, dateVerb: "opened")
                == "acme/shop #42 · jdoe")
    }

    @Test func subtitleAppendsDateVerbAndRelativeDateWhenPresent() {
        let date = Date(timeIntervalSince1970: 0)
        let subtitle = OnboardingViewLogic.subtitle(
            repo: "acme/shop", number: 42, detail: nil, date: date, dateVerb: "updated")
        #expect(subtitle.hasPrefix("acme/shop #42 · updated "))
    }

    @Test func subtitleJoinsAllPartsInOrderWhenBothArePresent() {
        let date = Date(timeIntervalSince1970: 0)
        let subtitle = OnboardingViewLogic.subtitle(
            repo: "acme/shop", number: 7, detail: "jdoe · draft", date: date, dateVerb: "updated")
        #expect(subtitle.hasPrefix("acme/shop #7 · jdoe · draft · updated "))
    }

    @Test func isDeclinedMatchesOnlyTheExactChangeCountTheReviewerDismissed() {
        #expect(OnboardingViewLogic.isDeclined(changeCount: 3, declinedChangeCount: 3))
        #expect(!OnboardingViewLogic.isDeclined(changeCount: 4, declinedChangeCount: 3))
    }

    @Test func isDeclinedIsFalseWhenNothingHasBeenDeclinedYet() {
        #expect(!OnboardingViewLogic.isDeclined(changeCount: 1, declinedChangeCount: nil))
    }

    @Test func offerFromReadableTextRecognizesAPullRequestLink() {
        let offer = OnboardingViewLogic.offer(
            fromReadableClipboardText: "check out https://github.com/acme/shop/pull/42 please")
        #expect(offer == .pullRequest("https://github.com/acme/shop/pull/42"))
    }

    @Test func offerFromReadableTextIsNilForNonPRTextOrNoClipboard() {
        #expect(OnboardingViewLogic.offer(fromReadableClipboardText: "just some notes") == nil)
        #expect(OnboardingViewLogic.offer(fromReadableClipboardText: nil) == nil)
    }

    @Test func offerFromDetectedPatternsOffersAnUnreadLinkWhenAWebURLWasDetected() {
        #expect(OnboardingViewLogic.offer(detectedProbableWebURL: true, changeCount: 7) == .unreadLink(changeCount: 7))
    }

    @Test func offerFromDetectedPatternsIsNilWhenNothingWasDetected() {
        #expect(OnboardingViewLogic.offer(detectedProbableWebURL: false, changeCount: 7) == nil)
    }

    @Test func resolveClipboardReadOpensARecognizedPullRequestLink() {
        let action = OnboardingViewLogic.resolveClipboardRead("https://github.com/acme/shop/pull/9")
        #expect(action == .open("https://github.com/acme/shop/pull/9"))
    }

    @Test func resolveClipboardReadFillsTheFieldForNonPRText() {
        let action = OnboardingViewLogic.resolveClipboardRead("https://example.com/not-a-pr")
        #expect(action == .fillField("https://example.com/not-a-pr"))
    }

    @Test func resolveClipboardReadDoesNothingForAnEmptyClipboard() {
        #expect(OnboardingViewLogic.resolveClipboardRead(nil) == .doNothing)
    }

    @Test func resolvedPasteTextCanonicalizesARecognizedPullRequestLink() {
        #expect(
            OnboardingViewLogic.resolvedPasteText("see github.com/acme/shop/pull/3 for details")
                == "https://github.com/acme/shop/pull/3")
    }

    @Test func resolvedPasteTextLeavesNonPRTextUnchanged() {
        #expect(OnboardingViewLogic.resolvedPasteText("not a link") == "not a link")
    }

    @Test func visibleRequestsCapsAtTheLimit() {
        let requests = (0..<8).map {
            ReviewRequest(
                url: "u\($0)", repo: "acme/shop", number: $0, title: "t\($0)", author: "a", isDraft: false,
                updatedAt: nil)
        }
        #expect(OnboardingViewLogic.visibleRequests(requests, limit: 5).count == 5)
        #expect(OnboardingViewLogic.visibleRequests(requests, limit: 5).map(\.number) == [0, 1, 2, 3, 4])
    }

    @Test func visibleRequestsIsEmptyWhenGHHasNotAnsweredYet() {
        #expect(OnboardingViewLogic.visibleRequests(nil, limit: 5).isEmpty)
    }

    @Test func shouldShowListsIsFalseOnlyWhenBothListsAreEmpty() {
        #expect(!OnboardingViewLogic.shouldShowLists(requests: [], recents: []))

        let request = ReviewRequest(
            url: "u", repo: "acme/shop", number: 1, title: "t", author: "a", isDraft: false, updatedAt: nil)
        #expect(OnboardingViewLogic.shouldShowLists(requests: [request], recents: []))

        let recent = AnalysisCache.RecentPR(url: "u", repo: "acme/shop", number: 1, title: "t", lastOpened: Date())
        #expect(OnboardingViewLogic.shouldShowLists(requests: [], recents: [recent]))
    }
}
