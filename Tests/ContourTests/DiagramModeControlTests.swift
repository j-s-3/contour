import SwiftUI
import Testing

@testable import Contour

struct DiagramModeControlTests {
    private func binding(_ mode: DiagramMode) -> (Binding<DiagramMode>, () -> DiagramMode) {
        let current = ModeBox(mode)
        return (Binding(get: { current.value }, set: { current.value = $0 }), { current.value })
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

    @Test func ignoresAModifiedKeyEvenWhenItWouldOtherwiseMatch() {
        let (b, read) = binding(.delta)
        _ = DiagramModeKeyHandling.handle(characters: "b", modifiers: [.command], mode: b)
        #expect(read() == .delta)
        _ = DiagramModeKeyHandling.handle(characters: "b", modifiers: [.control], mode: b)
        #expect(read() == .delta)
        _ = DiagramModeKeyHandling.handle(characters: "b", modifiers: [.option], mode: b)
        #expect(read() == .delta)
    }

    @Test func aNonExcludedModifierStillPassesThrough() {
        let (b, read) = binding(.delta)
        _ = DiagramModeKeyHandling.handle(characters: "b", modifiers: [.shift], mode: b)
        #expect(read() == .before)
    }

    @Test func onlyDeltaModeIsAccented() {
        #expect(DiagramModeControl.isAccented(.delta))
        #expect(!DiagramModeControl.isAccented(.before))
        #expect(!DiagramModeControl.isAccented(.after))
    }
}

private final class ModeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: DiagramMode
    init(_ mode: DiagramMode) { stored = mode }
    var value: DiagramMode {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
