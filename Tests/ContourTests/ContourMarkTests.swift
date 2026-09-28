import Testing
import Foundation
import SwiftUI
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

    /// The light-appearance palette uses deeper tones of the same two hues as dark, per
    /// its doc comment, rather than the icon's own (pale-on-dark-tile) colours.
    @Test func lightPaletteUsesDeeperTonesOfTheSameHues() {
        #expect(ContourMarkPalette.light.outer == (0x1F, 0x95, 0x9E))
        #expect(ContourMarkPalette.light.inner == (0xE0, 0x98, 0x12))
    }

    @Test func forSchemePicksDarkOnlyForDarkAppearance() {
        #expect(ContourMarkPalette.forScheme(.dark).outer == ContourMarkPalette.dark.outer)
        #expect(ContourMarkPalette.forScheme(.light).outer == ContourMarkPalette.light.outer)
    }

    /// The line warms from the outer hue at the base to the inner (peak) hue at the summit.
    @Test func lineColorRunsFromOuterAtTheBaseToThePeakAtTheSummit() {
        let palette = ContourMarkPalette.dark
        let expectedOuter = Color(.sRGB, red: palette.outer.0 / 255, green: palette.outer.1 / 255, blue: palette.outer.2 / 255)
        #expect(palette.line(level: 0) == expectedOuter)
        #expect(palette.line(level: 1) == palette.peak)
    }

    // MARK: - Geometry

    /// The mark is documented as "about 1.4:1", wider than tall.
    @Test func boundsAreWiderThanTallMatchingTheDocumentedAspectRatio() {
        #expect(ContourMarkGeometry.bounds.width > 0 && ContourMarkGeometry.bounds.height > 0)
        #expect(ContourMarkGeometry.aspectRatio > 1.3 && ContourMarkGeometry.aspectRatio < 1.5)
    }

    @Test func ringPointsReturnsExactlyTheRequestedCount() {
        let points = ContourMarkGeometry.ringPoints(centre: .zero, radius: 10, level: 0.5, count: 12)
        #expect(points.count == 12)
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
}
