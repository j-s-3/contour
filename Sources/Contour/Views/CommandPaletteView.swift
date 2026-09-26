import SwiftUI

private struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let symbol: String
    let action: () -> Void
}

/// §6/§12 — "keyboard-first workflows, command palette / Quick Open." Jumps directly into
/// any lens or any named node in the graph (decision, component, flow, entry
/// point) without walking the sidebar.
struct CommandPaletteView: View {
    let store: GraphStore
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Jump to a lens, decision, component, flow…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { runFirst() }
            }
            .padding(14)
            Divider()
            List(filtered) { command in
                Button(action: { command.action(); isPresented = false }) {
                    HStack {
                        Image(systemName: command.symbol).frame(width: 20)
                        VStack(alignment: .leading) {
                            Text(command.title)
                            if let subtitle = command.subtitle {
                                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 260)
        }
        .frame(width: 560)
        .onAppear { focused = true }
        .onExitCommand { isPresented = false }
    }

    private func runFirst() {
        if let first = filtered.first { first.action(); isPresented = false }
    }

    private var allCommands: [PaletteCommand] {
        var commands: [PaletteCommand] = [
            .init(title: "Go to Overview", subtitle: nil, symbol: "house") { store.navigate(to: .summary) },
            .init(title: "Go to Architecture", subtitle: nil, symbol: "square.stack.3d.up") { store.navigate(to: .architecture) },
            .init(title: "Go to Decisions", subtitle: nil, symbol: "checklist") { store.navigate(to: .decisions) },
            .init(title: "Go to Flows", subtitle: nil, symbol: "arrow.triangle.branch") { store.navigate(to: .flows) },
            .init(title: "Go to Raw diff", subtitle: nil, symbol: "doc.text") { store.navigate(to: .diff) },
            .init(title: "Open a different PR…", subtitle: nil, symbol: "arrow.uturn.left") { store.close() },
            .init(title: "Re-analyze (ignore cache)", subtitle: "re-runs all analysis stages for this PR", symbol: "arrow.clockwise") {
                if let url = store.lastPRURL { store.load(prURL: url, forceRefresh: true) }
            }
        ]
        guard let graph = store.graph else { return commands }
        for d in graph.decisions {
            commands.append(.init(title: graph.brief(for: d).question, subtitle: "Decision", symbol: "checklist") {
                store.navigate(to: .decisionDetail(d.id))
            })
        }
        for c in graph.architectureParts {
            let parent = c.parentId.flatMap(graph.component).map { "Part of \($0.title)" }
            commands.append(.init(title: c.title, subtitle: parent ?? "Architecture", symbol: "square.stack.3d.up") {
                store.navigate(to: .componentDetail(c.id))
            })
        }
        for f in graph.flows {
            commands.append(.init(title: graph.scenarioTitle(for: f), subtitle: "Flow", symbol: "arrow.triangle.branch") {
                store.navigate(to: .flowDetail(f.id))
            })
        }
        return commands
    }

    private var filtered: [PaletteCommand] {
        guard !query.isEmpty else { return allCommands }
        return allCommands.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}
