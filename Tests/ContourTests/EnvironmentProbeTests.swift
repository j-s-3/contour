import Testing
@testable import Contour

/// `EnvironmentProbe.swift` was at 0.00% coverage. The `actor`'s own methods
/// (`probe`/`probeAll`/`version`/`isGitHubAuthenticated`/`isJiraAuthenticated`) all shell
/// out via `Shell.which`/`Shell.run` against whatever tools happen to be installed on the
/// machine running the test, which is exactly the kind of non-deterministic, environment-
/// dependent behavior avoided elsewhere in this suite (see `AnalysisServiceTests`'s note on
/// not faking `pi`/`claude` on `PATH`). These pin the pure pieces instead: the `ExternalTool`
/// enum's descriptive properties, `ToolStatus`'s computed properties, and the `Dictionary`
/// extension built from hand-constructed statuses.
struct EnvironmentProbeTests {

    @Test func everyExternalToolHasANonEmptyDisplayNameAndRole() {
        for tool in ExternalTool.allCases {
            #expect(!tool.displayName.isEmpty)
            #expect(!tool.role.isEmpty)
        }
    }

    @Test func onlyGitIsRequired() {
        #expect(ExternalTool.git.isRequired)
        #expect(!ExternalTool.pi.isRequired)
        #expect(!ExternalTool.claude.isRequired)
        #expect(!ExternalTool.gh.isRequired)
        #expect(!ExternalTool.acli.isRequired)
    }

    @Test func displayNamesMatchTheirTool() {
        #expect(ExternalTool.git.displayName == "git")
        #expect(ExternalTool.pi.displayName == "pi")
        #expect(ExternalTool.claude.displayName == "Claude Code")
        #expect(ExternalTool.gh.displayName == "GitHub CLI")
        #expect(ExternalTool.acli.displayName == "Atlassian CLI")
    }

    @Test func toolStatusIsInstalledReflectsWhetherAPathWasFound() {
        let notInstalled = ToolStatus(tool: .git, path: nil, version: nil, authenticated: nil, detail: "Not installed")
        #expect(!notInstalled.isInstalled)
        #expect(!notInstalled.isUsable, "not installed can never be usable")

        let installed = ToolStatus(tool: .git, path: "/usr/bin/git", version: "2.40", authenticated: nil, detail: "2.40")
        #expect(installed.isInstalled)
    }

    /// `isUsable` requires `isInstalled` and treats a `nil` `authenticated` (tools that
    /// don't need auth, like `git`) as usable, but an explicit `false` as not.
    @Test func toolStatusIsUsableTreatsNilAuthenticatedAsUsableButFalseAsNot() {
        let noAuthNeeded = ToolStatus(tool: .git, path: "/usr/bin/git", version: nil, authenticated: nil, detail: "")
        #expect(noAuthNeeded.isUsable)

        let authenticated = ToolStatus(tool: .gh, path: "/usr/bin/gh", version: nil, authenticated: true, detail: "")
        #expect(authenticated.isUsable)

        let notAuthenticated = ToolStatus(tool: .gh, path: "/usr/bin/gh", version: nil, authenticated: false, detail: "")
        #expect(!notAuthenticated.isUsable)
    }

    @Test func toolStatusIDIsTheToolsRawValue() {
        let status = ToolStatus(tool: .acli, path: nil, version: nil, authenticated: nil, detail: "")
        #expect(status.id == "acli")
    }

    @Test func installedHarnessesListsOnlyThoseMarkedInstalled() {
        let none: [ExternalTool: ToolStatus] = [:]
        #expect(none.installedHarnesses.isEmpty)

        let piOnly: [ExternalTool: ToolStatus] = [
            .pi: ToolStatus(tool: .pi, path: "/usr/local/bin/pi", version: nil, authenticated: nil, detail: ""),
            .claude: ToolStatus(tool: .claude, path: nil, version: nil, authenticated: nil, detail: "Not installed"),
        ]
        #expect(piOnly.installedHarnesses == [.pi])

        let both: [ExternalTool: ToolStatus] = [
            .pi: ToolStatus(tool: .pi, path: "/usr/local/bin/pi", version: nil, authenticated: nil, detail: ""),
            .claude: ToolStatus(tool: .claude, path: "/usr/local/bin/claude", version: nil, authenticated: nil, detail: ""),
        ]
        #expect(Set(both.installedHarnesses) == Set([.pi, .claude]))
    }

    @Test func jiraAvailableRequiresAcliToBeUsableNotJustInstalled() {
        let notInstalled: [ExternalTool: ToolStatus] = [
            .acli: ToolStatus(tool: .acli, path: nil, version: nil, authenticated: nil, detail: "Not installed"),
        ]
        #expect(!notInstalled.jiraAvailable)

        let installedNotAuthed: [ExternalTool: ToolStatus] = [
            .acli: ToolStatus(tool: .acli, path: "/usr/local/bin/acli", version: nil, authenticated: false, detail: ""),
        ]
        #expect(!installedNotAuthed.jiraAvailable)

        let authed: [ExternalTool: ToolStatus] = [
            .acli: ToolStatus(tool: .acli, path: "/usr/local/bin/acli", version: nil, authenticated: true, detail: ""),
        ]
        #expect(authed.jiraAvailable)

        let missingKey: [ExternalTool: ToolStatus] = [:]
        #expect(!missingKey.jiraAvailable)
    }
}
