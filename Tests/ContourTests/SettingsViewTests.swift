import Testing
import SwiftUI
@testable import Contour

/// `SettingsViewLogic` is the status-derivation and precedence-aware footer logic
/// CLAUDE.md calls out for this file, pulled out of `SettingsView`/`ToolStatusRow`'s
/// bodies so it's directly testable against plain `ToolStatus`/`ExternalTool`/`HarnessID`
/// fixtures. The rest — the tab layout, pickers, override notices, the async probe — is
/// view rendering with no UI-testing infrastructure in this suite.
struct SettingsViewTests {

    // MARK: - harnessTool / label

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

    // MARK: - githubFooter

    @Test func githubFooterNamesEveryAccessMode() {
        #expect(SettingsViewLogic.githubFooter(for: .auto).contains("gh when it's installed"))
        #expect(SettingsViewLogic.githubFooter(for: .gh).contains("Always uses gh"))
        #expect(SettingsViewLogic.githubFooter(for: .anonymous).contains("anonymous API"))
    }

    // MARK: - jiraLabel

    @Test func jiraLabelIsPlainWhenAvailable() {
        #expect(SettingsViewLogic.jiraLabel(jiraAvailable: true) == TrackerID.jira.displayName)
    }

    @Test func jiraLabelNamesTheMissingCLIWhenUnavailable() {
        #expect(SettingsViewLogic.jiraLabel(jiraAvailable: false) == "Jira — acli not found")
    }

    // MARK: - symbol / tint

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
