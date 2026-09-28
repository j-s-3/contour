import Foundation

/// An external CLI Contour can use.
enum ExternalTool: String, CaseIterable, Sendable {
    case git
    case pi
    case claude
    case gh
    case acli

    var displayName: String {
        switch self {
        case .git: return "git"
        case .pi: return "pi"
        case .claude: return "Claude Code"
        case .gh: return "GitHub CLI"
        case .acli: return "Atlassian CLI"
        }
    }

    /// What Contour loses without it — shown in the wizard so an absent tool reads as a
    /// consequence rather than an error.
    var role: String {
        switch self {
        case .git: return "Required. Checks out the PR so analysis reads real code."
        case .pi, .claude: return "One AI harness is required. Contour drives whichever you pick."
        case .gh: return "Only needed for private PRs. Public PRs work without it."
        case .acli: return "Optional. Enables Jira as the issue tracker instead of GitHub issues."
        }
    }

    var isRequired: Bool { self == .git }
}

/// What a probe found.
struct ToolStatus: Identifiable, Sendable {
    var tool: ExternalTool
    /// nil means not installed.
    var path: String?
    var version: String?
    /// nil when the tool has no auth concept (git), otherwise whether it's usable.
    var authenticated: Bool?
    /// One line for the UI.
    var detail: String

    var id: String { tool.rawValue }
    var isInstalled: Bool { path != nil }
    /// Installed, and authenticated if that applies to it.
    var isUsable: Bool { isInstalled && (authenticated ?? true) }
}

/// The raw, side-effecting operations `EnvironmentProbe` needs from the outside world:
/// locating a binary and running it to completion. Exists so tests can supply canned
/// results instead of depending on which tools happen to be installed and authenticated
/// on the machine running the test suite — the same seam `PRSource` gives `GitHubService`.
struct EnvironmentProbeOperations: Sendable {
    var which: @Sendable (String) -> String?
    var run: @Sendable (String, [String]) async throws -> String

    static let live = EnvironmentProbeOperations(
        which: { Shell.which($0) },
        run: { try await Shell.run($0, $1) }
    )
}

/// Resolves which external tools are actually present and usable.
///
/// Exists so both the wizard and Settings show the same truth, and so a missing or
/// unauthenticated tool surfaces before a run instead of as a failure several minutes
/// into the pipeline.
actor EnvironmentProbe {
    private let operations: EnvironmentProbeOperations

    init(operations: EnvironmentProbeOperations = .live) {
        self.operations = operations
    }

    func probeAll() async -> [ExternalTool: ToolStatus] {
        var result: [ExternalTool: ToolStatus] = [:]
        // Sequential rather than concurrent: five short `--version` calls, and running
        // them in order keeps the wizard's rows from reshuffling as results land.
        for tool in ExternalTool.allCases {
            result[tool] = await probe(tool)
        }
        return result
    }

    func probe(_ tool: ExternalTool) async -> ToolStatus {
        guard let path = operations.which(tool.rawValue) else {
            return ToolStatus(tool: tool, path: nil, version: nil, authenticated: nil,
                              detail: "Not installed")
        }

        let version = await self.version(of: tool, at: path)

        switch tool {
        case .git, .pi, .claude:
            // No cheap, side-effect-free auth check for the harnesses: `pi auth check`
            // needs a provider argument, and `claude` has no offline equivalent. A bad
            // auth state surfaces on the first stage with the CLI's own error, which is
            // more accurate than anything Contour could guess here.
            return ToolStatus(tool: tool, path: path, version: version, authenticated: nil,
                              detail: version.map { "\($0) — \(path)" } ?? path)

        case .gh:
            let authed = await isGitHubAuthenticated()
            return ToolStatus(
                tool: tool, path: path, version: version, authenticated: authed,
                detail: authed ? "Authenticated — \(version ?? path)"
                               : "Installed but not authenticated. Run `gh auth login`."
            )

        case .acli:
            let authed = await isJiraAuthenticated()
            return ToolStatus(
                tool: tool, path: path, version: version, authenticated: authed,
                detail: authed ? "Authenticated — \(version ?? path)"
                               : "Installed but not authenticated. Run `acli jira auth login`."
            )
        }
    }

    private func version(of tool: ExternalTool, at path: String) async -> String? {
        guard let raw = try? await operations.run(path, ["--version"]) else { return nil }
        return raw
            .components(separatedBy: "\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isGitHubAuthenticated() async -> Bool {
        // `gh auth status` exits non-zero when no account is logged in, which the `run`
        // operation surfaces as a throw.
        (try? await operations.run("gh", ["auth", "status"])) != nil
    }

    private func isJiraAuthenticated() async -> Bool {
        (try? await operations.run("acli", ["jira", "auth", "status"])) != nil
    }
}

extension Dictionary where Key == ExternalTool, Value == ToolStatus {
    /// The harnesses that are actually installed, in a stable order.
    var installedHarnesses: [HarnessID] {
        HarnessID.allCases.filter { id in
            switch id {
            case .pi: return self[.pi]?.isInstalled == true
            case .claude: return self[.claude]?.isInstalled == true
            }
        }
    }

    var jiraAvailable: Bool { self[.acli]?.isUsable == true }
}
