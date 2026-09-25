import Foundation

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

/// Thin wrapper around Foundation.Process for the three external CLIs this app depends on:
/// `gh` (GitHub), `git` (checkout), and `pi` (AI analysis). No SDKs, no API keys held by this
/// app — every credential and network policy is inherited from whatever the CLI is already
/// configured with. See design doc §8, §9, §16.
enum Shell {

    /// Run a command to completion and return stdout as a String. Throws on non-zero exit.
    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: URL? = nil,
        stdin: String? = nil
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
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
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let d = handle.availableData
                if d.isEmpty { outPipe.fileHandleForReading.readabilityHandler = nil }
                else { outBox.append(d) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let d = handle.availableData
                if d.isEmpty { errPipe.fileHandleForReading.readabilityHandler = nil }
                else { errBox.append(d) }
            }

            process.terminationHandler = { proc in
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

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Run a command, yielding stdout line by line as it streams. Used for `pi --mode json`
    /// so the UI can show real progress substeps instead of a spinner (§10).
    static func stream(
        _ executable: String,
        _ arguments: [String],
        cwd: URL? = nil
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

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    return
                }
                lineBuffer.append(chunk)
                // Pull out complete lines and yield them; leave any partial line buffered.
                var remainder = lineBuffer.drain()
                while let newlineRange = remainder.range(of: Data([0x0A])) {
                    let lineData = remainder.subdata(in: remainder.startIndex..<newlineRange.lowerBound)
                    remainder.removeSubrange(remainder.startIndex..<newlineRange.upperBound)
                    if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                        continuation.yield(line)
                    }
                }
                if !remainder.isEmpty { lineBuffer.append(remainder) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let d = handle.availableData
                if d.isEmpty { errPipe.fileHandleForReading.readabilityHandler = nil }
                else { errBox.append(d) }
            }

            process.terminationHandler = { proc in
                let trailing = lineBuffer.snapshot()
                if !trailing.isEmpty, let line = String(data: trailing, encoding: .utf8), !line.isEmpty {
                    continuation.yield(line)
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

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// Checks common install locations first (no subprocess needed). Falls back to
    /// `/usr/bin/env` so PATH entries from asdf, nvm, or a custom Homebrew prefix still
    /// resolve exactly like they would in Terminal.
    private static func resolveExecutable(_ name: String) -> URL {
        if name.hasPrefix("/") { return URL(fileURLWithPath: name) }
        let known = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)", "/bin/\(name)"]
        for path in known where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
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
