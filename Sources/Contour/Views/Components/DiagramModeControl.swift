import SwiftUI

/// "Show: Before this PR | After this PR | What changed", and what's on screen now. Sits
/// directly above the drawing it filters, not across the header from it, so the reviewer
/// reads it as part of the diagram — and the sentence beside it says the drawing is only
/// one of three views (issue #30). Flows and Architecture share it.
struct DiagramModeControl: View {
    @Binding var mode: DiagramMode
    /// What's drawn, for the "Showing the … before this PR" sentence.
    let subject: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Show:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Show", selection: $mode) {
                ForEach(DiagramMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Before this PR (B), after it (A), or only what it changed (D)")
            Text(mode.showing(subject))
                .font(.callout.weight(.medium))
                .foregroundStyle(mode == .delta ? AnyShapeStyle(.blue) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .padding(.leading, 4)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: mode)
        }
    }
}

extension View {
    /// B / A / D switch a diagram's mode while its screen has keyboard focus. Typing
    /// elsewhere (the chat, a search field) never reaches here, and modified keys aren't ours.
    func diagramModeKeys(_ mode: Binding<DiagramMode>) -> some View {
        onKeyPress(phases: .down) { press in
            DiagramModeKeyHandling.handle(characters: press.characters, modifiers: press.modifiers, mode: mode)
        }
    }
}

/// Pulled out of `diagramModeKeys` (taking the raw key info explicitly rather than a live
/// `KeyPress`) so the switch's key handling is directly testable.
enum DiagramModeKeyHandling {
    static func handle(characters: String, modifiers: EventModifiers, mode: Binding<DiagramMode>) -> KeyPress.Result {
        guard modifiers.isDisjoint(with: [.command, .control, .option]),
              let new = DiagramMode(key: characters) else { return .ignored }
        mode.wrappedValue = new
        return .handled
    }
}
