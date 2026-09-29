#if DEBUG
import Foundation
import Testing
@testable import Contour

struct MainThreadWatchdogTests {
    @Test func freshBeatWithHighThresholdIsNotStalled() {
        let beat = MainThreadWatchdog.Beat()
        beat.touch()
        #expect(beat.checkStall(thresholdMs: 60_000) == nil)
    }

    @Test func zeroThresholdAlwaysReportsAStall() {
        let beat = MainThreadWatchdog.Beat()
        beat.touch()
        let elapsed = beat.checkStall(thresholdMs: 0)
        #expect(elapsed != nil)
        #expect(elapsed! >= 0)
    }

    @Test func stallIsReportedOnlyOnceUntilTheNextTouch() {
        let beat = MainThreadWatchdog.Beat()
        beat.touch()
        #expect(beat.checkStall(thresholdMs: 0) != nil, "first poll past threshold should report")
        #expect(beat.checkStall(thresholdMs: 0) == nil, "already-reported stall should not report again")
    }

    @Test func touchRearmsAfterAReportedStall() {
        let beat = MainThreadWatchdog.Beat()
        beat.touch()
        #expect(beat.checkStall(thresholdMs: 0) != nil)
        beat.touch()
        #expect(beat.checkStall(thresholdMs: 0) != nil, "touch() should re-arm reporting")
    }

    @Test func startIsANoOpWhenDisabledViaEnvironment() {
        MainThreadWatchdog.start(thresholdMs: 1, environment: ["CONTOUR_DISABLE_WATCHDOG": "1"])
    }

    @Test func startInstallsOnceAndIsIdempotentOnRepeatedCalls() {
        MainThreadWatchdog.start(thresholdMs: 60_000, environment: [:])
        MainThreadWatchdog.start(thresholdMs: 60_000, environment: [:])
    }
}
#endif
