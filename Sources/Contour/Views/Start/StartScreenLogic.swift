import Foundation

enum ClipboardOffer: Equatable {
    case pullRequest(String)
    case unreadLink(changeCount: Int)
}

enum StartScreenLogic {
    static let rowsShown = 10

    static func subtitle(repo: String, number: Int, detail: String?, date: Date?, dateVerb: String) -> String {
        var parts = ["\(repo) #\(number)"]
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

    static func shouldShowLists(requests: [ReviewRequest], recents: [AnalysisCache.RecentPR]) -> Bool {
        !requests.isEmpty || !recents.isEmpty
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
