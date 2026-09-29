import Testing
import Foundation
@testable import Contour

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
            case .textDelta, nil: continue
            }
        }
        return (progress, final)
    }

    @Test func piExtractsFinalTextPastNullThinkingBlock() throws {
        let (_, final) = try replay(PiHarness(), "pi-stream")
        #expect(final == "{\"lineCount\": 4}")
    }

    @Test func claudeExtractsFinalTextFromResultEvent() throws {
        let (_, final) = try replay(ClaudeHarness(), "claude-stream")
        #expect(final == "{\"lineCount\": 3}")
    }

    @Test func piDescribesEachToolCall() throws {
        let (progress, _) = try replay(PiHarness(), "pi-stream")
        #expect(progress == [
            "reading src/OrderService.java",
            "searching for queueCapture",
            "finding *.java",
            "listing src",
            "using sparkle",
        ])
    }

    @Test func claudeDescribesEachToolCall() throws {
        let (progress, _) = try replay(ClaudeHarness(), "claude-stream")
        #expect(progress == ["reading /repo/sample.txt"])
    }

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

    @Test func piPassesContextFileAsItsOwnArgument() throws {
        let args = try PiHarness().arguments(
            prompt: "analyze the diff", contextFile: ".contour-context.md",
            tier: .strong, systemPrompt: "sys"
        )
        let at = try #require(args.firstIndex(of: "@.contour-context.md"))
        #expect(args[at - 1] == "-p")
        #expect(args[at + 1] == "analyze the diff")
    }

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

struct HarnessStreamingTests {
    @Test func claudeReadsTextDeltasFromPartialMessages() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Because "}}}"#
        #expect(ClaudeHarness().interpret(line) == .textDelta("Because "))
        let thinking = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}}"#
        #expect(ClaudeHarness().interpret(thinking) == nil)
    }

    @Test func piReadsTextDeltasFromMessageUpdates() {
        let line = #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Because "}}"#
        #expect(PiHarness().interpret(line) == .textDelta("Because "))
        let thinking = #"{"type":"message_update","assistantMessageEvent":{"type":"thinking_delta","delta":"hmm"}}"#
        #expect(PiHarness().interpret(thinking) == nil)
    }

    @Test func onlyConversationArgumentsAskClaudeToStream() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let harness = ClaudeHarness(contextDirectory: dir)
        let stage = try harness.arguments(prompt: "p", contextFile: "c", tier: .fast, systemPrompt: "s")
        let chat = try harness.conversationArguments(prompt: "p", contextFile: "c", tier: .fast, systemPrompt: "s")
        #expect(!stage.contains("--include-partial-messages"))
        #expect(chat.contains("--include-partial-messages"))
        for flag in ["--restricted", "--safe-mode", "--allowedTools"] {
            #expect(chat.contains(flag))
        }
    }

    @Test func piConversationArgumentsKeepTheHardening() throws {
        let chat = try PiHarness().conversationArguments(prompt: "p", contextFile: "c", tier: .fast, systemPrompt: "s")
        for flag in ["--no-context-files", "--no-extensions", "--no-skills", "--no-session"] {
            #expect(chat.contains(flag))
        }
    }
}
