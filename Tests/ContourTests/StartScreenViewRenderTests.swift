import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct StartScreenViewRenderTests {
    private func render<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 1080, height: 720)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private struct NamespaceHost<Content: View>: View {
        @Namespace var ns
        let content: (Namespace.ID) -> Content
        var body: some View { content(ns) }
    }

    private func preferences() -> Preferences {
        let name = "contour.tests.start.render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Preferences(defaults: defaults, environment: [:])
    }

    private func requests() -> [ReviewRequest] {
        [
            ReviewRequest(
                url: "u1", repo: "acme/shop", number: 1, title: "t1", author: "a", isDraft: true, updatedAt: Date()),
            ReviewRequest(
                url: "u2", repo: "acme/shop", number: 2, title: "t2", author: "b", isDraft: false, updatedAt: nil),
        ]
    }

    private func recents() -> [AnalysisCache.RecentPR] {
        [AnalysisCache.RecentPR(url: "u3", repo: "acme/shop", number: 3, title: "t3", lastOpened: Date())]
    }

    private func loaded(
        recents: [AnalysisCache.RecentPR], requests: [ReviewRequest]?, selecting source: StartSource? = nil,
        watching: [String] = [],
        fetch: @escaping StartScreenModel.WatchedFetch = { _, _ in .failure(.unavailable) }
    ) async -> StartScreenModel {
        let prefs = preferences()
        prefs.watchedRepositories = watching.compactMap(WatchedRepository.parse)
        let model = StartScreenModel(
            preferences: prefs,
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { recents }, loadReviewRequests: { requests }, fetchWatched: fetch))
        model.loadRecents()
        await model.loadRemoteSources()
        if let source { model.select(source) }
        return model
    }

    private func watchedList(_ count: Int, hasMore: Bool = false) -> WatchedPullRequestList {
        WatchedPullRequestList(
            pullRequests: count == 0
                ? []
                : (1...count).map {
                    WatchedPullRequest(
                        url: "https://github.com/acme/api/pull/\($0)", number: $0, title: "t\($0)",
                        author: "mwright", isDraft: $0 == 1, createdAt: Date())
                },
            hasMore: hasMore, fetchedAt: Date())
    }

    @Test func theWelcomeLaysOutWhenNothingIsListed() async {
        let model = await loaded(recents: [], requests: nil)
        #expect(model.showsWelcome)
        _ = render(NamespaceHost { StartScreenView(model: model, markNamespace: $0, onSubmit: { _ in }) })
    }

    @Test func theBrowserLaysOutForEachSource() async {
        for source in [StartSource.reviewRequests, .recents] {
            let model = await loaded(recents: recents(), requests: requests(), selecting: source)
            _ = render(
                NamespaceHost {
                    StartScreenView(
                        model: model, initialURL: "https://github.com/acme/shop/pull/1", markNamespace: $0,
                        focusRequest: 2, onSubmit: { _ in })
                })
        }
    }

    @Test func eachSourceListLaysOutWithAndWithoutRows() async {
        let full = await loaded(recents: recents(), requests: requests(), selecting: .reviewRequests)
        let fullActions = StartScreenActions(model: full)
        #expect(render(StartSourceList(model: full, actions: fullActions, onOpen: { _ in })).height > 0)
        full.select(.recents)
        #expect(render(StartSourceList(model: full, actions: fullActions, onOpen: { _ in })).height > 0)

        let empty = await loaded(recents: [], requests: [], selecting: .reviewRequests)
        let emptyActions = StartScreenActions(model: empty)
        #expect(render(StartSourceList(model: empty, actions: emptyActions, onOpen: { _ in })).height > 0)
        empty.select(.recents)
        #expect(render(StartSourceList(model: empty, actions: emptyActions, onOpen: { _ in })).height > 0)
    }

    @Test func theSidebarLaysOutWithAndWithoutTheMark() async {
        let welcome = await loaded(recents: [], requests: nil)
        let browsing = await loaded(recents: recents(), requests: requests())
        for model in [welcome, browsing] {
            _ = render(
                NamespaceHost {
                    StartSidebar(model: model, actions: StartScreenActions(model: model), markNamespace: $0)
                })
        }
    }

    @Test func theBrowserLaysOutWithAWatchedRepositorySelected() async {
        let list = watchedList(10, hasMore: true)
        let model = await loaded(
            recents: recents(), requests: requests(), selecting: .watched("acme/api"),
            watching: ["acme/api", "acme/web"], fetch: { _, _ in .success(list) })
        #expect(model.count(for: .watched("acme/api")) == "10+")
        _ = render(NamespaceHost { StartScreenView(model: model, markNamespace: $0, onSubmit: { _ in }) })
        _ = render(
            StartSourceList(model: model, actions: StartScreenActions(model: model), onOpen: { _ in }))
    }

    @Test func theWatchedListLaysOutInEveryState() {
        let states: [WatchedLoadState?] = [
            nil, .loading, .loaded(watchedList(3)), .loaded(watchedList(0)),
            .loaded(watchedList(0, hasMore: true)), .failed(.notFound, keeping: nil),
            .failed(.rateLimited(resetAt: Date()), keeping: watchedList(2)),
        ]
        for state in states {
            let size = render(
                VStack(alignment: .leading) {
                    WatchedPullRequestsList(
                        repository: "acme/api", state: state, labels: { _ in ["draft", "yours"] },
                        failureMessage: { _ in "Couldn't list pull requests for acme/api." },
                        onRefresh: {}, onOpen: { _ in })
                })
            #expect(size.height > 0)
        }
    }

    @Test func aRowWithAHostileTitleStaysOneLineTall() {
        func height(_ title: String) -> CGFloat {
            render(
                PullRequestRow(
                    title: title, repo: nil, number: 1, detail: "mwright", date: nil, dateVerb: "opened",
                    url: "https://github.com/acme/api/pull/1", labels: ["draft"], onOpen: { _ in }
                ).frame(width: 500)
            ).height
        }
        let plain = height("Fix it")
        #expect(height(String(repeating: "A very long title ", count: 60)) == plain)
        #expect(height("first line\nsecond line\nthird line") == plain)
        #expect(height("**bold** [link](https://example.com) `code`") == plain)
    }

    @Test func labelsFailureMessagesAndMenusLayOut() {
        #expect(render(PullRequestLabel(text: "review requested")).width > 0)
        #expect(render(WatchedFailureMessage(text: "Couldn't list pull requests.", onRetry: {})).height > 0)
        #expect(
            render(
                VStack {
                    StartMenu(items: [
                        StartMenuItem(title: "Refresh", action: {}),
                        StartMenuItem(title: "Stop Watching acme/api", isDestructive: true, action: {}),
                    ])
                }
            ).width > 0)
    }

    @Test func thePopoverLaysOutWithAndWithoutSuggestions() {
        #expect(render(WatchRepositoryPopover(suggestions: [], onWatch: { _ in })).width > 0)
        #expect(
            render(WatchRepositoryPopover(suggestions: ["acme/web", "acme/infra"], onWatch: { _ in })).height > 0)
    }

    @Test func onlyWatchedSourcesAreInTheWatchedGroup() {
        #expect(StartSidebar.isWatched(.watched("acme/api")))
        #expect(!StartSidebar.isWatched(.recents))
        #expect(!StartSidebar.isWatched(.reviewRequests))
    }

    @Test func sourceRowsLayOutWithAndWithoutACount() {
        #expect(render(StartSourceRow(source: .reviewRequests, count: "3")).width > 0)
        #expect(render(StartSourceRow(source: .recents, count: nil)).width > 0)
    }

    @Test func listHeadersLayOutWithAndWithoutATrailingView() {
        #expect(render(StartListHeader(title: "Recently opened", systemImage: "clock")).width > 0)
        #expect(render(StartListHeader(title: "acme/api", systemImage: "eye") { Text("now") }).width > 0)
    }

    @Test func pullRequestRowsLayOut() {
        let size = render(
            VStack {
                PullRequestRow(
                    title: "Fix it", repo: "acme/shop", number: 3, detail: "jdoe · draft",
                    date: Date(), dateVerb: "updated",
                    url: "https://github.com/acme/shop/pull/3", onOpen: { _ in })
                PullRequestRow(
                    title: "Another", repo: "acme/shop", number: 4, detail: nil,
                    date: nil, dateVerb: "opened",
                    url: "https://github.com/acme/shop/pull/4", onOpen: { _ in })
            }
        )
        #expect(size.width > 0 && size.height > 0)
    }

    @Test func clipboardOfferRowLaysOutForBothOffers() {
        for offer in [ClipboardOffer.pullRequest("https://github.com/acme/shop/pull/1"), .unreadLink(changeCount: 4)] {
            _ = render(ClipboardOfferRow(offer: offer, onOpen: { _ in }, onOpenUnread: { _ in }, onDismiss: {}))
        }
    }

    @Test func performCarriesOutEachClipboardReadAction() {
        var opened: [String] = []
        var filled: [String] = []
        StartScreenLogic.perform(.open("u"), open: { opened.append($0) }, fillField: { filled.append($0) })
        StartScreenLogic.perform(.fillField("text"), open: { opened.append($0) }, fillField: { filled.append($0) })
        StartScreenLogic.perform(.doNothing, open: { opened.append($0) }, fillField: { filled.append($0) })
        #expect(opened == ["u"])
        #expect(filled == ["text"])
    }

    @Test func loadPastedTextAppliesTheResolvedText() async {
        StartScreenView.loadPastedText(from: [], apply: { _ in Issue.record("nothing was pasted") })

        let applied = await withCheckedContinuation { continuation in
            StartScreenView.loadPastedText(
                from: [NSItemProvider(object: "see github.com/acme/shop/pull/3" as NSString)]
            ) { continuation.resume(returning: $0) }
        }
        #expect(applied == "https://github.com/acme/shop/pull/3")
    }
}
