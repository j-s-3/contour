import Testing
import Foundation
@testable import Contour

struct UnifiedDiffTests {
    private func lines(_ text: String) -> String { text + "\n" }

    @Test func aModifiedFileWithSeveralHunksNumbersBothSides() throws {
        let files = UnifiedDiff.parse(lines("""
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
        @@ -20,2 +21,2 @@ fn b() {
        -    x
        +    y
         done
        """))

        #expect(files.count == 1)
        let file = try #require(files.first)
        #expect(file.status == .modified)
        #expect(file.oldPath == "src/input.rs" && file.newPath == "src/input.rs")
        #expect(file.additions == 3 && file.deletions == 2)
        #expect(file.hunks.count == 2)

        let first = file.hunks[0]
        #expect(first.header == "@@ -1,3 +1,4 @@ use std::io;")
        #expect(first.lines.map(\.kind) == [.context, .removed, .added, .added, .context])
        #expect(first.lines.map(\.oldLine) == [1, 2, nil, nil, 3])
        #expect(first.lines.map(\.newLine) == [1, nil, 2, 3, 4])
        #expect(first.lines[1].text == "    old();")

        let second = file.hunks[1]
        #expect((second.oldStart, second.oldCount, second.newStart, second.newCount) == (20, 2, 21, 2))
        #expect(second.lines.map(\.oldLine) == [20, nil, 21])
        #expect(second.lines.map(\.newLine) == [nil, 21, 22])
    }

    @Test func newAndDeletedFilesHaveOnlyOneSide() throws {
        let files = UnifiedDiff.parse(lines("""
        diff --git a/docs/new.md b/docs/new.md
        new file mode 100644
        index 0000000..3333333
        --- /dev/null
        +++ b/docs/new.md
        @@ -0,0 +1,2 @@
        +# Title
        +body
        diff --git a/old.txt b/old.txt
        deleted file mode 100644
        index 4444444..0000000
        --- a/old.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -gone
        """))

        #expect(files.count == 2)
        let added = files[0], deleted = files[1]
        #expect(added.status == .added && added.oldPath == nil && added.newPath == "docs/new.md")
        #expect(added.additions == 2 && added.deletions == 0)
        #expect(added.hunks[0].lines.map(\.newLine) == [1, 2])
        #expect(deleted.status == .deleted && deleted.newPath == nil && deleted.path == "old.txt")
        #expect(deleted.hunks[0].oldCount == 1)
        #expect(deleted.hunks[0].lines.map(\.oldLine) == [1])
    }

    @Test func aRenameKeepsBothPathsWithOrWithoutEdits() throws {
        let files = UnifiedDiff.parse(lines("""
        diff --git a/lib/a.swift b/lib/b.swift
        similarity index 100%
        rename from lib/a.swift
        rename to lib/b.swift
        diff --git a/x/old name.rs b/y/new name.rs
        similarity index 90%
        rename from x/old name.rs
        rename to y/new name.rs
        index 5555555..6666666 100644
        --- a/x/old name.rs
        +++ b/y/new name.rs
        @@ -1,1 +1,1 @@
        -a
        +b
        """))

        #expect(files.count == 2)
        #expect(files[0].status == .renamed)
        #expect(files[0].oldPath == "lib/a.swift" && files[0].newPath == "lib/b.swift")
        #expect(files[0].hunks.isEmpty)
        #expect(files[1].status == .renamed)
        #expect(files[1].oldPath == "x/old name.rs" && files[1].newPath == "y/new name.rs")
        #expect(files[1].additions == 1 && files[1].deletions == 1)
    }

    @Test func aBinaryFileHasNoHunks() throws {
        let files = UnifiedDiff.parse(lines("""
        diff --git a/assets/logo.png b/assets/logo.png
        index 7777777..8888888 100644
        Binary files a/assets/logo.png and b/assets/logo.png differ
        diff --git a/README.md b/README.md
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -x
        +y
        """))

        #expect(files.count == 2)
        #expect(files[0].isBinary && files[0].hunks.isEmpty && files[0].path == "assets/logo.png")
        #expect(!files[1].isBinary && files[1].hunks.count == 1)
    }

    @Test func noNewlineMarkersAreKeptButNumberNothing() throws {
        let files = UnifiedDiff.parse(lines("""
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -1,2 +1,2 @@
         keep
        -last
        \\ No newline at end of file
        +last
        \\ No newline at end of file
        """))

        let hunk = try #require(files.first?.hunks.first)
        #expect(hunk.lines.map(\.kind) == [.context, .removed, .noNewlineMarker, .added, .noNewlineMarker])
        #expect(hunk.lines[2].oldLine == nil && hunk.lines[2].newLine == nil)
        #expect(hunk.lines[3].newLine == 2)
        #expect(files[0].additions == 1 && files[0].deletions == 1)
    }

    @Test func bodyLinesThatLookLikeHeadersStayInTheHunk() throws {
        let files = UnifiedDiff.parse(lines("""
        diff --git a/notes.md b/notes.md
        --- a/notes.md
        +++ b/notes.md
        @@ -1,2 +1,2 @@
        --- a heading rule
        +++ a plus rule

        """))

        #expect(files.count == 1)
        let hunk = try #require(files.first?.hunks.first)
        #expect(hunk.lines.map(\.kind) == [.removed, .added, .context])
        #expect(hunk.lines[0].text == "-- a heading rule")
        #expect(files[0].oldPath == "notes.md")
    }

    @Test func aPlainUnifiedDiffWithoutGitHeadersSplitsIntoFiles() {
        let files = UnifiedDiff.parse(lines("""
        --- a/one.c\t2024-01-01 00:00:00
        +++ b/one.c\t2024-01-02 00:00:00
        @@ -1 +1 @@
        -a
        +b
        --- a/two.c
        +++ b/two.c
        @@ -3 +3,2 @@
         c
        +d
        """))

        #expect(files.map(\.path) == ["one.c", "two.c"])
        #expect(files[1].hunks[0].lines.map(\.newLine) == [3, 4])
    }

    @Test func anEmptyDiffHasNoFiles() {
        #expect(UnifiedDiff.parse("").isEmpty)
    }

    @Test func gitHeaderPathsHandlesQuotedPaths() throws {
        let files = UnifiedDiff.parse(lines("""
        diff --git "a/weird name.rs" "b/weird name.rs"
        --- "a/weird name.rs"
        +++ "b/weird name.rs"
        @@ -1 +1 @@
        -a
        +b
        """))
        let file = try #require(files.first)
        #expect(file.oldPath == "weird name.rs" && file.newPath == "weird name.rs")
    }

    @Test func copyFromAndToMarkACopiedFile() throws {
        let files = UnifiedDiff.parse(lines("""
        diff --git a/orig.rs b/copy.rs
        similarity index 100%
        copy from orig.rs
        copy to copy.rs
        """))
        let file = try #require(files.first)
        #expect(file.status == .copied)
        #expect(file.oldPath == "orig.rs" && file.newPath == "copy.rs")
    }

    @Test func quotedRenamePathsAreUnquoted() throws {
        let files = UnifiedDiff.parse(lines("""
        diff --git a/old.txt b/new.txt
        similarity index 100%
        rename from "old file.txt"
        rename to "new file.txt"
        """))
        let file = try #require(files.first)
        #expect(file.oldPath == "old file.txt" && file.newPath == "new file.txt")
    }

    @Test func aMalformedHunkHeaderIsIgnoredEntirely() throws {
        let files = UnifiedDiff.parse(lines("""
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ a/a.txt
        @@ garbage @@
         this line has nowhere to go
        """))
        let file = try #require(files.first)
        #expect(file.hunks.isEmpty)
    }

    private let sample = UnifiedDiff.parse("""
    diff --git a/src/a.rs b/src/a.rs
    --- a/src/a.rs
    +++ b/src/a.rs
    @@ -10,3 +10,4 @@
     a
    +b
     c
     d
    @@ -50,2 +51,2 @@
    -x
    +y
     z
    """ + "\n")

    @Test func aReferenceOverlapsOnlyTheHunksOnItsSide() throws {
        let file = try #require(sample.first)
        #expect(file.contains(CodeRef(path: "src/a.rs", startLine: 1, endLine: 1)))
        #expect(!file.contains(CodeRef(path: "src/b.rs", startLine: 1, endLine: 1)))
        #expect(file.hunks[0].overlaps(CodeRef(path: "src/a.rs", startLine: 12, endLine: 40)))
        #expect(!file.hunks[0].overlaps(CodeRef(path: "src/a.rs", startLine: 14, endLine: 40)))
        #expect(file.hunks[1].overlaps(CodeRef(path: "src/a.rs", startLine: 52, endLine: 52)))
        #expect(file.hunks[1].overlaps(CodeRef(path: "src/a.rs", startLine: 50, endLine: 50, side: .base)))
        #expect(!file.hunks[1].overlaps(CodeRef(path: "src/a.rs", startLine: 50, endLine: 50)))
    }

    @Test func hunksAreBadgedWithTheDecisionsAndFlowStagesThatCiteThem() {
        var graph = ContourSampleData.publishTriggeredReindex
        let ref = CodeRef(path: "src/a.rs", startLine: 11, endLine: 11)
        graph.decisions = [
            DecisionNode(id: "d1", title: "Sample more bytes",
                         decision: Statement(text: "x", provenance: .fact), confidence: .high,
                         refs: [ref, CodeRef(path: "src/a.rs", startLine: 10, endLine: 12)]),
            DecisionNode(id: "d2", title: "Unrelated",
                         decision: Statement(text: "x", provenance: .fact), confidence: .high,
                         refs: [CodeRef(path: "src/other.rs", startLine: 11, endLine: 11)]),
        ]
        graph.flows = [FlowNode(id: "f", title: "Open a file", behavior: FlowBehavior(nodes: [
            FlowBehaviorNode(id: "n1", label: "Classify content", refs: [CodeRef(path: "src/a.rs", startLine: 51, endLine: 51)]),
        ]))]

        let citations = graph.diffCitations(in: sample)
        #expect(citations["0:0"]?.map(\.title) == ["Sample more bytes"])
        #expect(citations["0:0"]?.first?.target == .decisionDetail("d1"))
        #expect(citations["0:1"]?.map(\.target) == [.flowNodeDetail(flowId: "f", nodeId: "n1")])
    }
}
