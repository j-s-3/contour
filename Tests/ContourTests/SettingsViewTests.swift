import Testing
import SwiftUI
@testable import Contour

struct SettingsViewTests {
    @Test func harnessToolMapsEachHarnessIdToItsExternalTool() {
        #expect(SettingsViewLogic.harnessTool(.pi) == .pi)
        #expect(SettingsViewLogic.harnessTool(.claude) == .claude)
    }

    @Test func labelIsJustTheNameWithNoStatusYet() {
        #expect(SettingsViewLogic.label(for: .pi, statuses: [:]) == "pi")
    }

    @Test func labelNamesNotInstalledWhenTheProbeFoundNoPath() {
        let status = ToolStatus(tool: .claude, path: nil, version: nil, authenticated: nil, detail: "not found")
        #expect(SettingsViewLogic.label(for: .claude, statuses: [.claude: status]) == "Claude Code — not installed")
    }

    @Test func labelAppendsTheDetectedVersionWhenPresent() {
        let status = ToolStatus(tool: .pi, path: "/usr/local/bin/pi", version: "1.2.3", authenticated: true, detail: "ok")
        #expect(SettingsViewLogic.label(for: .pi, statuses: [.pi: status]) == "pi — 1.2.3")
    }

    @Test func labelFallsBackToTheNameWhenInstalledWithNoVersion() {
        let status = ToolStatus(tool: .pi, path: "/usr/local/bin/pi", version: nil, authenticated: true, detail: "ok")
        #expect(SettingsViewLogic.label(for: .pi, statuses: [.pi: status]) == "pi")
    }

    @Test func githubFooterNamesEveryAccessMode() {
        #expect(SettingsViewLogic.githubFooter(for: .auto).contains("gh when it's installed"))
        #expect(SettingsViewLogic.githubFooter(for: .gh).contains("Always uses gh"))
        #expect(SettingsViewLogic.githubFooter(for: .anonymous).contains("anonymous API"))
    }

    @Test func jiraLabelIsPlainWhenAvailable() {
        #expect(SettingsViewLogic.jiraLabel(jiraAvailable: true) == TrackerID.jira.displayName)
    }

    @Test func jiraLabelNamesTheMissingCLIWhenUnavailable() {
        #expect(SettingsViewLogic.jiraLabel(jiraAvailable: false) == "Jira — acli not found")
    }

    @Test func overrideNoticeTextNamesTheSpecificVariable() {
        #expect(SettingsViewLogic.overrideNoticeText(for: "CONTOUR_HARNESS") == "Overridden by CONTOUR_HARNESS in the environment.")
        #expect(SettingsViewLogic.overrideNoticeText(for: "CONTOUR_TRACKER") == "Overridden by CONTOUR_TRACKER in the environment.")
    }

    @Test func symbolAndTintAreNeutralWithNoStatusYet() {
        #expect(SettingsViewLogic.symbol(for: nil, tool: .git) == "circle.dotted")
        #expect(SettingsViewLogic.tint(for: nil, tool: .git) == .secondary)
    }

    @Test func symbolAndTintAreGreenWhenUsable() {
        let status = ToolStatus(tool: .git, path: "/usr/bin/git", version: "2.0", authenticated: nil, detail: "ok")
        #expect(SettingsViewLogic.symbol(for: status, tool: .git) == "checkmark.circle.fill")
        #expect(SettingsViewLogic.tint(for: status, tool: .git) == .green)
    }

    @Test func symbolAndTintAreOrangeWhenInstalledButNotUsable() {
        let status = ToolStatus(tool: .gh, path: "/usr/bin/gh", version: "2.0", authenticated: false, detail: "not signed in")
        #expect(SettingsViewLogic.symbol(for: status, tool: .gh) == "exclamationmark.triangle.fill")
        #expect(SettingsViewLogic.tint(for: status, tool: .gh) == .orange)
    }

    @Test func absentRequiredToolIsRed() {
        let status = ToolStatus(tool: .git, path: nil, version: nil, authenticated: nil, detail: "not found")
        #expect(SettingsViewLogic.symbol(for: status, tool: .git) == "xmark.circle.fill")
        #expect(SettingsViewLogic.tint(for: status, tool: .git) == .red)
    }

    @Test func absentOptionalToolIsGreyNotRed() {
        let status = ToolStatus(tool: .acli, path: nil, version: nil, authenticated: nil, detail: "not found")
        #expect(SettingsViewLogic.symbol(for: status, tool: .acli) == "minus.circle")
        #expect(SettingsViewLogic.tint(for: status, tool: .acli) == .secondary)
    }
}

@MainActor
struct SettingsViewHostingTests {

    private func laidOutSize<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    @Test func everyTabLaysOutToANonEmptySize() {
        let view = SettingsView()
        #expect(laidOutSize(view.harnessTab).height > 0)
        #expect(laidOutSize(view.sourcesTab).height > 0)
        #expect(laidOutSize(view.windowTab).height > 0)
    }

    @Test func theTabViewShellBuilds() {
        #expect(laidOutSize(SettingsView()).width > 0)
    }

    @Test func toolStatusRowBuildsForEveryStatusShape() {
        let usable = ToolStatus(tool: .git, path: "/usr/bin/git", version: "2.0", authenticated: nil, detail: "ok")
        let absent = ToolStatus(tool: .acli, path: nil, version: nil, authenticated: nil, detail: "Not installed")
        #expect(laidOutSize(ToolStatusRow(status: nil, tool: .git)).height > 0)
        #expect(laidOutSize(ToolStatusRow(status: usable, tool: .git)).height > 0)
        #expect(laidOutSize(ToolStatusRow(status: absent, tool: .acli)).height > 0)
    }
}
