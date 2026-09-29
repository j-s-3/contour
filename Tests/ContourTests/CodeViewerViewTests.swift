import Foundation
import Testing
@testable import Contour

struct CodeViewerViewTests {
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

    @Test func numberedLinesAssignsOneBasedLineNumbersInOrder() {
        let rows = CodeViewerLogic.numberedLines("first\nsecond\nthird")
        #expect(rows.map(\.number) == [1, 2, 3])
        #expect(rows.map(\.text) == ["first", "second", "third"])
    }

    @Test func numberedLinesOfEmptyTextIsOneEmptyRow() {
        let rows = CodeViewerLogic.numberedLines("")
        #expect(rows.map(\.number) == [1])
        #expect(rows.map(\.text) == [""])
    }

    @Test func numberedLinesPreservesATrailingBlankLine() {
        let rows = CodeViewerLogic.numberedLines("a\nb\n")
        #expect(rows.map(\.number) == [1, 2, 3])
        #expect(rows.map(\.text) == ["a", "b", ""])
    }

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

    @Test func loadExcerptReturnsNoCheckoutWhenThereIsNoLocalCheckout() async {
        let ref = CodeRef(path: "a.swift", startLine: 1, endLine: 1)
        let outcome = await CodeViewerLogic.loadExcerpt(
            checkout: nil, ref: ref, contextLines: 6, service: RepoContextService()
        )
        guard case .noCheckout = outcome else { Issue.record("expected .noCheckout, got \(outcome)"); return }
    }

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


    @Test func showsBaseBadgeOnlyForBaseSide() {
        #expect(CodeViewerLogic.showsBaseBadge(CodeRef(path: "a", startLine: 1, endLine: 1, side: .base)))
        #expect(!CodeViewerLogic.showsBaseBadge(CodeRef(path: "a", startLine: 1, endLine: 1)))
    }

    @Test func expandContextWidensByEight() {
        var state = CodeViewerState()
        #expect(state.contextLines == 6)
        state.expandContext()
        #expect(state.contextLines == 14)
    }

    @Test func toggleWholeFileSwitchesRowsTitleAndExpandAvailability() {
        var state = CodeViewerState()
        state.lines = [(3, "x")]
        state.wholeFile = "a\nb"
        #expect(state.visibleRows.map(\.number) == [3])
        #expect(state.wholeFileToggleTitle == "Open whole file")
        #expect(!state.expandContextDisabled)

        let opened = state.toggleWholeFile()
        #expect(opened)
        #expect(state.visibleRows.map(\.text) == ["a", "b"])
        #expect(state.wholeFileToggleTitle == "Show excerpt")
        #expect(state.expandContextDisabled)

        let closed = state.toggleWholeFile()
        #expect(!closed)
        #expect(state.visibleRows.map(\.number) == [3])
    }

    @Test func excerptOutcomesSetLinesAndErrorMessage() {
        var state = CodeViewerState()
        state.apply(excerpt: .noCheckout)
        #expect(state.errorMessage == "No local checkout available.")
        state.apply(excerpt: .failed("boom"))
        #expect(state.errorMessage == "boom")
        state.apply(excerpt: .loaded([(1, "a")]))
        #expect(state.errorMessage == nil)
        #expect(state.lines.map(\.text) == ["a"])
    }

    @Test func wholeFileOutcomesKeepExcerptOnNoCheckoutAndSurfaceFailures() {
        var state = CodeViewerState()
        state.errorMessage = "old"
        state.apply(wholeFile: .noCheckout)
        #expect(state.errorMessage == "old")
        #expect(state.wholeFile.isEmpty)
        state.apply(wholeFile: .failed("nope"))
        #expect(state.errorMessage == "nope")
        state.apply(wholeFile: .loaded("hello"))
        #expect(state.errorMessage == nil)
        #expect(state.wholeFile == "hello")
    }
}
