import Testing
@testable import Contour

/// `CodeViewerLogic` is the line-range highlight resolution and whole-file line numbering
/// CLAUDE.md calls out for this file, pulled out of `CodeViewerView`'s body so it's testable
/// directly with fixture `CodeRef`s and source text.
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
}
