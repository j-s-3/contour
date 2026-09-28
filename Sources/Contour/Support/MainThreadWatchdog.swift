#if DEBUG
import Foundation
import os

/// Logs when the main thread stops returning to its run loop for longer than a threshold,
/// so a slow main-actor call — synchronous file I/O, a big `UnifiedDiff.parse`, a
/// `GraphLayoutEngine.layout` pass, `ArchitectureDiagramView`'s NSFont measurement — shows
/// up in the console the moment it happens during manual testing, instead of only being
/// felt as the window briefly not responding (§13/§14: the same scaling limits this exists
/// to catch during development). Debug builds only; see `ContourApp` for where it starts
/// and `Package.swift` for why the target can carry `#if DEBUG`-gated code like this.
///
/// A `CFRunLoopObserver` on the main run loop stamps a shared "last beat" time on every
/// activity it's notified of (about to process a source or timer, about to wait, ...). A
/// background `DispatchSourceTimer` wakes on a short interval and compares now against that
/// stamp: once the gap passes `thresholdMs`, the main thread hasn't returned to the run
/// loop in at least that long, which means it's still inside whatever it was doing when the
/// last beat landed. Logged once per stall, with the elapsed time, not once per poll — the
/// next beat (the main thread coming up for air) re-arms it.
enum MainThreadWatchdog {
    /// How long the main thread can go unresponsive before it's logged as blocked.
    static let defaultThresholdMs: Double = 250
    /// How often the background timer checks in. Small relative to the default threshold
    /// so the logged elapsed time is close to the real one, not off by a whole interval.
    private static let pollInterval: TimeInterval = 0.05

    private static let logger = Logger(subsystem: "com.contour.app", category: "MainThreadWatchdog")

    /// Shared between the run loop observer (fires on the main thread) and the polling
    /// timer (fires on a background queue), so its own state is behind a lock — same
    /// pattern as `ShellProcess.swift`'s `DataBox`. Internal rather than `private` so
    /// `MainThreadWatchdogTests` can drive the threshold/stall logic directly with
    /// `@testable import`, without waiting on a real run loop or timer.
    final class Beat: @unchecked Sendable {
        private let lock = NSLock()
        private var lastBeat = DispatchTime.now()
        private var stalled = false

        func touch() {
            lock.withLock {
                lastBeat = DispatchTime.now()
                stalled = false
            }
        }

        /// The elapsed time, the first poll after it crosses `thresholdMs`; nil on every
        /// poll after that until the main thread beats again, so one stall is logged once.
        func checkStall(thresholdMs: Double) -> Double? {
            lock.withLock {
                guard !stalled else { return nil }
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- lastBeat.uptimeNanoseconds) / 1_000_000
                guard elapsedMs >= thresholdMs else { return nil }
                stalled = true
                return elapsedMs
            }
        }
    }

    // Set once, from `start()`, and otherwise only read from the observer/timer callbacks
    // it installs — not a data race in practice, but marked unsafe rather than actor-bound
    // since this is a fire-and-forget diagnostic, not app state.
    nonisolated(unsafe) private static var beat: Beat?
    nonisolated(unsafe) private static var observer: CFRunLoopObserver?
    nonisolated(unsafe) private static var timer: DispatchSourceTimer?
    nonisolated(unsafe) private static var started = false

    /// Starts observing the main run loop. Safe to call more than once — only the first
    /// call does anything. Set `CONTOUR_DISABLE_WATCHDOG=1` to opt out entirely; on by
    /// default in debug builds, since it's inert (never installed) in a release build
    /// regardless of the environment. `environment` defaults to the real process
    /// environment; tests override it to exercise the opt-out without touching real
    /// process state (see the note on `CONTOUR_MOCK_ANALYSIS` in `CLAUDE.md` about why
    /// tests must not mutate process-global env vars).
    static func start(
        thresholdMs: Double = defaultThresholdMs,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard !started else { return }
        guard environment["CONTOUR_DISABLE_WATCHDOG"] != "1" else { return }
        started = true

        let beat = Beat()
        self.beat = beat

        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.allActivities.rawValue, true, 0
        ) { _, _ in beat.touch() }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.contour.app.watchdog", qos: .utility))
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler {
            if let elapsedMs = beat.checkStall(thresholdMs: thresholdMs) {
                logger.warning("Main thread blocked for \(Int(elapsedMs), privacy: .public) ms")
            }
        }
        timer.resume()
        self.timer = timer
    }
}
#endif
