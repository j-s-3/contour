import Foundation

/// Which snapshot a Flows or Architecture drawing shows. One value drives both screens, so
/// asking for "before this PR" on one is still true on the other.
///
/// "What changed" is the default: enough of the existing system to follow the story, with
/// only what this PR changed drawing the eye. Before and After are plain snapshots. The
/// words are the reviewer's, not a diff tool's — "Delta" meant nothing to a first-time
/// reader (issue #30).
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

    /// The single key that switches to this mode on a diagram screen.
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

    /// What the header says is on screen, so the reviewer knows there's something else to
    /// show. `subject` is what's drawn: "flow", "architecture".
    func showing(_ subject: String) -> String {
        switch self {
        case .before: return "Showing the \(subject) before this PR"
        case .after: return "Showing the \(subject) after this PR"
        case .delta: return "Showing what this PR changed"
        }
    }
}
