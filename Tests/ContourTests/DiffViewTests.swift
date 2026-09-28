import Testing
import Foundation
import SwiftUI
@testable import Contour

/// `UnifiedDiff` parsing is already covered by `UnifiedDiffTests`; this pins `DiffViewLogic`
/// — the file/hunk navigation, line highlighting, and path formatting CLAUDE.md calls out
/// for this file — pulled out of `DiffView`'s instance methods so it's testable the same
/// way, plus `DiffFileStatus.color` (already plain, no production change needed; `.label`
/// lives on the model and needed none either).
struct DiffViewTests {

    private func parsedFile(_ diff: String) throws -> DiffFile {
        try #require(UnifiedDiff.parse(diff + "\n").first)
    }

    private let modifiedDiff = """
    diff --git a/src/input.rs b/src/input.rs
    index 1111111..2222222 100644
    --- a/src/input.rs
    +++ b/src/input.rs
    @@ -1,3 +1,4 @@ use std::io;
     fn a() {
    -    old();
    +    new();
    +    more();
     }
    """

    private let deletedDiff = """
    diff --git a/src/gone.rs b/src/gone.rs
    deleted file mode 100644
    index 1111111..0000000
    --- a/src/gone.rs
    +++ /dev/null
    @@ -1,2 +0,0 @@
    -fn a() {}
    -fn b() {}
    """

    // MARK: - landingTarget

    @Test func landingTargetIsNilForANilReference() throws {
        let file = try parsedFile(modifiedDiff)
        #expect(DiffViewLogic.landingTarget(for: nil, in: [file]) == nil)
    }

    @Test func landingTargetIsNilWhenNoFileContainsTheReference() throws {
        let file = try parsedFile(modifiedDiff)
        let ref = CodeRef(path: "src/other.rs", startLine: 1, endLine: 1)
        #expect(DiffViewLogic.landingTarget(for: ref, in: [file]) == nil)
    }

    @Test func landingTargetFindsTheFileAndOverlappingHunk() throws {
        let file = try parsedFile(modifiedDiff)
        let ref = CodeRef(path: "src/input.rs", startLine: 2, endLine: 2)
        let target = try #require(DiffViewLogic.landingTarget(for: ref, in: [file]))
        #expect(target.file == file)
        #expect(target.hunk == file.hunks.first)
    }

    @Test func landingTargetFindsTheFileWithNoHunkWhenTheReferenceIsOutsideEveryHunk() throws {
        let file = try parsedFile(modifiedDiff)
        // Line 99 is well past this file's single hunk (lines 1-4 on the new side).
        let ref = CodeRef(path: "src/input.rs", startLine: 99, endLine: 99)
        let target = try #require(DiffViewLogic.landingTarget(for: ref, in: [file]))
        #expect(target.file == file)
        #expect(target.hunk == nil)
    }

    // MARK: - hunkRef

    @Test func hunkRefUsesTheNewSideForAModifiedFile() throws {
        let file = try parsedFile(modifiedDiff)
        let hunk = try #require(file.hunks.first)
        let ref = DiffViewLogic.hunkRef(hunk, in: file)
        #expect(ref.path == "src/input.rs")
        #expect(ref.side == .head)
        #expect((ref.startLine, ref.endLine) == (1, 4))
    }

    @Test func hunkRefUsesTheOldSideForADeletedFile() throws {
        let file = try parsedFile(deletedDiff)
        let hunk = try #require(file.hunks.first)
        let ref = DiffViewLogic.hunkRef(hunk, in: file)
        #expect(ref.path == "src/gone.rs")
        #expect(ref.side == .base)
        #expect((ref.startLine, ref.endLine) == (1, 2))
    }

    // MARK: - marker / markerColor

    @Test func markerAndColorMatchEveryLineKind() {
        #expect(DiffViewLogic.marker(.added) == "+")
        #expect(DiffViewLogic.marker(.removed) == "−")
        #expect(DiffViewLogic.marker(.context) == "")
        #expect(DiffViewLogic.marker(.noNewlineMarker) == "")

        #expect(DiffViewLogic.markerColor(.added) == .green)
        #expect(DiffViewLogic.markerColor(.removed) == .red)
        #expect(DiffViewLogic.markerColor(.context) == .secondary)
        #expect(DiffViewLogic.markerColor(.noNewlineMarker) == .secondary)
    }

    // MARK: - isFocused / background

    @Test func isFocusedMatchesTheCitedRangeOnTheCitedSide() throws {
        let file = try parsedFile(modifiedDiff)
        let addedLine = try #require(file.hunks.first?.lines.first { $0.kind == .added && $0.newLine == 2 })
        let focus = CodeRef(path: "src/input.rs", startLine: 2, endLine: 3)
        #expect(DiffViewLogic.isFocused(addedLine, in: file, focus: focus))
    }

    @Test func isFocusedIsFalseForALineOutsideTheCitedRange() throws {
        let file = try parsedFile(modifiedDiff)
        let contextLine = try #require(file.hunks.first?.lines.first { $0.kind == .context })
        let focus = CodeRef(path: "src/input.rs", startLine: 50, endLine: 60)
        #expect(!DiffViewLogic.isFocused(contextLine, in: file, focus: focus))
    }

    @Test func isFocusedIsFalseWithNoFocus() throws {
        let file = try parsedFile(modifiedDiff)
        let line = try #require(file.hunks.first?.lines.first)
        #expect(!DiffViewLogic.isFocused(line, in: file, focus: nil))
    }

    @Test func isFocusedIsFalseForADifferentFile() throws {
        let file = try parsedFile(modifiedDiff)
        let line = try #require(file.hunks.first?.lines.first)
        let focus = CodeRef(path: "src/other.rs", startLine: 1, endLine: 100)
        #expect(!DiffViewLogic.isFocused(line, in: file, focus: focus))
    }

    @Test func backgroundIsYellowWhenFocusedRegardlessOfKind() throws {
        let file = try parsedFile(modifiedDiff)
        let contextLine = try #require(file.hunks.first?.lines.first { $0.kind == .context })
        let focus = CodeRef(path: "src/input.rs", startLine: contextLine.newLine ?? 0, endLine: contextLine.newLine ?? 0)
        #expect(DiffViewLogic.background(contextLine, in: file, focus: focus) == Color.yellow.opacity(0.22))
    }

    @Test func backgroundFollowsTheLineKindWhenNotFocused() throws {
        let file = try parsedFile(modifiedDiff)
        let added = try #require(file.hunks.first?.lines.first { $0.kind == .added })
        let removed = try #require(file.hunks.first?.lines.first { $0.kind == .removed })
        let context = try #require(file.hunks.first?.lines.first { $0.kind == .context })
        #expect(DiffViewLogic.background(added, in: file, focus: nil) == Color.green.opacity(0.10))
        #expect(DiffViewLogic.background(removed, in: file, focus: nil) == Color.red.opacity(0.10))
        #expect(DiffViewLogic.background(context, in: file, focus: nil) == .clear)
    }

    // MARK: - gutterWidth

    @Test func gutterWidthGrowsWithLargerLineNumbers() throws {
        let small = try parsedFile(modifiedDiff)
        let smallWidth = DiffViewLogic.gutterWidth(small)

        // Enough lines to push the new-side count past 999 — the gutter has a 3-digit floor,
        // so a smaller number wouldn't move it.
        let manyLines = (1...1000).map { "+line\($0)" }.joined(separator: "\n")
        let bigDiff = """
        diff --git a/src/big.rs b/src/big.rs
        index 1111111..2222222 100644
        --- a/src/big.rs
        +++ b/src/big.rs
        @@ -0,0 +1,1000 @@
        \(manyLines)
        """
        let big = try parsedFile(bigDiff)
        #expect(DiffViewLogic.gutterWidth(big) > smallWidth)
    }

    // MARK: - fileName / directory

    @Test func fileNameIsTheLastPathComponent() {
        #expect(DiffViewLogic.fileName("src/main/java/App.java") == "App.java")
        #expect(DiffViewLogic.fileName("App.java") == "App.java")
    }

    @Test func directoryIsEverythingBeforeTheLastPathComponent() {
        #expect(DiffViewLogic.directory("src/main/java/App.java") == "src/main/java")
        #expect(DiffViewLogic.directory("App.java") == nil)
    }

    // MARK: - DiffFileStatus

    @Test func everyDiffFileStatusHasItsOwnLabel() {
        #expect(DiffFileStatus.modified.label == "Modified")
        #expect(DiffFileStatus.added.label == "Added")
        #expect(DiffFileStatus.deleted.label == "Deleted")
        #expect(DiffFileStatus.renamed.label == "Renamed")
        #expect(DiffFileStatus.copied.label == "Copied")
    }

    @Test func everyDiffFileStatusHasItsOwnColor() {
        #expect(DiffFileStatus.modified.color == .secondary)
        #expect(DiffFileStatus.added.color == .green)
        #expect(DiffFileStatus.deleted.color == .red)
        #expect(DiffFileStatus.renamed.color == .blue)
        #expect(DiffFileStatus.copied.color == .blue)
    }
}
