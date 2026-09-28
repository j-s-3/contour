import Testing
import Foundation
import SwiftUI
import AppKit
@testable import Contour

/// Smoke renders of the start-screen views. `OnboardingViewLogic` holds every decision
/// (see `OnboardingViewTests`), so what is left in these bodies is layout. Hosting each
/// view in an `NSHostingView` and forcing a layout pass evaluates its body and its
/// row/list builders, so a change that crashes on construction or in layout fails here
/// rather than at launch. The hosting view is never put in a window, so
/// `.onAppear`/`.task` (real `gh`, real analysis cache, real pasteboard) never fire.
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

    /// Pins that the start screen builds and lays out with no initial URL and with a
    /// pre-filled one (the retry-after-failure path).
    @Test func startScreenLaysOut() {
        _ = render(NamespaceHost { OnboardingView(markNamespace: $0, onSubmit: { _ in }) })
        _ = render(NamespaceHost {
            OnboardingView(initialURL: "https://github.com/acme/shop/pull/1", markNamespace: $0,
                           focusRequest: 2, onSubmit: { _ in })
        })
    }

    /// Pins that a PR list holding one row with detail and date and one without builds
    /// and lays out.
    @Test func pullRequestListAndRowsLayOut() {
        let size = render(
            PullRequestList(title: "Awaiting your review", systemImage: "person") {
                PullRequestRow(title: "Fix it", repo: "acme/shop", number: 3, detail: "jdoe · draft",
                               date: Date(), dateVerb: "updated",
                               url: "https://github.com/acme/shop/pull/3", onOpen: { _ in })
                PullRequestRow(title: "Another", repo: "acme/shop", number: 4, detail: nil,
                               date: nil, dateVerb: "opened",
                               url: "https://github.com/acme/shop/pull/4", onOpen: { _ in })
            }
        )
        #expect(size.width > 0 && size.height > 0)
    }

    /// Pins the analyzing screen's build for several stages, with and without a log.
    @Test func analyzingViewLaysOut() {
        let log = [PipelineProgressEntry(stage: "Analyzing architecture", detail: "Reading GraphStore.swift")]
        for stage in [PipelineStage.fetching, .architecture, .judgment] {
            _ = render(NamespaceHost { AnalyzingView(stage: stage, log: log, markNamespace: $0) })
        }
        _ = render(NamespaceHost { AnalyzingView(stage: .fetching, log: [], markNamespace: $0) })
    }

    /// Pins that both PR lists build from real rows: a draft and a non-draft review
    /// request, and a recent PR.
    @Test func pullRequestListsLayOutWithBothSources() {
        let requests = [
            ReviewRequest(url: "u1", repo: "acme/shop", number: 1, title: "t1", author: "a", isDraft: true, updatedAt: Date()),
            ReviewRequest(url: "u2", repo: "acme/shop", number: 2, title: "t2", author: "b", isDraft: false, updatedAt: nil),
        ]
        let recents = [AnalysisCache.RecentPR(url: "u3", repo: "acme/shop", number: 3, title: "t3", lastOpened: Date())]
        _ = render(PullRequestLists(requests: requests, recents: recents, onOpen: { _ in }))
        _ = render(PullRequestLists(requests: requests, recents: [], onOpen: { _ in }))
        _ = render(PullRequestLists(requests: [], recents: recents, onOpen: { _ in }))
        _ = render(PullRequestLists(requests: [], recents: [], onOpen: { _ in }))
    }

    /// Pins that both clipboard offers (a recognized PR and an unread link) build.
    @Test func clipboardOfferRowLaysOutForBothOffers() {
        for offer in [ClipboardOffer.pullRequest("https://github.com/acme/shop/pull/1"), .unreadLink(changeCount: 4)] {
            _ = render(ClipboardOfferRow(offer: offer, onOpen: { _ in }, onOpenUnread: { _ in }, onDismiss: {}))
        }
    }

    /// Pins that the activity console builds, and that the analyzing screen shows it (with
    /// its divider) when the reviewer has left activity expanded.
    @Test func analysisConsoleLaysOutAndShowsWhenExpanded() {
        let log = [
            PipelineProgressEntry(stage: "Opening", detail: "Fetching"),
            PipelineProgressEntry(stage: "Analyzing architecture", detail: "Reading GraphStore.swift"),
        ]
        _ = render(AnalysisConsoleView(log: log))

        let key = "showsAnalysisActivity"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        _ = render(NamespaceHost { AnalyzingView(stage: .architecture, log: log, markNamespace: $0) })
    }

    /// Pins that a resolved clipboard read opens a PR, fills the field, or does nothing,
    /// and never more than one of those.
    @Test func performCarriesOutEachClipboardReadAction() {
        var opened: [String] = []
        var filled: [String] = []
        OnboardingViewLogic.perform(.open("u"), open: { opened.append($0) }, fillField: { filled.append($0) })
        OnboardingViewLogic.perform(.fillField("text"), open: { opened.append($0) }, fillField: { filled.append($0) })
        OnboardingViewLogic.perform(.doNothing, open: { opened.append($0) }, fillField: { filled.append($0) })
        #expect(opened == ["u"])
        #expect(filled == ["text"])
    }

    /// Pins the paste hook: pasted text is resolved (a PR link canonicalized) and applied
    /// on the main queue, and an empty provider list does nothing.
    @Test func loadPastedTextAppliesTheResolvedText() async {
        OnboardingView.loadPastedText(from: [], apply: { _ in Issue.record("nothing was pasted") })

        let applied = await withCheckedContinuation { continuation in
            OnboardingView.loadPastedText(
                from: [NSItemProvider(object: "see github.com/acme/shop/pull/3" as NSString)]
            ) { continuation.resume(returning: $0) }
        }
        #expect(applied == "https://github.com/acme/shop/pull/3")
    }

    /// Pins that the failure screen builds with its two actions.
    @Test func failedViewLaysOut() {
        _ = render(FailedView(message: "Couldn't reach GitHub.", onRetry: {}, onOpenDifferent: {}))
    }
}
