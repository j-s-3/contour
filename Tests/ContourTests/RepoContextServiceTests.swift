import Foundation
import Testing
@testable import Contour

/// `RepoContextService.swift` was at 8.75% coverage (from earlier coverage PRs constructing
/// `RepoCheckout` incidentally; `checkout(_:)` itself, which clones from github.com over the
/// network, remains untested and untouched here). Per CLAUDE.md's guidance for this file,
/// `readLines`/`readWholeFile` are tested against a real local git repo fixture rather than a
/// network clone: the `.head` side just reads Foundation's `String(contentsOf:)` from a plain
/// temp directory, and the `.base` side goes through `Shell.run("git", ["show", ...])` against
/// a real, fully local `git init`+commit — no network, and `git` itself (unlike `pi`/`claude`)
/// is a build-time dependency of every checkout this app makes, not an optional harness.
struct RepoContextServiceTests {

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Initializes a real git repo at `dir`, commits `contents` for `path`, and returns that
    /// commit's SHA — the "base" the PR diffs against, and a plain temp directory the app's
    /// own `Shell.run` can act on exactly like a real checkout.
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

    /// Context is clamped to the file's actual bounds rather than requesting lines that
    /// don't exist, at both the start and the end of the file.
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

    /// `side: .base` reads the pre-PR blob through `git show <baseSha>:<path>` rather than
    /// the working tree, so it must see the committed content even after the working tree
    /// has since moved on (exactly what happens once the checkout fetches the PR head).
    @Test func readLinesOnTheBaseSideReadsTheCommittedBlobNotTheWorkingTree() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let baseSha = try await makeGitRepo(at: dir, path: "a.txt", contents: "committed line 1\ncommitted line 2\n")

        // The working tree now diverges from what was committed — the head checkout.
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

    /// `contextLines` defaults to 6 when the caller omits it (the code viewer's normal call
    /// shape). The other tests all pass it explicitly, which never exercises the compiler's
    /// default-argument path, so this pins the default's actual value rather than just its
    /// presence in the signature.
    @Test func readLinesDefaultsToSixLinesOfContextWhenOmitted() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = (1...20).map { "line \($0)" }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        let result = try await RepoContextService().readLines(in: checkout, path: "a.txt", startLine: 10, endLine: 10)
        #expect(result.lines.map(\.number) == Array(4...16), "default context is 6 lines either side")
    }

    /// A request whose entire range falls past the end of the file (e.g. a stale ref from a
    /// revision where the file was longer) must clamp to nothing rather than crash indexing
    /// into `allLines`, exercising the `where n <= allLines.count` guard's false branch.
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
