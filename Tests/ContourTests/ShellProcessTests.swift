import Foundation
import Testing
@testable import Contour

/// Fault injection for `Shell.run`/`Shell.stream` against `Fixtures/fake-cli.sh` (see its
/// section of `Fixtures/README.md`). `HarnessContractTests` replays captured JSONL, which
/// protects the happy path; these fixtures need a real process because the failure they
/// exercise depends on *how and when* it writes and exits, not just what it writes — a
/// hang, a burst right before exit, a line that isn't valid UTF-8.
struct ShellProcessTests {

    private func fakeCLI(_ behavior: String) throws -> (executable: String, arguments: [String]) {
        let url = try #require(
            Bundle.module.url(forResource: "fake-cli", withExtension: "sh", subdirectory: "Fixtures")
        )
        return ("/bin/sh", [url.path, behavior])
    }

    // MARK: - "the child is gone"

    /// `pgrep -f` excludes its own pid but not a caller's, so this calls it directly
    /// (mirroring `StopAnalysisTests`) rather than through a wrapping `/bin/sh -c`, whose
    /// own command line would otherwise contain — and so falsely match — the pattern.
    private func isRunning(_ pattern: String) async -> Bool {
        (try? await Shell.run("/usr/bin/pgrep", ["-f", pattern])) != nil
    }

    /// Whichever fixture behavior ran, plus the `sleep` the `hang` behavior `exec`s into
    /// (which drops "fake-cli.sh" from its own command line), should both be gone once
    /// `Shell` reports the run over. Polls briefly: `Process.terminate()` sends SIGTERM and
    /// returns immediately, it doesn't wait for the child to actually exit.
    private func fakeCLIProcessesGone() async -> Bool {
        for _ in 0..<30 {
            let stillThere = await isRunning("fake-cli.sh") || await isRunning("sleep 999999")
            if !stillThere { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    /// Runs one fixture behavior through `Shell.stream` to completion. Every call site
    /// follows this with `#expect(await fakeCLIProcessesGone())` — kept as an explicit step
    /// at each call site, not folded in here, so a failure there reads as its own line.
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

    // MARK: - Hang / inactivity watchdog

    /// The one fault that, without a watchdog, would hang the test suite itself rather than
    /// just fail it — so this is the acceptance criterion in code: it must complete within
    /// the test's own timeout, not wait forever on a stuck `claude`/`pi`.
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

    /// The default is generous on purpose — a slow model isn't a hang — so a process that
    /// produces output well inside the timeout must complete normally rather than being
    /// killed early.
    @Test func aQuickBehaviorIsUnaffectedByAGenerousWatchdog() async throws {
        let (lines, error) = try await collect("nonzero-with-stdout", inactivityTimeout: .seconds(30))
        #expect(lines.count == 1)
        // Its own nonzero exit surfaces, not a watchdog kill.
        let processError = try #require(error as? ProcessError)
        #expect(processError.exitCode == 1)
        #expect(!processError.stderr.contains("inactivity"))
        #expect(await fakeCLIProcessesGone())
    }

    // MARK: - Exit / stdout races

    @Test func exitMidStreamSurfacesAsAnErrorNotAnEmptyStage() async throws {
        let (lines, error) = try await collect("exit-mid-stream")
        // The one progress-shaped line it managed to write still arrives; there's just no
        // final result behind it.
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

    // MARK: - No lost output

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

    /// The pipe-drain race this pins: `terminationHandler` firing before
    /// `readabilityHandler` finished draining a chunk the process wrote right before
    /// exiting. `fake-cli.sh`'s `burst-then-exit` writes well past a pipe's buffer size in
    /// one line and exits immediately, so a lost tail would show up as a short line here.
    @Test func burstWrittenRightBeforeExitIsNotLostToTheDrainRace() async throws {
        let (lines, error) = try await collect("burst-then-exit")
        #expect(error == nil)
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        #expect(line.contains(String(repeating: "x", count: 1_000_000)))
        #expect(await fakeCLIProcessesGone())
    }

    /// Same race, same fixture, through `Shell.run` instead of `Shell.stream` — the fix
    /// applies to both.
    @Test func shellRunAlsoSurvivesTheBurstDrainRace() async throws {
        let (exe, args) = try fakeCLI("burst-then-exit")
        let out = try await Shell.run(exe, args)
        #expect(out.contains(String(repeating: "x", count: 1_000_000)))
        #expect(await fakeCLIProcessesGone())
    }

    // MARK: - Invalid UTF-8

    /// A line that isn't valid UTF-8 used to vanish from the stream with no trace. It must
    /// now still reach the caller — lossily decoded — rather than being silently dropped;
    /// see `Shell.stream`'s `yield` for where it's also logged.
    @Test func invalidUTF8LineIsNotSilentlyDropped() async throws {
        let (lines, error) = try await collect("invalid-utf8-line")
        #expect(error == nil)
        #expect(lines.count == 1, "the line must still arrive, not be dropped")
        let line = try #require(lines.first)
        #expect(line.contains("before-"))
        #expect(line.contains("-after"))
        #expect(await fakeCLIProcessesGone())
    }

    // MARK: - Unknown / rate-limit events, through a harness

    /// Both CLIs gain event types over time (§10), so an event type neither harness
    /// recognizes must be ignored rather than break the stage — pinned here by actually
    /// running a process that emits one, then handing its output to `ClaudeHarness`.
    @Test func unknownEventsAreIgnoredByBothHarnessesNotTreatedAsErrors() async throws {
        let (lines, error) = try await collect("unknown-events")
        #expect(error == nil)
        #expect(lines.count == 2)

        let claudeEvents = lines.map { ClaudeHarness().interpret($0) }
        #expect(claudeEvents[0] == nil) // the unrecognized event type
        #expect(claudeEvents[1] == .finalText(#"{"lineCount": 5}"#))

        for line in lines {
            #expect(PiHarness().interpret(line) == nil)
        }
        #expect(await fakeCLIProcessesGone())
    }

    /// `claude` interleaves `rate_limit_event` lines with real content in practice (see
    /// `claude-stream.jsonl`); this exercises the same shape coming through a live process
    /// rather than only a captured fixture.
    @Test func rateLimitEventsAreIgnoredThroughTheHarness() async throws {
        let (lines, error) = try await collect("rate-limit-events")
        #expect(error == nil)
        #expect(lines.count == 4)

        let claudeEvents = lines.map { ClaudeHarness().interpret($0) }
        #expect(claudeEvents[0] == nil)                                  // rate_limit_event
        #expect(claudeEvents[1] == .progress("reading /repo/b.txt"))     // tool_use
        #expect(claudeEvents[2] == nil)                                  // rate_limit_event
        #expect(claudeEvents[3] == .finalText(#"{"lineCount": 6}"#))
        #expect(await fakeCLIProcessesGone())
    }

    // MARK: - Cancellation still kills a hung child

    /// The watchdog is one way a stream ends a stuck process; a consumer that simply stops
    /// listening (§ `onTermination`) is another, and the fix must not have disturbed it.
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
