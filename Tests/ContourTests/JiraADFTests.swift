import Testing
@testable import Contour

/// `JiraTracker.swift` was at 22.34% coverage. `flattenADF` (Atlassian Document Format →
/// plain text, the actual "response-parsing logic" CLAUDE.md calls out for this file) was
/// `private` and untested; made it internal so it's directly testable against constructed
/// ADF fixtures rather than a real Jira response. `fetchTicket`/`browseURL`/
/// `authenticatedSiteHost` all shell out to `acli` and stay uncovered here, for the same
/// reason this suite doesn't fake `pi`/`claude`/`gh` on `PATH`.
struct JiraADFTests {

    @Test func flattenADFJoinsTheTextInASingleParagraph() {
        let doc: [String: Any] = [
            "type": "doc",
            "content": [["type": "paragraph", "content": [["type": "text", "text": "Hello world"]]]],
        ]
        #expect(JiraTracker.flattenADF(doc) == "Hello world")
    }

    /// Paragraph boundaries become newlines, per the doc comment on `flattenADF`.
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

    /// A hard break inside a paragraph starts a new line without starting a new paragraph.
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

    /// A list item gets a leading dash. Inline marks (bold/italic) aren't in this fixture
    /// at all, matching the doc comment's "inline marks are dropped" — there's nothing in
    /// the flattened output to distinguish marked text from plain text either way.
    @Test func flattenADFListItemGetsALeadingDash() {
        let listItem: [String: Any] = ["type": "listItem", "content": [["type": "text", "text": "Item text"]]]
        #expect(JiraTracker.flattenADF(listItem) == "- Item text")
    }

    @Test func flattenADFOfEmptyContentIsAnEmptyString() {
        #expect(JiraTracker.flattenADF(["type": "doc", "content": []]) == "")
        #expect(JiraTracker.flattenADF(["type": "paragraph", "content": []]) == "")
    }

    /// An unrecognized container type still recurses into its content rather than
    /// dropping it, so a Jira ADF shape this app doesn't explicitly model still flattens.
    @Test func flattenADFRecursesThroughUnknownContainerTypes() {
        let doc: [String: Any] = [
            "type": "bulletList",
            "content": [["type": "paragraph", "content": [["type": "text", "text": "Nested"]]]],
        ]
        #expect(JiraTracker.flattenADF(doc) == "Nested")
    }
}
