import Foundation
import SwiftUI
import Testing

@testable import Contour

struct ContourMarkTests {
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
            let worst = zip(actual, expected).map { abs($0 - $1) }.max() ?? .infinity
            #expect(worst <= 0.051, "ring \(ring.level) is off by up to \(worst)")
        }
    }

    @Test func peakMatchesTheIconArtwork() {
        #expect(abs(ContourMarkGeometry.peak.x - 594.8) < 0.051)
        #expect(abs(ContourMarkGeometry.peak.y - 466.0) < 0.051)
        #expect(abs(ContourMarkGeometry.peakRadius - 23.4) < 0.051)
    }

    @Test func darkPaletteIsTheIconPalette() {
        #expect(ContourMarkPalette.dark.outer == (0x3F, 0xC1, 0xC9))
        #expect(ContourMarkPalette.dark.inner == (0xFF, 0xC8, 0x57))
    }

    @Test func lightPaletteUsesDeeperTonesOfTheSameHues() {
        #expect(ContourMarkPalette.light.outer == (0x1F, 0x95, 0x9E))
        #expect(ContourMarkPalette.light.inner == (0xE0, 0x98, 0x12))
    }

    @Test func forSchemePicksDarkOnlyForDarkAppearance() {
        #expect(ContourMarkPalette.forScheme(.dark).outer == ContourMarkPalette.dark.outer)
        #expect(ContourMarkPalette.forScheme(.light).outer == ContourMarkPalette.light.outer)
    }

    @Test func lineColorRunsFromOuterAtTheBaseToThePeakAtTheSummit() {
        let palette = ContourMarkPalette.dark
        let expectedOuter = Color(
            .sRGB, red: palette.outer.0 / 255, green: palette.outer.1 / 255, blue: palette.outer.2 / 255)
        #expect(palette.line(level: 0) == expectedOuter)
        #expect(palette.line(level: 1) == palette.peak)
    }

    @Test func boundsAreWiderThanTallMatchingTheDocumentedAspectRatio() {
        #expect(ContourMarkGeometry.bounds.width > 0 && ContourMarkGeometry.bounds.height > 0)
        #expect(ContourMarkGeometry.aspectRatio > 1.3 && ContourMarkGeometry.aspectRatio < 1.5)
    }

    @Test func ringPointsReturnsExactlyTheRequestedCount() {
        let points = ContourMarkGeometry.ringPoints(centre: .zero, radius: 10, level: 0.5, count: 12)
        #expect(points.count == 12)
    }

    @Test func isCompactOnlyBelowTheThreshold() {
        #expect(ContourMarkView.isCompact(height: 39.999) == true)
        #expect(ContourMarkView.isCompact(height: 40) == false)
        #expect(ContourMarkView.isCompact(height: 104) == false)
    }

    @Test func visibleRingIndicesDropsEveryOtherRingWhenCompact() {
        #expect(ContourMarkGeometry.ringCount == 7, "the expectations below are written for 7 rings")
        #expect(ContourMarkView.visibleRingIndices(compact: false) == [0, 1, 2, 3, 4, 5, 6])
        #expect(ContourMarkView.visibleRingIndices(compact: true) == [0, 2, 4, 6])
    }

    @Test func lineWeightIsHeavierWhenCompact() {
        #expect(ContourMarkView.lineWeight(compact: false) == 1.25)
        #expect(ContourMarkView.lineWeight(compact: true) == 1.4)
        #expect(ContourMarkView.lineWeight(compact: true) > ContourMarkView.lineWeight(compact: false))
    }

    @Test func minStrokeWidthScalesInverselyWithTheDrawScale() {
        #expect(ContourMarkView.minStrokeWidth(compact: false, scale: 1) == 0.9)
        #expect(ContourMarkView.minStrokeWidth(compact: true, scale: 1) == 1.1)
        #expect(ContourMarkView.minStrokeWidth(compact: false, scale: 2) == 0.45)
    }

    @Test func strokeWidthNeverGoesBelowTheMinimum() {
        let proportional = ContourMarkGeometry.stroke * 1.0 * 1.25
        #expect(ContourMarkView.strokeWidth(widthFactor: 1.0, weight: 1.25, minWidth: 0) == proportional)
        #expect(ContourMarkView.strokeWidth(widthFactor: 0, weight: 1.25, minWidth: 5) == 5)
    }

    @Test func traceAlphaScalesWithRingOpacity() {
        #expect(ContourMarkView.traceAlpha(ringOpacity: 1.0) == 0.12)
        #expect(ContourMarkView.traceAlpha(ringOpacity: 0.5) == 0.06)
    }

    @Test func dotRadiusIsLargerWhenCompact() {
        #expect(ContourMarkView.dotRadius(compact: false) == ContourMarkGeometry.peakRadius)
        #expect(ContourMarkView.dotRadius(compact: true) == ContourMarkGeometry.peakRadius * 1.5)
    }

    @Test func circleRectIsCenteredOnThePointWithSideTwiceTheRadius() {
        let rect = ContourMarkView.circleRect(center: CGPoint(x: 10, y: 20), radius: 5)
        #expect(rect == CGRect(x: 5, y: 15, width: 10, height: 10))
    }

    @Test func haloRectIsCenteredOnThePeakWithTheHaloRadius() {
        let expected = CGRect(
            x: ContourMarkGeometry.peak.x - ContourMarkGeometry.haloRadius,
            y: ContourMarkGeometry.peak.y - ContourMarkGeometry.haloRadius,
            width: ContourMarkGeometry.haloRadius * 2,
            height: ContourMarkGeometry.haloRadius * 2)
        #expect(ContourMarkView.haloRect == expected)
        #expect(ContourMarkGeometry.haloRadius == ContourMarkGeometry.peakRadius * 2.2)
    }

    @Test func haloOpacityFadesInWithThePeakStage() {
        #expect(ContourMarkView.haloOpacity(peakStage: 0) == 0)
        #expect(ContourMarkView.haloOpacity(peakStage: 1) == 0.18)
    }

    @Test func peakDotOpacityIsFlooredThenReachesFullOpacity() {
        #expect(ContourMarkView.peakDotOpacity(peakStage: 0) == 0.12)
        #expect(ContourMarkView.peakDotOpacity(peakStage: 1) == 1)
    }

    @Test func heroHeightIsUsedOnTheWelcomeAndAnalysisScreens() {
        #expect(ContourMarkView.heroHeight == 104)
    }

    @Test func nothingIsResolvedAtZeroAndEverythingAtOne() {
        let none = ContourResolution.stages(0)
        #expect(none.peak == 0)
        #expect(none.rings.allSatisfy { $0 == 0 })

        let all = ContourResolution.stages(1)
        #expect(all.peak == 1)
        #expect(all.rings.allSatisfy { $0 == 1 })
    }

    @Test func peakResolvesFirstThenRingsFromTheSummitOutward() {
        for r in stride(from: 0.0, through: 1.0, by: 0.01) {
            let s = ContourResolution.stages(r)
            let order = [s.peak] + s.rings.reversed()
            for (earlier, later) in zip(order, order.dropFirst()) {
                #expect(earlier >= later, "at \(r)")
            }
        }
    }

    @Test func consecutiveRingsOverlapSoTheDrawingNeverStops() {
        let overlapping = stride(from: 0.0, through: 1.0, by: 0.01).contains { r in
            let s = ContourResolution.stages(r)
            return ([s.peak] + s.rings).filter { $0 > 0 && $0 < 1 }.count > 1
        }
        #expect(overlapping)
    }
}
