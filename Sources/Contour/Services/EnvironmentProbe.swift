import Foundation

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

struct ToolStatus: Identifiable, Sendable {
    var tool: ExternalTool
    var path: String?
    var version: String?
    var authenticated: Bool?
    var detail: String

    var id: String { tool.rawValue }
    var isInstalled: Bool { path != nil }
    var isUsable: Bool { isInstalled && (authenticated ?? true) }
}

struct EnvironmentProbeOperations: Sendable {
    var which: @Sendable (String) -> String?
    var run: @Sendable (String, [String]) async throws -> String

    static let live = EnvironmentProbeOperations(
        which: { Shell.which($0) },
        run: { try await Shell.run($0, $1) }
    )
}

actor EnvironmentProbe {
    private let operations: EnvironmentProbeOperations

    init(operations: EnvironmentProbeOperations = .live) {
        self.operations = operations
    }

    func probeAll() async -> [ExternalTool: ToolStatus] {
        var result: [ExternalTool: ToolStatus] = [:]
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
        (try? await operations.run("gh", ["auth", "status"])) != nil
    }

    private func isJiraAuthenticated() async -> Bool {
        (try? await operations.run("acli", ["jira", "auth", "status"])) != nil
    }
}

extension Dictionary where Key == ExternalTool, Value == ToolStatus {
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
