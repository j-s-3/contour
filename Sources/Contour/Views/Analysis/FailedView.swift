import SwiftUI

struct FailedView: View {
    let message: String
    var onRetry: () -> Void
    var onOpenDifferent: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Couldn't open this PR", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: onRetry)
                .keyboardShortcut(.defaultAction)
            Button("Open a different PR", action: onOpenDifferent)
        }
    }
}
