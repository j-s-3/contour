import Foundation
import os

private let shellLogger = Logger(subsystem: "Contour", category: "Shell")

struct ProcessError: LocalizedError {
    let command: String
    let exitCode: Int32
    let stderr: String
    var errorDescription: String? {
        "`\(command)` exited \(exitCode): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    func snapshot() -> Data { lock.withLock { data } }
    func drain() -> Data { lock.withLock { let d = data; data = Data(); return d } }
}

private final class ActivityClock: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ContinuousClock.now
    func touch() { lock.withLock { last = ContinuousClock.now } }
    func idle() -> Duration { lock.withLock { ContinuousClock.now - last } }
}

enum Shell {
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
            let ioLock = NSLock()

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

            let watchdog = Task {
                while !Task.isCancelled {
                    let idle = activity.idle()
                    if idle >= inactivityTimeout {
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

    static func which(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        return searchPaths(for: name).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func resolveExecutable(_ name: String) -> URL {
        if name.hasPrefix("/") { return URL(fileURLWithPath: name) }
        if let found = which(name) { return URL(fileURLWithPath: found) }
        return URL(fileURLWithPath: "/usr/bin/env")
    }

    private static func resolvedArguments(_ executable: String, _ arguments: [String]) -> [String] {
        let resolved = resolveExecutable(executable)
        return resolved.lastPathComponent == "env" && !executable.hasPrefix("/")
            ? [executable] + arguments
            : arguments
    }
}
