import Testing
@testable import Contour

struct DiagramModeTests {
    @Test func readsInReviewerLanguage() {
        #expect(DiagramMode.allCases.map(\.label) == ["Before this PR", "After this PR", "What changed"])
        #expect(DiagramMode.allCases.allSatisfy { !$0.label.localizedCaseInsensitiveContains("delta") })
    }

    @Test func eachModeHasItsOwnKey() {
        #expect(DiagramMode(key: "b") == .before)
        #expect(DiagramMode(key: "A") == .after)
        #expect(DiagramMode(key: "d") == .delta)
        #expect(DiagramMode(key: "x") == nil)
        #expect(DiagramMode(key: "") == nil)
        #expect(Set(DiagramMode.allCases.map(\.key)).count == DiagramMode.allCases.count)
    }

    @Test func headerSaysWhatIsOnScreen() {
        #expect(DiagramMode.delta.showing("flow") == "Showing what this PR changed")
        #expect(DiagramMode.before.showing("flow") == "Showing the flow before this PR")
        #expect(DiagramMode.after.showing("architecture") == "Showing the architecture after this PR")
    }

    @Test @MainActor func defaultsToWhatChanged() {
        #expect(GraphStore().diagramMode == .delta)
    }

    @Test func onlyDiagramScreensOfferTheSwitch() {
        let diagrams: [NavigationTarget] = [.architecture, .componentDetail("c"), .edgeDetail("e"),
                                            .flows, .flowDetail("f"), .flowNodeDetail(flowId: "f", nodeId: "n")]
        let others: [NavigationTarget] = [.summary, .decisions, .diff, .decisionDetail("d"), .consideration("q")]
        #expect(diagrams.filter { !$0.showsDiagram }.isEmpty)
        #expect(others.filter(\.showsDiagram).isEmpty)
    }
}
