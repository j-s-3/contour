import Foundation
import Testing
@testable import Contour

/// `Harness.swift` holds the harness-independent pieces around the `Harness` protocol
/// itself: `HarnessID`'s user-facing strings, `HarnessFactory`'s dispatch, `HarnessError`'s
/// message, and `StreamLine`'s shared JSON-line decode and tool-name normalization that
/// both `PiHarness` and `ClaudeHarness` build on. `HarnessContractTests` already replays
/// captured streams through `interpret`; these pin the smaller pieces around it that no
/// test referenced directly.
struct HarnessTests {

    @Test func harnessIDDisplayNamesExecutablesAndInstallHints() {
        #expect(HarnessID.pi.displayName == "pi")
        #expect(HarnessID.pi.executable == "pi")
        #expect(HarnessID.pi.installHint.contains("pi"))
        #expect(HarnessID.claude.displayName == "Claude Code")
        #expect(HarnessID.claude.executable == "claude")
        #expect(HarnessID.claude.installHint.contains("Claude Code"))
    }

    /// `HarnessFactory.make` is the only place a `HarnessID` becomes a concrete conformer —
    /// picking the wrong one would send every stage to the wrong CLI.
    @Test func harnessFactoryMakesTheMatchingConformer() {
        let contextDir = URL(fileURLWithPath: "/tmp")
        #expect(HarnessFactory.make(.pi, contextDirectory: contextDir).id == .pi)
        #expect(HarnessFactory.make(.claude, contextDirectory: contextDir).id == .claude)
    }

    @Test func harnessErrorNamesTheUnreadableFile() {
        struct Dummy: Error, LocalizedError { var errorDescription: String? { "boom" } }
        let error = HarnessError.contextFileUnreadable("context.md", underlying: Dummy())
        #expect(error.errorDescription == "Couldn't read the PR context file context.md: boom")
    }

    /// `StreamLine.object` is the shared tolerant line decode both CLIs' `interpret`
    /// funnel every line through — it must accept a JSON object and reject anything that
    /// isn't (malformed JSON, or valid JSON that isn't an object) without throwing.
    @Test func streamLineParsesObjectsAndRejectsAnythingElse() {
        #expect(StreamLine.object(#"{"type":"x","value":1}"#)?["type"] as? String == "x")
        #expect(StreamLine.object("not json") == nil)
        #expect(StreamLine.object("[1,2,3]") == nil)
    }

    /// Both CLIs expose the same four read-only capabilities under different names and
    /// argument keys; `describeTool` normalizes them into one progress-line vocabulary,
    /// falling back to a generic phrase when the tool is unrecognized or missing the
    /// argument its case expects.
    @Test func describeToolNormalizesTheFourReadOnlyCapabilities() {
        #expect(StreamLine.describeTool(name: "Read", path: "Foo.swift", pattern: nil) == "reading Foo.swift")
        #expect(StreamLine.describeTool(name: "grep", path: nil, pattern: "TODO") == "searching for TODO")
        #expect(StreamLine.describeTool(name: "find", path: nil, pattern: "*.swift") == "finding *.swift")
        #expect(StreamLine.describeTool(name: "Glob", path: nil, pattern: "*.swift") == "finding *.swift")
        #expect(StreamLine.describeTool(name: "ls", path: "src/", pattern: nil) == "listing src/")
        #expect(StreamLine.describeTool(name: "ls", path: nil, pattern: nil) == "using ls")
        #expect(StreamLine.describeTool(name: "unknown_tool", path: "x", pattern: "y") == "using unknown_tool")
    }

    /// `conversationArguments` defaults to `arguments` unless a conformer overrides it —
    /// pinned here since neither `PiHarness` nor `ClaudeHarness` overrides it today.
    @Test func conversationArgumentsDefaultsToArguments() throws {
        let harness = PiHarness()
        let a = try harness.arguments(prompt: "p", contextFile: "c.md", tier: .fast, systemPrompt: "s")
        let b = try harness.conversationArguments(prompt: "p", contextFile: "c.md", tier: .fast, systemPrompt: "s")
        #expect(a == b)
    }
}
