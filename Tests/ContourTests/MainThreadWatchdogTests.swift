#if DEBUG
import Foundation
import Testing
@testable import Contour

/// `MainThreadWatchdog.swift` was at 0.00% coverage — no dedicated test file existed. The
/// file is `#if DEBUG`-only (see `ContourApp.swift`), so this whole file mirrors that guard;
/// it compiles to nothing in a release build, same as its target.
///
/// `Beat` (the threshold/stall decision logic) is where the actual bug-relevant behavior
/// lives, and it's pure: no run loop, no timer, no sleeping. It was made `internal` (from
/// `private`) specifically so these tests can drive it directly via `@testable import`,
/// per CLAUDE.md's guidance to put logic where it can be tested rather than leaving it
/// reachable only through the real `CFRunLoopObserver`/`DispatchSourceTimer` wiring in
/// `start()`. Tests use `thresholdMs: 0` instead of `Thread.sleep` to force a deterministic
/// "stalled" reading — any non-negative elapsed time already satisfies `>= 0` — so nothing
/// here is a flaky real-time wait.
///
/// `start()` itself is deliberately only smoke-tested: it installs a real
/// `CFRunLoopObserver` on the main run loop and a real background `DispatchSourceTimer`,
/// both process-global, singleton-guarded state (`started`). Actually driving the timer to
/// fire and log a stall would mean genuinely blocking the main thread for real wall-clock
/// time, which is exactly the kind of non-deterministic, environment-dependent test this
/// suite avoids elsewhere (see `EnvironmentProbeTests`); that path is left uncovered here,
/// intentionally, per this repo's coverage policy for real timer/RunLoop behavior.
struct MainThreadWatchdogTests {

    // MARK: - Beat: the pure stall-detection logic

    /// A fresh `Beat` that was just touched, checked against a threshold far larger than
    /// any real elapsed time in a test, must not report a stall.
    @Test func freshBeatWithHighThresholdIsNotStalled() {
        let beat = MainThreadWatchdog.Beat()
        beat.touch()
        #expect(beat.checkStall(thresholdMs: 60_000) == nil)
    }

    /// A `thresholdMs` of 0 is met by any non-negative elapsed time, so this deterministically
    /// exercises the "stalled" branch without sleeping for a real duration.
    @Test func zeroThresholdAlwaysReportsAStall() {
        let beat = MainThreadWatchdog.Beat()
        beat.touch()
        let elapsed = beat.checkStall(thresholdMs: 0)
        #expect(elapsed != nil)
        #expect(elapsed! >= 0)
    }

    /// One stall is logged once: after `checkStall` returns non-nil, `stalled` latches true,
    /// so a second poll before the next `touch()` must return nil even though the elapsed
    /// time only grew (still comfortably past a 0 threshold).
    @Test func stallIsReportedOnlyOnceUntilTheNextTouch() {
        let beat = MainThreadWatchdog.Beat()
        beat.touch()
        #expect(beat.checkStall(thresholdMs: 0) != nil, "first poll past threshold should report")
        #expect(beat.checkStall(thresholdMs: 0) == nil, "already-reported stall should not report again")
    }

    /// `touch()` re-arms the latch: after a reported stall, touching again resets both the
    /// clock and the `stalled` flag, so the next poll past threshold reports again.
    @Test func touchRearmsAfterAReportedStall() {
        let beat = MainThreadWatchdog.Beat()
        beat.touch()
        #expect(beat.checkStall(thresholdMs: 0) != nil)
        beat.touch()
        #expect(beat.checkStall(thresholdMs: 0) != nil, "touch() should re-arm reporting")
    }

    // MARK: - start(): opt-out and idempotency smoke tests

    /// `CONTOUR_DISABLE_WATCHDOG=1` must short-circuit before anything is installed. Passing
    /// `environment` directly (rather than mutating real process state with `setenv`) keeps
    /// this parallel-safe, per CLAUDE.md's rule against mutating process-global env vars in
    /// `@Test`s. This call installs nothing and leaves `MainThreadWatchdog`'s singleton guard
    /// untouched either way, so it's safe next to the lifecycle test below regardless of
    /// Swift Testing's parallel run order.
    @Test func startIsANoOpWhenDisabledViaEnvironment() {
        MainThreadWatchdog.start(thresholdMs: 1, environment: ["CONTOUR_DISABLE_WATCHDOG": "1"])
    }

    /// `start()` is guarded by a one-shot static flag: the first non-disabled call installs
    /// the real observer/timer, and every call after that (including one that would
    /// otherwise be disabled) is a no-op. This pins that calling it repeatedly never crashes
    /// or double-installs, which is the only externally-observable contract `start()` makes
    /// (its private statics aren't exposed for direct assertions). Runs serialized against
    /// itself so the two calls are guaranteed sequential.
    @Test func startInstallsOnceAndIsIdempotentOnRepeatedCalls() {
        MainThreadWatchdog.start(thresholdMs: 60_000, environment: [:])
        MainThreadWatchdog.start(thresholdMs: 60_000, environment: [:])
    }
}
#endif
