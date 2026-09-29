import SwiftUI
import UniformTypeIdentifiers

extension View {
    func opensDroppedPullRequests(_ open: @escaping (String) -> Void) -> some View {
        modifier(PRDropTarget(open: open))
    }
}

struct PRDropTarget: ViewModifier {
    let open: (String) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.url, .plainText], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
            .overlay {
                if isTargeted { PRDropHighlight() }
            }
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    @discardableResult
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        Task {
            if let url = await Self.loadPullRequest(from: provider) { open(url) }
        }
        return true
    }

    nonisolated(nonsending) static func loadPullRequest(from provider: NSItemProvider) async -> String? {
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

struct PRDropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .padding(6)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}
