import AppKit
import SwiftUI
import Testing
@testable import Contour

/// Hosts `BehaviorChangeDiagramView` in a real `NSHostingView` and forces a layout pass, so
/// the view bodies (`ViewThatFits`, the before/after `Grid`, `StageBox`, `CappedWidth`) are
/// actually evaluated rather than only the pure helpers beside them (#129). The hosting
/// width picks which `Density` `ViewThatFits` settles on. The invariant pinned: no shape of
/// `BehaviorChange` (empty side, outcomes, added/removed steps, compact mode) traps while
/// rendering, and the diagram reports a non-empty size when there is anything to draw.
@MainActor
struct BehaviorChangeDiagramRenderTests {
    private func render(_ change: BehaviorChange, compact: Bool = false, width: CGFloat = 900) -> NSSize {
        let view = BehaviorChangeDiagramView(change: change, compact: compact) { _ in }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private let change = BehaviorChange(
        id: "c",
        title: "Retry",
        before: [
            BehaviorStage(id: "b1", label: "Request", tag: .both),
            BehaviorStage(id: "b2", label: "Fail fast", tag: .beforeOnly, outcome: .failure),
        ],
        after: [
            BehaviorStage(id: "a1", label: "Request", tag: .both),
            BehaviorStage(id: "a2", label: "Retry with backoff and a much longer label", tag: .afterOnly),
            BehaviorStage(id: "a3", label: "Succeeds", tag: .both, outcome: .success),
        ]
    )

    @Test func rendersAtEveryDensityWithoutTrapping() {
        // Wide enough for `.regular`, then narrower to step through `.tight`, `.wrapped`
        // and the horizontal `ScrollView` fallback.
        for width in [1200, 700, 400, 150] as [CGFloat] {
            #expect(render(change, width: width).height > 0)
        }
    }

    @Test func compactModeSkipsTheRegularDensity() {
        #expect(render(change, compact: true).height > 0)
    }

    @Test func emptySidesRenderTheirPlaceholderText() {
        #expect(render(BehaviorChange(id: "e", title: "Empty")).height > 0)
        #expect(render(BehaviorChange(id: "o", title: "One-sided",
                                      after: [BehaviorStage(id: "x", label: "New", tag: .afterOnly)])).height > 0)
    }
}
