import SwiftUI

struct StartSidebar: View {
    let model: StartScreenModel
    let actions: StartScreenActions
    var markNamespace: Namespace.ID
    @State private var choosingRepository = false

    static let markHeight: CGFloat = 24

    var body: some View {
        List(selection: model.selectionBinding) {
            ForEach(model.sources.filter { !Self.isWatched($0) }, id: \.self) { source in
                StartSourceRow(source: source, count: model.count(for: source))
            }
            Section("Watched") {
                ForEach(model.watched) { repository in
                    StartSourceRow(
                        source: .watched(repository.id), count: model.count(for: .watched(repository.id))
                    )
                    .tag(StartSource.watched(repository.id))
                    .contextMenu { StartMenu(items: actions.menu(for: repository)) }
                }
                Button {
                    choosingRepository = true
                } label: {
                    Label("Watch a repository…", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .selectionDisabled()
                .popover(isPresented: $choosingRepository, arrowEdge: .trailing) {
                    WatchRepositoryPopover(suggestions: model.suggestions) { input in
                        choosingRepository = false
                        actions.watch(input)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
    }

    nonisolated static func isWatched(_ source: StartSource) -> Bool {
        if case .watched = source { return true }
        return false
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !model.showsWelcome {
                ContourMarkView()
                    .matchesContourMark(in: markNamespace)
                    .frame(height: Self.markHeight)
            }
            Text("Contour")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct StartSourceRow: View {
    let source: StartSource
    let count: String?

    var body: some View {
        Label {
            Text(verbatim: StartScreenLogic.title(for: source))
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: StartScreenLogic.symbol(for: source))
        }
        .badge(count.map { Text(verbatim: $0) })
    }
}

struct StartMenu: View {
    let items: [StartMenuItem]

    var body: some View {
        ForEach(items) { item in
            Button(item.title, role: item.isDestructive ? .destructive : nil, action: item.action)
        }
    }
}
