import AppKit

final class HeadlessWindow: NSWindow {
    init(size: NSSize, styleMask: NSWindow.StyleMask = [.titled]) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size), styleMask: styleMask, backing: .buffered,
            defer: false)
        Self.hide(self)
        isReleasedWhenClosed = false
    }

    override func beginSheet(
        _ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)?
    ) {
        Self.hide(sheetWindow)
        super.beginSheet(sheetWindow, completionHandler: handler)
        Self.hide(sheetWindow)
    }

    override func beginCriticalSheet(
        _ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)?
    ) {
        Self.hide(sheetWindow)
        super.beginCriticalSheet(sheetWindow, completionHandler: handler)
        Self.hide(sheetWindow)
    }

    private static func hide(_ window: NSWindow) {
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
    }
}
