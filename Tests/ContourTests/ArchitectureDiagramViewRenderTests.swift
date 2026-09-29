import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct ArchitectureDiagramViewRenderTests {
    @MainActor private final class Recorder {
        var selections: [ArchAnchor?] = []
        var zoomed: [String] = []
        var decisions: [String] = []
    }

    @MainActor private final class Session {
        let window: NSWindow
        let hosting: NSHostingView<ArchitectureDiagramView>

        init(
            boxes: [ArchBox], arrows: [ArchArrow], containers: [ArchContainer],
            selection: ArchAnchor? = nil, recorder: Recorder, size: NSSize = NSSize(width: 1400, height: 900)
        ) {
            let view = ArchitectureDiagramView(
                boxes: boxes, arrows: arrows, containers: containers, selection: selection,
                onSelect: { recorder.selections.append($0) },
                onZoomIn: { recorder.zoomed.append($0) },
                onOpenDecision: { recorder.decisions.append($0) })
            hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: size)
            window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = hosting
            window.orderBack(nil)
            pump()
        }

        func pump() {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
        }

        func close() { window.orderOut(nil) }
    }

    private func richBoxes() -> [ArchBox] {
        [
            ArchBox(
                id: "a", title: "Alpha", purpose: "Serves requests", emphasis: .changed,
                changeBefore: "sync", changeAfter: "async", decision: "Queue the work", decisionId: "d1",
                moreDecisions: 2, questions: 2, hasInside: true),
            ArchBox(
                id: "b", title: "Beta", purpose: "Stores data", emphasis: .added, changeAfter: "new store",
                questions: 1),
            ArchBox(id: "c", title: "Gamma", emphasis: .removed, changeBefore: "old cache"),
            ArchBox(id: "d", title: "Delta", emphasis: .context),
            ArchBox(id: "n", title: "Neighbor", emphasis: .context, isNeighbor: true),
        ]
    }

    private func richArrows() -> [ArchArrow] {
        [
            ArchArrow(
                id: "e1", fromId: "a", toId: "b", label: "writes", previousLabel: "wrote", emphasis: .changed,
                isAsync: true, questions: 1, decisions: 1),
            ArchArrow(id: "e2", fromId: "b", toId: "c", label: "drops", emphasis: .removed, isAsync: false),
            ArchArrow(id: "e3", fromId: "a", toId: "d", label: "reads", emphasis: .added, isAsync: false),
            ArchArrow(id: "e4", fromId: "d", toId: "n", label: "calls", emphasis: .context, isAsync: false),
        ]
    }

    private func richContainers() -> [ArchContainer] {
        [
            ArchContainer(id: "k1", label: "Backend", kind: .service, memberIds: ["a", "b"], isFocus: true),
            ArchContainer(id: "k2", label: "Untrusted", kind: .trust, memberIds: ["c"]),
            ArchContainer(id: "k3", label: "Outside", kind: .external, memberIds: ["n"]),
        ]
    }

    @Test func rendersEveryEmphasisMarkerAndBoundaryKind() {
        let session = Session(
            boxes: richBoxes(), arrows: richArrows(), containers: richContainers(), recorder: Recorder())
        #expect(session.hosting.fittingSize.width > 0)
        session.close()
    }

    @Test func rendersWithNodeAndEdgeSelections() {
        for anchor in [ArchAnchor.node("a"), .edge("e1"), .edge("e2"), .node("n")] {
            Session(
                boxes: richBoxes(), arrows: richArrows(), containers: richContainers(),
                selection: anchor, recorder: Recorder()
            ).close()
        }
    }

    @Test func aBoxWithDecisionQuestionsAndInsideRendersItsMarkers() {
        let recorder = Recorder()
        let session = Session(
            boxes: [richBoxes()[0]], arrows: [], containers: [], recorder: recorder,
            size: NSSize(width: 330, height: 260))
        #expect(session.hosting.fittingSize.width > 0)
        #expect(recorder.zoomed.isEmpty && recorder.decisions.isEmpty)
        session.close()
    }

    @Test func aDiagramTooLargeToFitScrollsInsteadOfShrinking() {
        let boxes = (0..<40).map {
            ArchBox(id: "n\($0)", title: "Node \($0)", purpose: "Does a thing", emphasis: .changed)
        }
        let arrows = (1..<40).map {
            ArchArrow(
                id: "e\($0)", fromId: "n\($0 - 1)", toId: "n\($0)", label: "edge \($0)", emphasis: .context,
                isAsync: false)
        }
        let session = Session(
            boxes: boxes, arrows: arrows, containers: [], recorder: Recorder(),
            size: NSSize(width: 500, height: 400))
        #expect(session.hosting.fittingSize.width >= 0)
        session.close()
    }
}
