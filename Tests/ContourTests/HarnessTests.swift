import Foundation
import Testing

@testable import Contour

struct HarnessTests {
    @Test func harnessIDDisplayNamesExecutablesAndInstallHints() {
        #expect(HarnessID.pi.displayName == "pi")
        #expect(HarnessID.pi.executable == "pi")
        #expect(HarnessID.pi.installHint.contains("pi"))
        #expect(HarnessID.claude.displayName == "Claude Code")
        #expect(HarnessID.claude.executable == "claude")
        #expect(HarnessID.claude.installHint.contains("Claude Code"))
    }

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

    @Test func streamLineParsesObjectsAndRejectsAnythingElse() {
        #expect(StreamLine.object(#"{"type":"x","value":1}"#)?["type"] as? String == "x")
        #expect(StreamLine.object("not json") == nil)
        #expect(StreamLine.object("[1,2,3]") == nil)
    }

    @Test func describeToolNormalizesTheFourReadOnlyCapabilities() {
        #expect(StreamLine.describeTool(name: "Read", path: "Foo.swift", pattern: nil) == "reading Foo.swift")
        #expect(StreamLine.describeTool(name: "grep", path: nil, pattern: "TODO") == "searching for TODO")
        #expect(StreamLine.describeTool(name: "find", path: nil, pattern: "*.swift") == "finding *.swift")
        #expect(StreamLine.describeTool(name: "Glob", path: nil, pattern: "*.swift") == "finding *.swift")
        #expect(StreamLine.describeTool(name: "ls", path: "src/", pattern: nil) == "listing src/")
        #expect(StreamLine.describeTool(name: "ls", path: nil, pattern: nil) == "using ls")
        #expect(StreamLine.describeTool(name: "unknown_tool", path: "x", pattern: "y") == "using unknown_tool")
    }

    @Test func conversationArgumentsDefaultsToArguments() throws {
        let harness = PiHarness()
        let a = try harness.arguments(prompt: "p", contextFile: "c.md", tier: .fast, systemPrompt: "s")
        let b = try harness.conversationArguments(prompt: "p", contextFile: "c.md", tier: .fast, systemPrompt: "s")
        #expect(a == b)
    }
}
