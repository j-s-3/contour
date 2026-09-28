import Foundation
import Testing
@testable import Contour

/// `CodeViewerLogic` is the line-range highlight resolution, whole-file line numbering, and
/// load-outcome branching (missing checkout / success / failure) CLAUDE.md calls out for this
/// file, pulled out of `CodeViewerView`'s body and `@State`-mutating private methods so it's
/// testable directly with fixture `CodeRef`s, source text, and (for `loadExcerpt`/`loadWholeFile`)
/// a real, local, no-network git checkout — the same fixture pattern `RepoContextServiceTests`
/// uses, since `readLines`/`readWholeFile` themselves are already covered there and this instead
/// pins the branching `CodeViewerView` layers on top of them.
struct CodeViewerViewTests {

    // MARK: - isInRef

    @Test func isInRefIsTrueForEveryLineWithinTheCitedRangeInclusive() {
        let ref = CodeRef(path: "a.swift", startLine: 10, endLine: 12)
        #expect(CodeViewerLogic.isInRef(10, ref: ref))
        #expect(CodeViewerLogic.isInRef(11, ref: ref))
        #expect(CodeViewerLogic.isInRef(12, ref: ref))
    }

    @Test func isInRefIsFalseJustOutsideTheCitedRange() {
        let ref = CodeRef(path: "a.swift", startLine: 10, endLine: 12)
        #expect(!CodeViewerLogic.isInRef(9, ref: ref))
        #expect(!CodeViewerLogic.isInRef(13, ref: ref))
    }

    @Test func isInRefHandlesASingleLineRange() {
        let ref = CodeRef(path: "a.swift", startLine: 5, endLine: 5)
        #expect(CodeViewerLogic.isInRef(5, ref: ref))
        #expect(!CodeViewerLogic.isInRef(4, ref: ref))
        #expect(!CodeViewerLogic.isInRef(6, ref: ref))
    }

    // MARK: - numberedLines

    @Test func numberedLinesAssignsOneBasedLineNumbersInOrder() {
        let rows = CodeViewerLogic.numberedLines("first\nsecond\nthird")
        #expect(rows.map(\.number) == [1, 2, 3])
        #expect(rows.map(\.text) == ["first", "second", "third"])
    }

    @Test func numberedLinesOfEmptyTextIsOneEmptyRow() {
        // "".components(separatedBy: "\n") is [""], matching a genuinely empty file.
        let rows = CodeViewerLogic.numberedLines("")
        #expect(rows.map(\.number) == [1])
        #expect(rows.map(\.text) == [""])
    }

    @Test func numberedLinesPreservesATrailingBlankLine() {
        let rows = CodeViewerLogic.numberedLines("a\nb\n")
        #expect(rows.map(\.number) == [1, 2, 3])
        #expect(rows.map(\.text) == ["a", "b", ""])
    }

    // MARK: - loadExcerpt / loadWholeFile fixtures

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Initializes a real git repo at `dir`, commits `contents` for `path`, and returns that
    /// commit's SHA, mirroring `RepoContextServiceTests`' fixture: a plain temp directory
    /// `Shell.run` can act on exactly like a real checkout, no network involved.
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

    // MARK: - loadExcerpt

    /// `load()`'s missing-checkout guard: no local checkout means `.noCheckout`, which
    /// `CodeViewerView` turns into "No local checkout available." without touching `lines`.
    @Test func loadExcerptReturnsNoCheckoutWhenThereIsNoLocalCheckout() async {
        let ref = CodeRef(path: "a.swift", startLine: 1, endLine: 1)
        let outcome = await CodeViewerLogic.loadExcerpt(
            checkout: nil, ref: ref, contextLines: 6, service: RepoContextService()
        )
        guard case .noCheckout = outcome else { Issue.record("expected .noCheckout, got \(outcome)"); return }
    }

    /// The success path reads exactly the cited range plus context from a real (no-network)
    /// checkout on the working-tree (`.head`) side — the excerpt `CodeViewerView` renders.
    @Test func loadExcerptReturnsTheCitedRangeFromARealCheckout() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let contents = (1...10).map { "line \($0)" }.joined(separator: "\n")
        try contents.write(to: dir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)

        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        let ref = CodeRef(path: "a.swift", startLine: 5, endLine: 5)
        let outcome = await CodeViewerLogic.loadExcerpt(
            checkout: checkout, ref: ref, contextLines: 1, service: RepoContextService()
        )
        guard case .loaded(let lines) = outcome else { Issue.record("expected .loaded, got \(outcome)"); return }
        #expect(lines.map(\.number) == [4, 5, 6])
        #expect(lines.map(\.text) == ["line 4", "line 5", "line 6"])
    }

    /// `ref.side == .base` is threaded through to `readLines`, so the excerpt comes from the
    /// committed blob rather than a working tree that has since moved on — the same distinction
    /// `RepoContextServiceTests` pins at the service layer, exercised here through the view's
    /// own extracted decision.
    @Test func loadExcerptOnTheBaseSideReadsTheCommittedBlobNotTheWorkingTree() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let baseSha = try await makeGitRepo(at: dir, path: "a.swift", contents: "committed\n")
        try "working tree now\n".write(to: dir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)

        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: baseSha, symbolIndexPath: nil)
        let ref = CodeRef(path: "a.swift", startLine: 1, endLine: 1, side: .base)
        let outcome = await CodeViewerLogic.loadExcerpt(
            checkout: checkout, ref: ref, contextLines: 0, service: RepoContextService()
        )
        guard case .loaded(let lines) = outcome else { Issue.record("expected .loaded, got \(outcome)"); return }
        #expect(lines.first?.text == "committed")
    }

    /// A path that doesn't exist in the checkout throws from `readLines`; `loadExcerpt` turns
    /// that into `.failed` with the error's message rather than propagating it, matching
    /// `load()`'s original `catch { errorMessage = error.localizedDescription }`.
    @Test func loadExcerptReturnsFailedWhenTheFileDoesNotExist() async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        let ref = CodeRef(path: "missing.swift", startLine: 1, endLine: 1)
        let outcome = await CodeViewerLogic.loadExcerpt(
            checkout: checkout, ref: ref, contextLines: 0, service: RepoContextService()
        )
        guard case .failed(let message) = outcome else { Issue.record("expected .failed, got \(outcome)"); return }
        #expect(!message.isEmpty)
    }

    // MARK: - loadWholeFile

    /// `loadWholeFile()`'s missing-checkout guard is a silent no-op in the original code (it
    /// neither sets `wholeFile` nor `errorMessage`), unlike `load()`'s guard — pinning that
    /// asymmetry so a future refactor doesn't accidentally unify the two behaviors.
    @Test func loadWholeFileReturnsNoCheckoutWhenThereIsNoLocalCheckout() async {
        let outcome = await CodeViewerLogic.loadWholeFile(checkout: nil, path: "a.swift", service: RepoContextService())
        guard case .noCheckout = outcome else { Issue.record("expected .noCheckout, got \(outcome)"); return }
    }

    @Test func loadWholeFileReturnsTheFilesFullContentsFromARealCheckout() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "whole file contents\nsecond line".write(to: dir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)

        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        let outcome = await CodeViewerLogic.loadWholeFile(checkout: checkout, path: "a.swift", service: RepoContextService())
        guard case .loaded(let content) = outcome else { Issue.record("expected .loaded, got \(outcome)"); return }
        #expect(content == "whole file contents\nsecond line")
    }

    @Test func loadWholeFileReturnsFailedWhenTheFileDoesNotExist() async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        let outcome = await CodeViewerLogic.loadWholeFile(checkout: checkout, path: "missing.swift", service: RepoContextService())
        guard case .failed(let message) = outcome else { Issue.record("expected .failed, got \(outcome)"); return }
        #expect(!message.isEmpty)
    }
}
