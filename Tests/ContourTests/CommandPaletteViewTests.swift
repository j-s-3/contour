import Testing
import Foundation
import AppKit
@testable import Contour

/// CLAUDE.md's guidance for this file: extract command filtering/matching/ranking logic
/// into a plain type beside the view and test it directly with fixed input lists and
/// queries. `allCommands`/`filtered` are pulled out as static functions on
/// `CommandPaletteView` for exactly that. `PaletteCommand.action` is a closure (not
/// `Sendable`), and `CommandPaletteView` is a `View` (implicitly `@MainActor`), so every
/// test that touches either function runs on the main actor.
///
/// Beyond listing the commands, most of this file's remaining coverage gap is in the
/// `action` closures themselves — each command is a line of `PRGraph`/`GraphStore` wiring
/// that only runs once `action()` is actually invoked. `.serialized`: invoking
/// `copyReviewSummary`'s action drives the real `NSPasteboard.general`, a process-wide
/// resource — same caution as `PRSessionCommandsTests`. `openOnGitHub`'s action is never
/// invoked here for the same reason `PRSessionCommandsTests` doesn't: it would launch a
/// real browser via `NSWorkspace.shared.open` from CI. Likewise `"Re-analyze"` and `"Stop
/// analysis"`'s actions call `GraphStore.load`/need a live `AnalysisPipeline`, which no
/// test in this repository drives (it spawns a real harness process) — those two closure
/// bodies, `CommandPaletteView.body`, `runFirst()`, and the `onAppear`/`onExitCommand`
/// modifiers are the irreducible-SwiftUI/side-effecting remainder this file can't reach.
@Suite(.serialized)
struct CommandPaletteViewTests {

    private static func command(_ title: String) -> PaletteCommand {
        PaletteCommand(title: title, subtitle: nil, symbol: "circle", action: {})
    }

    // MARK: - filtered

    @MainActor
    @Test func filteredReturnsEverythingForAnEmptyQuery() {
        let commands = [Self.command("Go to Overview"), Self.command("Go to Decisions")]
        #expect(CommandPaletteView.filtered(commands, query: "").map(\.title) == ["Go to Overview", "Go to Decisions"])
    }

    @MainActor
    @Test func filteredMatchesACaseInsensitiveSubstringOfTheTitle() {
        let commands = [Self.command("Go to Overview"), Self.command("Go to Decisions")]
        #expect(CommandPaletteView.filtered(commands, query: "deci").map(\.title) == ["Go to Decisions"])
    }

    @MainActor
    @Test func filteredReturnsEmptyWhenNothingMatches() {
        let commands = [Self.command("Go to Overview")]
        #expect(CommandPaletteView.filtered(commands, query: "nonsense").isEmpty)
    }

    // MARK: - allCommands

    @MainActor
    @Test func allCommandsAlwaysIncludesTheCoreNavigationCommands() {
        let titles = CommandPaletteView.allCommands(store: GraphStore()).map(\.title)
        #expect(titles.contains("Go to Overview"))
        #expect(titles.contains("Go to Architecture"))
        #expect(titles.contains("Go to Decisions"))
        #expect(titles.contains("Go to Flows"))
        #expect(titles.contains("Go to Raw diff"))
        #expect(titles.contains("Open a different PR…"))
        #expect(titles.contains("Re-analyze (ignore cache)"))
    }

    /// The Overview lens (the default) isn't a diagram screen, so there's no "Show:" switch
    /// to offer.
    @Test @MainActor func allCommandsOffersNoDiagramSwitchOffADiagramScreen() {
        let titles = CommandPaletteView.allCommands(store: GraphStore()).map(\.title)
        #expect(!titles.contains { $0.hasPrefix("Show: ") })
    }

    /// On a diagram screen, the switch offers the two modes that aren't already showing —
    /// `.delta` is `GraphStore`'s default — inserted first, ahead of the fixed navigation list.
    @Test @MainActor func allCommandsOffersTheOtherDiagramModesFirstOnADiagramScreen() {
        let store = GraphStore()
        store.navigate(to: .architecture)
        let commands = CommandPaletteView.allCommands(store: store)
        #expect(Set(commands.prefix(2).map(\.title)) == ["Show: Before this PR", "Show: After this PR"])
        #expect(!(commands.map(\.title).contains("Show: What changed")))
    }

    @Test @MainActor func allCommandsHasNoGraphOnlyCommandsWithoutAGraphLoaded() {
        let titles = CommandPaletteView.allCommands(store: GraphStore()).map(\.title)
        #expect(!titles.contains("Copy review summary"))
        #expect(!titles.contains("Open on GitHub"))
    }

    /// Once a graph is loaded, every decision, architecture part, and flow gets its own
    /// jump-to command, alongside the graph-only utility commands.
    @Test @MainActor func allCommandsListsEveryDecisionPartAndFlowOnceAGraphIsLoaded() {
        let store = GraphStore()
        let graph = ContourSampleData.publishTriggeredReindex
        store.handle(.graph(graph))
        let titles = CommandPaletteView.allCommands(store: store).map(\.title)

        #expect(titles.contains("Copy review summary"))
        #expect(titles.contains("Open on GitHub"))
        for d in graph.decisions {
            #expect(titles.contains(graph.brief(for: d).question))
        }
        for c in graph.architectureParts {
            #expect(titles.contains(c.title))
        }
        for f in graph.flows {
            #expect(titles.contains(graph.scenarioTitle(for: f)))
        }
    }

    // MARK: - Command actions

    private static func action(_ title: String, in commands: [PaletteCommand]) -> (() -> Void)? {
        commands.first { $0.title == title }?.action
    }

    /// Each "Go to …" command's action is the closure that actually calls
    /// `store.navigate(to:)`; without invoking it, that line never runs.
    @Test @MainActor func goToCommandsNavigateToTheirLens() {
        let store = GraphStore()
        let commands = CommandPaletteView.allCommands(store: store)

        Self.action("Go to Architecture", in: commands)?()
        #expect(store.current == .architecture)
        Self.action("Go to Decisions", in: commands)?()
        #expect(store.current == .decisions)
        Self.action("Go to Flows", in: commands)?()
        #expect(store.current == .flows)
        Self.action("Go to Raw diff", in: commands)?()
        #expect(store.current == .diff)
        Self.action("Go to Overview", in: commands)?()
        #expect(store.current == .summary)
    }

    /// "Open a different PR…" is the palette's way to `GraphStore.close()`; drives it
    /// through a synthetic `.fatal` event (per `GraphStore.handle`'s doc comment, the seam
    /// for driving state transitions without a real pipeline) rather than `load()`, which
    /// no test in this repository invokes since it can spawn a real harness process.
    @Test @MainActor func openADifferentPRClosesTheSession() {
        let store = GraphStore()
        store.handle(.fatal("network unreachable"))
        #expect(store.phase == .failed("network unreachable"))

        Self.action("Open a different PR…", in: CommandPaletteView.allCommands(store: store))?()

        #expect(store.phase == .idle)
    }

    /// On a diagram screen, invoking a "Show: …" command's action is what actually flips
    /// `store.diagramMode` — the switch itself, not just its offered titles.
    @Test @MainActor func showDiagramModeCommandSwitchesTheStoresDiagramMode() {
        let store = GraphStore()
        store.navigate(to: .architecture)
        #expect(store.diagramMode == .delta)

        Self.action("Show: Before this PR", in: CommandPaletteView.allCommands(store: store))?()

        #expect(store.diagramMode == .before)
    }

    /// "Copy review summary" puts `PRGraph.reviewSummaryMarkdown` on the real pasteboard —
    /// safe to drive directly, same as `PRSessionCommandsTests.copyLinkPutsThePullRequestURLOnThePasteboard`.
    @Test @MainActor func copyReviewSummaryCommandPutsTheMarkdownOnThePasteboard() {
        let store = GraphStore()
        let graph = ContourSampleData.publishTriggeredReindex
        store.handle(.graph(graph))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("unrelated", forType: .string)

        Self.action("Copy review summary", in: CommandPaletteView.allCommands(store: store))?()

        #expect(pasteboard.string(forType: .string) == graph.reviewSummaryMarkdown)
    }

    /// Each decision/part/flow command's action navigates to that element's detail —
    /// pins that the per-element commands built in the `for` loops are wired to the right
    /// id, not just present with the right title.
    @Test @MainActor func decisionPartAndFlowCommandsNavigateToTheirDetail() {
        let store = GraphStore()
        let graph = ContourSampleData.publishTriggeredReindex
        store.handle(.graph(graph))
        let commands = CommandPaletteView.allCommands(store: store)

        guard let decision = graph.decisions.first else {
            Issue.record("fixture has no decisions to exercise")
            return
        }
        Self.action(graph.brief(for: decision).question, in: commands)?()
        #expect(store.current == .decisionDetail(decision.id))

        guard let part = graph.architectureParts.first else {
            Issue.record("fixture has no architecture parts to exercise")
            return
        }
        Self.action(part.title, in: commands)?()
        #expect(store.current == .componentDetail(part.id))

        guard let flow = graph.flows.first else {
            Issue.record("fixture has no flows to exercise")
            return
        }
        Self.action(graph.scenarioTitle(for: flow), in: commands)?()
        #expect(store.current == .flowDetail(flow.id))
    }
}
