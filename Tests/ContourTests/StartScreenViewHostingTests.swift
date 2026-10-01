import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
@Suite(.serialized)
struct StartScreenViewHostingTests {
    private struct NamespaceHost<Content: View>: View {
        @Namespace var ns
        let content: (Namespace.ID) -> Content
        var body: some View { content(ns) }
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

    private func preferences() -> Preferences {
        let name = "contour.tests.start.hosting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Preferences(defaults: defaults, environment: [:])
    }

    private func host(
        recorder: Recorder, board: NSPasteboard, initialURL: String? = nil, requests: [ReviewRequest]? = nil
    ) -> NSWindow {
        _ = NSApplication.shared
        let recentPRs = recents()
        let model = StartScreenModel(
            preferences: preferences(),
            dependencies: StartScreenModel.Dependencies(
                loadRecents: {
                    recorder.recentLoads += 1
                    return recentPRs
                },
                loadReviewRequests: {
                    recorder.requestLoads += 1
                    return requests
                }))
        let view = NamespaceHost { namespace in
            StartScreenView(
                model: model, initialURL: initialURL, markNamespace: namespace, pasteboard: board,
                onSubmit: { recorder.submitted.append($0) })
        }
        let hosting = NSHostingView(rootView: view)
        let window = HeadlessWindow(size: NSSize(width: 1080, height: 720), styleMask: [.titled, .closable])
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

    private func button(in window: NSWindow, named name: String) -> NSObject? {
        guard let root = window.contentView else { return nil }
        for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            _ = NSApp.perform(
                NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: attribute)
        }
        settle(root)
        func text(_ object: NSObject, _ name: String) -> String? {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue() as? String
        }
        func walk(_ node: Any) -> NSObject? {
            guard let object = node as? NSObject else { return nil }
            let isButton =
                [NSAccessibility.Role.button.rawValue, NSAccessibility.Role.link.rawValue]
                .contains(text(object, "accessibilityRole") ?? "")
            let names = ["accessibilityLabel", "accessibilityHelp", "accessibilityTitle"].compactMap {
                text(object, $0)
            }
            if isButton, names.contains(where: { $0.contains(name) }) { return object }
            let childrenSelector = NSSelectorFromString("accessibilityChildren")
            guard object.responds(to: childrenSelector) else { return nil }
            let children = object.perform(childrenSelector)?.takeUnretainedValue()
            for child in children as? [Any] ?? [] {
                if let found = walk(child) { return found }
            }
            return nil
        }
        return walk(root)
    }

    private func press(_ name: String, in window: NSWindow) -> Bool {
        guard let target = button(in: window, named: name) else { return false }
        _ = target.perform(NSSelectorFromString("accessibilityPerformPress"))
        if let content = window.contentView { settle(content) }
        return true
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

    @Test func pastingFromTheClipboardFillsTheFieldForReturnToOpen() {
        let recorder = Recorder()
        let window = host(recorder: recorder, board: pasteboard(holding: prURL))
        #expect(press("Paste from clipboard", in: window))
        pressReturn(in: window)
        #expect(recorder.submitted == [prURL])
        window.close()
    }

    @Test func dismissingTheClipboardOfferRemovesIt() {
        let recorder = Recorder()
        let window = host(recorder: recorder, board: pasteboard(holding: prURL))
        #expect(button(in: window, named: "from clipboard?") != nil)
        #expect(press("Dismiss", in: window))
        #expect(button(in: window, named: "from clipboard?") == nil)
        #expect(recorder.submitted.isEmpty)
        window.close()
    }

    @Test func loadTestDataOpensTheMockPullRequest() {
        setenv("CONTOUR_MOCK_ANALYSIS", "1", 1)
        defer { unsetenv("CONTOUR_MOCK_ANALYSIS") }
        let recorder = Recorder()
        let window = host(recorder: recorder, board: pasteboard(holding: nil))
        #expect(press("Load test data", in: window))
        #expect(recorder.submitted == [MockAnalysisFixtures.sourcePRURL])
        window.close()
    }

    @Test func recentsAreListedWhileReviewRequestsAreStillLoading() async {
        _ = NSApplication.shared
        let recorder = Recorder()
        let recentPRs = recents()
        let heldRequests = requests()
        let (gate, release) = AsyncStream<Void>.makeStream()
        let model = StartScreenModel(
            preferences: preferences(),
            dependencies: StartScreenModel.Dependencies(
                loadRecents: {
                    recorder.recentLoads += 1
                    return recentPRs
                },
                loadReviewRequests: {
                    recorder.requestLoads += 1
                    for await _ in gate { break }
                    return heldRequests
                }))
        let view = NamespaceHost { namespace in
            StartScreenView(
                model: model, markNamespace: namespace, pasteboard: pasteboard(holding: nil), onSubmit: { _ in })
        }
        let hosting = NSHostingView(rootView: view)
        let window = HeadlessWindow(size: NSSize(width: 1080, height: 720), styleMask: [.titled, .closable])
        window.contentView = hosting
        window.orderBack(nil)
        settle(hosting)
        #expect(recorder.requestLoads == 1)
        #expect(model.reviewRequests == nil)
        #expect(model.recents.map(\.number) == [7])
        #expect(!model.showsWelcome)
        release.yield()
        for _ in 0..<20 where model.reviewRequests == nil {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.reviewRequests?.map(\.number) == [8])
        window.close()
    }

    @Test func theURLFieldKeepsFocusWhenTheListsArriveAfterTheWelcome() async {
        _ = NSApplication.shared
        let lateRequests = requests()
        let (gate, release) = AsyncStream<Void>.makeStream()
        let model = StartScreenModel(
            preferences: preferences(),
            dependencies: StartScreenModel.Dependencies(
                loadRecents: { [] },
                loadReviewRequests: {
                    for await _ in gate { break }
                    return lateRequests
                }))
        let view = NamespaceHost { namespace in
            StartScreenView(
                model: model, markNamespace: namespace, pasteboard: pasteboard(holding: nil), onSubmit: { _ in })
        }
        let hosting = NSHostingView(rootView: view)
        let window = HeadlessWindow(size: NSSize(width: 1080, height: 720), styleMask: [.titled, .closable])
        window.contentView = hosting
        window.orderBack(nil)
        settle(hosting)
        #expect(model.showsWelcome)
        #expect((window.firstResponder as? NSTextView)?.isFieldEditor == true)
        release.yield()
        for _ in 0..<20 where model.showsWelcome {
            try? await Task.sleep(for: .milliseconds(25))
        }
        settle(hosting)
        #expect(!model.showsWelcome)
        #expect((window.firstResponder as? NSTextView)?.isFieldEditor == true)
        window.close()
    }

    @Test func theModelKeepsItsListsAfterTheViewGoesAway() {
        let recorder = Recorder()
        let recentPRs = recents()
        let model = StartScreenModel(
            preferences: preferences(),
            dependencies: StartScreenModel.Dependencies(
                loadRecents: {
                    recorder.recentLoads += 1
                    return recentPRs
                },
                loadReviewRequests: { nil }))
        let view = NamespaceHost { namespace in
            StartScreenView(model: model, markNamespace: namespace, onSubmit: { _ in })
        }
        let hosting = NSHostingView(rootView: view)
        let window = HeadlessWindow(size: NSSize(width: 1080, height: 720), styleMask: [.titled, .closable])
        window.contentView = hosting
        window.orderBack(nil)
        settle(hosting)
        window.close()
        #expect(model.recents.map(\.number) == [7])
    }
}
