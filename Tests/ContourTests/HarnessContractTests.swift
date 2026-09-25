import Testing
import Foundation
@testable import Contour

/// The guard that keeps the harness abstraction honest.
///
/// Each conformer claims it can turn one CLI's stream into `HarnessEvent`s and build that
/// CLI's argv. Both claims are checked here against **captured real output** (see
/// `Fixtures/README.md` for provenance), so a drift in either CLI's event schema fails the
/// suite instead of surfacing as an empty analysis stage after a slow, paid model run.
struct HarnessContractTests {

    private func fixtureLines(_ name: String) throws -> [String] {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")
        )
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func replay(_ harness: any Harness, _ fixture: String) throws -> (progress: [String], final: String?) {
        var progress: [String] = []
        var final: String?
        for line in try fixtureLines(fixture) {
            switch harness.interpret(line) {
            case .progress(let d): progress.append(d)
            case .finalText(let t): final = t
            case nil: continue
            }
        }
        return (progress, final)
    }

    // MARK: - Final text

    /// pi's authoritative final message is `message_end` for the assistant role. The
    /// captured stream contains a `thinking` block whose `text` is null *before* the real
    /// text block, so taking "the last content block" would yield nothing — the extraction
    /// must filter on block type. That null-thinking block is exactly why this fixture is
    /// worth keeping.
    @Test func piExtractsFinalTextPastNullThinkingBlock() throws {
        let (_, final) = try replay(PiHarness(), "pi-stream")
        #expect(final == "{\"lineCount\": 4}")
    }

    /// claude reports its final text once, on the `result`/`success` event — not on the
    /// assistant message that produced it.
    @Test func claudeExtractsFinalTextFromResultEvent() throws {
        let (_, final) = try replay(ClaudeHarness(), "claude-stream")
        #expect(final == "{\"lineCount\": 3}")
    }

    // MARK: - Progress

    @Test func piDescribesEachToolCall() throws {
        let (progress, _) = try replay(PiHarness(), "pi-stream")
        #expect(progress == [
            "reading src/OrderService.java",
            "searching for queueCapture",
            "finding *.java",
            "listing src",
            "using sparkle",          // unknown tool falls back to its name
        ])
    }

    @Test func claudeDescribesEachToolCall() throws {
        let (progress, _) = try replay(ClaudeHarness(), "claude-stream")
        #expect(progress == ["reading /repo/sample.txt"])
    }

    /// claude interleaves hook and rate-limit lines with real content. They must be
    /// ignored silently: anything else turns routine noise into a failed stage.
    @Test func claudeIgnoresHookAndRateLimitNoise() throws {
        let noise = [
            #"{"type":"system","subtype":"hook_started","hook":"PreToolUse"}"#,
            #"{"type":"rate_limit_event","status":"allowed"}"#,
            #"{"type":"system","subtype":"init","cwd":"/repo"}"#,
        ]
        for line in noise {
            #expect(ClaudeHarness().interpret(line) == nil)
        }
    }

    @Test(arguments: [
        PiHarness() as any Harness,
        ClaudeHarness(contextDirectory: URL(fileURLWithPath: NSTemporaryDirectory())) as any Harness,
    ])
    func garbageLinesAreIgnored(harness: any Harness) {
        #expect(harness.interpret("") == nil)
        #expect(harness.interpret("not json at all") == nil)
        #expect(harness.interpret("{}") == nil)
        #expect(harness.interpret(#"{"type":"something_new"}"#) == nil)
    }

    // MARK: - Argument construction

    /// pi resolves `@file` by scanning a raw argv token for a leading "@", so the file
    /// reference has to be its own argument. Joining it to the prompt makes pi treat the
    /// whole blob as one nonexistent path — a real bug that cost debugging time in
    /// Aperture, so it is pinned here rather than left to a comment.
    @Test func piPassesContextFileAsItsOwnArgument() throws {
        let args = try PiHarness().arguments(
            prompt: "analyze the diff", contextFile: ".contour-context.md",
            tier: .strong, systemPrompt: "sys"
        )
        let at = try #require(args.firstIndex(of: "@.contour-context.md"))
        #expect(args[at - 1] == "-p")
        #expect(args[at + 1] == "analyze the diff")
    }

    /// claude has no `@file` convention, so the context file's *contents* must reach the
    /// model inside the prompt. Both harnesses therefore deliver the same text; only the
    /// mechanism differs.
    @Test func claudeInlinesContextFileContents() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent(".contour-context.md")
        try "PR TITLE: add retry\n<UNTRUSTED_PR_CONTENT>body</UNTRUSTED_PR_CONTENT>"
            .write(to: file, atomically: true, encoding: .utf8)

        let args = try ClaudeHarness(contextDirectory: dir).arguments(
            prompt: "analyze the diff", contextFile: ".contour-context.md",
            tier: .strong, systemPrompt: "sys"
        )
        let prompt = try #require(args.last)
        #expect(prompt.contains("PR TITLE: add retry"))
        #expect(prompt.contains("<UNTRUSTED_PR_CONTENT>body</UNTRUSTED_PR_CONTENT>"))
        #expect(prompt.contains("analyze the diff"))
        #expect(!args.contains("@.contour-context.md"))
    }

    @Test func effortTierMapsToEachCLIsOwnFlag() throws {
        let pi = try PiHarness().arguments(prompt: "p", contextFile: "c", tier: .fast, systemPrompt: "s")
        #expect(pi.contains("--thinking"))
        #expect(pi[pi.firstIndex(of: "--thinking")! + 1] == "low")

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let claude = try ClaudeHarness(contextDirectory: dir)
            .arguments(prompt: "p", contextFile: "missing.md", tier: .strong, systemPrompt: "s")
        #expect(claude.contains("--effort"))
        #expect(claude[claude.firstIndex(of: "--effort")! + 1] == "high")
    }

    /// Both harnesses must refuse to inherit instruction files, skills, hooks, or plugins
    /// from the checkout. The checkout is the PR under review — attacker-controlled content
    /// for any PR off the internet — so anything it can inject as *instructions* is a
    /// prompt-injection vector that the `<UNTRUSTED_PR_CONTENT>` wrapper does not cover.
    @Test func bothHarnessesRefuseProjectResidentCustomization() throws {
        let pi = try PiHarness().arguments(prompt: "p", contextFile: "c", tier: .fast, systemPrompt: "s")
        #expect(pi.contains("--no-context-files"))
        #expect(pi.contains("--no-extensions"))
        #expect(pi.contains("--no-skills"))
        #expect(pi.contains("--no-session"))

        let claude = try ClaudeHarness(contextDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
            .arguments(prompt: "p", contextFile: "missing.md", tier: .fast, systemPrompt: "s")
        #expect(claude.contains("--restricted"))
        #expect(claude.contains("--safe-mode"))
    }

    /// Read-only means read-only on both sides, whatever each CLI calls its tools.
    @Test func neitherHarnessGrantsWriteOrExecuteTools() throws {
        let pi = try PiHarness().arguments(prompt: "p", contextFile: "c", tier: .fast, systemPrompt: "s")
        let piTools = pi[pi.firstIndex(of: "--tools")! + 1]
        #expect(piTools == "read,grep,find,ls")

        let claude = try ClaudeHarness(contextDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
            .arguments(prompt: "p", contextFile: "missing.md", tier: .fast, systemPrompt: "s")
        let claudeTools = claude[claude.firstIndex(of: "--allowedTools")! + 1]
        #expect(claudeTools == "Read,Grep,Glob")
        for forbidden in ["Bash", "Edit", "Write", "WebFetch"] {
            #expect(!claudeTools.contains(forbidden))
        }
    }

    /// A model override is opt-in. With none set, neither harness passes `--model` at all,
    /// so each CLI's own configured default applies. Forcing a bare pattern like "sonnet"
    /// reintroduces exactly the vendor coupling this fork exists to remove — and once
    /// matched an unauthenticated provider during Aperture's development.
    @Test func modelFlagIsOmittedUnlessOverridden() throws {
        AnalysisTier.modelOverrides = [:]
        let pi = try PiHarness().arguments(prompt: "p", contextFile: "c", tier: .fast, systemPrompt: "s")
        #expect(!pi.contains("--model"))

        AnalysisTier.modelOverrides = [.fast: "haiku"]
        defer { AnalysisTier.modelOverrides = [:] }
        let piPinned = try PiHarness().arguments(prompt: "p", contextFile: "c", tier: .fast, systemPrompt: "s")
        #expect(piPinned[piPinned.firstIndex(of: "--model")! + 1] == "haiku")
    }
}
