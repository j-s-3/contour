import Foundation
import Testing

@testable import Contour

struct CodeRefVerifierTests {
    private final class TempRepo {
        let root: URL
        let baseSha: String

        init() async throws {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("contour-refs-\(UUID().uuidString)", isDirectory: true)
            func write(_ path: String, _ text: String) throws {
                try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
            }
            func git(_ args: String...) async throws -> String { try await Shell.run("git", args, cwd: root) }

            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
            try write("src/lib.rs", "fn a() {}\nfn b() {}\n")
            try write("src/old.rs", "one\ntwo\nthree")
            _ = try await git("init", "-q")
            _ = try await git("add", ".")
            _ = try await git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "base")
            baseSha = try await git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
            try FileManager.default.removeItem(at: root.appendingPathComponent("src/old.rs"))
            try write("src/lib.rs", "fn a() {}\nfn b() {}\nfn c() {}\nfn d() {}\nfn e() {}\n")
            self.root = root
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        var verifier: CodeRefVerifier { CodeRefVerifier(rootDir: root, baseSha: baseSha) }
    }

    @Test func aRefInsideAHeadFileResolves() async throws {
        let repo = try await TempRepo()
        let ref = CodeRef(path: "src/lib.rs", startLine: 2, endLine: 4)
        #expect(await repo.verifier.resolve(ref) == ref)
    }

    @Test func aMissingFileOrARangePastTheEndDoesNot() async throws {
        let repo = try await TempRepo()
        let v = repo.verifier
        #expect(await v.resolve(CodeRef(path: "src/nope.rs", startLine: 1, endLine: 2)) == nil)
        #expect(await v.resolve(CodeRef(path: "src/lib.rs", startLine: 6, endLine: 8)) == nil)
        #expect(await v.resolve(CodeRef(path: "src/lib.rs", startLine: 0, endLine: 1)) == nil)
        #expect(await v.resolve(CodeRef(path: "src", startLine: 1, endLine: 1)) == nil)
        #expect(await v.resolve(CodeRef(path: "../escape.rs", startLine: 1, endLine: 1)) == nil)
    }

    @Test func aRangeRunningPastTheEndIsTrimmedAndThePathTidied() async throws {
        let repo = try await TempRepo()
        let resolved = await repo.verifier.resolve(CodeRef(path: "./src/lib.rs", startLine: 4, endLine: 40))
        #expect(resolved == CodeRef(path: "src/lib.rs", startLine: 4, endLine: 5))
    }

    @Test func baseRefsResolveThroughGitShow() async throws {
        let repo = try await TempRepo()
        let v = repo.verifier
        #expect(await v.resolve(CodeRef(path: "src/lib.rs", startLine: 1, endLine: 2, side: .base)) != nil)
        #expect(await v.resolve(CodeRef(path: "src/lib.rs", startLine: 4, endLine: 5, side: .base)) == nil)
    }

    @Test func aHeadRefToADeletedFileMovesToBase() async throws {
        let repo = try await TempRepo()
        let resolved = await repo.verifier.resolve(CodeRef(path: "src/old.rs", startLine: 2, endLine: 3))
        #expect(resolved?.side == .base)
        #expect(resolved?.endLine == 3)
    }

    @Test func lineCountsFollowEditorNumbering() {
        #expect(CodeRefVerifier.lineCount(of: Data()) == 0)
        #expect(CodeRefVerifier.lineCount(of: Data("a".utf8)) == 1)
        #expect(CodeRefVerifier.lineCount(of: Data("a\n".utf8)) == 1)
        #expect(CodeRefVerifier.lineCount(of: Data("a\nb".utf8)) == 2)
    }

    @Test func aDecisionWhoseRefsAllFailIsDemotedAndCounted() async throws {
        let repo = try await TempRepo()
        let grounded = DecisionNode(
            id: "ok", title: "Grounded", decision: Statement(text: "Does X", provenance: .fact), confidence: .high,
            refs: [
                CodeRef(path: "src/lib.rs", startLine: 1, endLine: 2),
                CodeRef(path: "src/ghost.rs", startLine: 1, endLine: 1),
            ]
        )
        let invented = DecisionNode(
            id: "bad", title: "Invented", decision: Statement(text: "Does Y", provenance: .fact), confidence: .high,
            refs: [CodeRef(path: "src/ghost.rs", startLine: 3, endLine: 9)]
        )
        let (result, check) = await repo.verifier.verify(.decisions([grounded, invented]))
        guard case .decisions(let decisions) = result else {
            Issue.record("wrong stage")
            return
        }

        #expect(decisions[0].refs.map(\.path) == ["src/lib.rs"])
        #expect(decisions[0].confidence == .high)
        #expect(decisions[0].decision.provenance == .fact)

        #expect(decisions[1].refs.isEmpty)
        #expect(decisions[1].confidence == .low)
        #expect(decisions[1].decision.provenance == .interpretation)
        #expect(decisions[1].decision.confidence == .low)

        #expect(check.checked == 3)
        #expect(check.unresolvedCount == 2)
        #expect(check.unresolved == ["src/ghost.rs:1-1", "src/ghost.rs:3-9"])
    }

    @Test func aDecisionWithNoRefsIsLeftAlone() async throws {
        let repo = try await TempRepo()
        let bare = DecisionNode(
            id: "d", title: "T", decision: Statement(text: "Z", provenance: .fact), confidence: .high)
        let (result, check) = await repo.verifier.verify(.decisions([bare]))
        guard case .decisions(let decisions) = result else {
            Issue.record("wrong stage")
            return
        }
        #expect(decisions[0].confidence == .high)
        #expect(check.checked == 0)
    }

    @Test func claimsStayClaimsAndOtherStatementsAreLowered() {
        let claim = Statement(text: "Fixes #1", provenance: .claim, source: "PR description").demotedForUnverifiedRefs()
        #expect(claim.provenance == .claim)
        let guess = Statement(text: "Probably", provenance: .interpretation, confidence: .high)
            .demotedForUnverifiedRefs()
        #expect(guess.provenance == .interpretation && guess.confidence == .low)
    }

    @Test func componentsAndConsiderationsAreDemotedToo() async throws {
        let repo = try await TempRepo()
        let v = repo.verifier
        let arch = try StageDecoding.decode(
            StageDecoding.ArchitectureResult.self,
            from: [
                "components": [
                    [
                        "id": "c", "title": "Input", "changeKind": "changed",
                        "summary": ["text": "Reads input", "provenance": "fact"],
                        "refs": [["path": "src/missing.rs", "startLine": 1, "endLine": 2]],
                    ]
                ]
            ])
        let (archResult, _) = await v.verify(.architecture(arch))
        guard case .architecture(let a) = archResult else {
            Issue.record("wrong stage")
            return
        }
        #expect(a.components[0].summary?.provenance == .interpretation)

        var judgment = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: [:])
        judgment.considerations = [
            Consideration(
                id: "q", question: "Safe?", detail: "", provenance: .fact, confidence: .high,
                refs: [CodeRef(path: "src/lib.rs", startLine: 99, endLine: 99)])
        ]
        let (judgmentResult, check) = await v.verify(.judgment(judgment))
        guard case .judgment(let j) = judgmentResult else {
            Issue.record("wrong stage")
            return
        }
        #expect(j.considerations[0].provenance == .interpretation)
        #expect(j.considerations[0].confidence == .low)
        #expect(check.unresolvedCount == 1)
    }

    @Test func aStagesTallyIsReplacedOnRetryAndClearedWithItsSlice() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.record(RefCheck(checked: 10, unresolvedCount: 2), for: .decisions)
        graph.record(RefCheck(checked: 5, unresolvedCount: 1), for: .flows)
        #expect(graph.refCheckTotal?.checked == 15)
        #expect(graph.refCheckTotal?.unresolvedCount == 3)

        graph.record(RefCheck(checked: 8, unresolvedCount: 0), for: .decisions)
        #expect(graph.refCheckTotal?.checked == 13)

        graph.clear(.flows)
        #expect(graph.refCheckTotal?.checked == 8)
        #expect(graph.refCheckTotal?.unresolvedCount == 0)
    }
}
