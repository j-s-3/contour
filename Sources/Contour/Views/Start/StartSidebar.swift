import SwiftUI

struct StartSidebar: View {
    let model: StartScreenModel
    var markNamespace: Namespace.ID

    static let markHeight: CGFloat = 24

    var body: some View {
        List(selection: model.selectionBinding) {
            ForEach(model.sources, id: \.self) { source in
                StartSourceRow(source: source, count: model.count(for: source))
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
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
