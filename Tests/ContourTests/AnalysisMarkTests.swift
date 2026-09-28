import Testing
import Foundation
@testable import Contour

/// `AnalysisMark.swift` draws the mark shown while a PR is analyzed. Its only real logic —
/// how much of the mark each pipeline stage resolves, how the drawn value eases toward
/// that target, and how Reduce Motion quantizes it — lives in `AnalysisResolution` and
/// `AnalyzingMark.Smoother`, both plain (non-View) types, so it's pinned here directly.
/// The view body itself (`Group`, `TimelineView`, `.onChange`) has no UI-testing
/// infrastructure in this suite to host it, per CLAUDE.md's guidance for this file.
struct AnalysisMarkTests {

    // MARK: - Pipeline-stage slices

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

    // MARK: - Reduce Motion's stepped resolution

    /// `steppedTarget` is what `AnalyzingMark.body`'s Reduce Motion branch draws: the same
    /// `target(stage:elapsed:)` value, quantized down to a whole ring-step so a ring fades
    /// in all at once instead of animating a line growing across it.
    @Test func steppedTargetQuantizesDownToWholeRingSteps() {
        let ringCount = 7
        let steps = Double(ringCount + 1)
        for elapsed in stride(from: 0.0, through: 200.0, by: 3.7) {
            let raw = AnalysisResolution.target(stage: .architecture, elapsed: elapsed)
            let stepped = AnalysisResolution.steppedTarget(stage: .architecture, elapsed: elapsed, ringCount: ringCount)
            // Always a multiple of 1/steps, and never ahead of the true (un-stepped) target.
            let scaled = stepped * steps
            #expect(abs(scaled - scaled.rounded()) < 1e-9, "stepped=\(stepped) at elapsed=\(elapsed)")
            #expect(stepped <= raw + 1e-9)
            #expect(raw - stepped < 1 / steps + 1e-9, "quantization should never fall a whole step behind")
        }
    }

    @Test func steppedTargetIsZeroAtTheStartOfTheFirstStage() {
        #expect(AnalysisResolution.steppedTarget(stage: .fetching, elapsed: 0, ringCount: 7) == 0)
    }

    /// A finished analysis (elapsed far past every stage's typical duration) still steps up
    /// to the final whole step, not past 1.
    @Test func steppedTargetNeverExceedsOne() {
        let stepped = AnalysisResolution.steppedTarget(stage: .judgment, elapsed: 100_000, ringCount: 7)
        #expect(stepped <= 1)
    }

    /// A different ring count changes the step size, not just a constant offset.
    @Test func steppedTargetStepSizeTracksRingCount() {
        let elapsed = 30.0
        let finer = AnalysisResolution.steppedTarget(stage: .understanding, elapsed: elapsed, ringCount: 15)
        let coarser = AnalysisResolution.steppedTarget(stage: .understanding, elapsed: elapsed, ringCount: 3)
        let raw = AnalysisResolution.target(stage: .understanding, elapsed: elapsed)
        #expect(abs(finer - raw) <= abs(coarser - raw) + 1e-9, "more steps quantizes closer to the true target")
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
