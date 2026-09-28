import Testing
import Foundation
@testable import Contour

/// `AnalyzingView.headline(_:)` was already a plain static function; `PullRequestRow`'s
/// subtitle formatting and `AnalyzingView`'s console-summary formatting were pulled out
/// into `OnboardingViewLogic` / `AnalyzingView.latestDetail(log:stage:)` per CLAUDE.md's
/// guidance for this file, so both are directly testable without a view instance. The rest
/// — the URL field, clipboard offer, PR lists, the analyzing console — is view rendering
/// and clipboard/NSPasteboard interaction with no UI-testing infrastructure in this suite.
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
}
