import Testing
@testable import Contour

struct JiraADFTests {
    @Test func flattenADFJoinsTheTextInASingleParagraph() {
        let doc: [String: Any] = [
            "type": "doc",
            "content": [["type": "paragraph", "content": [["type": "text", "text": "Hello world"]]]],
        ]
        #expect(JiraTracker.flattenADF(doc) == "Hello world")
    }

    @Test func flattenADFSeparatesParagraphsWithNewlines() {
        let doc: [String: Any] = [
            "type": "doc",
            "content": [
                ["type": "paragraph", "content": [["type": "text", "text": "First paragraph"]]],
                ["type": "paragraph", "content": [["type": "text", "text": "Second paragraph"]]],
            ],
        ]
        #expect(JiraTracker.flattenADF(doc) == "First paragraph\nSecond paragraph")
    }

    @Test func flattenADFTreatsHeadingsLikeParagraphs() {
        let doc: [String: Any] = [
            "type": "doc",
            "content": [
                ["type": "heading", "content": [["type": "text", "text": "Title"]]],
                ["type": "paragraph", "content": [["type": "text", "text": "Body"]]],
            ],
        ]
        #expect(JiraTracker.flattenADF(doc) == "Title\nBody")
    }

    @Test func flattenADFHardBreakStartsANewLine() {
        let paragraph: [String: Any] = [
            "type": "paragraph",
            "content": [
                ["type": "text", "text": "Line one"],
                ["type": "hardBreak"],
                ["type": "text", "text": "Line two"],
            ],
        ]
        #expect(JiraTracker.flattenADF(paragraph) == "Line one\nLine two")
    }

    @Test func flattenADFListItemGetsALeadingDash() {
        let listItem: [String: Any] = ["type": "listItem", "content": [["type": "text", "text": "Item text"]]]
        #expect(JiraTracker.flattenADF(listItem) == "- Item text")
    }

    @Test func flattenADFOfEmptyContentIsAnEmptyString() {
        #expect(JiraTracker.flattenADF(["type": "doc", "content": []]) == "")
        #expect(JiraTracker.flattenADF(["type": "paragraph", "content": []]) == "")
    }

    @Test func flattenADFRecursesThroughUnknownContainerTypes() {
        let doc: [String: Any] = [
            "type": "bulletList",
            "content": [["type": "paragraph", "content": [["type": "text", "text": "Nested"]]]],
        ]
        #expect(JiraTracker.flattenADF(doc) == "Nested")
    }
}
