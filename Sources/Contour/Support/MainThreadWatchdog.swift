#if DEBUG
    import Foundation
    import os

    enum MainThreadWatchdog {
        static let defaultThresholdMs: Double = 250
        private static let pollInterval: TimeInterval = 0.05

        private static let logger = Logger(subsystem: "com.contour.app", category: "MainThreadWatchdog")

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

            func checkStall(thresholdMs: Double) -> Double? {
                lock.withLock {
                    guard !stalled else { return nil }
                    let elapsedMs =
                        Double(DispatchTime.now().uptimeNanoseconds &- lastBeat.uptimeNanoseconds) / 1_000_000
                    guard elapsedMs >= thresholdMs else { return nil }
                    stalled = true
                    return elapsedMs
                }
            }
        }

        @MainActor private static var beat: Beat?
        @MainActor private static var observer: CFRunLoopObserver?
        @MainActor private static var timer: any DispatchSourceTimer?
        @MainActor private static var started = false

        @MainActor static func start(
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
            ) { @Sendable _, _ in beat.touch() }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = observer

            let timer = DispatchSource.makeTimerSource(
                queue: DispatchQueue(label: "com.contour.app.watchdog", qos: .utility))
            timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
            timer.setEventHandler { @Sendable in
                if let elapsedMs = beat.checkStall(thresholdMs: thresholdMs) {
                    logger.warning("Main thread blocked for \(Int(elapsedMs), privacy: .public) ms")
                }
            }
            timer.resume()
            self.timer = timer
        }
    }
#endif
