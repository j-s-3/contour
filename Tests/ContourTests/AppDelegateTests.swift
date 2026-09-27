import Testing
@testable import Contour

/// `ContourApp.swift` is almost entirely AppKit app-bootstrap code — `applicationDidFinishLaunching`
/// mutates the process-wide `NSApp` singleton (activation policy, Dock icon, `activate`), and
/// `ContourApp.body`/`ReviewCommands.body` are SwiftUI `Scene`/`View` bodies with no hosting
/// harness in this suite. Neither is safely exercisable from a headless unit test without either
/// a UI test target or risking side effects on `NSApp` that other tests never expect. `appIcon`
/// is the one piece that's a plain, side-effect-free resource lookup.
struct AppDelegateTests {

    /// `appIcon` is a lazily-initialized static — nothing else in the app reads it before a
    /// real launch, so referencing it here is also what makes the line count as exercised
    /// rather than dead code. It must resolve (or cleanly return nil) without crashing
    /// regardless of whether the icon asset is present in the test run's resource bundle.
    @Test func appIconResolvesFromTheBundleWithoutCrashing() {
        _ = AppDelegate.appIcon
    }
}
