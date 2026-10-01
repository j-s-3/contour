import Foundation
import Testing
import os

@testable import Contour

@MainActor
struct StartScreenModelWatchingTests {
    private actor Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            for waiter in waiters { waiter.resume() }
            waiters = []
        }
    }

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private typealias Fetch =
        @Sendable (WatchedRepository, GitHubAccessMode) async -> Result<WatchedPullRequestList, WatchedFailure>

    private func preferences(watching ids: [String] = []) -> Preferences {
        let name = "contour.tests.start.watching.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let preferences = Preferences(defaults: defaults, environment: [:])
        preferences.watchedRepositories = ids.compactMap(WatchedRepository.parse)
        return preferences
    }

    nonisolated private func list(_ numbers: [Int], hasMore: Bool = false) -> WatchedPullRequestList {
        WatchedPullRequestList(
            pullRequests: numbers.map {
                WatchedPullRequest(
                    url: "https://github.com/acme/api/pull/\($0)", number: $0, title: "t\($0)", author: "mwright",
                    isDraft: false, createdAt: nil)
            },
            hasMore: hasMore, fetchedAt: Date(timeIntervalSince1970: 1_000_000))
    }

    private func model(
        preferences: Preferences, clock: Clock = Clock(), anonymous: Bool = false,
        recents: [AnalysisCache.RecentPR] = [], requests: [ReviewRequest]? = nil, login: String? = nil,
        fetch: @escaping Fetch
    ) -> StartScreenModel {
        StartScreenModel(
            preferences: preferences,
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { recents }, loadReviewRequests: { requests },
                fetchWatched: fetch, loadViewerLogin: { _ in login },
                usesAnonymousAccess: { _ in anonymous }, now: { clock.now }))
    }

    private func yield(until condition: () -> Bool) async -> Bool {
        for _ in 0..<10_000 where !condition() { await Task.yield() }
        return condition()
    }

    private func counting(_ calls: OSAllocatedUnfairLock<[String]>, returning list: WatchedPullRequestList) -> Fetch {
        { repository, _ in
            calls.withLock { $0.append(repository.id) }
            return .success(list)
        }
    }

    @Test func watchedRepositoriesAreSourcesInTheOrderTheyWereAdded() {
        let model = model(preferences: preferences(watching: ["acme/web", "acme/api"])) { _, _ in
            .failure(.unavailable)
        }
        #expect(model.sources == [.recents, .watched("acme/web"), .watched("acme/api")])
        #expect(!model.showsWelcome)
    }

    @Test func watchingAddsSelectsStoresAndFetches() async {
        let prefs = preferences()
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let model = model(preferences: prefs, fetch: counting(calls, returning: list([1, 2])))
        #expect(await model.watch("https://github.com/acme/api/pull/9"))
        #expect(model.watched.map(\.id) == ["acme/api"])
        #expect(prefs.watchedRepositories.map(\.id) == ["acme/api"])
        #expect(model.selection == .watched("acme/api"))
        #expect(prefs.lastStartSource == .watched("acme/api"))
        #expect(model.state(for: "acme/api") == .loaded(list([1, 2])))
        #expect(model.count(for: .watched("acme/api")) == "2")
        #expect(calls.withLock { $0 } == ["acme/api"])
    }

    @Test func inputThatNamesNoRepositoryChangesNothing() async {
        let prefs = preferences()
        let model = model(preferences: prefs) { _, _ in
            Issue.record("nothing should be fetched")
            return .failure(.unavailable)
        }
        #expect(await model.watch("--flag/x") == false)
        #expect(model.watched.isEmpty)
        #expect(prefs.watchedRepositories.isEmpty)
    }

    @Test func watchingTheSameRepositoryInAnotherCaseSelectsTheExistingEntry() async {
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let model = model(
            preferences: preferences(watching: ["Acme/API", "acme/web"]),
            fetch: counting(calls, returning: list([1])))
        model.select(.recents)
        #expect(await model.watch("acme/api"))
        #expect(model.watched.map(\.id) == ["Acme/API", "acme/web"])
        #expect(model.selection == .watched("Acme/API"))
        #expect(calls.withLock { $0 }.isEmpty)
    }

    @Test func isWatchedIgnoresCaseAndNothingIsWatchedWithoutAName() {
        let model = model(preferences: preferences(watching: ["Acme/API"])) { _, _ in .failure(.unavailable) }
        #expect(model.isWatched("acme/api"))
        #expect(!model.isWatched("acme/web"))
        #expect(!model.isWatched(nil))
    }

    @Test func stopWatchingRemovesTheRepositoryItsListAndItsSelection() async {
        let prefs = preferences(watching: ["acme/api", "acme/web"])
        let model = model(preferences: prefs, requests: []) { _, _ in .success(self.list([1])) }
        model.loadRecents()
        await model.loadRemoteSources()
        model.select(.watched("acme/api"))
        model.stopWatching("ACME/api")
        #expect(model.watched.map(\.id) == ["acme/web"])
        #expect(prefs.watchedRepositories.map(\.id) == ["acme/web"])
        #expect(model.state(for: "acme/api") == nil)
        #expect(model.selection == .reviewRequests)
        #expect(prefs.lastStartSource == nil)
    }

    @Test func stopWatchingAnotherRepositoryLeavesTheSelectionAlone() {
        let model = model(preferences: preferences(watching: ["acme/api", "acme/web"])) { _, _ in
            .failure(.unavailable)
        }
        model.select(.watched("acme/web"))
        model.stopWatching("acme/api")
        #expect(model.selection == .watched("acme/web"))
    }

    @Test func toggleWatchAddsThenRemoves() async {
        let model = model(preferences: preferences()) { _, _ in .success(self.list([1])) }
        await model.toggleWatch("acme/api")
        #expect(model.isWatched("acme/api"))
        await model.toggleWatch("acme/api")
        #expect(!model.isWatched("acme/api"))
    }

    @Test func reloadFetchesEveryWatchedRepositoryAndTheViewerOnce() async {
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let logins = OSAllocatedUnfairLock<Int>(initialState: 0)
        let prefs = preferences(watching: ["acme/api", "acme/web"])
        let model = StartScreenModel(
            preferences: prefs,
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { [] }, loadReviewRequests: { [] },
                fetchWatched: counting(calls, returning: list([1])),
                loadViewerLogin: { _ in
                    logins.withLock { $0 += 1 }
                    return "jstephens"
                },
                usesAnonymousAccess: { _ in false }, now: { Date(timeIntervalSince1970: 1_000_000) }))
        model.loadRecents()
        await model.loadRemoteSources()
        model.loadRecents()
        await model.loadRemoteSources()
        #expect(Set(calls.withLock { $0 }) == ["acme/api", "acme/web"])
        #expect(calls.withLock { $0 }.count == 2)
        #expect(model.viewerLogin == "jstephens")
        #expect(logins.withLock { $0 } == 1)
    }

    @Test func aCancelledWatchedFetchKeepsNothingAndIsRetriedNextTime() async {
        let gate = Gate()
        let calls = OSAllocatedUnfairLock<Int>(initialState: 0)
        let model = model(preferences: preferences(watching: ["acme/api"])) { _, _ in
            calls.withLock { $0 += 1 }
            await gate.wait()
            return .failure(.unavailable)
        }
        let first = Task { await model.refresh("acme/api") }
        #expect(await yield { model.state(for: "acme/api") != nil })
        first.cancel()
        await gate.open()
        await first.value
        #expect(model.state(for: "acme/api") == nil)
        await model.refreshWatched(force: false)
        #expect(calls.withLock { $0 } == 2)
        #expect(model.state(for: "acme/api") == .failed(.unavailable, keeping: nil))
    }

    @Test func aCancelledRemoteLoadLeavesTheReviewRequestsAlone() async {
        let gate = Gate()
        let prefs = preferences()
        let model = StartScreenModel(
            preferences: prefs,
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { [] },
                loadReviewRequests: {
                    await gate.wait()
                    return []
                }))
        let loading = Task { await model.loadRemoteSources() }
        loading.cancel()
        await gate.open()
        await loading.value
        #expect(model.reviewRequests == nil)
    }

    @Test func aFreshListIsNotFetchedAgainUntilItGoesStale() async {
        let clock = Clock()
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let model = model(
            preferences: preferences(watching: ["acme/api"]), clock: clock,
            fetch: counting(calls, returning: list([1])))
        await model.refreshWatched(force: false)
        clock.now += 119
        await model.refreshWatched(force: false)
        #expect(calls.withLock { $0 }.count == 1)
        clock.now += 1
        await model.refreshWatched(force: false)
        #expect(calls.withLock { $0 }.count == 2)
    }

    @Test func anonymousListsStayFreshForTenMinutes() async {
        let clock = Clock()
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let model = model(
            preferences: preferences(watching: ["acme/api"]), clock: clock, anonymous: true,
            fetch: counting(calls, returning: list([1])))
        await model.refreshWatched(force: false)
        clock.now += 599
        await model.refreshWatched(force: false)
        #expect(calls.withLock { $0 }.count == 1)
        clock.now += 1
        await model.refreshWatched(force: false)
        #expect(calls.withLock { $0 }.count == 2)
    }

    @Test func aFailedAttemptAlsoCountsAsFreshSoItIsNotRetriedOnEveryActivation() async {
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let model = model(preferences: preferences(watching: ["acme/api"])) { repository, _ in
            calls.withLock { $0.append(repository.id) }
            return .failure(.notFound)
        }
        await model.refreshWatched(force: false)
        await model.refreshWatched(force: false)
        #expect(calls.withLock { $0 }.count == 1)
        #expect(model.count(for: .watched("acme/api")) == "!")
    }

    @Test func forcingAndRefreshingOneRepositoryAlwaysFetch() async {
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let model = model(
            preferences: preferences(watching: ["acme/api", "acme/web"]),
            fetch: counting(calls, returning: list([1])))
        await model.refreshWatched(force: false)
        await model.refreshWatched(force: true)
        await model.refresh("acme/web")
        await model.refresh("acme/unknown")
        #expect(calls.withLock { $0 }.count == 5)
        #expect(calls.withLock { $0 }.last == "acme/web")
    }

    @Test func oneRepositoryFailingLeavesTheOthersListed() async {
        let model = model(preferences: preferences(watching: ["acme/api", "acme/vault"])) { repository, _ in
            repository.name == "vault" ? .failure(.notFound) : .success(self.list([1, 2]))
        }
        await model.refreshWatched(force: false)
        #expect(model.state(for: "acme/api") == .loaded(list([1, 2])))
        #expect(model.state(for: "acme/vault") == .failed(.notFound, keeping: nil))
    }

    @Test func aFailedRefreshKeepsTheRowsAlreadyShown() async {
        let fails = OSAllocatedUnfairLock<Bool>(initialState: false)
        let model = model(preferences: preferences(watching: ["acme/api"])) { _, _ in
            fails.withLock { $0 } ? .failure(.unavailable) : .success(self.list([1, 2]))
        }
        await model.refresh("acme/api")
        fails.withLock { $0 = true }
        await model.refresh("acme/api")
        #expect(model.state(for: "acme/api") == .failed(.unavailable, keeping: list([1, 2])))
    }

    @Test func aRepositoryShowsLoadingOnlyUntilItsFirstAnswer() async {
        let gate = Gate()
        let model = model(preferences: preferences(watching: ["acme/api"])) { _, _ in
            await gate.wait()
            return .success(self.list([1]))
        }
        let refreshing = Task { await model.refresh("acme/api") }
        #expect(await yield { model.state(for: "acme/api") != nil })
        #expect(model.state(for: "acme/api") == .loading)
        await gate.open()
        await refreshing.value
        #expect(model.state(for: "acme/api") == .loaded(list([1])))
    }

    @Test func aRepositoryRemovedWhileItsFetchIsInFlightLeavesNoStateBehind() async {
        let gate = Gate()
        let prefs = preferences()
        let model = model(preferences: prefs) { _, _ in
            await gate.wait()
            return .success(self.list([1]))
        }
        let adding = Task { await model.watch("acme/api") }
        #expect(await yield { model.state(for: "acme/api") != nil })
        model.stopWatching("acme/api")
        await gate.open()
        _ = await adding.value
        #expect(model.watched.isEmpty)
        #expect(model.state(for: "acme/api") == nil)
        #expect(model.sources == [.recents])
        #expect(prefs.watchedRepositories.isEmpty)
    }

    @Test func aListOfOnlyBotsHasNoCountAndIsNotTheWelcome() async {
        let model = model(preferences: preferences(watching: ["acme/api"])) { _, _ in
            .success(self.list([], hasMore: true))
        }
        await model.refreshWatched(force: false)
        #expect(model.count(for: .watched("acme/api")) == nil)
        #expect(!model.showsWelcome)
    }

    @Test func labelsUseTheViewerAndTheLoadedReviewRequests() async {
        let requested = ReviewRequest(
            url: "u", repo: "acme/api", number: 2, title: "t", author: "a", isDraft: false, updatedAt: nil)
        let model = model(
            preferences: preferences(watching: ["acme/api"]), requests: [requested], login: "mwright"
        ) { _, _ in .success(self.list([1, 2])) }
        model.loadRecents()
        await model.loadRemoteSources()
        let rows = model.state(for: "acme/api")?.list?.pullRequests ?? []
        #expect(rows.map { model.labels(for: $0, in: "acme/api") } == [["yours"], ["yours", "review requested"]])
    }

    @Test func theViewerIsNeverYoursUnderAnonymousAccess() async {
        let requested = ReviewRequest(
            url: "u", repo: "acme/api", number: 2, title: "t", author: "a", isDraft: false, updatedAt: nil)
        let model = model(
            preferences: preferences(watching: ["acme/api"]), anonymous: true, requests: [requested],
            login: "mwright"
        ) { _, _ in .success(self.list([1, 2])) }
        await model.loadRemoteSources()
        let rows = model.state(for: "acme/api")?.list?.pullRequests ?? []
        #expect(rows.map { model.labels(for: $0, in: "acme/api") } == [[], ["review requested"]])
    }

    @Test func retryingAFailureWithNoRowsShowsAsFetchingUntilTheAnswerLands() async {
        let gate = Gate()
        let gated = OSAllocatedUnfairLock<Bool>(initialState: false)
        let model = model(preferences: preferences(watching: ["acme/api"])) { _, _ in
            if gated.withLock({ $0 }) { await gate.wait() }
            return .failure(.unavailable)
        }
        await model.refresh("acme/api")
        #expect(model.state(for: "acme/api") == .failed(.unavailable, keeping: nil))
        #expect(!model.isFetching("acme/api"))
        gated.withLock { $0 = true }
        let retrying = Task { await model.refresh("acme/api") }
        #expect(await yield { model.isFetching("acme/api") })
        #expect(model.state(for: "acme/api") == .failed(.unavailable, keeping: nil))
        await gate.open()
        await retrying.value
        #expect(!model.isFetching("acme/api"))
    }

    @Test func overlappingFetchesOfOneRepositoryStayFetchingUntilBothLand() async {
        let gate = Gate()
        let model = model(preferences: preferences(watching: ["acme/api"])) { _, _ in
            await gate.wait()
            return .success(self.list([1]))
        }
        let first = Task { await model.refresh("acme/api") }
        let second = Task { await model.refresh("acme/api") }
        #expect(await yield { model.state(for: "acme/api") == .loading })
        #expect(model.isFetching("acme/api"))
        await gate.open()
        await first.value
        await second.value
        #expect(!model.isFetching("acme/api"))
    }

    @Test func failureMessagesSayWhetherAccessIsAnonymous() {
        let anonymous = model(preferences: preferences(), anonymous: true) { _, _ in .failure(.notFound) }
        let signedIn = model(preferences: preferences(), anonymous: false) { _, _ in .failure(.notFound) }
        #expect(
            anonymous.failureMessage(for: .notFound, repository: "acme/api")
                == WatchedPullRequests.message(for: .notFound, repository: "acme/api", anonymous: true))
        #expect(
            signedIn.failureMessage(for: .notFound, repository: "acme/api")
                == WatchedPullRequests.message(for: .notFound, repository: "acme/api", anonymous: false))
    }

    @Test func suggestionsComeFromLoadedRecentsAndLeaveOutWatchedRepositories() async {
        let recents = [
            AnalysisCache.RecentPR(url: "u", repo: "acme/api", number: 1, title: "t", lastOpened: Date()),
            AnalysisCache.RecentPR(url: "u", repo: "acme/web", number: 2, title: "t", lastOpened: Date()),
        ]
        let model = model(preferences: preferences(watching: ["acme/api"]), recents: recents) { _, _ in
            .success(self.list([1]))
        }
        model.loadRecents()
        await model.loadRemoteSources()
        #expect(model.suggestions == ["acme/web"])
    }

    @Test func liveDependenciesChooseAnonymousAccessWhenToldTo() {
        let live = StartScreenModel.Dependencies.live
        #expect(live.usesAnonymousAccess(.anonymous))
        #expect(live.now() <= Date())
    }
}
