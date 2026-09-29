import Foundation
import Testing
@testable import Contour

struct RepoContextServiceTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeGitRepo(at dir: URL, path: String, contents: String) async throws -> String {
        try contents.write(to: dir.appendingPathComponent(path), atomically: true, encoding: .utf8)
        _ = try await Shell.run("git", ["init", "-q"], cwd: dir)
        _ = try await Shell.run("git", ["config", "user.email", "test@example.com"], cwd: dir)
        _ = try await Shell.run("git", ["config", "user.name", "Test"], cwd: dir)
        _ = try await Shell.run("git", ["add", path], cwd: dir)
        _ = try await Shell.run("git", ["commit", "-q", "-m", "initial"], cwd: dir)
        return try await Shell.run("git", ["rev-parse", "HEAD"], cwd: dir)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func readWholeFileReadsFromTheCheckoutsRootDirectory() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "hello from the checkout".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        let content = try await RepoContextService().readWholeFile(in: checkout, path: "a.txt")
        #expect(content == "hello from the checkout")
    }

    @Test func readLinesOnTheHeadSideReadsDirectlyFromTheWorkingTree() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = (1...20).map { "line \($0)" }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        let result = try await RepoContextService().readLines(
            in: checkout, path: "a.txt", startLine: 10, endLine: 12, contextLines: 2
        )
        #expect(result.refStart == 10 && result.refEnd == 12)
        #expect(result.lines.map(\.number) == [8, 9, 10, 11, 12, 13, 14])
        #expect(result.lines.first?.text == "line 8")
    }

    @Test func readLinesClampsContextToTheFilesBounds() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = (1...5).map { "line \($0)" }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        let result = try await RepoContextService().readLines(
            in: checkout, path: "a.txt", startLine: 1, endLine: 5, contextLines: 6
        )
        #expect(result.lines.map(\.number) == [1, 2, 3, 4, 5], "never below line 1 or past the last line")
    }

    @Test func readLinesOnTheBaseSideReadsTheCommittedBlobNotTheWorkingTree() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let baseSha = try await makeGitRepo(at: dir, path: "a.txt", contents: "committed line 1\ncommitted line 2\n")

        try "working tree line 1\nworking tree line 2\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: baseSha, symbolIndexPath: nil)
        let result = try await RepoContextService().readLines(
            in: checkout, path: "a.txt", startLine: 1, endLine: 1, contextLines: 0, side: .base
        )
        #expect(result.lines.first?.text == "committed line 1")
    }

    @Test func repoContextErrorDescribesTheGitFailure() {
        let error = RepoContextError.gitFailed("fatal: not a git repository")
        #expect(error.errorDescription == "fatal: not a git repository")
    }

    @Test func readLinesDefaultsToSixLinesOfContextWhenOmitted() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = (1...20).map { "line \($0)" }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        let result = try await RepoContextService().readLines(in: checkout, path: "a.txt", startLine: 10, endLine: 10)
        #expect(result.lines.map(\.number) == Array(4...16), "default context is 6 lines either side")
    }

    @Test func readLinesReturnsEmptyWhenTheRequestedRangeIsEntirelyPastTheEndOfTheFile() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = (1...3).map { "line \($0)" }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        let result = try await RepoContextService().readLines(
            in: checkout, path: "a.txt", startLine: 10, endLine: 12, contextLines: 0
        )
        #expect(result.lines.isEmpty)
        #expect(result.refStart == 10 && result.refEnd == 12, "the requested range is echoed back even when nothing matched")
    }
}
