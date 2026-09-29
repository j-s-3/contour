import Testing
import Foundation
@testable import Contour

struct PreferencesTests {
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

    @Test func storedChoiceSurvivesUninstall() {
        #expect(PreferenceResolution.harness(env: [:], stored: .claude, installed: [.pi]) == .claude)
    }

    @Test func soleInstalledHarnessIsUsedWithoutAsking() {
        #expect(PreferenceResolution.harness(env: [:], stored: nil, installed: [.claude]) == .claude)
    }

    @Test func ambiguousInstallYieldsNoChoice() {
        #expect(PreferenceResolution.harness(env: [:], stored: nil, installed: [.pi, .claude]) == nil)
    }

    @Test func nothingInstalledYieldsNoChoice() {
        #expect(PreferenceResolution.harness(env: [:], stored: nil, installed: []) == nil)
    }

    @Test func githubIssuesAreTheDefault() {
        #expect(PreferenceResolution.tracker(env: [:], stored: nil, jiraAvailable: false) == .github)
    }

    @Test func jiraIsNotAdoptedMerelyBecauseAcliExists() {
        #expect(PreferenceResolution.tracker(env: [:], stored: nil, jiraAvailable: true) == .github)
    }

    @Test func jiraIsUsedOnceChosenAndAvailable() {
        #expect(PreferenceResolution.tracker(env: [:], stored: .jira, jiraAvailable: true) == .jira)
    }

    @Test func jiraWithoutAcliFallsBackToGitHub() {
        #expect(PreferenceResolution.tracker(env: [:], stored: .jira, jiraAvailable: false) == .github)
        #expect(PreferenceResolution.tracker(env: ["CONTOUR_TRACKER": "jira"], stored: nil, jiraAvailable: false) == .github)
    }

    @Test func trackerCanBeTurnedOffEntirely() {
        #expect(PreferenceResolution.tracker(env: [:], stored: TrackerID.none, jiraAvailable: true) == .none)
        #expect(PreferenceResolution.tracker(env: ["CONTOUR_TRACKER": "none"], stored: .jira, jiraAvailable: true) == .none)
    }

    @Test func githubAccessDefaultsToAuto() {
        #expect(PreferenceResolution.githubAccess(env: [:], stored: nil) == .auto)
    }

    @Test func githubAccessHonorsStoredThenEnvironment() {
        #expect(PreferenceResolution.githubAccess(env: [:], stored: .anonymous) == .anonymous)
        #expect(PreferenceResolution.githubAccess(env: ["CONTOUR_GITHUB_ACCESS": "gh"], stored: .anonymous) == .gh)
    }

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

    @Test func fullScreenIsOptIn() {
        let defaults = UserDefaults(suiteName: "contour.tests.\(UUID().uuidString)")!
        let prefs = Preferences(defaults: defaults, environment: [:])
        #expect(prefs.opensInFullScreen == false)

        prefs.opensInFullScreen = true
        #expect(Preferences(defaults: defaults, environment: [:]).opensInFullScreen)
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "contour.tests.\(UUID().uuidString)")!
    }

    @Test func storedHarnessRoundTripsAndDefaultsToNil() {
        let prefs = Preferences(defaults: freshDefaults(), environment: [:])
        #expect(prefs.storedHarness == nil)
        prefs.storedHarness = .claude
        #expect(prefs.storedHarness == .claude)
        prefs.storedHarness = nil
        #expect(prefs.storedHarness == nil)
    }

    @Test func storedTrackerRoundTripsAndDefaultsToNil() {
        let prefs = Preferences(defaults: freshDefaults(), environment: [:])
        #expect(prefs.storedTracker == nil)
        prefs.storedTracker = .jira
        #expect(prefs.storedTracker == .jira)
    }

    @Test func storedGitHubAccessRoundTripsAndDefaultsToNil() {
        let prefs = Preferences(defaults: freshDefaults(), environment: [:])
        #expect(prefs.storedGitHubAccess == nil)
        prefs.storedGitHubAccess = .anonymous
        #expect(prefs.storedGitHubAccess == .anonymous)
    }

    @Test func hasCompletedOnboardingRoundTripsAndDefaultsToFalse() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults, environment: [:])
        #expect(!prefs.hasCompletedOnboarding)
        prefs.hasCompletedOnboarding = true
        #expect(Preferences(defaults: defaults, environment: [:]).hasCompletedOnboarding)
    }

    @Test func resolvedHarnessUsesInstalledHarnessesFromTheInstance() {
        let prefs = Preferences(defaults: freshDefaults(), environment: [:])
        prefs.installedHarnesses = [.pi]
        #expect(prefs.resolvedHarness == .pi)

        prefs.storedHarness = .claude
        #expect(prefs.resolvedHarness == .claude, "a stored choice wins even though only pi is installed")
    }

    @Test func resolvedTrackerUsesJiraAvailabilityFromTheInstance() {
        let prefs = Preferences(defaults: freshDefaults(), environment: [:])
        #expect(prefs.resolvedTracker == .github)
        prefs.storedTracker = .jira
        #expect(prefs.resolvedTracker == .github, "jira isn't available yet")
        prefs.jiraAvailable = true
        #expect(prefs.resolvedTracker == .jira)
    }

    @Test func resolvedGitHubAccessHonorsTheEnvironmentOverride() {
        let prefs = Preferences(defaults: freshDefaults(), environment: ["CONTOUR_GITHUB_ACCESS": "anonymous"])
        prefs.storedGitHubAccess = .gh
        #expect(prefs.resolvedGitHubAccess == .anonymous)
    }

    @Test func isOverriddenByEnvironmentReflectsWhetherTheKeyIsSet() {
        let prefs = Preferences(defaults: freshDefaults(), environment: ["CONTOUR_HARNESS": "claude"])
        #expect(prefs.isOverriddenByEnvironment("CONTOUR_HARNESS"))
        #expect(!prefs.isOverriddenByEnvironment("CONTOUR_TRACKER"))
    }

    @Test func everyGitHubAccessModeHasADisplayName() {
        #expect(GitHubAccessMode.auto.displayName == "Automatic")
        #expect(GitHubAccessMode.gh.displayName == "Always use gh")
        #expect(GitHubAccessMode.anonymous.displayName == "Anonymous API only")
    }
}

struct ExecutableResolutionTests {
    @Test func pathEntriesPrecedeHardcodedFallbacks() {
        let paths = Shell.searchPaths(for: "claude")
        let homebrew = paths.firstIndex(of: "/opt/homebrew/bin/claude")
        guard let homebrew else { return }

        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        for (index, candidate) in paths.enumerated() where index < homebrew {
            let dir = (candidate as NSString).deletingLastPathComponent
            #expect(pathDirs.contains(Substring(dir)))
        }
    }

    @Test func fallbacksIncludeUserLocalBin() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(Shell.searchPaths(for: "claude").contains("\(home)/.local/bin/claude"))
    }

    @Test func absolutePathsAreNotSearched() {
        #expect(Shell.which("/definitely/not/here/claude") == nil)
        #expect(Shell.which("/bin/sh") == "/bin/sh")
    }
}
