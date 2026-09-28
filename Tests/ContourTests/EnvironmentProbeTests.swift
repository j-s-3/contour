import Testing
@testable import Contour

/// `EnvironmentProbe.swift` was at 0.00% coverage because the `actor`'s own methods
/// (`probe`/`probeAll`/`version`/`isGitHubAuthenticated`/`isJiraAuthenticated`) all shelled
/// out via `Shell.which`/`Shell.run` directly, against whatever tools happen to be
/// installed on the machine running the test — exactly the kind of non-deterministic,
/// environment-dependent behavior avoided elsewhere in this suite (see
/// `AnalysisServiceTests`'s note on not faking `pi`/`claude` on `PATH`). `EnvironmentProbe`
/// now takes an injectable `EnvironmentProbeOperations` (the same seam `PRSource` gives
/// `GitHubService`), so these pin the pure pieces (the `ExternalTool` enum's descriptive
/// properties, `ToolStatus`'s computed properties, the `Dictionary` extension) *and* the
/// actor's own branches, run against canned `which`/`run` results instead of the real
/// machine.
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

    // MARK: - EnvironmentProbe.probe / probeAll, against canned operations

    /// Builds an `EnvironmentProbeOperations` from plain, `Sendable` lookup tables instead
    /// of a stateful recorder, so the closures need no locking: `which` maps a tool's raw
    /// value to a resolved path (absent = not installed), and `run` maps a
    /// space-joined "executable arg1 arg2…" key to either canned stdout or a thrown
    /// `ProcessError` (a key in neither table also throws, matching a real non-zero exit).
    private func operations(
        which: [String: String] = [:],
        stdout: [String: String] = [:],
        failing: Set<String> = []
    ) -> EnvironmentProbeOperations {
        EnvironmentProbeOperations(
            which: { which[$0] },
            run: { exe, args in
                let key = ([exe] + args).joined(separator: " ")
                if failing.contains(key) {
                    throw ProcessError(command: key, exitCode: 1, stderr: "canned failure")
                }
                if let out = stdout[key] { return out }
                throw ProcessError(command: key, exitCode: 127, stderr: "no canned response for \(key)")
            }
        )
    }

    /// A tool absent from `which`'s results probes as not installed, with every other field
    /// nil, regardless of which kind of tool it is (harness vs. `gh`/`acli`, which take the
    /// auth-check branch only once `which` succeeds).
    @Test func probeReportsNotInstalledWhenWhichFindsNothing() async {
        let probe = EnvironmentProbe(operations: operations())
        let status = await probe.probe(.git)
        #expect(status.path == nil)
        #expect(status.version == nil)
        #expect(status.authenticated == nil)
        #expect(status.detail == "Not installed")
        #expect(!status.isInstalled)
    }

    /// `git`/`pi`/`claude` have no auth concept: `authenticated` stays nil even when
    /// installed, and the detail line combines the parsed version with the resolved path.
    @Test func probeForAHarnessCombinesVersionAndPathWithNoAuthCheck() async {
        let ops = operations(
            which: ["git": "/usr/bin/git"],
            stdout: ["/usr/bin/git --version": "git version 2.43.0\n"]
        )
        let probe = EnvironmentProbe(operations: ops)
        let status = await probe.probe(.git)
        #expect(status.path == "/usr/bin/git")
        #expect(status.version == "git version 2.43.0")
        #expect(status.authenticated == nil)
        #expect(status.detail == "git version 2.43.0 — /usr/bin/git")
        #expect(status.isUsable, "no auth concept means installed is usable")
    }

    /// `version` takes only the first line of `--version` output and trims it — real
    /// `claude --version` output can carry a trailing newline or extra lines.
    @Test func versionParsingTakesFirstLineTrimmed() async {
        let ops = operations(
            which: ["claude": "/usr/local/bin/claude"],
            stdout: ["/usr/local/bin/claude --version": "  1.2.3 (build 456)  \nSome extra line\n"]
        )
        let probe = EnvironmentProbe(operations: ops)
        let status = await probe.probe(.claude)
        #expect(status.version == "1.2.3 (build 456)")
    }

    /// When the `--version` call itself fails (old binary, unrecognized flag), `version` is
    /// swallowed to nil rather than propagating the error, and the detail line falls back to
    /// the bare path.
    @Test func probeToleratesAVersionCommandThatFails() async {
        let ops = operations(
            which: ["pi": "/usr/local/bin/pi"],
            failing: ["/usr/local/bin/pi --version"]
        )
        let probe = EnvironmentProbe(operations: ops)
        let status = await probe.probe(.pi)
        #expect(status.path == "/usr/local/bin/pi")
        #expect(status.version == nil)
        #expect(status.authenticated == nil)
        #expect(status.detail == "/usr/local/bin/pi")
    }

    /// `gh`'s auth check is hardcoded to invoke `gh auth status` (not the resolved path) —
    /// pinned here by resolving `which` to a custom path but only canning the bare-name key.
    @Test func probeForGHWhenAuthenticatedReportsVersionAndAuthedDetail() async {
        let ops = operations(
            which: ["gh": "/custom/bin/gh"],
            stdout: [
                "/custom/bin/gh --version": "gh version 2.50.0 (2024-01-01)\n",
                "gh auth status": "Logged in to github.com as octocat\n",
            ]
        )
        let probe = EnvironmentProbe(operations: ops)
        let status = await probe.probe(.gh)
        #expect(status.path == "/custom/bin/gh")
        #expect(status.version == "gh version 2.50.0 (2024-01-01)")
        #expect(status.authenticated == true)
        #expect(status.detail == "Authenticated — gh version 2.50.0 (2024-01-01)")
        #expect(status.isUsable)
    }

    /// Installed but `gh auth status` exits non-zero (no account logged in): `authenticated`
    /// is false, the detail line points at the fix, and `isUsable` goes false too.
    @Test func probeForGHWhenNotAuthenticatedReportsTheFixInTheDetail() async {
        let ops = operations(
            which: ["gh": "/usr/local/bin/gh"],
            stdout: ["/usr/local/bin/gh --version": "gh version 2.50.0\n"],
            failing: ["gh auth status"]
        )
        let probe = EnvironmentProbe(operations: ops)
        let status = await probe.probe(.gh)
        #expect(status.authenticated == false)
        #expect(status.detail == "Installed but not authenticated. Run `gh auth login`.")
        #expect(status.isInstalled)
        #expect(!status.isUsable)
    }

    /// `gh`'s "Authenticated — …" detail falls back to the bare path when `--version` itself
    /// failed, mirroring the harness branch's `version.map { … } ?? path` fallback.
    @Test func probeForGHAuthenticatedWithNoVersionFallsBackToPathInDetail() async {
        let ops = operations(
            which: ["gh": "/usr/local/bin/gh"],
            stdout: ["gh auth status": "Logged in\n"],
            failing: ["/usr/local/bin/gh --version"]
        )
        let probe = EnvironmentProbe(operations: ops)
        let status = await probe.probe(.gh)
        #expect(status.version == nil)
        #expect(status.authenticated == true)
        #expect(status.detail == "Authenticated — /usr/local/bin/gh")
    }

    /// `acli`'s auth check mirrors `gh`'s: hardcoded to `acli jira auth status`, and success
    /// reports Jira as authenticated with the Jira-specific fix in the failure detail.
    @Test func probeForAcliWhenAuthenticatedReportsVersionAndAuthedDetail() async {
        let ops = operations(
            which: ["acli": "/opt/homebrew/bin/acli"],
            stdout: [
                "/opt/homebrew/bin/acli --version": "acli 1.0.0\n",
                "acli jira auth status": "Authenticated to Jira\n",
            ]
        )
        let probe = EnvironmentProbe(operations: ops)
        let status = await probe.probe(.acli)
        #expect(status.authenticated == true)
        #expect(status.detail == "Authenticated — acli 1.0.0")
        #expect(status.isUsable)
    }

    @Test func probeForAcliWhenNotAuthenticatedReportsTheJiraFixInTheDetail() async {
        let ops = operations(
            which: ["acli": "/opt/homebrew/bin/acli"],
            stdout: ["/opt/homebrew/bin/acli --version": "acli 1.0.0\n"],
            failing: ["acli jira auth status"]
        )
        let probe = EnvironmentProbe(operations: ops)
        let status = await probe.probe(.acli)
        #expect(status.authenticated == false)
        #expect(status.detail == "Installed but not authenticated. Run `acli jira auth login`.")
        #expect(!status.isUsable)
    }

    /// `probeAll` probes every `ExternalTool` case and keys the result by tool, exercising
    /// the loop that `probe`-level tests above never touch on their own.
    @Test func probeAllCoversEveryExternalToolCase() async {
        let ops = operations(
            which: [
                "git": "/usr/bin/git",
                "pi": "/usr/local/bin/pi",
                "gh": "/usr/local/bin/gh",
                // "claude" and "acli" deliberately absent: not installed.
            ],
            stdout: [
                "/usr/bin/git --version": "git version 2.43.0\n",
                "/usr/local/bin/pi --version": "pi 0.9\n",
                "/usr/local/bin/gh --version": "gh version 2.50.0\n",
                "gh auth status": "Logged in\n",
            ]
        )
        let probe = EnvironmentProbe(operations: ops)
        let results = await probe.probeAll()

        #expect(Set(results.keys) == Set(ExternalTool.allCases))
        #expect(results[.git]?.isInstalled == true)
        #expect(results[.pi]?.isInstalled == true)
        #expect(results[.gh]?.authenticated == true)
        #expect(results[.claude]?.isInstalled == false)
        #expect(results[.acli]?.isInstalled == false)
    }
}
