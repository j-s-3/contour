import Foundation
import Testing
@testable import Contour

/// "Stop analysis": what landed stays, everything else is stopped and resumable one section
/// at a time, and stopping really ends the subprocesses that were billing for it.
struct StopAnalysisTests {

    /// Mid-run: two stages landed, one failed, two running, judgment not started.
    private func midRun() -> [PipelineStage: StageStatus] {
        [
            .fetching: .done, .checkingOut: .done, .cacheCheck: .done, .ticket: .running(detail: nil),
            .behaviorChange: .done, .understanding: .running(detail: nil),
            .architecture: .failed("boom"), .decisions: .running(detail: "2 found so far"),
            .flows: .stale,
        ]
    }

    private func stopped(_ statuses: [PipelineStage: StageStatus]) -> AnalysisState {
        var state = AnalysisState(stages: statuses)
        state.stages.merge(AnalysisState.stopping(statuses)) { _, new in new }
        return state
    }

    // MARK: - What stopping changes

    @Test func stoppingKeepsWhatLandedAndStopsEverythingElse() {
        let changes = AnalysisState.stopping(midRun())
        #expect(changes[.understanding] == .stopped)
        #expect(changes[.decisions] == .stopped)
        #expect(changes[.flows] == .stopped, "a slice from the previous revision still needed replacing")
        #expect(changes[.judgment] == .stopped, "a stage that never started is stopped too")
        #expect(changes[.behaviorChange] == nil)
        #expect(changes[.architecture] == nil, "a failure keeps its message")
        #expect(changes[.fetching] == nil)
    }

    @Test func anInterruptedIssueLookupIsSimplyOver() {
        #expect(AnalysisState.stopping(midRun())[.ticket] == .done)
    }

    @Test func stoppingAFinishedAnalysisChangesNothing() {
        var statuses: [PipelineStage: StageStatus] = [:]
        for stage in PipelineStage.allCases { statuses[stage] = .done }
        statuses[.flows] = .failed("boom")
        #expect(AnalysisState.stopping(statuses).isEmpty)
        #expect(!AnalysisState(stages: statuses).canStop)
    }

    // MARK: - The state it leaves

    @Test func afterStoppingNothingIsLeftToStopAndStoppedSectionsShow() {
        #expect(AnalysisState(stages: midRun()).canStop)
        let state = stopped(midRun())
        #expect(!state.canStop)
        #expect(state.remainingCount == 0)
        #expect(state.stoppedSections == [.whatChanged, .decisions, .flows, .questions])
        #expect(state.failedSections == [.architecture])
        #expect(state.sectionStatus(.context) == .done)
    }

    @Test func aStoppedStageOffersRetryLikeAFailedOne() {
        #expect(StageStatus.stopped.canRetry)
        #expect(StageStatus.failed("x").canRetry)
        #expect(StageStatus.stopped.isSettled)
        for status in [StageStatus.pending, .running(detail: nil), .done, .stale] {
            #expect(!status.canRetry)
        }
        let state = stopped(midRun())
        #expect(state.retryStage(for: .whatChanged) == .understanding, "not the before/after, which landed")
        #expect(state.retryStage(for: .questions) == .judgment)
        #expect(state.retryStage(for: .context) == nil)
    }

    @Test func aResumedStageReadsAsRunningAndMakesTheAnalysisStoppableAgain() {
        var state = stopped(midRun())
        state.stages[.decisions] = .running(detail: nil)
        #expect(state.sectionStatus(.decisions).isRunning)
        #expect(state.stoppedSections == [.whatChanged, .flows, .questions])
        #expect(state.canStop)
    }

    @Test func aFailureStillWinsOverAStopInTheSameSection() {
        var state = AnalysisState()
        state.stages[.behaviorChange] = .failed("boom")
        state.stages[.understanding] = .stopped
        #expect(state.sectionStatus(.whatChanged).failure == "boom")
    }

    @Test func aStoppedRunIsNotRecordedAsAFullOrUsefulAnalysis() {
        var state = stopped(midRun())
        state.isComplete = true
        var metrics = AnalysisMetrics(pr: "https://github.com/acme/shop/pull/7")
        metrics.update(state: state, graph: nil, diffAvailable: true)
        #expect(metrics.elapsed(.fullAnalysis) == nil)
        #expect(metrics.elapsed(.usefulOverview) == nil)
    }

    // MARK: - Subprocesses

    /// A `sleep` with a duration no other process will have, so `pgrep` finds only ours.
    private func uniqueSleep() -> String { "30.\(Int.random(in: 100_000...999_999))" }

    private func isRunning(_ commandLine: String) async -> Bool {
        (try? await Shell.run("/usr/bin/pgrep", ["-f", commandLine])) != nil
    }

    /// Whether the process is gone, allowing it a moment to exit after being signalled.
    private func exits(_ commandLine: String) async -> Bool {
        for _ in 0..<20 {
            guard await isRunning(commandLine) else { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    @Test func cancellingARunTerminatesItsProcess() async {
        let duration = uniqueSleep()
        let task = Task { try await Shell.run("/bin/sleep", [duration]) }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(await isRunning("sleep \(duration)"), "precondition: it started")
        task.cancel()
        let result = await task.result
        #expect(throws: (any Error).self) { try result.get() }
        #expect(await exits("sleep \(duration)"))
    }

    @Test func cancellingAStreamTerminatesItsProcess() async {
        let duration = uniqueSleep()
        let task = Task { for try await _ in Shell.stream("/bin/sleep", [duration]) {} }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(await isRunning("sleep \(duration)"), "precondition: it started")
        task.cancel()
        _ = await task.result
        #expect(await exits("sleep \(duration)"))
    }
}
