import Foundation

enum StartSource: Hashable, Sendable {
    case reviewRequests
    case recents
    case watched(String)

    private static let watchedPrefix = "watched:"

    var storageKey: String {
        switch self {
        case .reviewRequests: return "reviewRequests"
        case .recents: return "recents"
        case .watched(let id): return Self.watchedPrefix + id
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "reviewRequests": self = .reviewRequests
        case "recents": self = .recents
        default:
            guard storageKey.hasPrefix(Self.watchedPrefix) else { return nil }
            let id = String(storageKey.dropFirst(Self.watchedPrefix.count))
            guard !id.isEmpty else { return nil }
            self = .watched(id)
        }
    }
}
