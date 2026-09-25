import Testing
import Foundation
@testable import Contour

/// Precedence is env > stored > detected. These are pure-function tests, so they pin the
/// rule without touching `UserDefaults` or the real environment.
struct PreferencesTests {

    // MARK: - Harness

    @Test func environmentBeatsStoredChoice() {
        let picked = PreferenceResolution.harness(
            env: ["CONTOUR_HARNESS": "claude"], stored: .pi, installed: [.pi, .claude]
        )
        #expect(picked == .claude)
    }

    @Test func environmentIsCaseInsensitive() {
        #expect(PreferenceResolution.harness(env: ["CONTOUR_HARNESS": "CLAUDE"], stored: nil, installed: []) == .claude)
    }

    @Test func unrecognizedEnvironmentValueFallsThroughRatherThanFailing() {
        let picked = PreferenceResolution.harness(
            env: ["CONTOUR_HARNESS": "gpt"], stored: .pi, installed: [.pi]
        )
        #expect(picked == .pi)
    }

    @Test func storedChoiceBeatsDetection() {
        let picked = PreferenceResolution.harness(env: [:], stored: .pi, installed: [.pi, .claude])
        #expect(picked == .pi)
    }

    /// A stored choice survives that harness being uninstalled. Silently switching to the
    /// other one would analyze the PR with a different model than the user picked, and say
    /// nothing about it; the UI reports it as missing instead.
    @Test func storedChoiceSurvivesUninstall() {
        #expect(PreferenceResolution.harness(env: [:], stored: .claude, installed: [.pi]) == .claude)
    }

    @Test func soleInstalledHarnessIsUsedWithoutAsking() {
        #expect(PreferenceResolution.harness(env: [:], stored: nil, installed: [.claude]) == .claude)
    }

    /// Two installed and nothing chosen is genuinely ambiguous — the wizard asks rather
    /// than picking a winner by list order.
    @Test func ambiguousInstallYieldsNoChoice() {
        #expect(PreferenceResolution.harness(env: [:], stored: nil, installed: [.pi, .claude]) == nil)
    }

    @Test func nothingInstalledYieldsNoChoice() {
        #expect(PreferenceResolution.harness(env: [:], stored: nil, installed: []) == nil)
    }

    // MARK: - Tracker

    @Test func githubIssuesAreTheDefault() {
        #expect(PreferenceResolution.tracker(env: [:], stored: nil, jiraAvailable: false) == .github)
    }

    /// Jira stays opt-in even when `acli` is installed and authenticated — detection alone
    /// must not change where Contour looks for the problem statement.
    @Test func jiraIsNotAdoptedMerelyBecauseAcliExists() {
        #expect(PreferenceResolution.tracker(env: [:], stored: nil, jiraAvailable: true) == .github)
    }

    @Test func jiraIsUsedOnceChosenAndAvailable() {
        #expect(PreferenceResolution.tracker(env: [:], stored: .jira, jiraAvailable: true) == .jira)
    }

    /// Choosing Jira without `acli` is a misconfiguration, not a reason to fail a run:
    /// fall back to GitHub issues, which need nothing installed.
    @Test func jiraWithoutAcliFallsBackToGitHub() {
        #expect(PreferenceResolution.tracker(env: [:], stored: .jira, jiraAvailable: false) == .github)
        #expect(PreferenceResolution.tracker(env: ["CONTOUR_TRACKER": "jira"], stored: nil, jiraAvailable: false) == .github)
    }

    @Test func trackerCanBeTurnedOffEntirely() {
        #expect(PreferenceResolution.tracker(env: [:], stored: TrackerID.none, jiraAvailable: true) == .none)
        #expect(PreferenceResolution.tracker(env: ["CONTOUR_TRACKER": "none"], stored: .jira, jiraAvailable: true) == .none)
    }

    // MARK: - GitHub access

    @Test func githubAccessDefaultsToAuto() {
        #expect(PreferenceResolution.githubAccess(env: [:], stored: nil) == .auto)
    }

    @Test func githubAccessHonorsStoredThenEnvironment() {
        #expect(PreferenceResolution.githubAccess(env: [:], stored: .anonymous) == .anonymous)
        #expect(PreferenceResolution.githubAccess(env: ["CONTOUR_GITHUB_ACCESS": "gh"], stored: .anonymous) == .gh)
    }

    // MARK: - Model overrides

    /// Overrides are opt-in: blank fields must leave `AnalysisTier` empty so each CLI's own
    /// configured default applies.
    @Test func blankModelOverridesArePushedAsNoOverrideAtAll() {
        let defaults = UserDefaults(suiteName: "contour.tests.\(UUID().uuidString)")!
        let prefs = Preferences(defaults: defaults, environment: [:])
        prefs.fastModelOverride = "   "
        prefs.strongModelOverride = ""
        #expect(AnalysisTier.modelOverrides.isEmpty)

        prefs.strongModelOverride = "opus"
        #expect(AnalysisTier.modelOverrides[.strong] == "opus")
        #expect(AnalysisTier.modelOverrides[.fast] == nil)

        AnalysisTier.modelOverrides = [:]
    }
}
