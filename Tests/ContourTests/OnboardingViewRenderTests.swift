import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct OnboardingViewRenderTests {
    private func render<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private struct NamespaceHost<Content: View>: View {
        @Namespace var ns
        let content: (Namespace.ID) -> Content
        var body: some View { content(ns) }
    }

    @Test func startScreenLaysOut() {
        _ = render(NamespaceHost { OnboardingView(markNamespace: $0, onSubmit: { _ in }) })
        _ = render(
            NamespaceHost {
                OnboardingView(
                    initialURL: "https://github.com/acme/shop/pull/1", markNamespace: $0,
                    focusRequest: 2, onSubmit: { _ in })
            })
    }

    @Test func pullRequestListAndRowsLayOut() {
        let size = render(
            PullRequestList(title: "Awaiting your review", systemImage: "person") {
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

    @Test func pullRequestListsLayOutWithBothSources() {
        let requests = [
            ReviewRequest(
                url: "u1", repo: "acme/shop", number: 1, title: "t1", author: "a", isDraft: true, updatedAt: Date()),
            ReviewRequest(
                url: "u2", repo: "acme/shop", number: 2, title: "t2", author: "b", isDraft: false, updatedAt: nil),
        ]
        let recents = [AnalysisCache.RecentPR(url: "u3", repo: "acme/shop", number: 3, title: "t3", lastOpened: Date())]
        _ = render(PullRequestLists(requests: requests, recents: recents, onOpen: { _ in }))
        _ = render(PullRequestLists(requests: requests, recents: [], onOpen: { _ in }))
        _ = render(PullRequestLists(requests: [], recents: recents, onOpen: { _ in }))
        _ = render(PullRequestLists(requests: [], recents: [], onOpen: { _ in }))
    }

    @Test func clipboardOfferRowLaysOutForBothOffers() {
        for offer in [ClipboardOffer.pullRequest("https://github.com/acme/shop/pull/1"), .unreadLink(changeCount: 4)] {
            _ = render(ClipboardOfferRow(offer: offer, onOpen: { _ in }, onOpenUnread: { _ in }, onDismiss: {}))
        }
    }

    @Test func performCarriesOutEachClipboardReadAction() {
        var opened: [String] = []
        var filled: [String] = []
        OnboardingViewLogic.perform(.open("u"), open: { opened.append($0) }, fillField: { filled.append($0) })
        OnboardingViewLogic.perform(.fillField("text"), open: { opened.append($0) }, fillField: { filled.append($0) })
        OnboardingViewLogic.perform(.doNothing, open: { opened.append($0) }, fillField: { filled.append($0) })
        #expect(opened == ["u"])
        #expect(filled == ["text"])
    }

    @Test func loadPastedTextAppliesTheResolvedText() async {
        OnboardingView.loadPastedText(from: [], apply: { _ in Issue.record("nothing was pasted") })

        let applied = await withCheckedContinuation { continuation in
            OnboardingView.loadPastedText(
                from: [NSItemProvider(object: "see github.com/acme/shop/pull/3" as NSString)]
            ) { continuation.resume(returning: $0) }
        }
        #expect(applied == "https://github.com/acme/shop/pull/3")
    }
}
