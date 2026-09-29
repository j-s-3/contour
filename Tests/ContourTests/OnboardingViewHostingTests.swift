import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
@Suite(.serialized)
struct OnboardingViewHostingTests {
    private struct NamespaceHost<Content: View>: View {
        @Namespace var ns
        let content: (Namespace.ID) -> Content
        var body: some View { content(ns) }
    }

    @Observable
    fileprivate final class LogModel {
        var log: [PipelineProgressEntry] = [PipelineProgressEntry(stage: "Opening", detail: "Fetching")]
    }

    fileprivate struct ConsoleHost: View {
        let model: LogModel
        var body: some View { AnalysisConsoleView(log: model.log) }
    }

    private final class Recorder {
        var submitted: [String] = []
        var recentLoads = 0
        var requestLoads = 0
    }

    private let prURL = "https://github.com/acme/shop/pull/7"

    private func pasteboard(holding text: String?) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("contour.tests.\(UUID().uuidString)"))
        board.clearContents()
        if let text { board.setString(text, forType: .string) }
        return board
    }

    private func recents() -> [AnalysisCache.RecentPR] {
        [AnalysisCache.RecentPR(url: prURL, repo: "acme/shop", number: 7, title: "Seven", lastOpened: Date())]
    }

    private func requests() -> [ReviewRequest] {
        [
            ReviewRequest(
                url: "https://github.com/acme/shop/pull/8", repo: "acme/shop", number: 8, title: "Eight",
                author: "jdoe", isDraft: false, updatedAt: Date())
        ]
    }

    private func host(
        recorder: Recorder, board: NSPasteboard, initialURL: String? = nil, requests: [ReviewRequest]? = nil
    ) -> NSWindow {
        _ = NSApplication.shared
        let recentPRs = recents()
        let view = NamespaceHost { namespace in
            OnboardingView(
                initialURL: initialURL, markNamespace: namespace, pasteboard: board,
                loadRecents: {
                    recorder.recentLoads += 1
                    return recentPRs
                },
                loadReviewRequests: {
                    recorder.requestLoads += 1
                    return requests
                },
                onSubmit: { recorder.submitted.append($0) })
        }
        let hosting = NSHostingView(rootView: view)
        let window = HeadlessWindow(size: NSSize(width: 900, height: 700), styleMask: [.titled, .closable])
        window.contentView = hosting
        window.orderBack(nil)
        settle(hosting)
        return window
    }

    private func settle(_ view: NSView) {
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func pressReturn(in window: NSWindow) {
        guard let view = window.contentView else { return }
        window.makeFirstResponder(view)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)
            {
                window.sendEvent(event)
            }
        }
        settle(view)
    }

    @Test func appearingLoadsRecentsAndReviewRequests() {
        let recorder = Recorder()
        let window = host(recorder: recorder, board: pasteboard(holding: nil), requests: requests())
        #expect(recorder.recentLoads == 1)
        #expect(recorder.requestLoads == 1)
        window.close()
    }

    @Test func returnOpensTheEnteredPullRequest() {
        let recorder = Recorder()
        let window = host(recorder: recorder, board: pasteboard(holding: nil), initialURL: prURL)
        pressReturn(in: window)
        #expect(recorder.submitted == [prURL])
        window.close()
    }

    @Test func returnIgnoresTextThatIsNotAPullRequest() {
        let recorder = Recorder()
        let window = host(recorder: recorder, board: pasteboard(holding: nil), initialURL: "not a link")
        pressReturn(in: window)
        #expect(recorder.submitted.isEmpty)
        window.close()
    }

    @Test func aReadableClipboardLinkIsOfferedOnAppear() {
        let recorder = Recorder()
        let window = host(recorder: recorder, board: pasteboard(holding: prURL))
        #expect(recorder.recentLoads == 1)
        window.close()
    }

    @Test func returningToTheAppRechecksTheClipboard() {
        let recorder = Recorder()
        let board = pasteboard(holding: nil)
        let window = host(recorder: recorder, board: board)
        board.clearContents()
        board.setString(prURL, forType: .string)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        if let content = window.contentView { settle(content) }
        window.close()
    }

    @Test func mockModeOffersTheTestDataButton() {
        setenv("CONTOUR_MOCK_ANALYSIS", "1", 1)
        defer { unsetenv("CONTOUR_MOCK_ANALYSIS") }
        let recorder = Recorder()
        let window = host(recorder: recorder, board: pasteboard(holding: nil))
        #expect(MockAnalysisFixtures.isEnabled)
        window.close()
    }

    @Test func consoleFollowsNewEntriesAsTheyArrive() {
        let model = LogModel()
        let hosting = NSHostingView(rootView: ConsoleHost(model: model))
        let window = HeadlessWindow(size: NSSize(width: 600, height: 300), styleMask: [.titled, .closable])
        window.contentView = hosting
        window.orderBack(nil)
        settle(hosting)
        model.log.append(PipelineProgressEntry(stage: "Analyzing architecture", detail: "Reading GraphStore.swift"))
        settle(hosting)
        #expect(model.log.count == 2)
        window.close()
    }
}
