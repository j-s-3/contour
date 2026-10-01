import Foundation
import Observation

enum GitHubAccessMode: String, Codable, CaseIterable, Sendable {
    case auto
    case gh
    case anonymous

    var displayName: String {
        switch self {
        case .auto: return "Automatic"
        case .gh: return "Always use gh"
        case .anonymous: return "Anonymous API only"
        }
    }
}

enum PreferenceResolution {
    static func harness(env: [String: String], stored: HarnessID?, installed: [HarnessID]) -> HarnessID? {
        if let raw = env["CONTOUR_HARNESS"], let id = HarnessID(rawValue: raw.lowercased()) {
            return id
        }
        if let stored { return stored }
        if installed.count == 1 { return installed[0] }
        return nil
    }

    static func tracker(env: [String: String], stored: TrackerID?, jiraAvailable: Bool) -> TrackerID {
        if let raw = env["CONTOUR_TRACKER"], let id = TrackerID(rawValue: raw.lowercased()) {
            return (id == .jira && !jiraAvailable) ? .github : id
        }
        if let stored {
            return (stored == .jira && !jiraAvailable) ? .github : stored
        }
        return .github
    }

    static func githubAccess(env: [String: String], stored: GitHubAccessMode?) -> GitHubAccessMode {
        if let raw = env["CONTOUR_GITHUB_ACCESS"], let mode = GitHubAccessMode(rawValue: raw.lowercased()) {
            return mode
        }
        return stored ?? .auto
    }
}

@Observable
final class Preferences {
    @MainActor static let shared = Preferences()

    private let defaults: UserDefaults
    private let environment: [String: String]

    var installedHarnesses: [HarnessID] = []
    var jiraAvailable: Bool = false

    init(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        self.environment = environment
    }

    private enum Key {
        static let harness = "harness"
        static let tracker = "tracker"
        static let githubAccess = "githubAccess"
        static let fastModel = "fastModelOverride"
        static let strongModel = "strongModelOverride"
        static let onboarded = "hasCompletedOnboarding"
        static let fullScreen = "opensInFullScreen"
        static let lastStartSource = "lastStartSource"
        static let watchedRepositories = "watchedRepositories"
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
        set {
            defaults.set(newValue, forKey: Key.fastModel)
            applyModelOverrides()
        }
    }

    var strongModelOverride: String {
        get { defaults.string(forKey: Key.strongModel) ?? "" }
        set {
            defaults.set(newValue, forKey: Key.strongModel)
            applyModelOverrides()
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    var opensInFullScreen: Bool {
        get { defaults.bool(forKey: Key.fullScreen) }
        set { defaults.set(newValue, forKey: Key.fullScreen) }
    }

    var lastStartSource: StartSource? {
        get { defaults.string(forKey: Key.lastStartSource).flatMap(StartSource.init(storageKey:)) }
        set { defaults.set(newValue?.storageKey, forKey: Key.lastStartSource) }
    }

    var watchedRepositories: [WatchedRepository] {
        get { (defaults.stringArray(forKey: Key.watchedRepositories) ?? []).compactMap(WatchedRepository.parse) }
        set { defaults.set(newValue.map(\.id), forKey: Key.watchedRepositories) }
    }

    var resolvedHarness: HarnessID? {
        PreferenceResolution.harness(env: environment, stored: storedHarness, installed: installedHarnesses)
    }

    var resolvedTracker: TrackerID {
        PreferenceResolution.tracker(env: environment, stored: storedTracker, jiraAvailable: jiraAvailable)
    }

    var resolvedGitHubAccess: GitHubAccessMode {
        PreferenceResolution.githubAccess(env: environment, stored: storedGitHubAccess)
    }

    func isOverriddenByEnvironment(_ key: String) -> Bool {
        environment[key] != nil
    }

    func applyModelOverrides() {
        var overrides: [AnalysisTier: String] = [:]
        let fast = fastModelOverride.trimmingCharacters(in: .whitespaces)
        let strong = strongModelOverride.trimmingCharacters(in: .whitespaces)
        if !fast.isEmpty { overrides[.fast] = fast }
        if !strong.isEmpty { overrides[.strong] = strong }
        AnalysisTier.modelOverrides = overrides
    }
}
