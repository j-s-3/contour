import Testing
import SwiftUI
@testable import Contour

/// `DiagramModeControl.swift`'s own logic beyond `DiagramMode` itself (already covered by
/// `DiagramModeTests`) is the B/A/D keyboard switch, pulled out to `DiagramModeKeyHandling`
/// so it's testable without a live `KeyPress` event, and the mode label's accent-color
/// decision, pulled out to `isAccented` so it's testable without a view instance. The rest
/// of the file — the `HStack`/`Picker`/`Text` body itself — is view rendering with no
/// UI-testing infrastructure in this suite (see issue #113, and the same acceptance in
/// `WelcomeWizardTests.swift` / `BadgesTests.swift`).
struct DiagramModeControlTests {

    private func binding(_ mode: DiagramMode) -> (Binding<DiagramMode>, () -> DiagramMode) {
        var current = mode
        return (Binding(get: { current }, set: { current = $0 }), { current })
    }

    @Test func handlesEachModesOwnKeyCaseInsensitively() {
        let (b, read) = binding(.delta)
        _ = DiagramModeKeyHandling.handle(characters: "B", modifiers: [], mode: b)
        #expect(read() == .before)
        _ = DiagramModeKeyHandling.handle(characters: "a", modifiers: [], mode: b)
        #expect(read() == .after)
        _ = DiagramModeKeyHandling.handle(characters: "D", modifiers: [], mode: b)
        #expect(read() == .delta)
    }

    @Test func ignoresAKeyThatIsntAnyModesShortcut() {
        let (b, read) = binding(.delta)
        _ = DiagramModeKeyHandling.handle(characters: "x", modifiers: [], mode: b)
        #expect(read() == .delta, "unrelated key doesn't change the mode")
    }

    /// A modified key (⌘B, say) is a different command entirely and isn't ours to intercept.
    @Test func ignoresAModifiedKeyEvenWhenItWouldOtherwiseMatch() {
        let (b, read) = binding(.delta)
        _ = DiagramModeKeyHandling.handle(characters: "b", modifiers: [.command], mode: b)
        #expect(read() == .delta)
        _ = DiagramModeKeyHandling.handle(characters: "b", modifiers: [.control], mode: b)
        #expect(read() == .delta)
        _ = DiagramModeKeyHandling.handle(characters: "b", modifiers: [.option], mode: b)
        #expect(read() == .delta)
    }

    /// Only command/control/option are excluded — an incidental modifier like shift still
    /// passes through.
    @Test func aNonExcludedModifierStillPassesThrough() {
        let (b, read) = binding(.delta)
        _ = DiagramModeKeyHandling.handle(characters: "b", modifiers: [.shift], mode: b)
        #expect(read() == .before)
    }

    /// "What changed" is the only mode that isn't a plain before/after snapshot, so it's
    /// the only one whose label gets the accent color — pins that against the other two.
    @Test func onlyDeltaModeIsAccented() {
        #expect(DiagramModeControl.isAccented(.delta))
        #expect(!DiagramModeControl.isAccented(.before))
        #expect(!DiagramModeControl.isAccented(.after))
    }
}
