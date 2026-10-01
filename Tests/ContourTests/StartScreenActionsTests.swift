import Foundation
import Testing

@testable import Contour

@MainActor
struct StartScreenActionsTests {
    @MainActor
    private final class Spawned {
        var operations: [@MainActor () async -> Void] = []

        func runAll() async {
            let pending = operations
            operations = []
            for operation in pending { await operation() }
        }
    }

    private final class Opened {
        var urls: [URL] = []
    }

    private func yield(until condition: () -> Bool) async -> Bool {
        for _ in 0..<10_000 where !condition() { await Task.yield() }
        return condition()
    }

    private func preferences(watching ids: [String] = []) -> Preferences {
        let name = "contour.tests.start.actions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let preferences = Preferences(defaults: defaults, environment: [:])
        preferences.watchedRepositories = ids.compactMap(WatchedRepository.parse)
        return preferences
    }

    private let list = WatchedPullRequestList(
        pullRequests: [
            WatchedPullRequest(
                url: "https://github.com/acme/api/pull/1", number: 1, title: "t", author: "a", isDraft: false,
                createdAt: nil)
        ], hasMore: false, fetchedAt: Date(timeIntervalSince1970: 1_000_000))

    private func model(watching ids: [String] = []) -> StartScreenModel {
        let list = list
        return StartScreenModel(
            preferences: preferences(watching: ids),
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { [] }, loadReviewRequests: { nil }, fetchWatched: { _, _ in .success(list) }))
    }

    private func actions(_ model: StartScreenModel, _ spawned: Spawned, _ opened: Opened = Opened())
        -> StartScreenActions
    {
        StartScreenActions(
            model: model, openURL: { opened.urls.append($0) }, spawn: { spawned.operations.append($0) })
    }

    @Test func watchAddsTheRepositoryOnceTheSpawnedWorkRuns() async {
        let model = model()
        let spawned = Spawned()
        actions(model, spawned).watch("acme/api")
        #expect(model.watched.isEmpty)
        await spawned.runAll()
        #expect(model.watched.map(\.id) == ["acme/api"])
        #expect(model.state(for: "acme/api") == .loaded(list))
    }

    @Test func refreshFetchesThatRepository() async {
        let model = model(watching: ["acme/api"])
        let spawned = Spawned()
        actions(model, spawned).refresh("acme/api")()
        await spawned.runAll()
        #expect(model.state(for: "acme/api") == .loaded(list))
    }

    @Test func refreshStaleFetchesWhatHasNeverBeenFetched() async {
        let model = model(watching: ["acme/api", "acme/web"])
        let spawned = Spawned()
        actions(model, spawned).refreshStale()
        await spawned.runAll()
        #expect(model.state(for: "acme/api") == .loaded(list))
        #expect(model.state(for: "acme/web") == .loaded(list))
    }

    @Test func toggleWatchAddsAndThenRemoves() async {
        let model = model()
        let spawned = Spawned()
        let actions = actions(model, spawned)
        actions.toggleWatch("acme/api")()
        await spawned.runAll()
        #expect(model.isWatched("acme/api"))
        actions.toggleWatch("acme/api")()
        await spawned.runAll()
        #expect(!model.isWatched("acme/api"))
    }

    @Test func aWatchedRepositorysMenuRefreshesOpensAndStopsWatching() async {
        let model = model(watching: ["acme/api"])
        let spawned = Spawned()
        let opened = Opened()
        let repository = WatchedRepository(owner: "acme", name: "api")
        let menu = actions(model, spawned, opened).menu(for: repository)

        #expect(menu.map(\.title) == ["Refresh", "Open Repository on GitHub", "Stop Watching acme/api"])
        #expect(menu.map(\.isDestructive) == [false, false, true])
        #expect(menu.map(\.id) == menu.map(\.title))

        menu[0].action()
        await spawned.runAll()
        #expect(model.state(for: "acme/api") == .loaded(list))

        menu[1].action()
        #expect(opened.urls == [URL(string: "https://github.com/acme/api")!])

        menu[2].action()
        #expect(model.watched.isEmpty)
    }

    @Test func theDefaultSpawnRunsTheWork() async {
        let model = model()
        StartScreenActions(model: model).watch("acme/api")
        #expect(await yield { model.isWatched("acme/api") })
        #expect(await yield { model.state(for: "acme/api")?.list != nil })
        #expect(model.watched.map(\.id) == ["acme/api"])
    }
}
