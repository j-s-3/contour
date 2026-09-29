import Testing
import SwiftUI
import AppKit
@testable import Contour

/// `CodeViewerView`'s body, header and row builder are SwiftUI code whose decisions live in
/// `CodeViewerLogic` / `CodeViewerState`. This hosts the real view in an `NSHostingView` in
/// each state (excerpt, whole file, error banner, base-side ref) so every builder runs against
/// realistic rows; it pins that none of those states traps while building or laying out.
@MainActor
struct CodeViewerViewRenderTests {

    private func host(_ ref: CodeRef, state: CodeViewerState) -> NSHostingView<CodeViewerView> {
        let view = CodeViewerView(ref: ref, checkout: nil, initialState: state, onBack: {})
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func excerptRendersWithHighlightedRange() {
        var state = CodeViewerState()
        state.lines = (1...12).map { ($0, $0 == 5 ? "" : "line \($0)") }
        let hosting = host(CodeRef(path: "a.swift", startLine: 4, endLine: 6), state: state)
        #expect(hosting.fittingSize.width >= 0)
    }

    @Test func wholeFileRendersFromNumberedText() {
        var state = CodeViewerState()
        state.wholeFile = "one\ntwo\n\nfour"
        _ = state.toggleWholeFile()
        _ = host(CodeRef(path: "a.swift", startLine: 2, endLine: 3), state: state)
    }

    @Test func errorBannerRendersInPlaceOfCode() {
        var state = CodeViewerState()
        state.apply(excerpt: .noCheckout)
        _ = host(CodeRef(path: "a.swift", startLine: 1, endLine: 1), state: state)
    }

    @Test func baseSideRefRendersTheBaseBadge() {
        _ = host(CodeRef(path: "old.swift", startLine: 1, endLine: 2, side: .base), state: CodeViewerState())
    }
}
