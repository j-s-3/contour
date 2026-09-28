import SwiftUI

/// The Contour mark without the app-icon tile: nested contour rings climbing to one
/// highlighted peak. The rounded-square icon stays the macOS app icon (Dock, Finder,
/// Spotlight); inside the app, this raw mark is the brand.
///
/// The geometry is a port of `mark()` in `scripts/generate-logo.py`, not a trace of its
/// output, so the app can draw each ring on its own and animate it. `ContourMarkTests`
/// checks every ring against `Assets/Logo/contour-icon.svg`, so the two can't drift.
enum ContourMarkGeometry {
    static let ringCount = 7

    /// One contour line, in the 1024-point icon canvas. Index 0 is the outermost ring.
    struct Ring {
        var level: Double
        var points: [CGPoint]
        var path: Path
        /// Relative to the icon's stroke of 14.
        var widthFactor: Double
        var opacity: Double
    }

    // Same arguments `tile()` passes to `mark()`.
    private static let centre = CGPoint(x: 470, y: 570)
    private static let scale = 520.0
    static let stroke = 14.0

    static let peak = CGPoint(x: centre.x + scale * 0.24, y: centre.y - scale * 0.2)
    static let peakRadius = scale * 0.045
    static let haloRadius = peakRadius * 2.2

    static let rings: [Ring] = (0..<ringCount).map { k in
        let level = Double(k) / Double(ringCount - 1)
        // Rings step inward non-linearly and their centres race toward the peak, so the
        // lines crowd on the steep north-east slope.
        let radius = scale * lerp(1.0, 0.17, pow(level, 0.75))
        let c = CGPoint(x: lerp(centre.x, peak.x, pow(level, 0.45)),
                        y: lerp(centre.y, peak.y, pow(level, 0.45)))
        let points = ringPoints(centre: c, radius: radius, level: level)
        return Ring(level: level, points: points, path: smoothPath(points),
                    widthFactor: lerp(0.8, 1.15, level), opacity: lerp(0.55, 1.0, level))
    }

    /// Everything the mark draws, strokes included, in canvas coordinates. The mark is
    /// wider than tall (about 1.4:1) and its peak sits up and to the right of centre.
    static let bounds: CGRect = {
        var box = rings[0].path.boundingRect
        for ring in rings { box = box.union(ring.path.boundingRect) }
        return box.insetBy(dx: -stroke * 1.2, dy: -stroke * 1.2)
    }()

    static var aspectRatio: Double { bounds.width / bounds.height }

    /// One organic closed contour. Harmonics shrink with level so the summit is rounder.
    static func ringPoints(centre c: CGPoint, radius: Double, level: Double, count n: Int = 180) -> [CGPoint] {
        let wobble = lerp(1.0, 0.45, level)
        return (0..<n).map { i in
            let th = 2 * Double.pi * Double(i) / Double(n)
            let r = radius * (1
                + wobble * 0.16 * sin(th + 0.6)
                + wobble * 0.13 * sin(2 * th + 1.9 + level * 0.7)
                + wobble * 0.07 * sin(3 * th + 0.4 - level * 0.9)
                + wobble * 0.035 * sin(5 * th + 2.2 + level * 1.2))
            return CGPoint(x: c.x + r * cos(th), y: c.y + r * sin(th) * 0.9)
        }
    }

    /// Closed Catmull-Rom spline through the points, as cubic Béziers — the same curve
    /// `smooth_path` writes into the SVG.
    static func bezierSegments(_ pts: [CGPoint]) -> [(c1: CGPoint, c2: CGPoint, end: CGPoint)] {
        let n = pts.count
        return (0..<n).map { i in
            let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            return (c1, c2, p2)
        }
    }

    private static func smoothPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: pts[0])
        for s in bezierSegments(pts) { path.addCurve(to: s.end, control1: s.c1, control2: s.c2) }
        path.closeSubpath()
        return path
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

/// The mark's colours: teal outer contours warming to an amber summit. The icon's
/// palette is drawn for its deep-ink tile, which is also what a dark window looks like.
/// On a light window pale amber all but disappears, so light appearance uses deeper
/// tones of the same two hues.
struct ContourMarkPalette {
    var outer: (Double, Double, Double)
    var inner: (Double, Double, Double)

    static let dark = ContourMarkPalette(outer: (0x3F, 0xC1, 0xC9), inner: (0xFF, 0xC8, 0x57))
    static let light = ContourMarkPalette(outer: (0x1F, 0x95, 0x9E), inner: (0xE0, 0x98, 0x12))

    static func forScheme(_ scheme: ColorScheme) -> ContourMarkPalette { scheme == .dark ? .dark : .light }

    /// Same easing as the generator: the colour warms late, near the summit.
    func line(level: Double) -> Color {
        let t = pow(level, 1.4)
        let l = ContourMarkGeometry.lerp
        return Color(.sRGB, red: l(outer.0, inner.0, t) / 255, green: l(outer.1, inner.1, t) / 255,
                     blue: l(outer.2, inner.2, t) / 255)
    }

    var peak: Color { line(level: 1) }
}

/// Draws the raw Contour mark, fully or partly resolved.
///
/// `resolution` runs from 0 (only a faint trace of the rings) to 1 (the whole mark). The
/// peak resolves first, then the rings from the summit outward — the shape of the change
/// coming into focus from its most important point. Only the ring being resolved moves;
/// nothing pulses or loops, so a stalled stage reads as "still working", not "thinking".
struct ContourMarkView: View {
    var resolution: Double = 1
    /// Draw the ring being resolved as a growing line. Off, rings fade in whole instead —
    /// what Reduce Motion gets.
    var drawsProgressively = true

    @Environment(\.colorScheme) private var colorScheme

    /// The mark's height on the welcome and analysis screens.
    nonisolated static let heroHeight: CGFloat = 104

    /// Below this height the inner rings crowd into a smudge, so the mark drops every
    /// other ring — the same optical simplification any logo gets at favicon size.
    nonisolated private static let compactHeight: CGFloat = 40

    /// How visible an unresolved ring is: enough that the shape is already there, faintly,
    /// before it is understood.
    nonisolated private static let traceOpacity = 0.12

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .aspectRatio(ContourMarkGeometry.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: - Pure state derivation (kept out of `draw` so it's testable without a
    // live GraphicsContext; see ContourMarkTests).

    /// Below `compactHeight` the inner rings crowd into a smudge, so the mark drops every
    /// other ring — the same optical simplification any logo gets at favicon size.
    nonisolated static func isCompact(height: CGFloat) -> Bool { height < compactHeight }

    /// Ring indices actually drawn: all of them normally, every other one when compact.
    /// Indexed like `ContourMarkGeometry.rings` (outermost first).
    nonisolated static func visibleRingIndices(compact: Bool) -> [Int] {
        ContourMarkGeometry.rings.indices.filter { !compact || $0 % 2 == 0 }
    }

    /// The icon crops the outer rings to its tile; showing them whole shrinks the mark
    /// about 1.4×, so the lines get some of that weight back — more of it when compact,
    /// where thin lines vanish first.
    nonisolated static func lineWeight(compact: Bool) -> Double { compact ? 1.4 : 1.25 }

    /// Keep strokes legible at small sizes: never thinner than ~1pt on screen. `scale` is
    /// the screen-points-per-canvas-point factor for the current draw.
    nonisolated static func minStrokeWidth(compact: Bool, scale: Double) -> Double {
        (compact ? 1.1 : 0.9) / scale
    }

    /// A single ring's stroke width: proportional to the icon's stroke and how far out the
    /// ring sits, floored at `minWidth` so it never goes illegibly thin.
    nonisolated static func strokeWidth(widthFactor: Double, weight: Double, minWidth: Double) -> Double {
        max(ContourMarkGeometry.stroke * widthFactor * weight, minWidth)
    }

    /// How visible an unresolved ring's faint trace is, scaled by that ring's own opacity.
    nonisolated static func traceAlpha(ringOpacity: Double) -> Double { ringOpacity * Self.traceOpacity }

    /// The dot at the peak is enlarged when compact, since a favicon-sized mark needs a
    /// bigger dot to read at all.
    nonisolated static func dotRadius(compact: Bool) -> Double {
        compact ? ContourMarkGeometry.peakRadius * 1.5 : ContourMarkGeometry.peakRadius
    }

    /// The square bounding a circle of `radius` centred on `center`.
    nonisolated static func circleRect(center: CGPoint, radius: Double) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// The soft halo behind the peak, sized off `ContourMarkGeometry.haloRadius`. Only drawn
    /// when not compact — there's no room for it at favicon size.
    nonisolated static var haloRect: CGRect {
        circleRect(center: ContourMarkGeometry.peak, radius: ContourMarkGeometry.haloRadius)
    }

    /// The halo fades in with the peak and is never fully opaque.
    nonisolated static func haloOpacity(peakStage: Double) -> Double { 0.18 * peakStage }

    /// The peak dot is never fully invisible even before resolving (floored at
    /// `traceOpacity`), then eases to fully opaque as `peakStage` reaches 1.
    nonisolated static func peakDotOpacity(peakStage: Double) -> Double {
        Self.traceOpacity + (1 - Self.traceOpacity) * peakStage
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let geo = ContourMarkGeometry.self
        let k = min(size.width / geo.bounds.width, size.height / geo.bounds.height)
        context.translateBy(x: (size.width - geo.bounds.width * k) / 2, y: (size.height - geo.bounds.height * k) / 2)
        context.scaleBy(x: k, y: k)
        context.translateBy(x: -geo.bounds.minX, y: -geo.bounds.minY)

        let palette = ContourMarkPalette.forScheme(colorScheme)
        let compact = Self.isCompact(height: size.height)
        let minWidth = Self.minStrokeWidth(compact: compact, scale: k)
        let weight = Self.lineWeight(compact: compact)
        let stages = ContourResolution.stages(resolution)

        for index in Self.visibleRingIndices(compact: compact) {
            let ring = geo.rings[index]
            let amount = stages.ring(index)
            let colour = palette.line(level: ring.level)
            let width = Self.strokeWidth(widthFactor: ring.widthFactor, weight: weight, minWidth: minWidth)
            let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)

            if amount < 1 {
                context.stroke(ring.path, with: .color(colour.opacity(Self.traceAlpha(ringOpacity: ring.opacity))), style: style)
            }
            guard amount > 0 else { continue }
            if drawsProgressively {
                context.stroke(ring.path.trimmedPath(from: 0, to: amount),
                               with: .color(colour.opacity(ring.opacity)), style: style)
            } else {
                context.stroke(ring.path, with: .color(colour.opacity(ring.opacity * amount)), style: style)
            }
        }

        // The peak fades in once and then holds still: no pulse.
        let peakStage = stages.peak
        let dotRadius = Self.dotRadius(compact: compact)
        let dot = Self.circleRect(center: geo.peak, radius: dotRadius)
        if !compact {
            context.fill(Path(ellipseIn: Self.haloRect), with: .color(palette.peak.opacity(Self.haloOpacity(peakStage: peakStage))))
        }
        context.fill(Path(ellipseIn: dot), with: .color(palette.peak.opacity(Self.peakDotOpacity(peakStage: peakStage))))
    }
}

extension View {
    /// Carries the mark from one screen to the next (welcome → analysis) so it reads as
    /// one object. Under Reduce Motion the screens just crossfade.
    func matchesContourMark(in namespace: Namespace.ID) -> some View {
        modifier(ContourMarkMatch(namespace: namespace))
    }
}

private struct ContourMarkMatch: ViewModifier {
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.matchedGeometryEffect(id: "contour-mark", in: namespace)
        }
    }
}

/// How far along each part of the mark is, for a given overall resolution. Pure, so the
/// ordering can be tested without drawing anything.
enum ContourResolution {
    struct Stages {
        /// 0...1 for the peak.
        var peak: Double
        /// 0...1 per ring, indexed outermost-first like `ContourMarkGeometry.rings`.
        var rings: [Double]
        func ring(_ index: Int) -> Double { rings[index] }
    }

    /// The peak, then the rings innermost to outermost, each taking an equal share of the
    /// resolution. Shares overlap slightly so one ring starts as the last one closes,
    /// rather than the drawing stopping dead between rings.
    static func stages(_ resolution: Double) -> Stages {
        let r = min(max(resolution, 0), 1)
        let parts = Double(ContourMarkGeometry.ringCount + 1)
        let overlap = 0.25
        // Consecutive shares start `unit * (1 - overlap)` apart and the last ends at 1.
        let unit = 1 / ((parts - 1) * (1 - overlap) + 1)
        func share(_ order: Int) -> Double {
            let begin = Double(order) * unit * (1 - overlap)
            // Snap the last sliver: rounding would otherwise leave the outermost ring a
            // hair short at full resolution, a visible gap where its line should close.
            let amount = (r - begin) / unit
            return amount > 1 - 1e-9 ? 1 : max(amount, 0)
        }
        let count = ContourMarkGeometry.ringCount
        // rings[0] is outermost, so it resolves last.
        return Stages(peak: share(0), rings: (0..<count).map { share(count - $0) })
    }
}
