import Foundation
import os

/// Where a line `Shell.stream` can't just drop gets logged instead — currently only
/// invalid-UTF-8 lines (see `Shell.stream`'s `yieldLine`).
private let shellLogger = Logger(subsystem: "Contour", category: "Shell")

/// Errors surfaced from shelling out to `gh`, `git`, or `pi`.
struct ProcessError: LocalizedError {
    let command: String
    let exitCode: Int32
    let stderr: String
    var errorDescription: String? {
        "`\(command)` exited \(exitCode): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

/// `Process`'s `readabilityHandler` and `terminationHandler` fire on GCD-managed queues
/// with no ordering guarantee relative to each other. This box gives both a single lock
/// around the buffer instead of a bare captured `var`, which is what Swift 6's strict
/// concurrency checking is (correctly) unhappy about otherwise.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    func snapshot() -> Data { lock.withLock { data } }
    func drain() -> Data { lock.withLock { let d = data; data = Data(); return d } }
}

/// Last-activity timestamp for `Shell.stream`'s inactivity watchdog, touched from the same
/// GCD-managed readability-handler queues `DataBox` guards against — so it needs the same
/// lock-protected box rather than a bare captured `var`.
private final class ActivityClock: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ContinuousClock.now
    func touch() { lock.withLock { last = ContinuousClock.now } }
    /// How long it's been since the last `touch()`.
    func idle() -> Duration { lock.withLock { ContinuousClock.now - last } }
}

/// Thin wrapper around Foundation.Process for the three external CLIs this app depends on:
/// `gh` (GitHub), `git` (checkout), and `pi` (AI analysis). No SDKs, no API keys held by this
/// app — every credential and network policy is inherited from whatever the CLI is already
/// configured with. See design doc §8, §9, §16.
enum Shell {

    /// Run a command to completion and return stdout as a String. Throws on non-zero exit.
    /// Cancelling the calling task terminates the process, so stopping an analysis
    /// mid-checkout doesn't leave the checkout running on.
    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: URL? = nil,
        stdin: String? = nil
    ) async throws -> String {
        try Task.checkCancellation()
        let process = Process()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.executableURL = resolveExecutable(executable)
                process.arguments = resolvedArguments(executable, arguments)
                if let cwd { process.currentDirectoryURL = cwd }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                if let stdin {
                    let inPipe = Pipe()
                    process.standardInput = inPipe
                    inPipe.fileHandleForWriting.write(Data(stdin.utf8))
                    try? inPipe.fileHandleForWriting.close()
                }

                let outBox = DataBox()
                let errBox = DataBox()
                // One lock around every read of either pipe: the readability handlers and
                // the termination-time drain below run on different queues, and two readers
                // pulling from the same descriptor at once could append chunks out of order.
                let ioLock = NSLock()
                outPipe.fileHandleForReading.readabilityHandler = { handle in
                    ioLock.withLock {
                        let d = handle.availableData
                        if d.isEmpty { outPipe.fileHandleForReading.readabilityHandler = nil }
                        else { outBox.append(d) }
                    }
                }
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    ioLock.withLock {
                        let d = handle.availableData
                        if d.isEmpty { errPipe.fileHandleForReading.readabilityHandler = nil }
                        else { errBox.append(d) }
                    }
                }

                process.terminationHandler = { proc in
                    // `terminationHandler` and `readabilityHandler` fire on independent GCD
                    // queues with no ordering guarantee, so a process that writes a burst and
                    // exits immediately can have this handler run before the last chunk was
                    // read. Clear the handlers and read whatever is left directly before
                    // snapshotting, rather than trust the handler already saw it.
                    ioLock.withLock {
                        outPipe.fileHandleForReading.readabilityHandler = nil
                        errPipe.fileHandleForReading.readabilityHandler = nil
                        if let remaining = (try? outPipe.fileHandleForReading.readToEnd()) ?? nil, !remaining.isEmpty {
                            outBox.append(remaining)
                        }
                        if let remaining = (try? errPipe.fileHandleForReading.readToEnd()) ?? nil, !remaining.isEmpty {
                            errBox.append(remaining)
                        }
                    }
                    let out = String(data: outBox.snapshot(), encoding: .utf8) ?? ""
                    let err = String(data: errBox.snapshot(), encoding: .utf8) ?? ""
                    if proc.terminationStatus == 0 {
                        continuation.resume(returning: out)
                    } else {
                        continuation.resume(throwing: ProcessError(
                            command: "\(executable) \(arguments.joined(separator: " "))",
                            exitCode: proc.terminationStatus,
                            stderr: err.isEmpty ? out : err
                        ))
                    }
                }

                // Cancelled while this was being set up: `onCancel` found nothing running
                // to terminate, so don't start it now.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Run a command, yielding stdout line by line as it streams. Used for `pi --mode json`
    /// so the UI can show real progress substeps instead of a spinner (§10).
    ///
    /// - Parameter inactivityTimeout: if the process produces no output at all (stdout or
    ///   stderr) for this long, it is killed and the stream finishes with a `ProcessError`
    ///   that says so, instead of waiting forever on a hung `claude`/`pi` process. Generous
    ///   by default so a slow model is never mistaken for a hang; tests pass a fraction of a
    ///   second to exercise the watchdog itself.
    static func stream(
        _ executable: String,
        _ arguments: [String],
        cwd: URL? = nil,
        inactivityTimeout: Duration = .seconds(600)
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = resolveExecutable(executable)
            process.arguments = resolvedArguments(executable, arguments)
            if let cwd { process.currentDirectoryURL = cwd }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let lineBuffer = DataBox()
            let errBox = DataBox()
            let activity = ActivityClock()
            // One lock around every read of either pipe and the line extraction that
            // follows it: the readability handlers and the termination-time drain run on
            // different queues, and two readers on one descriptor could reorder lines.
            let ioLock = NSLock()

            // Pulls complete lines out of `chunk` (appended after whatever partial line is
            // already buffered) and yields each one; leaves any partial line in `lineBuffer`
            // for the next chunk, or for the termination-time drain below.
            @Sendable func extractLines(from chunk: Data) {
                guard !chunk.isEmpty else { return }
                lineBuffer.append(chunk)
                var remainder = lineBuffer.drain()
                while let newlineRange = remainder.range(of: Data([0x0A])) {
                    let lineData = remainder.subdata(in: remainder.startIndex..<newlineRange.lowerBound)
                    remainder.removeSubrange(remainder.startIndex..<newlineRange.upperBound)
                    yieldLine(lineData)
                }
                if !remainder.isEmpty { lineBuffer.append(remainder) }
            }

            // A line that isn't valid UTF-8 used to be silently discarded here. Log it and
            // decode it lossily (replacement characters for the bad bytes) instead, so a
            // malformed line is visible — to the log, and still handed to the caller — rather
            // than just vanishing from the stream.
            @Sendable func yieldLine(_ lineData: Data) {
                guard !lineData.isEmpty else { return }
                if let line = String(data: lineData, encoding: .utf8) {
                    continuation.yield(line)
                } else {
                    let lossy = String(decoding: lineData, as: UTF8.self)
                    shellLogger.error(
                        "\(executable, privacy: .public): non-UTF-8 line from stream (\(lineData.count, privacy: .public) bytes), decoded lossily: \(lossy, privacy: .public)"
                    )
                    continuation.yield(lossy)
                }
            }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                ioLock.withLock {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        outPipe.fileHandleForReading.readabilityHandler = nil
                        return
                    }
                    activity.touch()
                    extractLines(from: chunk)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                ioLock.withLock {
                    let d = handle.availableData
                    if d.isEmpty { errPipe.fileHandleForReading.readabilityHandler = nil }
                    else { activity.touch(); errBox.append(d) }
                }
            }

            // Inactivity watchdog: polls rather than firing one timer, since any output
            // pushes the deadline back out. It sleeps for exactly however long is left
            // before checking again, so a generous default costs nothing while idle.
            let watchdog = Task {
                while !Task.isCancelled {
                    let idle = activity.idle()
                    if idle >= inactivityTimeout {
                        // Finish first, then kill: once the process is terminated its
                        // `terminationHandler` finishes the stream too, with a plain
                        // nonzero-exit error and an empty stderr, and whichever finish lands
                        // first is the one the consumer sees. Finishing here first makes the
                        // handler's a no-op, so the error always says it was the watchdog.
                        continuation.finish(throwing: ProcessError(
                            command: "\(executable) \(arguments.joined(separator: " "))",
                            exitCode: -1,
                            stderr: "killed after \(inactivityTimeout) with no output (inactivity watchdog)"
                        ))
                        if process.isRunning { process.terminate() }
                        return
                    }
                    try? await Task.sleep(for: max(inactivityTimeout - idle, .milliseconds(50)))
                }
            }

            process.terminationHandler = { proc in
                watchdog.cancel()
                // Same drain race as `run`: `terminationHandler` can fire before the
                // readability handler drained the last chunk a process wrote right before
                // exiting. Clear the handlers and read whatever is left directly.
                ioLock.withLock {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    if let remaining = (try? outPipe.fileHandleForReading.readToEnd()) ?? nil, !remaining.isEmpty {
                        extractLines(from: remaining)
                    }
                    if let remaining = (try? errPipe.fileHandleForReading.readToEnd()) ?? nil, !remaining.isEmpty {
                        errBox.append(remaining)
                    }
                    let trailing = lineBuffer.snapshot()
                    if !trailing.isEmpty { yieldLine(trailing) }
                }
                if proc.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    let err = String(data: errBox.snapshot(), encoding: .utf8) ?? ""
                    continuation.finish(throwing: ProcessError(
                        command: "\(executable) \(arguments.joined(separator: " "))",
                        exitCode: proc.terminationStatus,
                        stderr: err
                    ))
                }
            }

            // A consumer that stops listening (a cancelled chat turn, a PR reload mid-run)
            // must not leave the CLI running and billing in the background.
            continuation.onTermination = { _ in
                watchdog.cancel()
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                watchdog.cancel()
                continuation.finish(throwing: error)
            }
        }
    }

    /// Checks common install locations first (no subprocess needed). Falls back to
    /// `/usr/bin/env` so PATH entries from asdf, nvm, or a custom Homebrew prefix still
    /// resolve exactly like they would in Terminal.
    /// Search order for a bare command name: the inherited `PATH` first, then a list of
    /// common install locations.
    ///
    /// PATH must come first so Contour runs the same binary the user's shell does. This is
    /// not hypothetical — two `claude` installs (an older Homebrew one and a newer
    /// `~/.local/bin` one) differ in which flags they accept, and preferring a hardcoded
    /// directory silently ran the wrong one.
    ///
    /// The fallback list still matters: a GUI app launched from Finder inherits a minimal
    /// PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), so without it Homebrew and user-local
    /// installs are invisible unless Contour was started from a terminal. `~/.local/bin`
    /// is there specifically because Claude Code installs to it by default.
    static func searchPaths(for name: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fromPATH = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/\(name)" }
        let fallbacks = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.local/bin/\(name)",
            "\(home)/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
        ]
        return fromPATH + fallbacks
    }

    /// Absolute path for a command, or nil if nothing executable was found. Used by
    /// `EnvironmentProbe` to report what is actually installed.
    static func which(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        return searchPaths(for: name).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func resolveExecutable(_ name: String) -> URL {
        if name.hasPrefix("/") { return URL(fileURLWithPath: name) }
        if let found = which(name) { return URL(fileURLWithPath: found) }
        // Last resort: let `env` try PATH, which still works when Contour was launched
        // from a shell that knows about an install location not listed above.
        return URL(fileURLWithPath: "/usr/bin/env")
    }

    /// When resolution fell back to `env`, the original name must become argv[0] of the
    /// child rather than of this wrapper, since `env` itself takes the target name as its
    /// first argument.
    private static func resolvedArguments(_ executable: String, _ arguments: [String]) -> [String] {
        let resolved = resolveExecutable(executable)
        return resolved.lastPathComponent == "env" && !executable.hasPrefix("/")
            ? [executable] + arguments
            : arguments
    }
}
