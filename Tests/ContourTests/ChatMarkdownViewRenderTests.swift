import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct ChatMarkdownViewRenderTests {
    private func render(_ view: ChatMarkdownView, width: CGFloat = 400) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: width, height: 600)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    @Test func everyBlockKindRendersAndStacksVertically() {
        let markdown = """
            # Heading
            A paragraph with **bold** and a [link](https://example.com).
            - bullet item
            1. numbered item
            ```
            let x = 1
            ```
            """
        let full = render(ChatMarkdownView(text: markdown))
        let paragraphOnly = render(ChatMarkdownView(text: "A paragraph"))
        #expect(full.height > paragraphOnly.height)
    }

    @Test func eachBlockKindContributesHeight() {
        let empty = render(ChatMarkdownView(text: ""))
        for text in ["# Title", "- item", "1. item", "```\ncode\n```", "plain"] {
            #expect(render(ChatMarkdownView(text: text)).height > empty.height)
        }
    }

    @Test func linkifyRewritesTextBeforeItIsRendered() {
        final class Seen: @unchecked Sendable { var inputs: [String] = [] }
        let seen = Seen()
        let view = ChatMarkdownView(text: "See #12") { input in
            seen.inputs.append(input)
            return input.replacingOccurrences(of: "#12", with: "[#12](https://example.com/12)")
        }
        _ = render(view)
        #expect(seen.inputs.contains("See #12"))
    }

    @Test func attributedTextAppliesLinkifyAndKeepsLinks() {
        let attributed = ChatMarkdownView.attributedText(for: "PR #7") {
            $0.replacingOccurrences(of: "#7", with: "[#7](https://example.com/7)")
        }
        #expect(attributed.runs.contains { $0.link == URL(string: "https://example.com/7") })
    }
}
