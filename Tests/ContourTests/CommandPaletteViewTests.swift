import AppKit
import Foundation
import Testing

@testable import Contour

@Suite(.serialized)
struct CommandPaletteViewTests {
    private static func command(_ title: String) -> PaletteCommand {
        PaletteCommand(title: title, subtitle: nil, symbol: "circle", action: {})
    }

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

    @Test @MainActor func allCommandsOffersNoDiagramSwitchOffADiagramScreen() {
        let titles = CommandPaletteView.allCommands(store: GraphStore()).map(\.title)
        #expect(!titles.contains { $0.hasPrefix("Show: ") })
    }

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

    private static func action(_ title: String, in commands: [PaletteCommand]) -> (() -> Void)? {
        commands.first { $0.title == title }?.action
    }

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

    @Test @MainActor func openADifferentPRClosesTheSession() {
        let store = GraphStore()
        store.handle(.fatal("network unreachable"))
        #expect(store.phase == .failed("network unreachable"))

        Self.action("Open a different PR…", in: CommandPaletteView.allCommands(store: store))?()

        #expect(store.phase == .idle)
    }

    @Test @MainActor func showDiagramModeCommandSwitchesTheStoresDiagramMode() {
        let store = GraphStore()
        store.navigate(to: .architecture)
        #expect(store.diagramMode == .delta)

        Self.action("Show: Before this PR", in: CommandPaletteView.allCommands(store: store))?()

        #expect(store.diagramMode == .before)
    }

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
