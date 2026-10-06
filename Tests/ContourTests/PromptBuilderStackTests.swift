import Testing

@testable import Contour

struct PromptBuilderStackTests {
    private func context() -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/api/pull/3", owner: "acme", repo: "api", number: 3, title: "Layer 3",
            body: "Because reasons", author: "mwright", state: "OPEN", headRefName: "c", baseRefName: "b",
            headSha: "h3", baseSha: "b3", isCrossRepository: false, headCloneURL: "https://github.com/acme/api.git",
            additions: 1, deletions: 0, changedFiles: 2, files: ["a.swift", "b.swift"], commits: [], comments: [],
            reviews: [], diff: "diff")
    }

    private func stack(current: Int = 2) -> PRStack {
        PRStack(
            layers: [
                PRStackTests.layer(1, head: "a", base: "main"),
                PRStackTests.layer(2, head: "b", base: "a"),
                PRStackTests.layer(3, head: "c", base: "b"),
                PRStackTests.layer(4, head: "d", base: "c"),
            ],
            currentIndex: current)
    }

    @Test func contextFileWithoutAStackIsUnchanged() {
        let plain = PromptBuilder.contextFileContents(context())
        #expect(plain == PromptBuilder.contextFileContents(context(), stack: nil))
        #expect(!plain.contains("Stack:"))
    }

    @Test func stackBlockNamesThePositionAndWhichLayersAreInTheCheckout() {
        let block = PromptBuilder.stackBlock(stack())
        #expect(block.hasPrefix("Stack: this pull request is part 3 of 4."))
        #expect(block.contains("Layers 1-2 are already merged into this checkout"))
        #expect(block.contains("Layers 4-4 build on this one and are not in the checkout."))
        #expect(
            block.contains(
                "<UNTRUSTED_PR_CONTENT>\n1. #1 Layer 1\n2. #2 Layer 2\n3. #3 Layer 3   (this PR)\n4. #4 Layer 4\n"
                    + "</UNTRUSTED_PR_CONTENT>\n"))
    }

    @Test func stackBlockAtTheBottomOmitsTheLowerSentence() {
        let block = PromptBuilder.stackBlock(stack(current: 0))
        #expect(!block.contains("already merged into this checkout"))
        #expect(block.contains("Layers 2-4 build on this one"))
    }

    @Test func stackBlockAtTheTopOmitsTheUpperSentence() {
        let block = PromptBuilder.stackBlock(stack(current: 3))
        #expect(block.contains("Layers 1-3 are already merged into this checkout"))
        #expect(!block.contains("build on this one"))
    }

    @Test func contextFilePutsTheStackBlockBetweenBaseAndChangedFiles() throws {
        let text = PromptBuilder.contextFileContents(context(), stack: stack())
        let base = try #require(text.range(of: "Base: "))
        let stackRange = try #require(text.range(of: "Stack: this pull request"))
        let files = try #require(text.range(of: "Changed files ("))
        #expect(base.lowerBound < stackRange.lowerBound)
        #expect(stackRange.lowerBound < files.lowerBound)
    }
}
