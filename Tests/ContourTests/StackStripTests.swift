import AppKit
import SwiftUI
import Testing

@testable import Contour

struct StackStripTests {
    private let stack = PRStackTests.three

    @Test func positionTextSaysWhereTheLayerSits() {
        #expect(StackStripLogic.positionText(stack) == "Part 2 of 3 in a stack")
    }

    @Test func chipLabelLeadsWithTheOneBasedIndex() {
        #expect(StackStripLogic.chipLabel(index: 0, layer: stack.layers[0]) == "1 · Layer 1")
    }

    @Test func tooltipNamesTitleAuthorAndSizeWhenKnown() {
        var layer = stack.layers[2]
        layer.size = StackLayer.Size(additions: 120, deletions: 7, changedFiles: 9)
        #expect(StackStripLogic.tooltip(layer) == "#3 Layer 3\nmwright · +120 \u{2212}7 · 9 files")
        #expect(StackStripLogic.tooltip(stack.layers[0]) == "#1 Layer 1\nmwright")
    }

    @Test func tooltipUsesSingularForOneFile() {
        var layer = stack.layers[0]
        layer.size = StackLayer.Size(additions: 1, deletions: 0, changedFiles: 1)
        #expect(StackStripLogic.tooltip(layer).hasSuffix("1 file"))
    }

    @Test func statusSymbolMarksCachedLayersOnly() {
        #expect(StackStripLogic.statusSymbol(.cached) == "checkmark.circle.fill")
        #expect(StackStripLogic.statusSymbol(nil) == nil)
    }

    @MainActor
    @Test func theStripRendersWithAndWithoutStatuses() {
        let view = StackStrip(stack: stack, statuses: [1: .cached], openLayer: { _ in })
        let renderer = ImageRenderer(content: view.frame(width: 900, height: 80))
        renderer.scale = 1
        #expect(renderer.nsImage != nil)
        let bare = ImageRenderer(
            content: StackStrip(stack: stack, statuses: [:], openLayer: { _ in }).frame(width: 400, height: 80))
        bare.scale = 1
        #expect(bare.nsImage != nil)
    }

    @MainActor
    @Test func pressingAChipOpensThatLayerButNotTheCurrentOne() {
        final class Recorder {
            var opened: [Int] = []
        }
        let recorder = Recorder()
        let strip = StackStrip(stack: stack, statuses: [:], openLayer: { recorder.opened.append($0.number) })
        let hosting = NSHostingView(rootView: strip)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 80)
        let window = HeadlessWindow(size: hosting.frame.size)
        window.contentView = hosting
        window.orderBack(nil)
        for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            _ = NSApp.perform(
                NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: attribute)
        }
        for _ in 0..<3 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            press(in: hosting)
        }
        window.orderOut(nil)
        #expect(Set(recorder.opened) == [1, 3])
    }

    private func press(in root: Any) {
        guard let object = root as? NSObject else { return }
        let role = object.perform(NSSelectorFromString("accessibilityRole"))?.takeUnretainedValue() as? String
        if role == NSAccessibility.Role.button.rawValue {
            _ = object.perform(NSSelectorFromString("accessibilityPerformPress"))
        }
        let children = object.perform(NSSelectorFromString("accessibilityChildren"))?.takeUnretainedValue()
        for child in children as? [Any] ?? [] { press(in: child) }
    }
}
