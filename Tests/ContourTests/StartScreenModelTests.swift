import Foundation
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct StartScreenModelTests {
    private func preferences() -> Preferences {
        let name = "contour.tests.start.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Preferences(defaults: defaults, environment: [:])
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

    private func model(
        preferences: Preferences, recents: [AnalysisCache.RecentPR] = [], requests: [ReviewRequest]? = nil
    ) -> StartScreenModel {
        StartScreenModel(
            preferences: preferences,
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { recents }, loadReviewRequests: { requests }))
    }

    @Test func beforeAnythingLoadsTheOnlySourceIsRecentlyOpened() {
        let model = model(preferences: preferences(), requests: [request(1)])
        #expect(model.sources == [.recents])
        #expect(model.selection == .recents)
        #expect(model.showsWelcome)
    }

    @Test func loadRecentsFillsRecentsWithoutAskingGH() {
        var requestLoads = 0
        let model = StartScreenModel(
            preferences: preferences(),
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { [recent(1)] },
                loadReviewRequests: {
                    requestLoads += 1
                    return [request(1)]
                }))
        model.loadRecents()
        #expect(model.recents.map(\.number) == [1])
        #expect(model.reviewRequests == nil)
        #expect(requestLoads == 0)
        #expect(!model.showsWelcome)
    }

    @Test func reviewRequestsBecomeASourceOnceGHAnswers() async {
        let model = model(preferences: preferences(), recents: [recent(1)], requests: [])
        await model.reload()
        #expect(model.sources == [.reviewRequests, .recents])
        #expect(model.recents.map(\.number) == [1])
    }

    @Test func whenGHCannotAnswerReviewRequestsAreNotASource() async {
        let model = model(preferences: preferences(), recents: [recent(1)], requests: nil)
        await model.reload()
        #expect(model.sources == [.recents])
        #expect(model.visibleReviewRequests.isEmpty)
    }

    @Test func withNothingRememberedSelectionPrefersReviewRequests() async {
        let model = model(preferences: preferences(), recents: [recent(1)], requests: [request(1)])
        await model.reload()
        #expect(model.selection == .reviewRequests)
    }

    @Test func aChosenSourceIsRememberedByTheNextModel() async {
        let prefs = preferences()
        let first = model(preferences: prefs, recents: [recent(1)], requests: [request(1)])
        await first.reload()
        first.select(.recents)
        #expect(first.selection == .recents)

        let second = model(preferences: prefs, recents: [recent(1)], requests: [request(1)])
        await second.reload()
        #expect(second.selection == .recents)
    }

    @Test func aRememberedSourceThatNoLongerExistsFallsBack() async {
        let prefs = preferences()
        prefs.lastStartSource = .watched("acme/gone")
        let model = model(preferences: prefs, recents: [recent(1)], requests: [request(1)])
        await model.reload()
        #expect(model.selection == .reviewRequests)
    }

    @Test func aRememberedReviewRequestSelectionReturnsOnceGHAnswers() async {
        let prefs = preferences()
        prefs.lastStartSource = .reviewRequests
        let model = model(preferences: prefs, recents: [recent(1)], requests: [request(1)])
        #expect(model.selection == .recents)
        await model.reload()
        #expect(model.selection == .reviewRequests)
    }

    @Test func welcomeGivesWayAsSoonAsAnySourceHasRows() async {
        let model = model(preferences: preferences(), recents: [recent(1)], requests: nil)
        await model.reload()
        #expect(!model.showsWelcome)
    }

    @Test func reviewRequestsAreCappedAtTenAndCounted() async {
        let model = model(preferences: preferences(), requests: (1...14).map(request))
        await model.reload()
        #expect(model.visibleReviewRequests.count == 10)
        #expect(model.count(for: .reviewRequests) == "10")
        #expect(model.count(for: .recents) == nil)
        #expect(model.count(for: .watched("acme/api")) == nil)
    }

    @Test func theSelectionBindingReadsAndWritesTheSelection() async {
        let model = model(preferences: preferences(), recents: [recent(1)], requests: [request(1)])
        await model.reload()
        let binding = model.selectionBinding
        #expect(binding.wrappedValue == .reviewRequests)
        binding.wrappedValue = .recents
        #expect(model.selection == .recents)
        binding.wrappedValue = nil
        #expect(model.selection == .recents)
    }

    @Test func liveDependenciesReadTheRealSources() async {
        let live = StartScreenModel.Dependencies.live
        #expect(live.loadRecents().count <= StartScreenLogic.rowsShown)
    }
}
