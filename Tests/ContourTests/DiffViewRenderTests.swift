import Testing
import SwiftUI
import AppKit
@testable import Contour

/// `DiffView`'s body, file list, headers, hunk headers, line rows and its small private
/// views are SwiftUI composition with no decisions left in them (those live in
/// `DiffViewLogic`). This hosts the real view in a window-less `NSHostingView` over a diff
/// exercising every branch: modified, added, deleted, renamed, binary and empty files, an
/// empty diff, a focused reference, and a hunk cited by more decisions than fit inline (the
/// "+N" menu). It pins that none of those combinations traps while building or laying out,
/// which the pure-logic tests cannot see.
@MainActor
struct DiffViewRenderTests {

    private let diffText = """
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
    \\ No newline at end of file
    @@ -20,2 +21,2 @@ fn later()
    -x
    +y
    diff --git a/src/added.rs b/src/added.rs
    new file mode 100644
    index 0000000..1111111
    --- /dev/null
    +++ b/src/added.rs
    @@ -0,0 +1,1 @@
    +fn added() {}
    diff --git a/src/gone.rs b/src/gone.rs
    deleted file mode 100644
    index 1111111..0000000
    --- a/src/gone.rs
    +++ /dev/null
    @@ -1,2 +0,0 @@
    -fn a() {}
    -fn b() {}
    diff --git a/old/name.rs b/new/name.rs
    similarity index 100%
    rename from old/name.rs
    rename to new/name.rs
    diff --git a/logo.png b/logo.png
    index 1111111..2222222 100644
    Binary files a/logo.png and b/logo.png differ
    diff --git a/empty.txt b/empty.txt
    new file mode 100644
    index 0000000..e69de29

    """

    private func graphCiting(_ path: String, count: Int) -> PRGraph {
        var graph = ContourSampleData.publishTriggeredReindex
        let template = graph.decisions[0]
        graph.decisions = (0..<count).map { n in
            var d = template
            d.id = "cite-\(n)"
            d.title = "Citing decision \(n)"
            d.refs = [CodeRef(path: path, startLine: 1, endLine: 3)]
            d.tradeoffs = []
            return d
        }
        return graph
    }

    private func host(_ view: DiffView) -> NSHostingView<DiffView> {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 4000)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func aMixedDiffRendersWithOverflowingCitations() {
        let files = UnifiedDiff.parse(diffText)
        #expect(files.count == 6)
        let hosting = host(DiffView(files: files, graph: graphCiting("src/input.rs", count: 5)))
        #expect(hosting.fittingSize.width >= 0)
    }

    @Test func aFocusedReferenceRenders() {
        let files = UnifiedDiff.parse(diffText)
        let head = CodeRef(path: "src/input.rs", startLine: 2, endLine: 3)
        _ = host(DiffView(files: files, graph: graphCiting("src/input.rs", count: 1), focus: head))
        let base = CodeRef(path: "src/gone.rs", startLine: 1, endLine: 1, side: .base)
        _ = host(DiffView(files: files, graph: graphCiting("src/gone.rs", count: 1), focus: base))
    }

    @Test func anEmptyDiffShowsThePlaceholder() {
        _ = host(DiffView(files: [], graph: ContourSampleData.publishTriggeredReindex))
    }

    @Test func everyStatusGlyphAndCitationBadgeBuilds() {
        for status in [DiffFileStatus.modified, .added, .deleted, .renamed, .copied] {
            let file = DiffFile(id: 0, oldPath: "a", newPath: "b", status: status)
            _ = host(DiffView(files: [file], graph: ContourSampleData.publishTriggeredReindex))
        }
    }
}
