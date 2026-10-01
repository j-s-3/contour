import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class StartScreenModel {
    struct Dependencies {
        var loadRecents: () -> [AnalysisCache.RecentPR]
        var loadReviewRequests: @MainActor () async -> [ReviewRequest]?

        @MainActor static var live: Dependencies {
            Dependencies(
                loadRecents: { AnalysisCache().recentPRs(limit: StartScreenLogic.rowsShown) },
                loadReviewRequests: {
                    await ReviewRequests.fetch(access: Preferences.shared.resolvedGitHubAccess)
                })
        }
    }

    private(set) var recents: [AnalysisCache.RecentPR] = []
    private(set) var reviewRequests: [ReviewRequest]?
    private var remembered: StartSource?

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let dependencies: Dependencies

    init(preferences: Preferences, dependencies: Dependencies) {
        self.preferences = preferences
        self.dependencies = dependencies
        remembered = preferences.lastStartSource
    }

    var visibleReviewRequests: [ReviewRequest] {
        StartScreenLogic.visibleRequests(reviewRequests, limit: StartScreenLogic.rowsShown)
    }

    var sources: [StartSource] {
        StartScreenLogic.sources(reviewRequestsAvailable: reviewRequests != nil, watched: [])
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
        StartScreenLogic.showsWelcome(requests: visibleReviewRequests, recents: recents, watchedCount: 0)
    }

    func select(_ source: StartSource) {
        remembered = source
        preferences.lastStartSource = source
    }

    func count(for source: StartSource) -> String? {
        switch source {
        case .reviewRequests: return StartScreenLogic.count(rows: visibleReviewRequests.count)
        case .recents, .watched: return nil
        }
    }

    func loadRecents() {
        recents = dependencies.loadRecents()
    }

    func loadReviewRequests() async {
        let result = await dependencies.loadReviewRequests()
        guard !Task.isCancelled else { return }
        reviewRequests = result
    }
}
