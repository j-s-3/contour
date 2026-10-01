import Foundation

enum ClipboardOffer: Equatable {
    case pullRequest(String)
    case unreadLink(changeCount: Int)
}

enum WatchedLoadState: Equatable, Sendable {
    case loading
    case loaded(WatchedPullRequestList)
    case failed(WatchedFailure, keeping: WatchedPullRequestList?)

    var list: WatchedPullRequestList? {
        switch self {
        case .loading: return nil
        case .loaded(let list): return list
        case .failed(_, let kept): return kept
        }
    }

    var failure: WatchedFailure? {
        if case .failed(let failure, _) = self { return failure }
        return nil
    }
}

enum StartScreenLogic {
    static let rowsShown = 10
    static let freshForGH: TimeInterval = 120
    static let freshAnonymously: TimeInterval = 600
    static let suggestionLimit = 5

    static func isFresh(lastAttempt: Date?, now: Date, anonymous: Bool) -> Bool {
        guard let lastAttempt else { return false }
        return now.timeIntervalSince(lastAttempt) < (anonymous ? freshAnonymously : freshForGH)
    }

    static func state(
        after result: Result<WatchedPullRequestList, WatchedFailure>, previous: WatchedLoadState?
    ) -> WatchedLoadState {
        switch result {
        case .success(let list): return .loaded(list)
        case .failure(let failure): return .failed(failure, keeping: previous?.list)
        }
    }

    static func count(_ state: WatchedLoadState?) -> String? {
        switch state {
        case .none, .loading:
            return nil
        case .failed:
            return "!"
        case .loaded(let list):
            guard let rows = count(rows: list.pullRequests.count) else { return nil }
            return list.hasMore ? "\(rows)+" : rows
        }
    }

    static func labels(
        for pullRequest: WatchedPullRequest, repository: String, viewerLogin: String?,
        reviewRequests: [ReviewRequest]
    ) -> [String] {
        var labels: [String] = []
        if pullRequest.isDraft { labels.append("draft") }
        if let viewerLogin, pullRequest.author.caseInsensitiveCompare(viewerLogin) == .orderedSame {
            labels.append("yours")
        }
        let requested = reviewRequests.contains {
            $0.number == pullRequest.number && $0.repo.caseInsensitiveCompare(repository) == .orderedSame
        }
        if requested { labels.append("review requested") }
        return labels
    }

    static func suggestions(
        recents: [AnalysisCache.RecentPR], watched: [WatchedRepository], limit: Int = suggestionLimit
    ) -> [String] {
        var seen: Set<String> = []
        var suggestions: [String] = []
        for recent in recents {
            guard let repository = WatchedRepository.parse(recent.repo),
                !watched.contains(where: { $0.matches(repository.id) }),
                seen.insert(repository.id.lowercased()).inserted
            else { continue }
            suggestions.append(repository.id)
        }
        return Array(suggestions.prefix(limit))
    }

    static func canWatch(_ input: String) -> Bool {
        WatchedRepository.parse(input) != nil
    }

    static func emptyMessage(for list: WatchedPullRequestList) -> String {
        list.hasMore
            ? "The newest \(WatchedPullRequests.fetchLimit) open pull requests are all automated."
            : "No open pull requests."
    }

    static func fetchedLabel(_ date: Date) -> String {
        "updated \(date.formatted(.relative(presentation: .named)))"
    }

    static func subtitle(repo: String?, number: Int, detail: String?, date: Date?, dateVerb: String) -> String {
        var parts = [repo.map { "\($0) #\(number)" } ?? "#\(number)"]
        if let detail { parts.append(detail) }
        if let date { parts.append("\(dateVerb) \(date.formatted(.relative(presentation: .named)))") }
        return parts.joined(separator: " · ")
    }

    static func isDeclined(changeCount: Int, declinedChangeCount: Int?) -> Bool {
        changeCount == declinedChangeCount
    }

    static func offer(fromReadableClipboardText text: String?) -> ClipboardOffer? {
        text.flatMap(PRLink.extract(from:)).map(ClipboardOffer.pullRequest)
    }

    static func offer(detectedProbableWebURL: Bool, changeCount: Int) -> ClipboardOffer? {
        detectedProbableWebURL ? .unreadLink(changeCount: changeCount) : nil
    }

    enum ClipboardReadAction: Equatable {
        case open(String)
        case fillField(String)
        case doNothing
    }

    static func resolveClipboardRead(_ clip: String?) -> ClipboardReadAction {
        guard let clip else { return .doNothing }
        if let url = PRLink.extract(from: clip) { return .open(url) }
        return .fillField(clip)
    }

    static func perform(_ action: ClipboardReadAction, open: (String) -> Void, fillField: (String) -> Void) {
        switch action {
        case .open(let url): open(url)
        case .fillField(let text): fillField(text)
        case .doNothing: break
        }
    }

    static func resolvedPasteText(_ text: String) -> String {
        PRLink.extract(from: text) ?? text
    }

    static func visibleRequests(_ requests: [ReviewRequest]?, limit: Int) -> [ReviewRequest] {
        Array((requests ?? []).prefix(limit))
    }

    static func sources(reviewRequestsAvailable: Bool, watched: [String]) -> [StartSource] {
        var sources: [StartSource] = []
        if reviewRequestsAvailable { sources.append(.reviewRequests) }
        sources.append(.recents)
        sources += watched.map(StartSource.watched)
        return sources
    }

    static func resolvedSelection(remembered: StartSource?, sources: [StartSource]) -> StartSource {
        if let remembered, sources.contains(remembered) { return remembered }
        return sources.first ?? .recents
    }

    static func showsWelcome(
        requests: [ReviewRequest], recents: [AnalysisCache.RecentPR], watchedCount: Int
    ) -> Bool {
        requests.isEmpty && recents.isEmpty && watchedCount == 0
    }

    static func title(for source: StartSource) -> String {
        switch source {
        case .reviewRequests: return "Awaiting your review"
        case .recents: return "Recently opened"
        case .watched(let id): return id
        }
    }

    static func symbol(for source: StartSource) -> String {
        switch source {
        case .reviewRequests: return "person.crop.circle.badge.questionmark"
        case .recents: return "clock.arrow.circlepath"
        case .watched: return "eye"
        }
    }

    static func emptyMessage(for source: StartSource) -> String {
        switch source {
        case .reviewRequests: return "Nothing is waiting for your review."
        case .recents: return "Pull requests you open will appear here."
        case .watched: return "No open pull requests."
        }
    }

    static func count(rows: Int) -> String? {
        rows > 0 ? String(rows) : nil
    }
}
