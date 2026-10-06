import Testing

@testable import Contour

struct PRStackTests {
    static func layer(_ number: Int, head: String, base: String) -> StackLayer {
        StackLayer(
            url: "https://github.com/acme/api/pull/\(number)", number: number, title: "Layer \(number)",
            author: "mwright", isDraft: false, headRefName: head, baseRefName: base,
            headSha: "h\(number)", baseSha: "b\(number)", size: nil)
    }

    static let three = PRStack(
        layers: [layer(1, head: "a", base: "main"), layer(2, head: "b", base: "a"), layer(3, head: "c", base: "b")],
        currentIndex: 1)

    @Test func positionCountsFromOneAndNamesTheStackSize() {
        #expect(Self.three.position == "Part 2 of 3")
        #expect(Self.three.current.number == 2)
    }

    @Test func layerOffsetWalksUpAndDownAndStopsAtTheEnds() {
        #expect(Self.three.layer(offset: 1)?.number == 3)
        #expect(Self.three.layer(offset: -1)?.number == 1)
        #expect(Self.three.layer(offset: 2) == nil)
        #expect(Self.three.layer(offset: -2) == nil)
    }

    @Test func validBranchNamesPass() {
        for name in ["main", "feature/x-1", "CLM-53522-01-data-layer", "babakks/refresh-token-a-foundation", "v1.2"] {
            #expect(PRStack.isValidBranchName(name), "\(name)")
        }
    }

    @Test func invalidBranchNamesAreRejected() {
        for name in [
            "", "-flag", "a..b", "a@{b", "a.lock", "a/", "a.", "a//b", "a b", "a~b", "a^b", "a:b", "a?b", "a*b",
            "a[b", "a\\b", "a\u{7f}b", "a\nb", "/a", ".a", "a/.b",
        ] {
            #expect(!PRStack.isValidBranchName(name), "\(name)")
        }
    }

    @Test func layersAreIdentifiedByPullRequestNumber() {
        #expect(Self.layer(7, head: "x", base: "main").id == 7)
    }

    @Test func theChainIsCappedAtThirtyTwoLayers() {
        #expect(PRStack.maximumLayers == 32)
    }
}
