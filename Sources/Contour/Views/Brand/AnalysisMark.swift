import SwiftUI

enum AnalysisResolution {
    private static let slices: [(stage: PipelineStage, start: Double, typicalSeconds: Double)] = [
        (.fetching, 0.00, 4),
        (.checkingOut, 0.04, 10),
        (.cacheCheck, 0.10, 2),
        (.ticket, 0.12, 4),
        (.behaviorChange, 0.14, 45),
        (.understanding, 0.24, 45),
        (.architecture, 0.36, 60),
        (.decisions, 0.54, 120),
        (.flows, 0.72, 120),
        (.judgment, 0.86, 90),
    ]

    static func target(state: AnalysisState) -> Double {
        guard !state.isComplete else { return 1 }
        guard let first = slices.firstIndex(where: { PipelineStage.analysis.contains($0.stage) }) else { return 1 }
        var total = slices[first].start
        for i in first..<slices.count where state.status(slices[i].stage).isSettled {
            let end = i + 1 < slices.count ? slices[i + 1].start : 1
            total += end - slices[i].start
        }
        return total
    }

    static func target(stage: PipelineStage, elapsed: TimeInterval) -> Double {
        guard let i = slices.firstIndex(where: { $0.stage == stage }) else { return 1 }
        let slice = slices[i]
        let end = i + 1 < slices.count ? slices[i + 1].start : 1
        let progress = 1 - exp(-max(elapsed, 0) / (slice.typicalSeconds * 0.9))
        return slice.start + (end - slice.start) * progress
    }

    static func approach(from current: Double, to target: Double, over dt: TimeInterval) -> Double {
        guard target > current else { return current }
        let step = (target - current) * min(max(dt, 0) / 0.5, 1)
        return min(current + step, target)
    }

    static func steppedTarget(stage: PipelineStage, elapsed: TimeInterval, ringCount: Int) -> Double {
        let steps = Double(ringCount + 1)
        return (target(stage: stage, elapsed: elapsed) * steps).rounded(.down) / steps
    }
}

struct AnalyzingMark: View {
    let stage: PipelineStage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stageStarted = Date()
    @State private var smoother = Smoother()

    var body: some View {
        Group {
            if reduceMotion {
                let stepped = AnalysisResolution.steppedTarget(
                    stage: stage, elapsed: 0,
                    ringCount: ContourMarkGeometry.ringCount)
                ContourMarkView(resolution: stepped, drawsProgressively: false)
                    .animation(.easeInOut(duration: 0.8), value: stepped)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let target = AnalysisResolution.target(
                        stage: stage,
                        elapsed: timeline.date.timeIntervalSince(stageStarted))
                    ContourMarkView(resolution: smoother.value(toward: target, at: timeline.date))
                }
            }
        }
        .onChange(of: stage) { _, _ in stageStarted = Date() }
    }

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
