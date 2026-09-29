import Testing
import SwiftUI
import AppKit
@testable import Contour

@MainActor
@Suite(.serialized)
struct ContentViewHostingTests {

    private func render(_ store: GraphStore, needsOnboarding: Bool = false) -> NSWindow {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: ContentView(store: store, needsOnboarding: needsOnboarding))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        settle(host)
        return window
    }

    private func settle(_ host: NSView) {
        for _ in 0..<2 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func reviewStore(status: StageStatus = .done) -> GraphStore {
        let store = GraphStore(phase: .opening)
        store.handle(.graph(ContourSampleData.publishTriggeredReindex))
        store.handle(.diff("diff --git a/a.swift b/a.swift\n--- a/a.swift\n+++ b/a.swift\n@@ -1 +1 @@\n-a\n+b\n"))
        for stage in PipelineStage.analysis { store.handle(.status(stage, status)) }
        return store
    }

    @Test func rendersTheStartScreen() {
        let store = GraphStore()
        let window = render(store)
        #expect(store.phase == .idle)
        window.close()
    }

    @Test func rendersTheOpeningScreen() {
        let store = GraphStore(phase: .opening)
        let window = render(store)
        #expect(store.phase == .opening)
        window.close()
    }

    @Test func rendersFirstRunOnboarding() {
        let store = GraphStore()
        let window = render(store, needsOnboarding: true)
        #expect(store.phase == .idle)
        window.close()
    }

    @Test func rendersTheFailedScreen() {
        let store = GraphStore()
        store.handle(.fatal("boom"))
        let window = render(store)
        #expect(store.phase == .failed("boom"))
        window.close()
    }

    @Test func rendersEveryLensOfAnOpenReview() {
        let store = reviewStore()
        #expect(store.phase == .review)
        let window = render(store)
        let targets: [NavigationTarget] = [
            .architecture, .decisions, .flows, .diff, .files,
            .evidence(CodeRef(path: "a.swift", startLine: 1, endLine: 1)),
            .summary,
        ]
        for target in targets {
            store.navigate(to: target)
            settle(window.contentView!)
        }
        #expect(store.current == .summary)
        window.close()
    }

    @Test func rendersEachSectionStateWithAndWithoutContent() {
        for status in [StageStatus.failed("x"), .stopped, .running(detail: "working"), .done] {
            for hasContent in [true, false] {
                var graph = ContourSampleData.publishTriggeredReindex
                if !hasContent { graph.components = []; graph.decisions = []; graph.flows = [] }
                let store = GraphStore(phase: .opening)
                store.handle(.graph(graph))
                store.handle(.revalidating(fromHead: "abc1234"))
                for stage in PipelineStage.analysis { store.handle(.status(stage, status)) }
                let window = render(store)
                for target in [NavigationTarget.architecture, .decisions, .flows, .diff] {
                    store.navigate(to: target)
                    settle(window.contentView!)
                }
                #expect(store.phase == .review)
                window.close()
            }
        }
    }

    @Test func rendersReviewButtonsInEachSubmissionState() {
        for review in [PRReview.State.submitting(.approve), .submitted(.approve),
                       .submitting(.requestChanges), .submitted(.requestChanges),
                       .failed(.approve, "nope"), .failed(.requestChanges, "nope")] {
            let store = GraphStore(phase: .opening, review: review)
            store.handle(.graph(ContourSampleData.publishTriggeredReindex))
            let window = render(store)
            #expect(store.review == review)
            window.close()
        }
    }

    @Test func rendersTheDecisionsRowAsFullyReviewed() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = [Consideration(id: "q1", question: "Why?", detail: "d", relatedIds: ["d1"])]
        graph.decisions = [DecisionNode(id: "d1", title: "D1", decision: Statement(text: "x", provenance: .fact), confidence: .high)]
        let store = GraphStore(phase: .opening)
        store.handle(.graph(graph))
        for stage in PipelineStage.analysis { store.handle(.status(stage, .done)) }
        store.setReviewerState(.accepted, forDecision: "d1")
        let progress = store.graph?.reviewProgress()
        #expect(progress?.total == 1)
        #expect(progress?.reviewed == 1)
        let window = render(store)
        window.close()
    }

    @Test func rendersTheConversationsInspector() {
        let store = reviewStore()
        store.toggleConversations()
        let window = render(store)
        #expect(store.conversations.isPresented)
        store.toggleConversations()
        settle(window.contentView!)
        #expect(!store.conversations.isPresented)
        window.close()
    }

    @Test func fullScreenNotificationKeepsTheReviewOpen() {
        let store = reviewStore()
        let window = render(store)
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        settle(window.contentView!)
        #expect(store.phase == .review)
        window.close()
    }

    @Test func openLensEnvironmentVariableNavigatesOnceTheReviewOpens() {
        setenv("CONTOUR_OPEN_LENS", "flows", 1)
        defer { unsetenv("CONTOUR_OPEN_LENS") }
        let store = GraphStore(phase: .opening)
        let window = render(store)
        store.handle(.graph(ContourSampleData.publishTriggeredReindex))
        settle(window.contentView!)
        #expect(store.current == .flows)
        window.close()
    }

    private func pressShortcut(_ characters: String, modifiers: NSEvent.ModifierFlags, in window: NSWindow) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0)
        if let event { _ = window.contentView?.performKeyEquivalent(with: event) }
        settle(window.contentView!)
    }

    @Test func reviewPhaseWithoutAGraphFallsBackToTheStartScreen() {
        let store = GraphStore(phase: .review)
        let window = render(store)
        #expect(store.graph == nil)
        window.close()
    }

    @Test func keyboardShortcutsAskAndOpenThePalette() {
        let store = reviewStore()
        let window = render(store)
        pressShortcut("a", modifiers: [.command, .shift], in: window)
        pressShortcut("k", modifiers: [.command], in: window)
        #expect(store.phase == .review)
        window.close()
    }
}

