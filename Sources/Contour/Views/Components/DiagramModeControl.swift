import SwiftUI

struct DiagramModeControl: View {
    @Binding var mode: DiagramMode
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
                .foregroundStyle(Self.isAccented(mode) ? AnyShapeStyle(.blue) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .padding(.leading, 4)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: mode)
        }
    }

    nonisolated static func isAccented(_ mode: DiagramMode) -> Bool {
        mode == .delta
    }
}

extension View {
    func diagramModeKeys(_ mode: Binding<DiagramMode>) -> some View {
        onKeyPress(phases: .down) { press in
            DiagramModeKeyHandling.handle(characters: press.characters, modifiers: press.modifiers, mode: mode)
        }
    }
}

enum DiagramModeKeyHandling {
    static func handle(characters: String, modifiers: EventModifiers, mode: Binding<DiagramMode>) -> KeyPress.Result {
        guard modifiers.isDisjoint(with: [.command, .control, .option]),
              let new = DiagramMode(key: characters) else { return .ignored }
        mode.wrappedValue = new
        return .handled
    }
}
