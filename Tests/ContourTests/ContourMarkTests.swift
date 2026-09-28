import Testing
import Foundation
@testable import Contour

/// The in-app mark is drawn from a Swift port of `scripts/generate-logo.py`, so these
/// pin it to the artwork the icon is rendered from.
struct ContourMarkTests {

    // MARK: - Parity with the logo artwork

    /// Every coordinate of every ring's path in the committed icon SVG, in order.
    private static func svgRingCoordinates() throws -> [[Double]] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let svg = try String(contentsOf: root.appendingPathComponent("Assets/Logo/contour-icon.svg"), encoding: .utf8)
        let paths = try Regex(#"<path d="([^"]+)""#)
        let number = try Regex(#"-?\d+(?:\.\d+)?"#)
        return svg.matches(of: paths).map { match in
            let d = String(match.output[1].substring ?? "")
            return d.matches(of: number).map { Double(String(d[$0.range]))! }
        }
    }

    /// The same sequence the SVG path holds: the start point, then each Bézier's two
    /// control points and end point.
    private static func swiftRingCoordinates(_ ring: ContourMarkGeometry.Ring) -> [Double] {
        var out: [CGFloat] = [ring.points[0].x, ring.points[0].y]
        for s in ContourMarkGeometry.bezierSegments(ring.points) {
            out += [s.c1.x, s.c1.y, s.c2.x, s.c2.y, s.end.x, s.end.y]
        }
        return out.map(Double.init)
    }

    @Test func ringsMatchTheIconArtwork() throws {
        let svg = try Self.svgRingCoordinates()
        #expect(svg.count == ContourMarkGeometry.ringCount)
        for (ring, expected) in zip(ContourMarkGeometry.rings, svg) {
            let actual = Self.swiftRingCoordinates(ring)
            #expect(actual.count == expected.count)
            // The SVG is written to one decimal place.
            let worst = zip(actual, expected).map { abs($0 - $1) }.max() ?? .infinity
            #expect(worst <= 0.051, "ring \(ring.level) is off by up to \(worst)")
        }
    }

    @Test func peakMatchesTheIconArtwork() {
        // <circle cx="594.8" cy="466.0" r="23.4" fill="#FFC857"/>
        #expect(abs(ContourMarkGeometry.peak.x - 594.8) < 0.051)
        #expect(abs(ContourMarkGeometry.peak.y - 466.0) < 0.051)
        #expect(abs(ContourMarkGeometry.peakRadius - 23.4) < 0.051)
    }

    @Test func darkPaletteIsTheIconPalette() {
        // Outermost and innermost stroke colours in the SVG: #3FC1C9 and #FFC857.
        #expect(ContourMarkPalette.dark.outer == (0x3F, 0xC1, 0xC9))
        #expect(ContourMarkPalette.dark.inner == (0xFF, 0xC8, 0x57))
    }

    // MARK: - Resolving the mark

    @Test func nothingIsResolvedAtZeroAndEverythingAtOne() {
        let none = ContourResolution.stages(0)
        #expect(none.peak == 0)
        #expect(none.rings.allSatisfy { $0 == 0 })

        let all = ContourResolution.stages(1)
        #expect(all.peak == 1)
        #expect(all.rings.allSatisfy { $0 == 1 })
    }

    @Test func peakResolvesFirstThenRingsFromTheSummitOutward() {
        // Order of resolution: peak, innermost ring (last index), ..., outermost (index 0).
        for r in stride(from: 0.0, through: 1.0, by: 0.01) {
            let s = ContourResolution.stages(r)
            let order = [s.peak] + s.rings.reversed()
            for (earlier, later) in zip(order, order.dropFirst()) {
                #expect(earlier >= later, "at \(r)")
            }
        }
    }

    @Test func consecutiveRingsOverlapSoTheDrawingNeverStops() {
        // Somewhere in the range, more than one part is mid-resolve at once.
        let overlapping = stride(from: 0.0, through: 1.0, by: 0.01).contains { r in
            let s = ContourResolution.stages(r)
            return ([s.peak] + s.rings).filter { $0 > 0 && $0 < 1 }.count > 1
        }
        #expect(overlapping)
    }

    // MARK: - Analysis progress

    private static let pipelineOrder: [PipelineStage] = [
        .fetching, .checkingOut, .cacheCheck, .ticket, .behaviorChange, .understanding,
        .architecture, .decisions, .flows, .judgment,
    ]

    @Test func everyStageHasItsOwnSliceInPipelineOrder() {
        let starts = Self.pipelineOrder.map { AnalysisResolution.target(stage: $0, elapsed: 0) }
        #expect(starts.first == 0)
        #expect(starts.last! < 1)
        for (a, b) in zip(starts, starts.dropFirst()) { #expect(a < b) }
    }

    /// In an open review the stages run in parallel: each settled stage resolves its own
    /// slice, in whatever order they finish, and only a finished analysis is whole.
    @Test func anOpenReviewResolvesOneSliceForEachSettledStage() {
        var state = AnalysisState()
        let opened = AnalysisResolution.target(state: state)
        #expect(opened > 0 && opened < 0.2)

        state.stages[.decisions] = .done
        let oneDone = AnalysisResolution.target(state: state)
        #expect(oneDone > opened)

        state.stages[.architecture] = .failed("boom")
        let twoSettled = AnalysisResolution.target(state: state)
        #expect(twoSettled > oneDone, "a failed stage is settled too")

        // Retrying decisions gives its slice back until it settles again.
        state.stages[.decisions] = .running(detail: nil)
        let retrying = AnalysisResolution.target(state: state)
        #expect(retrying < twoSettled)
        #expect(abs(retrying - opened - (twoSettled - oneDone)) < 1e-9, "only architecture's slice remains")

        for stage in PipelineStage.analysis { state.stages[stage] = .done }
        #expect(abs(AnalysisResolution.target(state: state) - 1) < 1e-9)
        state.isComplete = true
        #expect(AnalysisResolution.target(state: state) == 1)
    }

    @Test func aLongStageCreepsTowardItsEndButNeverClaimsTheNextStage() {
        let start = AnalysisResolution.target(stage: .decisions, elapsed: 0)
        let next = AnalysisResolution.target(stage: .flows, elapsed: 0)
        let later = AnalysisResolution.target(stage: .decisions, elapsed: 60)
        let muchLater = AnalysisResolution.target(stage: .decisions, elapsed: 3600)
        #expect(start < later)
        #expect(later < muchLater)
        #expect(muchLater <= next)
    }

    @Test func drawnResolutionEasesTowardTheTargetAndNeverGoesBack() {
        let halfway = AnalysisResolution.approach(from: 0.2, to: 0.4, over: 0.25)
        #expect(halfway > 0.2 && halfway < 0.4)
        #expect(AnalysisResolution.approach(from: 0.2, to: 0.4, over: 5) == 0.4)
        #expect(AnalysisResolution.approach(from: 0.5, to: 0.3, over: 1) == 0.5)
    }

    // MARK: - AnalyzingMark.Smoother (frame-to-frame memory for `approach`)

    /// The first frame has no prior timestamp to measure elapsed time against, so it must
    /// not jump straight to the target; only later frames, once `dt` is known, ease toward it.
    @Test func smootherDoesNotMoveOnItsFirstFrameThenEasesTowardTheTarget() {
        let smoother = AnalyzingMark.Smoother()
        let start = Date(timeIntervalSince1970: 1000)
        #expect(smoother.value(toward: 0.5, at: start) == 0)

        let midway = smoother.value(toward: 0.5, at: start.addingTimeInterval(0.25))
        #expect(midway > 0 && midway < 0.5)

        #expect(smoother.value(toward: 0.5, at: start.addingTimeInterval(5.25)) == 0.5)
    }

    @Test func smootherNeverMovesBackwardWhenTheTargetDrops() {
        let smoother = AnalyzingMark.Smoother()
        let start = Date(timeIntervalSince1970: 2000)
        _ = smoother.value(toward: 0.6, at: start)
        #expect(smoother.value(toward: 0.6, at: start.addingTimeInterval(5)) == 0.6)
        #expect(smoother.value(toward: 0.2, at: start.addingTimeInterval(6)) == 0.6)
    }
}
