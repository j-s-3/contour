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
        try lines.joined(separator: "\n").write(
            to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

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
        try lines.joined(separator: "\n").write(
            to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

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

        try "working tree line 1\nworking tree line 2\n".write(
            to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

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
        try lines.joined(separator: "\n").write(
            to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        let result = try await RepoContextService().readLines(in: checkout, path: "a.txt", startLine: 10, endLine: 10)
        #expect(result.lines.map(\.number) == Array(4...16), "default context is 6 lines either side")
    }

    @Test func readLinesReturnsEmptyWhenTheRequestedRangeIsEntirelyPastTheEndOfTheFile() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = (1...3).map { "line \($0)" }
        try lines.joined(separator: "\n").write(
            to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        let result = try await RepoContextService().readLines(
            in: checkout, path: "a.txt", startLine: 10, endLine: 12, contextLines: 0
        )
        #expect(result.lines.isEmpty)
        #expect(
            result.refStart == 10 && result.refEnd == 12, "the requested range is echoed back even when nothing matched"
        )
    }

    private struct RemoteFixture {
        var remote: URL
        var baseSha: String
        var headSha: String
    }

    private func makeRemote(at remote: URL) async throws -> RemoteFixture {
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        _ = try await Shell.run("git", ["init", "-q", "-b", "main"], cwd: remote)
        _ = try await Shell.run("git", ["config", "user.email", "test@example.com"], cwd: remote)
        _ = try await Shell.run("git", ["config", "user.name", "Test"], cwd: remote)
        try "base\n".write(to: remote.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await Shell.run("git", ["add", "a.txt"], cwd: remote)
        _ = try await Shell.run("git", ["commit", "-q", "-m", "base"], cwd: remote)
        let baseSha = try await headOf(remote)
        _ = try await Shell.run("git", ["checkout", "-q", "-b", "feature"], cwd: remote)
        try "head\n".write(to: remote.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await Shell.run("git", ["commit", "-q", "-am", "head"], cwd: remote)
        let headSha = try await headOf(remote)
        _ = try await Shell.run("git", ["update-ref", "refs/pull/7/head", headSha], cwd: remote)
        _ = try await Shell.run("git", ["checkout", "-q", "main"], cwd: remote)
        return RemoteFixture(remote: remote, baseSha: baseSha, headSha: headSha)
    }

    private func context(_ fixture: RemoteFixture, baseRefName: String = "main", baseSha: String? = nil) -> RawPRContext
    {
        RawPRContext(
            url: "https://github.com/octo/widgets/pull/7", owner: "octo", repo: "widgets", number: 7,
            title: "t", body: "", author: "a", state: "OPEN", headRefName: "feature", baseRefName: baseRefName,
            headSha: fixture.headSha, baseSha: baseSha ?? fixture.baseSha, isCrossRepository: false,
            headCloneURL: "", additions: 0, deletions: 0, changedFiles: 1, files: ["a.txt"], commits: [],
            comments: [], reviews: [], diff: "")
    }

    private func headOf(_ dir: URL) async throws -> String {
        try await Shell.run("git", ["rev-parse", "HEAD"], cwd: dir).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func service(cache root: URL, remote: URL) -> RepoContextService {
        let remotePath = remote.path
        return RepoContextService(cacheRoot: root.appendingPathComponent("cache"), remoteURL: { _ in remotePath })
    }

    @Test func checkoutClonesTheRepoAndChecksOutThePullRequestHead() async throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeRemote(at: root.appendingPathComponent("remote"))
        let service = service(cache: root, remote: fixture.remote)

        let checkout = try await service.checkout(context(fixture))

        #expect(
            checkout.rootDir
                == root.appendingPathComponent("cache").appendingPathComponent("octo-widgets", isDirectory: true))
        #expect(checkout.headSha == fixture.headSha && checkout.baseSha == fixture.baseSha)
        #expect(checkout.symbolIndexPath == nil)
        #expect(try await headOf(checkout.rootDir) == fixture.headSha)
        #expect(try await service.readWholeFile(in: checkout, path: "a.txt") == "head\n")
    }

    @Test func checkoutOfAnAlreadyCurrentCloneDoesNotTouchTheRemote() async throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeRemote(at: root.appendingPathComponent("remote"))
        let service = service(cache: root, remote: fixture.remote)
        _ = try await service.checkout(context(fixture))

        try FileManager.default.removeItem(at: fixture.remote)
        let again = try await service.checkout(context(fixture))

        #expect(try await headOf(again.rootDir) == fixture.headSha, "no clone or fetch was needed")
    }

    @Test func checkoutMovesAnExistingCloneToANewPullRequestHead() async throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeRemote(at: root.appendingPathComponent("remote"))
        let service = service(cache: root, remote: fixture.remote)
        let first = try await service.checkout(context(fixture))

        let remote = fixture.remote
        _ = try await Shell.run("git", ["checkout", "-q", "feature"], cwd: remote)
        try "newer\n".write(to: remote.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await Shell.run("git", ["commit", "-q", "-am", "newer"], cwd: remote)
        let newerSha = try await headOf(remote)
        _ = try await Shell.run("git", ["update-ref", "refs/pull/7/head", newerSha], cwd: remote)
        var moved = context(fixture)
        moved.headSha = newerSha

        let second = try await service.checkout(moved)

        #expect(second.rootDir == first.rootDir)
        #expect(try await headOf(second.rootDir) == newerSha)
        #expect(try await service.readWholeFile(in: second, path: "a.txt") == "newer\n")
    }

    @Test func checkoutToleratesABaseRefThatCannotBeFetchedWhenTheBaseCommitIsPresent() async throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeRemote(at: root.appendingPathComponent("remote"))
        let service = service(cache: root, remote: fixture.remote)

        let checkout = try await service.checkout(context(fixture, baseRefName: "deleted-branch"))

        #expect(try await headOf(checkout.rootDir) == fixture.headSha)
    }

    @Test func checkoutToleratesABaseRefAndBaseCommitThatCannotBeFetched() async throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeRemote(at: root.appendingPathComponent("remote"))
        let service = service(cache: root, remote: fixture.remote)
        let missingBase = String(repeating: "0", count: 40)

        let checkout = try await service.checkout(
            context(fixture, baseRefName: "deleted-branch", baseSha: missingBase))

        #expect(try await headOf(checkout.rootDir) == fixture.headSha)
        #expect(checkout.baseSha == missingBase)
    }

    @Test func checkoutThrowsWhenTheCloneFails() async throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = RemoteFixture(remote: root, baseSha: "b", headSha: "h")
        let service = service(cache: root, remote: root.appendingPathComponent("no-such-remote"))

        await #expect(throws: (any Error).self) {
            _ = try await service.checkout(context(fixture))
        }
    }

    @Test func defaultCacheRootLivesUnderApplicationSupportContourRepos() {
        let root = RepoContextService.defaultCacheRoot()
        #expect(root.path.hasSuffix("Contour/repos"))
    }
}
