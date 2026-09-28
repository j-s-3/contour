import Testing
@testable import Contour

/// `WelcomeWizardLogic` is the step-validation and precedence-derivation logic CLAUDE.md
/// calls out for this file, pulled out of `WelcomeWizard`'s body so it's directly testable
/// against simulated `EnvironmentProbe`/`Preferences` results. The rest — the three panes'
/// content, the footer's step navigation (`step += 1`/`step -= 1`), and the async tool
/// probe (`refresh()`, which is I/O against a real `EnvironmentProbe`) — is SwiftUI `body`
/// rendering with no UI-testing/hosting infrastructure in this suite (same gap documented
/// in `AppDelegateTests`/`CommandPaletteViewTests`), so it stays untested here on purpose
/// rather than being forced through a contrived harness.
struct WelcomeWizardTests {

    // MARK: - pane(forStep:)

    /// Steps 0 and 1 show the intro and environment panes; this is the wizard's whole
    /// page state machine, so pinning it catches an off-by-one if a page is ever
    /// inserted or reordered.
    @Test func paneForStepMapsTheFirstTwoStepsToTheirOwnPage() {
        #expect(WelcomeWizardLogic.pane(forStep: 0) == .intro)
        #expect(WelcomeWizardLogic.pane(forStep: 1) == .environment)
    }

    /// Step 2 (the last page) and anything past it land on the closing pane, matching the
    /// `default` case this mapping replaced in `content`'s switch.
    @Test func paneForStepFallsBackToFirstPRForStepTwoAndBeyond() {
        #expect(WelcomeWizardLogic.pane(forStep: 2) == .firstPR)
        #expect(WelcomeWizardLogic.pane(forStep: 99) == .firstPR)
    }

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

    // MARK: - continueDisabled

    @Test func continueDisabledIsFalseOnPanesOtherThanTheEnvironmentStep() {
        // Only step 1 (the environment pane) has anything that can block continuing;
        // the intro pane (0) has no blocker to check.
        #expect(!WelcomeWizardLogic.continueDisabled(step: 0, blocker: "git is required"))
    }

    @Test func continueDisabledIsTrueOnTheEnvironmentStepWithABlocker() {
        #expect(WelcomeWizardLogic.continueDisabled(step: 1, blocker: "git is required"))
    }

    @Test func continueDisabledIsFalseOnTheEnvironmentStepOnceUnblocked() {
        #expect(!WelcomeWizardLogic.continueDisabled(step: 1, blocker: nil))
    }

    // MARK: - finishButtonTitle

    @Test func finishButtonTitleIsFinishWithAnEmptyURL() {
        #expect(WelcomeWizardLogic.finishButtonTitle(urlText: "") == "Finish")
    }

    @Test func finishButtonTitleIsOpenPROnceAURLIsTyped() {
        #expect(WelcomeWizardLogic.finishButtonTitle(urlText: "https://github.com/acme/shop/pull/42") == "Open PR")
    }
}
