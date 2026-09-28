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

/// Internal rather than private so `PRDropTargetTests` can call `loadPullRequest` directly
/// against a real `NSItemProvider`, per CLAUDE.md's guidance to test this file's
/// drop-payload parsing the same way as `PRLinkTests`.
struct PRDropTarget: ViewModifier {
    let open: (String) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.url, .plainText], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                Self.loadPullRequest(from: provider) { url in
                    if let url { DispatchQueue.main.async { open(url) } }
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
    static func loadPullRequest(from provider: NSItemProvider, completion: @escaping (String?) -> Void) {
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                completion(url.flatMap(PRLink.pullRequestURL(from:)))
            }
        } else if provider.canLoadObject(ofClass: String.self) {
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                completion(text.flatMap(PRLink.extract(from:)))
            }
        } else {
            completion(nil)
        }
    }
}
