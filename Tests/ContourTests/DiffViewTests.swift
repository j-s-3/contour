import Testing
import Foundation
import SwiftUI
@testable import Contour

struct DiffViewTests {
    private func parsedFile(_ diff: String) throws -> DiffFile {
        try #require(UnifiedDiff.parse(diff + "\n").first)
    }

    private func parsedFiles() throws -> [DiffFile] {
        let files = UnifiedDiff.parse(modifiedDiff + "\n" + deletedDiff + "\n")
        try #require(files.count == 2)
        return files
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
        let ref = CodeRef(path: "src/input.rs", startLine: 99, endLine: 99)
        let target = try #require(DiffViewLogic.landingTarget(for: ref, in: [file]))
        #expect(target.file == file)
        #expect(target.hunk == nil)
    }

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

    @Test func gutterWidthGrowsWithLargerLineNumbers() throws {
        let small = try parsedFile(modifiedDiff)
        let smallWidth = DiffViewLogic.gutterWidth(small)

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

    @Test func fileNameIsTheLastPathComponent() {
        #expect(DiffViewLogic.fileName("src/main/java/App.java") == "App.java")
        #expect(DiffViewLogic.fileName("App.java") == "App.java")
    }

    @Test func directoryIsEverythingBeforeTheLastPathComponent() {
        #expect(DiffViewLogic.directory("src/main/java/App.java") == "src/main/java")
        #expect(DiffViewLogic.directory("App.java") == nil)
    }

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

    @Test func fileCountLabelIsSingularForExactlyOneFile() {
        #expect(DiffViewLogic.fileCountLabel(1) == "1 file")
        #expect(DiffViewLogic.fileCountLabel(0) == "0 files")
        #expect(DiffViewLogic.fileCountLabel(2) == "2 files")
    }

    @Test func totalLineCountsSumsAcrossEveryFile() throws {
        let files = try parsedFiles()
        let totals = DiffViewLogic.totalLineCounts(files)
        #expect(totals == (2, 3))
    }

    @Test func totalLineCountsIsZeroForNoFiles() {
        let totals = DiffViewLogic.totalLineCounts([])
        #expect(totals == (0, 0))
    }

    @Test func toggleAllCollapsedCollapsesEveryFileWhenNoneAreCollapsed() throws {
        let files = try parsedFiles()
        let next = DiffViewLogic.toggleAllCollapsed(files: files, collapsed: [])
        #expect(next == Set([0, 1]))
    }

    @Test func toggleAllCollapsedExpandsEveryFileWhenAnyAreCollapsed() throws {
        let files = try parsedFiles()
        let next = DiffViewLogic.toggleAllCollapsed(files: files, collapsed: [0])
        #expect(next.isEmpty)
    }

    @Test func toggleCollapsedInsertsAnExpandedFileAndRemovesACollapsedOne() {
        #expect(DiffViewLogic.toggleCollapsed(1, in: []) == [1])
        #expect(DiffViewLogic.toggleCollapsed(1, in: [1, 2]) == [2])
    }

    @Test func removingFileDropsOnlyTheGivenFile() {
        #expect(DiffViewLogic.removingFile(1, from: [1, 2]) == [2])
        #expect(DiffViewLogic.removingFile(3, from: [1, 2]) == [1, 2])
    }

    @Test func emptyStateNoteIsBinaryTextRegardlessOfHunks() {
        let file = DiffFile(id: 0, oldPath: "a.png", newPath: "a.png", status: .modified, isBinary: true)
        #expect(DiffViewLogic.emptyStateNote(for: file) == "Binary file not shown")
    }

    @Test func emptyStateNoteIsNilWhenTheFileHasHunksToRender() throws {
        let file = try parsedFile(modifiedDiff)
        #expect(DiffViewLogic.emptyStateNote(for: file) == nil)
    }

    @Test func emptyStateNoteDistinguishesRenamedAddedDeletedAndOtherwiseUnchanged() {
        let renamed = DiffFile(id: 0, oldPath: "old.rs", newPath: "new.rs", status: .renamed)
        let added = DiffFile(id: 1, oldPath: nil, newPath: "new.rs", status: .added)
        let deleted = DiffFile(id: 2, oldPath: "gone.rs", newPath: nil, status: .deleted)
        let modified = DiffFile(id: 3, oldPath: "m.rs", newPath: "m.rs", status: .modified)
        #expect(DiffViewLogic.emptyStateNote(for: renamed) == "Renamed without content changes")
        #expect(DiffViewLogic.emptyStateNote(for: added) == "Empty file")
        #expect(DiffViewLogic.emptyStateNote(for: deleted) == "Empty file")
        #expect(DiffViewLogic.emptyStateNote(for: modified) == "No content changes")
    }

    @Test func headerTitleShowsTheRenameArrowWhenBothPathsAreKnown() {
        let file = DiffFile(id: 0, oldPath: "old/path.rs", newPath: "new/path.rs", status: .renamed)
        let title = DiffViewLogic.headerTitle(for: file)
        #expect(title.old == "old/path.rs")
        #expect(title.new == "new/path.rs")
    }

    @Test func headerTitleFallsBackToThePathForACopyMissingEitherSide() {
        let file = DiffFile(id: 0, oldPath: nil, newPath: "new/path.rs", status: .copied)
        let title = DiffViewLogic.headerTitle(for: file)
        #expect(title.old == nil)
        #expect(title.new == "new/path.rs")
    }

    @Test func headerTitleIsJustThePathForAModifiedFile() {
        let file = DiffFile(id: 0, oldPath: "m.rs", newPath: "m.rs", status: .modified)
        let title = DiffViewLogic.headerTitle(for: file)
        #expect(title.old == nil)
        #expect(title.new == "m.rs")
    }

    private func citation(_ n: Int) -> DiffCitation {
        DiffCitation(kind: .decision, title: "Decision \(n)", target: .decisionDetail("d\(n)"))
    }

    @Test func visibleCitationsShowsEverythingWhenAtOrBelowTheLimit() {
        let citations = (0..<3).map { citation($0) }
        let visible = DiffViewLogic.visibleCitations(citations)
        #expect(visible.shown == citations)
        #expect(visible.overflow.isEmpty)
    }

    @Test func visibleCitationsSplitsTheOverflowAtTheLimit() {
        let citations = (0..<5).map { citation($0) }
        let visible = DiffViewLogic.visibleCitations(citations)
        #expect(visible.shown == Array(citations.prefix(3)))
        #expect(visible.overflow == Array(citations.suffix(2)))
    }
}
