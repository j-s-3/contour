import SwiftUI

extension ReviewerState {
    var symbol: String {
        switch self {
        case .unreviewed: return "circle"
        case .accepted: return "checkmark"
        case .questioned: return "questionmark"
        case .discuss: return "bubble.left.and.bubble.right"
        }
    }

    var tint: Color {
        switch self {
        case .unreviewed: return .secondary
        case .accepted: return .green
        case .questioned: return .orange
        case .discuss: return .blue
        }
    }

    var chipLabel: String {
        switch self {
        case .unreviewed: return "Unreviewed"
        case .accepted: return "Reviewed"
        case .questioned: return "Question"
        case .discuss: return "Discussing"
        }
    }
}
