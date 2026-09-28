import Testing
@testable import Contour

/// `WelcomeWizardLogic` is the step-validation and precedence-derivation logic CLAUDE.md
/// calls out for this file, pulled out of `WelcomeWizard`'s body so it's directly testable
/// against simulated `EnvironmentProbe`/`Preferences` results. The rest — the three panes,
/// the footer's step navigation, the async tool probe (`refresh()`) — is view rendering
/// and `EnvironmentProbe` I/O with no UI-testing infrastructure in this suite.
struct WelcomeWizardTests {

    // MARK: - needsHarnessChoice

    @Test func needsHarnessChoiceIsFalseWithZeroOrOneInstalled() {
        #expect(!WelcomeWizardLogic.needsHarnessChoice(installedHarnesses: []))
        #expect(!WelcomeWizardLogic.needsHarnessChoice(installedHarnesses: [.pi]))
    }

    @Test func needsHarnessChoiceIsTrueWithMoreThanOneInstalled() {
        #expect(WelcomeWizardLogic.needsHarnessChoice(installedHarnesses: [.pi, .claude]))
    }

    // MARK: - blocker

    private func status(_ tool: ExternalTool, installed: Bool) -> ToolStatus {
        ToolStatus(tool: tool, path: installed ? "/usr/bin/\(tool.rawValue)" : nil, version: nil, authenticated: nil, detail: "")
    }

    @Test func blockerNamesGitWhenGitIsMissing() {
        let statuses: [ExternalTool: ToolStatus] = [.git: status(.git, installed: false)]
        let blocker = WelcomeWizardLogic.blocker(statuses: statuses, installedHarnesses: [.pi], resolvedHarness: .pi)
        #expect(blocker == "git is required — Contour checks the PR out locally so analysis reads real code.")
    }

    @Test func blockerNamesNoHarnessFoundWhenNoneAreInstalled() {
        let statuses: [ExternalTool: ToolStatus] = [.git: status(.git, installed: true)]
        let blocker = WelcomeWizardLogic.blocker(statuses: statuses, installedHarnesses: [], resolvedHarness: nil)
        #expect(blocker == "No AI harness found. Install pi or Claude Code, then re-check.")
    }

    @Test func blockerAsksToPickAHarnessWhenSeveralAreInstalledButNoneChosen() {
        let statuses: [ExternalTool: ToolStatus] = [.git: status(.git, installed: true)]
        let blocker = WelcomeWizardLogic.blocker(statuses: statuses, installedHarnesses: [.pi, .claude], resolvedHarness: nil)
        #expect(blocker == "Pick a harness to continue.")
    }

    @Test func blockerIsNilOnceGitAndAResolvedHarnessAreBothPresent() {
        let statuses: [ExternalTool: ToolStatus] = [.git: status(.git, installed: true)]
        #expect(WelcomeWizardLogic.blocker(statuses: statuses, installedHarnesses: [.pi], resolvedHarness: .pi) == nil)
    }

    @Test func blockerIsNilBeforeTheProbeHasReportedAnythingForGit() {
        // No entry for .git yet (probe still running): `statuses[.git]?.isInstalled` reads
        // nil, not false, so this isn't treated as "git missing".
        #expect(WelcomeWizardLogic.blocker(statuses: [:], installedHarnesses: [.pi], resolvedHarness: .pi) == nil)
    }

    // MARK: - readySummary

    @Test func readySummaryNamesNoHarnessWhenNoneIsResolved() {
        let summary = WelcomeWizardLogic.readySummary(resolvedHarness: nil, ghUsable: false, resolvedTracker: .github)
        #expect(summary.contains("Analyzing with no harness"))
    }

    @Test func readySummaryNamesTheResolvedHarness() {
        let summary = WelcomeWizardLogic.readySummary(resolvedHarness: .claude, ghUsable: false, resolvedTracker: .github)
        #expect(summary.contains("Analyzing with Claude Code"))
    }

    @Test func readySummaryPrefersGhWhenUsable() {
        let summary = WelcomeWizardLogic.readySummary(resolvedHarness: .pi, ghUsable: true, resolvedTracker: .github)
        #expect(summary.contains("gh (public and private PRs)"))
    }

    @Test func readySummaryFallsBackToTheAnonymousAPIWhenGhIsNotUsable() {
        let summary = WelcomeWizardLogic.readySummary(resolvedHarness: .pi, ghUsable: false, resolvedTracker: .github)
        #expect(summary.contains("anonymous API (public PRs)"))
    }

    @Test func readySummaryNamesTheResolvedTracker() {
        let summary = WelcomeWizardLogic.readySummary(resolvedHarness: .pi, ghUsable: true, resolvedTracker: .jira)
        #expect(summary.hasSuffix("looking up issues in \(TrackerID.jira.displayName)."))
    }

    // MARK: - canFinish

    @Test func canFinishIsTrueWithAnEmptyURL() {
        #expect(WelcomeWizardLogic.canFinish(urlText: ""))
    }

    @Test func canFinishIsTrueWithARecognizedPullRequestURL() {
        #expect(WelcomeWizardLogic.canFinish(urlText: "https://github.com/acme/shop/pull/42"))
    }

    @Test func canFinishIsFalseWithUnrecognizedText() {
        #expect(!WelcomeWizardLogic.canFinish(urlText: "not a url"))
    }
}
