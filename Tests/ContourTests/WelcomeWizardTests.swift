import Testing

@testable import Contour

struct WelcomeWizardTests {
    @Test func paneForStepMapsTheFirstTwoStepsToTheirOwnPage() {
        #expect(WelcomeWizardLogic.pane(forStep: 0) == .intro)
        #expect(WelcomeWizardLogic.pane(forStep: 1) == .environment)
    }

    @Test func paneForStepFallsBackToFirstPRForStepTwoAndBeyond() {
        #expect(WelcomeWizardLogic.pane(forStep: 2) == .firstPR)
        #expect(WelcomeWizardLogic.pane(forStep: 99) == .firstPR)
    }

    @Test func needsHarnessChoiceIsFalseWithZeroOrOneInstalled() {
        #expect(!WelcomeWizardLogic.needsHarnessChoice(installedHarnesses: []))
        #expect(!WelcomeWizardLogic.needsHarnessChoice(installedHarnesses: [.pi]))
    }

    @Test func needsHarnessChoiceIsTrueWithMoreThanOneInstalled() {
        #expect(WelcomeWizardLogic.needsHarnessChoice(installedHarnesses: [.pi, .claude]))
    }

    private func status(_ tool: ExternalTool, installed: Bool) -> ToolStatus {
        ToolStatus(
            tool: tool, path: installed ? "/usr/bin/\(tool.rawValue)" : nil, version: nil, authenticated: nil,
            detail: "")
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
        let blocker = WelcomeWizardLogic.blocker(
            statuses: statuses, installedHarnesses: [.pi, .claude], resolvedHarness: nil)
        #expect(blocker == "Pick a harness to continue.")
    }

    @Test func blockerIsNilOnceGitAndAResolvedHarnessAreBothPresent() {
        let statuses: [ExternalTool: ToolStatus] = [.git: status(.git, installed: true)]
        #expect(WelcomeWizardLogic.blocker(statuses: statuses, installedHarnesses: [.pi], resolvedHarness: .pi) == nil)
    }

    @Test func blockerIsNilBeforeTheProbeHasReportedAnythingForGit() {
        #expect(WelcomeWizardLogic.blocker(statuses: [:], installedHarnesses: [.pi], resolvedHarness: .pi) == nil)
    }

    @Test func readySummaryNamesNoHarnessWhenNoneIsResolved() {
        let summary = WelcomeWizardLogic.readySummary(resolvedHarness: nil, ghUsable: false, resolvedTracker: .github)
        #expect(summary.contains("Analyzing with no harness"))
    }

    @Test func readySummaryNamesTheResolvedHarness() {
        let summary = WelcomeWizardLogic.readySummary(
            resolvedHarness: .claude, ghUsable: false, resolvedTracker: .github)
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

    @Test func canFinishIsTrueWithAnEmptyURL() {
        #expect(WelcomeWizardLogic.canFinish(urlText: ""))
    }

    @Test func canFinishIsTrueWithARecognizedPullRequestURL() {
        #expect(WelcomeWizardLogic.canFinish(urlText: "https://github.com/acme/shop/pull/42"))
    }

    @Test func canFinishIsFalseWithUnrecognizedText() {
        #expect(!WelcomeWizardLogic.canFinish(urlText: "not a url"))
    }

    @Test func continueDisabledIsFalseOnPanesOtherThanTheEnvironmentStep() {
        #expect(!WelcomeWizardLogic.continueDisabled(step: 0, blocker: "git is required"))
    }

    @Test func continueDisabledIsTrueOnTheEnvironmentStepWithABlocker() {
        #expect(WelcomeWizardLogic.continueDisabled(step: 1, blocker: "git is required"))
    }

    @Test func continueDisabledIsFalseOnTheEnvironmentStepOnceUnblocked() {
        #expect(!WelcomeWizardLogic.continueDisabled(step: 1, blocker: nil))
    }

    @Test func finishButtonTitleIsFinishWithAnEmptyURL() {
        #expect(WelcomeWizardLogic.finishButtonTitle(urlText: "") == "Finish")
    }

    @Test func finishButtonTitleIsOpenPROnceAURLIsTyped() {
        #expect(WelcomeWizardLogic.finishButtonTitle(urlText: "https://github.com/acme/shop/pull/42") == "Open PR")
    }
}
