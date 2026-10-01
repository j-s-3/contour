import AppKit
import Foundation

struct StartMenuItem: Identifiable {
    var title: String
    var isDestructive = false
    var action: () -> Void

    var id: String { title }
}

@MainActor
struct StartScreenActions {
    typealias Spawn = (@escaping @MainActor () async -> Void) -> Void

    let model: StartScreenModel
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var spawn: Spawn = { operation in Task { await operation() } }

    func watch(_ input: String) {
        spawn { await model.watch(input) }
    }

    func refresh(_ id: String) -> () -> Void {
        { spawn { await model.refresh(id) } }
    }

    func refreshStale() {
        spawn { await model.refreshWatched(force: false) }
    }

    func toggleWatch(_ id: String) -> () -> Void {
        { spawn { await model.toggleWatch(id) } }
    }

    func menu(for repository: WatchedRepository) -> [StartMenuItem] {
        [
            StartMenuItem(title: "Refresh", action: refresh(repository.id)),
            StartMenuItem(
                title: "Open Repository on GitHub",
                action: { if let url = repository.url { openURL(url) } }),
            StartMenuItem(
                title: "Stop Watching \(repository.id)", isDestructive: true,
                action: { model.stopWatching(repository.id) }),
        ]
    }
}
