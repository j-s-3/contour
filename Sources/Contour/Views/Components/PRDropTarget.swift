import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Opens a pull request link dropped anywhere on this view — a URL dragged out of a
    /// browser's address bar, or a Slack message or email that contains one. A drop that
    /// carries no PR link is ignored rather than opened as a failed review.
    func opensDroppedPullRequests(_ open: @escaping (String) -> Void) -> some View {
        modifier(PRDropTarget(open: open))
    }
}

private struct PRDropTarget: ViewModifier {
    let open: (String) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.url, .plainText], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                Task {
                    if let url = await Self.loadPullRequest(from: provider) { open(url) }
                }
                return true
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .padding(6)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    /// A browser drag carries a URL; a text drag carries the surrounding words too, so it
    /// is searched rather than taken whole.
    ///
    /// Bridged through a continuation rather than a plain completion handler: `loadObject`'s
    /// own completion handler is `@Sendable`, and a plain `(String?) -> Void` closure isn't,
    /// so handing it straight to `loadObject` is what Swift 6's strict concurrency checking
    /// is (correctly) unhappy about. The continuation only ever captures itself, which is.
    private static func loadPullRequest(from provider: NSItemProvider) async -> String? {
        if provider.canLoadObject(ofClass: URL.self) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url.flatMap(PRLink.pullRequestURL(from:)))
                }
            }
        } else if provider.canLoadObject(ofClass: String.self) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    continuation.resume(returning: text.flatMap(PRLink.extract(from:)))
                }
            }
        }
        return nil
    }
}
