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
        recents: [AnalysisCache.RecentPR], requests: [ReviewRequest]?, selecting source: StartSource? = nil
    ) async -> StartScreenModel {
        let model = StartScreenModel(
            preferences: preferences(),
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { recents }, loadReviewRequests: { requests }))
        await model.reload()
        if let source { model.select(source) }
        return model
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
        #expect(render(StartSourceList(model: full, onOpen: { _ in })).height > 0)
        full.select(.recents)
        #expect(render(StartSourceList(model: full, onOpen: { _ in })).height > 0)

        let empty = await loaded(recents: [], requests: [], selecting: .reviewRequests)
        #expect(render(StartSourceList(model: empty, onOpen: { _ in })).height > 0)
        empty.select(.recents)
        #expect(render(StartSourceList(model: empty, onOpen: { _ in })).height > 0)
    }

    @Test func theSidebarLaysOutWithAndWithoutTheMark() async {
        let welcome = await loaded(recents: [], requests: nil)
        let browsing = await loaded(recents: recents(), requests: requests())
        for model in [welcome, browsing] {
            _ = render(NamespaceHost { StartSidebar(model: model, markNamespace: $0) })
        }
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
