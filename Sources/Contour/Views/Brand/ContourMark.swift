import SwiftUI

enum ContourMarkGeometry {
    static let ringCount = 7

    struct Ring {
        var level: Double
        var points: [CGPoint]
        var path: Path
        var widthFactor: Double
        var opacity: Double
    }

    private static let centre = CGPoint(x: 470, y: 570)
    private static let scale = 520.0
    static let stroke = 14.0

    static let peak = CGPoint(x: centre.x + scale * 0.24, y: centre.y - scale * 0.2)
    static let peakRadius = scale * 0.045
    static let haloRadius = peakRadius * 2.2

    static let rings: [Ring] = (0..<ringCount).map { k in
        let level = Double(k) / Double(ringCount - 1)
        let radius = scale * lerp(1.0, 0.17, pow(level, 0.75))
        let c = CGPoint(x: lerp(centre.x, peak.x, pow(level, 0.45)),
                        y: lerp(centre.y, peak.y, pow(level, 0.45)))
        let points = ringPoints(centre: c, radius: radius, level: level)
        return Ring(level: level, points: points, path: smoothPath(points),
                    widthFactor: lerp(0.8, 1.15, level), opacity: lerp(0.55, 1.0, level))
    }

    static let bounds: CGRect = {
        var box = rings[0].path.boundingRect
        for ring in rings { box = box.union(ring.path.boundingRect) }
        return box.insetBy(dx: -stroke * 1.2, dy: -stroke * 1.2)
    }()

    static var aspectRatio: Double { bounds.width / bounds.height }

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

struct ContourMarkPalette {
    var outer: (Double, Double, Double)
    var inner: (Double, Double, Double)

    static let dark = ContourMarkPalette(outer: (0x3F, 0xC1, 0xC9), inner: (0xFF, 0xC8, 0x57))
    static let light = ContourMarkPalette(outer: (0x1F, 0x95, 0x9E), inner: (0xE0, 0x98, 0x12))

    static func forScheme(_ scheme: ColorScheme) -> ContourMarkPalette { scheme == .dark ? .dark : .light }

    func line(level: Double) -> Color {
        let t = pow(level, 1.4)
        let l = ContourMarkGeometry.lerp
        return Color(.sRGB, red: l(outer.0, inner.0, t) / 255, green: l(outer.1, inner.1, t) / 255,
                     blue: l(outer.2, inner.2, t) / 255)
    }

    var peak: Color { line(level: 1) }
}

struct ContourMarkView: View {
    var resolution: Double = 1
    var drawsProgressively = true

    @Environment(\.colorScheme) private var colorScheme

    nonisolated static let heroHeight: CGFloat = 104

    nonisolated private static let compactHeight: CGFloat = 40

    nonisolated private static let traceOpacity = 0.12

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .aspectRatio(ContourMarkGeometry.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }

    nonisolated static func isCompact(height: CGFloat) -> Bool { height < compactHeight }

    nonisolated static func visibleRingIndices(compact: Bool) -> [Int] {
        ContourMarkGeometry.rings.indices.filter { !compact || $0 % 2 == 0 }
    }

    nonisolated static func lineWeight(compact: Bool) -> Double { compact ? 1.4 : 1.25 }

    nonisolated static func minStrokeWidth(compact: Bool, scale: Double) -> Double {
        (compact ? 1.1 : 0.9) / scale
    }

    nonisolated static func strokeWidth(widthFactor: Double, weight: Double, minWidth: Double) -> Double {
        max(ContourMarkGeometry.stroke * widthFactor * weight, minWidth)
    }

    nonisolated static func traceAlpha(ringOpacity: Double) -> Double { ringOpacity * Self.traceOpacity }

    nonisolated static func dotRadius(compact: Bool) -> Double {
        compact ? ContourMarkGeometry.peakRadius * 1.5 : ContourMarkGeometry.peakRadius
    }

    nonisolated static func circleRect(center: CGPoint, radius: Double) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    nonisolated static var haloRect: CGRect {
        circleRect(center: ContourMarkGeometry.peak, radius: ContourMarkGeometry.haloRadius)
    }

    nonisolated static func haloOpacity(peakStage: Double) -> Double { 0.18 * peakStage }

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

enum ContourResolution {
    struct Stages {
        var peak: Double
        var rings: [Double]
        func ring(_ index: Int) -> Double { rings[index] }
    }

    static func stages(_ resolution: Double) -> Stages {
        let r = min(max(resolution, 0), 1)
        let parts = Double(ContourMarkGeometry.ringCount + 1)
        let overlap = 0.25
        let unit = 1 / ((parts - 1) * (1 - overlap) + 1)
        func share(_ order: Int) -> Double {
            let begin = Double(order) * unit * (1 - overlap)
            let amount = (r - begin) / unit
            return amount > 1 - 1e-9 ? 1 : max(amount, 0)
        }
        let count = ContourMarkGeometry.ringCount
        return Stages(peak: share(0), rings: (0..<count).map { share(count - $0) })
    }
}
