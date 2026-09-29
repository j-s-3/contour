import Foundation

enum DiagramMode: String, CaseIterable, Identifiable, Sendable {
    case before, after, delta
    var id: String { rawValue }

    var label: String {
        switch self {
        case .before: return "Before this PR"
        case .after: return "After this PR"
        case .delta: return "What changed"
        }
    }

    var key: String {
        switch self {
        case .before: return "b"
        case .after: return "a"
        case .delta: return "d"
        }
    }

    init?(key: String) {
        guard let mode = Self.allCases.first(where: { $0.key == key.lowercased() }) else { return nil }
        self = mode
    }

    func showing(_ subject: String) -> String {
        switch self {
        case .before: return "Showing the \(subject) before this PR"
        case .after: return "Showing the \(subject) after this PR"
        case .delta: return "Showing what this PR changed"
        }
    }
}
