import Foundation
import Observation

/// How Contour reaches GitHub.
enum GitHubAccessMode: String, Codable, CaseIterable, Sendable {
    /// Use `gh` when it's installed and authenticated; otherwise the anonymous REST API.
    case auto
    /// Always use `gh`; fail with a clear message if it isn't usable.
    case gh
    /// Always use the anonymous REST API, even when `gh` is available. Exists so the
    /// public-PR path — the one a new user hits, and therefore the one most worth
    /// exercising — can be tested deliberately rather than only by accident.
    case anonymous

    var displayName: String {
        switch self {
        case .auto: return "Automatic"
        case .gh: return "Always use gh"
        case .anonymous: return "Anonymous API only"
        }
    }
}

/// Resolution rules, kept as pure functions so precedence is testable without touching
/// `UserDefaults`, the environment, or the filesystem.
///
/// Precedence everywhere: **environment > stored > detected**. The environment wins so a
/// test or script can pin behavior; detection loses to a stored choice so Contour never
/// silently switches harness because the user installed a second CLI.
enum PreferenceResolution {

    static func harness(env: [String: String], stored: HarnessID?, installed: [HarnessID]) -> HarnessID? {
        if let raw = env["CONTOUR_HARNESS"], let id = HarnessID(rawValue: raw.lowercased()) {
            return id
        }
        // A stored choice is honored even if that harness has since been uninstalled —
        // the UI reports it as missing rather than quietly analyzing with a different
        // model than the one the user picked.
        if let stored { return stored }
        if installed.count == 1 { return installed[0] }
        // Zero installed (nothing to run) or several (an ambiguous choice the user should
        // make themselves, in the wizard).
        return nil
    }

    static func tracker(env: [String: String], stored: TrackerID?, jiraAvailable: Bool) -> TrackerID {
        if let raw = env["CONTOUR_TRACKER"], let id = TrackerID(rawValue: raw.lowercased()) {
            // Asking for Jira without `acli` present is a misconfiguration, not a reason
            // to fail a run: fall back to GitHub issues, which need no extra tooling.
            return (id == .jira && !jiraAvailable) ? .github : id
        }
        if let stored {
            return (stored == .jira && !jiraAvailable) ? .github : stored
        }
        // GitHub issues are the default because they need nothing installed and every PR
        // already lives on GitHub. Jira is opt-in even when `acli` is present.
        return .github
    }

    static func githubAccess(env: [String: String], stored: GitHubAccessMode?) -> GitHubAccessMode {
        if let raw = env["CONTOUR_GITHUB_ACCESS"], let mode = GitHubAccessMode(rawValue: raw.lowercased()) {
            return mode
        }
        return stored ?? .auto
    }
}

/// User-visible settings, persisted in `UserDefaults` and surfaced by the Settings scene
/// and the first-run wizard.
@Observable
final class Preferences {
    @MainActor static let shared = Preferences()

    private let defaults: UserDefaults
    private let environment: [String: String]

    /// What the last environment probe found installed. Set by the wizard/Settings after
    /// probing; drives the "only one harness installed, just use it" case.
    var installedHarnesses: [HarnessID] = []
    var jiraAvailable: Bool = false

    init(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        self.environment = environment
    }

    // MARK: - Stored values

    private enum Key {
        static let harness = "harness"
        static let tracker = "tracker"
        static let githubAccess = "githubAccess"
        static let fastModel = "fastModelOverride"
        static let strongModel = "strongModelOverride"
        static let onboarded = "hasCompletedOnboarding"
        static let fullScreen = "opensInFullScreen"
    }

    var storedHarness: HarnessID? {
        get { (defaults.string(forKey: Key.harness)).flatMap(HarnessID.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Key.harness) }
    }

    var storedTracker: TrackerID? {
        get { (defaults.string(forKey: Key.tracker)).flatMap(TrackerID.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Key.tracker) }
    }

    var storedGitHubAccess: GitHubAccessMode? {
        get { (defaults.string(forKey: Key.githubAccess)).flatMap(GitHubAccessMode.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Key.githubAccess) }
    }

    var fastModelOverride: String {
        get { defaults.string(forKey: Key.fastModel) ?? "" }
        set { defaults.set(newValue, forKey: Key.fastModel); applyModelOverrides() }
    }

    var strongModelOverride: String {
        get { defaults.string(forKey: Key.strongModel) ?? "" }
        set { defaults.set(newValue, forKey: Key.strongModel); applyModelOverrides() }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    /// Off by default: a reviewer usually arrives from a link in Slack or a browser, and
    /// taking over a whole Space loses the window they came from. The window reopens at
    /// its last frame instead.
    var opensInFullScreen: Bool {
        get { defaults.bool(forKey: Key.fullScreen) }
        set { defaults.set(newValue, forKey: Key.fullScreen) }
    }

    // MARK: - Resolved values

    /// nil means "Contour can't run yet" — either nothing is installed, or both are and
    /// the user hasn't chosen. Both cases are the wizard's job to resolve.
    var resolvedHarness: HarnessID? {
        PreferenceResolution.harness(env: environment, stored: storedHarness, installed: installedHarnesses)
    }

    var resolvedTracker: TrackerID {
        PreferenceResolution.tracker(env: environment, stored: storedTracker, jiraAvailable: jiraAvailable)
    }

    var resolvedGitHubAccess: GitHubAccessMode {
        PreferenceResolution.githubAccess(env: environment, stored: storedGitHubAccess)
    }

    /// True when an env var is pinning a value, so the UI can say the control is being
    /// overridden instead of appearing not to work.
    func isOverriddenByEnvironment(_ key: String) -> Bool {
        environment[key] != nil
    }

    /// Pushes the per-tier model overrides into `AnalysisTier`, which is what the
    /// harnesses actually read. Call once at launch and on every change.
    func applyModelOverrides() {
        var overrides: [AnalysisTier: String] = [:]
        let fast = fastModelOverride.trimmingCharacters(in: .whitespaces)
        let strong = strongModelOverride.trimmingCharacters(in: .whitespaces)
        if !fast.isEmpty { overrides[.fast] = fast }
        if !strong.isEmpty { overrides[.strong] = strong }
        AnalysisTier.modelOverrides = overrides
    }
}
