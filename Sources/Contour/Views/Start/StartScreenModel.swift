import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class StartScreenModel {
    typealias WatchedFetch =
        @Sendable (WatchedRepository, GitHubAccessMode) async -> Result<WatchedPullRequestList, WatchedFailure>

    struct Dependencies {
        var loadRecents: () -> [AnalysisCache.RecentPR]
        var loadReviewRequests: @MainActor () async -> [ReviewRequest]?
        var fetchWatched: WatchedFetch = { _, _ in .failure(.unavailable) }
        var loadViewerLogin: @Sendable (GitHubAccessMode) async -> String? = { _ in nil }
        var usesAnonymousAccess: (GitHubAccessMode) -> Bool = { $0 == .anonymous }
        var now: () -> Date = { Date() }

        @MainActor static var live: Dependencies {
            let service = WatchedPullRequests()
            return Dependencies(
                loadRecents: { AnalysisCache().recentPRs(limit: StartScreenLogic.rowsShown) },
                loadReviewRequests: {
                    await ReviewRequests.fetch(access: Preferences.shared.resolvedGitHubAccess)
                },
                fetchWatched: { await service.fetch($0, access: $1) },
                loadViewerLogin: { await service.viewerLogin(access: $0) },
                usesAnonymousAccess: {
                    WatchedPullRequests.transport(access: $0, ghAvailable: Shell.which("gh") != nil) == .rest
                },
                now: { Date() })
        }
    }

    private(set) var recents: [AnalysisCache.RecentPR] = []
    private(set) var reviewRequests: [ReviewRequest]?
    private(set) var watched: [WatchedRepository]
    private(set) var viewerLogin: String?
    private var states: [String: WatchedLoadState] = [:]
    private var remembered: StartSource?

    @ObservationIgnored private var lastAttempts: [String: Date] = [:]
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let dependencies: Dependencies

    init(preferences: Preferences, dependencies: Dependencies) {
        self.preferences = preferences
        self.dependencies = dependencies
        watched = preferences.watchedRepositories
        remembered = preferences.lastStartSource
    }

    var visibleReviewRequests: [ReviewRequest] {
        StartScreenLogic.visibleRequests(reviewRequests, limit: StartScreenLogic.rowsShown)
    }

    var sources: [StartSource] {
        StartScreenLogic.sources(reviewRequestsAvailable: reviewRequests != nil, watched: watched.map(\.id))
    }

    var selection: StartSource {
        StartScreenLogic.resolvedSelection(remembered: remembered, sources: sources)
    }

    var selectionBinding: Binding<StartSource?> {
        Binding(
            get: { self.selection },
            set: { if let source = $0 { self.select(source) } }
        )
    }

    var showsWelcome: Bool {
        StartScreenLogic.showsWelcome(
            requests: visibleReviewRequests, recents: recents, watchedCount: watched.count)
    }

    var suggestions: [String] {
        StartScreenLogic.suggestions(recents: recents, watched: watched)
    }

    func select(_ source: StartSource) {
        remembered = source
        preferences.lastStartSource = source
    }

    func count(for source: StartSource) -> String? {
        switch source {
        case .reviewRequests: return StartScreenLogic.count(rows: visibleReviewRequests.count)
        case .recents: return nil
        case .watched(let id): return StartScreenLogic.count(states[id])
        }
    }

    func state(for id: String) -> WatchedLoadState? { states[id] }

    func isWatched(_ id: String?) -> Bool {
        guard let id else { return false }
        return watched.contains { $0.matches(id) }
    }

    func labels(for pullRequest: WatchedPullRequest, in repository: String) -> [String] {
        StartScreenLogic.labels(
            for: pullRequest, repository: repository, viewerLogin: viewerLogin,
            reviewRequests: reviewRequests ?? [])
    }

    func failureMessage(for failure: WatchedFailure, repository: String) -> String {
        WatchedPullRequests.message(
            for: failure, repository: repository,
            anonymous: dependencies.usesAnonymousAccess(preferences.resolvedGitHubAccess))
    }

    func loadRecents() {
        recents = dependencies.loadRecents()
    }

    func loadReviewRequests() async {
        let result = await dependencies.loadReviewRequests()
        guard !Task.isCancelled else { return }
        reviewRequests = result
    }

    func loadRemoteSources() async {
        async let refreshing: Void = refreshWatched(force: false)
        await loadReviewRequests()
        if viewerLogin == nil {
            let login = await dependencies.loadViewerLogin(preferences.resolvedGitHubAccess)
            if !Task.isCancelled { viewerLogin = login }
        }
        await refreshing
    }

    @discardableResult
    func watch(_ input: String) async -> Bool {
        guard let repository = WatchedRepository.parse(input) else { return false }
        if let existing = watched.first(where: { $0.matches(repository.id) }) {
            select(.watched(existing.id))
            return true
        }
        watched.append(repository)
        preferences.watchedRepositories = watched
        select(.watched(repository.id))
        await refresh(repository.id)
        return true
    }

    func stopWatching(_ id: String) {
        guard let repository = watched.first(where: { $0.matches(id) }) else { return }
        watched.removeAll { $0.id == repository.id }
        preferences.watchedRepositories = watched
        states[repository.id] = nil
        lastAttempts[repository.id] = nil
        if remembered == .watched(repository.id) {
            remembered = nil
            preferences.lastStartSource = nil
        }
    }

    func toggleWatch(_ id: String) async {
        if isWatched(id) {
            stopWatching(id)
        } else {
            await watch(id)
        }
    }

    func refresh(_ id: String) async {
        guard let repository = watched.first(where: { $0.matches(id) }) else { return }
        await fetch([repository])
    }

    func refreshWatched(force: Bool) async {
        let anonymous = dependencies.usesAnonymousAccess(preferences.resolvedGitHubAccess)
        let moment = dependencies.now()
        await fetch(
            watched.filter {
                force || !StartScreenLogic.isFresh(lastAttempt: lastAttempts[$0.id], now: moment, anonymous: anonymous)
            })
    }

    private func fetch(_ repositories: [WatchedRepository]) async {
        let access = preferences.resolvedGitHubAccess
        let fetchWatched = dependencies.fetchWatched
        let moment = dependencies.now()
        for repository in repositories {
            lastAttempts[repository.id] = moment
            if states[repository.id] == nil { states[repository.id] = .loading }
        }
        await withTaskGroup(of: (String, Result<WatchedPullRequestList, WatchedFailure>).self) { group in
            for repository in repositories {
                group.addTask { (repository.id, await fetchWatched(repository, access)) }
            }
            for await (id, result) in group where watched.contains(where: { $0.id == id }) {
                if Task.isCancelled {
                    lastAttempts[id] = nil
                    if states[id] == .loading { states[id] = nil }
                    continue
                }
                states[id] = StartScreenLogic.state(after: result, previous: states[id])
            }
        }
    }
}
