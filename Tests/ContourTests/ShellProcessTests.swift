import Foundation
import Testing
@testable import Contour

@Suite(.serialized)
struct ShellProcessTests {
    private func fakeCLI(_ behavior: String) throws -> (executable: String, arguments: [String]) {
        let url = try #require(
            Bundle.module.url(forResource: "fake-cli", withExtension: "sh", subdirectory: "Fixtures")
        )
        return ("/bin/sh", [url.path, behavior])
    }

    private func isRunning(_ pattern: String) async -> Bool {
        (try? await Shell.run("/usr/bin/pgrep", ["-f", pattern])) != nil
    }

    private func fakeCLIProcessesGone() async -> Bool {
        for _ in 0..<30 {
            let fixtureRunning = await isRunning("fake-cli.sh")
            let sleepRunning = await isRunning("sleep 999999")
            if !fixtureRunning && !sleepRunning { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func collect(
        _ behavior: String,
        inactivityTimeout: Duration = .seconds(600)
    ) async throws -> (lines: [String], error: Error?) {
        let (exe, args) = try fakeCLI(behavior)
        var lines: [String] = []
        var thrown: Error?
        do {
            for try await line in Shell.stream(exe, args, inactivityTimeout: inactivityTimeout) {
                lines.append(line)
            }
        } catch {
            thrown = error
        }
        return (lines, thrown)
    }

    @Test func hangIsKilledByTheInactivityWatchdog() async throws {
        let start = ContinuousClock.now
        let (lines, error) = try await collect("hang", inactivityTimeout: .milliseconds(200))
        let elapsed = ContinuousClock.now - start
        #expect(lines.isEmpty)
        let processError = try #require(error as? ProcessError)
        #expect(processError.stderr.contains("inactivity"))
        #expect(elapsed < .seconds(10), "the watchdog should have ended this in ~200ms, not \(elapsed)")
        #expect(await fakeCLIProcessesGone())
    }

    @Test func aQuickBehaviorIsUnaffectedByAGenerousWatchdog() async throws {
        let (lines, error) = try await collect("nonzero-with-stdout", inactivityTimeout: .seconds(30))
        #expect(lines.count == 1)
        let processError = try #require(error as? ProcessError)
        #expect(processError.exitCode == 1)
        #expect(!processError.stderr.contains("inactivity"))
        #expect(await fakeCLIProcessesGone())
    }

    @Test func exitMidStreamSurfacesAsAnErrorNotAnEmptyStage() async throws {
        let (lines, error) = try await collect("exit-mid-stream")
        #expect(lines.count == 1)
        let processError = try #require(error as? ProcessError)
        #expect(processError.exitCode == 7)
        #expect(await fakeCLIProcessesGone())
    }

    @Test func nonzeroExitWinsOverValidStdout() async throws {
        let (lines, error) = try await collect("nonzero-with-stdout")
        #expect(lines == [#"{"type":"result","subtype":"success","result":"{\"lineCount\": 1}"}"#])
        let processError = try #require(error as? ProcessError)
        #expect(processError.exitCode == 1)
        #expect(processError.stderr.contains("stage failed"))
        #expect(await fakeCLIProcessesGone())
    }

    @Test func shellRunAlsoSurfacesNonzeroExitOverStdout() async throws {
        let (exe, args) = try fakeCLI("nonzero-with-stdout")
        var thrown: Error?
        do {
            _ = try await Shell.run(exe, args)
        } catch {
            thrown = error
        }
        let processError = try #require(thrown as? ProcessError)
        #expect(processError.exitCode == 1)
        #expect(processError.stderr.contains("stage failed"))
        #expect(await fakeCLIProcessesGone())
    }

    @Test func partialLastLineWithNoTrailingNewlineIsStillYielded() async throws {
        let (lines, error) = try await collect("partial-last-line")
        #expect(error == nil)
        #expect(lines == [#"{"type":"result","subtype":"success","result":"{\"lineCount\": 2}"}"#])
        #expect(await fakeCLIProcessesGone())
    }

    @Test func hugeLineIsDeliveredWhole() async throws {
        let (lines, error) = try await collect("huge-line")
        #expect(error == nil)
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        #expect(line.contains(String(repeating: "x", count: 10_000_000)))
        #expect(await fakeCLIProcessesGone())
    }

    @Test func burstWrittenRightBeforeExitIsNotLostToTheDrainRace() async throws {
        let (lines, error) = try await collect("burst-then-exit")
        #expect(error == nil)
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        #expect(line.contains(String(repeating: "x", count: 1_000_000)))
        #expect(await fakeCLIProcessesGone())
    }

    @Test func shellRunAlsoSurvivesTheBurstDrainRace() async throws {
        let (exe, args) = try fakeCLI("burst-then-exit")
        let out = try await Shell.run(exe, args)
        #expect(out.contains(String(repeating: "x", count: 1_000_000)))
        #expect(await fakeCLIProcessesGone())
    }

    @Test func invalidUTF8LineIsNotSilentlyDropped() async throws {
        let (lines, error) = try await collect("invalid-utf8-line")
        #expect(error == nil)
        #expect(lines.count == 1, "the line must still arrive, not be dropped")
        let line = try #require(lines.first)
        #expect(line.contains("before-"))
        #expect(line.contains("-after"))
        #expect(await fakeCLIProcessesGone())
    }

    @Test func unknownEventsAreIgnoredByBothHarnessesNotTreatedAsErrors() async throws {
        let (lines, error) = try await collect("unknown-events")
        #expect(error == nil)
        #expect(lines.count == 2)

        let claudeEvents = lines.map { ClaudeHarness().interpret($0) }
        #expect(claudeEvents[0] == nil)
        #expect(claudeEvents[1] == .finalText(#"{"lineCount": 5}"#))

        for line in lines {
            #expect(PiHarness().interpret(line) == nil)
        }
        #expect(await fakeCLIProcessesGone())
    }

    @Test func rateLimitEventsAreIgnoredThroughTheHarness() async throws {
        let (lines, error) = try await collect("rate-limit-events")
        #expect(error == nil)
        #expect(lines.count == 4)

        let claudeEvents = lines.map { ClaudeHarness().interpret($0) }
        #expect(claudeEvents[0] == nil)
        #expect(claudeEvents[1] == .progress("reading /repo/b.txt"))
        #expect(claudeEvents[2] == nil)
        #expect(claudeEvents[3] == .finalText(#"{"lineCount": 6}"#))
        #expect(await fakeCLIProcessesGone())
    }

    @Test func cancellingAStreamStillKillsAHungChild() async throws {
        let (exe, args) = try fakeCLI("hang")
        let task = Task {
            for try await _ in Shell.stream(exe, args) {}
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(await isRunning("sleep 999999"), "precondition: it started")
        task.cancel()
        _ = await task.result
        #expect(await fakeCLIProcessesGone())
    }
}
