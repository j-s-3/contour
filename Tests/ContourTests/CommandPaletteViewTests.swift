import Testing
import Foundation
@testable import Contour

/// CLAUDE.md's guidance for this file: extract command filtering/matching/ranking logic
/// into a plain type beside the view and test it directly with fixed input lists and
/// queries. `allCommands`/`filtered` are pulled out as static functions on
/// `CommandPaletteView` for exactly that. `PaletteCommand.action` is a closure (not
/// `Sendable`), and `CommandPaletteView` is a `View` (implicitly `@MainActor`), so every
/// test that touches either function runs on the main actor.
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
}
