import SwiftUI

/// How much of the Contour mark to resolve while a PR is analyzed.
///
/// Not a percentage-complete meter: the pipeline can't know how long a harness call will
/// take. Each stage owns a slice of the mark sized by how much it typically costs, and
/// within a stage the mark eases toward the end of that slice without reaching it, so a
/// long stage keeps creeping instead of freezing, and never claims to be finished before
/// it is.
enum AnalysisResolution {
    /// Pipeline order, each with where its slice of the mark starts and how long it
    /// usually runs. The quick mechanical stages resolve the peak; the model stages
    /// resolve the rings.
    private static let slices: [(stage: PipelineStage, start: Double, typicalSeconds: Double)] = [
        (.fetching, 0.00, 4),
        (.checkingOut, 0.04, 10),
        (.cacheCheck, 0.10, 2),
        (.ticket, 0.12, 4),
        (.behaviorChange, 0.14, 45),
        (.architecture, 0.24, 60),
        (.intent, 0.36, 40),
        (.eli5, 0.44, 45),
        (.decisions, 0.54, 120),
        (.flows, 0.72, 120),
        (.judgment, 0.86, 90),
    ]

    /// The resolution `elapsed` seconds into `stage`.
    static func target(stage: PipelineStage, elapsed: TimeInterval) -> Double {
        guard let i = slices.firstIndex(where: { $0.stage == stage }) else { return 1 } // .done
        let slice = slices[i]
        let end = i + 1 < slices.count ? slices[i + 1].start : 1
        // Two-thirds of the way through the slice at the typical duration, ~95% at triple.
        let progress = 1 - exp(-max(elapsed, 0) / (slice.typicalSeconds * 0.9))
        return slice.start + (end - slice.start) * progress
    }

    /// Moves the drawn resolution toward the target over about half a second, so a stage
    /// that finishes early finishes its ring instead of snapping. Never moves backward.
    static func approach(from current: Double, to target: Double, over dt: TimeInterval) -> Double {
        guard target > current else { return current }
        let step = (target - current) * min(max(dt, 0) / 0.5, 1)
        return min(current + step, target)
    }
}

/// The large mark shown while a PR is analyzed, resolving as the pipeline advances.
struct AnalyzingMark: View {
    let stage: PipelineStage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stageStarted = Date()
    @State private var smoother = Smoother()

    var body: some View {
        Group {
            if reduceMotion {
                // No drawing motion: whole rings fade in, one at a time, as stages complete.
                let rings = Double(ContourMarkGeometry.ringCount + 1)
                let stepped = (AnalysisResolution.target(stage: stage, elapsed: 0) * rings).rounded(.down) / rings
                ContourMarkView(resolution: stepped, drawsProgressively: false)
                    .animation(.easeInOut(duration: 0.8), value: stepped)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let target = AnalysisResolution.target(stage: stage,
                                                           elapsed: timeline.date.timeIntervalSince(stageStarted))
                    ContourMarkView(resolution: smoother.value(toward: target, at: timeline.date))
                }
            }
        }
        .onChange(of: stage) { _, _ in stageStarted = Date() }
    }

    /// Frame-to-frame memory for `AnalysisResolution.approach`. A plain class, not state:
    /// it changes every frame and must not itself invalidate the view.
    final class Smoother {
        private var current = 0.0
        private var last: Date?

        func value(toward target: Double, at date: Date) -> Double {
            let dt = last.map { date.timeIntervalSince($0) } ?? 0
            last = date
            current = AnalysisResolution.approach(from: current, to: target, over: dt)
            return current
        }
    }
}

/// The small mark in the review toolbar. The review opens once analysis is done, so it
/// arrives resolved, says so, and fades away after a few seconds.
struct AnalysisStatusIndicator: View {
    /// Identifies the analysis, so opening another PR shows the status again.
    let id: String
    let fromCache: Bool

    @State private var visible = true

    var body: some View {
        HStack(spacing: 6) {
            if visible {
                ContourMarkView()
                    .frame(height: 13)
                Text(fromCache ? "Opened saved analysis" : "Analysis complete")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .transition(.opacity)
        .task(id: id) {
            visible = true
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeOut(duration: 0.8)) { visible = false }
        }
    }
}
