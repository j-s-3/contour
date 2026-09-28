import SwiftUI

/// The Settings scene (⌘,). Every control here is one of the three pluggable choices, a
/// model override on top of the chosen harness, or how the window opens.
///
/// Options that can't work are shown disabled with the reason, rather than hidden: a user
/// wondering why Jira isn't offered is better served by a greyed row saying "acli not
/// found" than by no row at all.
struct SettingsView: View {
    @State private var preferences = Preferences.shared
    @State private var statuses: [ExternalTool: ToolStatus] = [:]
    @State private var isProbing = false

    private let probe = EnvironmentProbe()

    var body: some View {
        TabView {
            harnessTab
                .tabItem { Label("Harness", systemImage: "cpu") }
            sourcesTab
                .tabItem { Label("Sources", systemImage: "arrow.triangle.branch") }
            windowTab
                .tabItem { Label("Window", systemImage: "macwindow") }
        }
        .frame(width: 520, height: 400)
        .task { await refresh() }
    }

    // MARK: - Harness

    private var harnessTab: some View {
        Form {
            Section {
                Picker("AI harness", selection: harnessBinding) {
                    ForEach(HarnessID.allCases, id: \.self) { id in
                        Text(label(for: id)).tag(Optional(id))
                    }
                    Text("Not selected").tag(Optional<HarnessID>.none)
                }
                .pickerStyle(.inline)
                .disabled(preferences.isOverriddenByEnvironment("CONTOUR_HARNESS"))

                if preferences.isOverriddenByEnvironment("CONTOUR_HARNESS") {
                    overrideNotice("CONTOUR_HARNESS")
                }
            } header: {
                Text("Harness")
            } footer: {
                Text("Contour drives whichever CLI you pick and inherits its provider, model, and credentials. It never stores an API key of its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Fast stages") {
                    TextField("harness default", text: $preferences.fastModelOverride)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Judgment stages") {
                    TextField("harness default", text: $preferences.strongModelOverride)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("Model overrides")
            } footer: {
                Text("Leave blank to use the harness's own configured model. A bare pattern like \"sonnet\" can match an unauthenticated provider when several are configured, so set these only if you know which you want.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var harnessBinding: Binding<HarnessID?> {
        Binding(
            get: { preferences.resolvedHarness },
            set: { preferences.storedHarness = $0 }
        )
    }

    private func label(for id: HarnessID) -> String {
        SettingsViewLogic.label(for: id, statuses: statuses)
    }

    // MARK: - Sources

    private var sourcesTab: some View {
        Form {
            Section {
                Picker("GitHub access", selection: Binding(
                    get: { preferences.resolvedGitHubAccess },
                    set: { preferences.storedGitHubAccess = $0 }
                )) {
                    ForEach(GitHubAccessMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .disabled(preferences.isOverriddenByEnvironment("CONTOUR_GITHUB_ACCESS"))

                if preferences.isOverriddenByEnvironment("CONTOUR_GITHUB_ACCESS") {
                    overrideNotice("CONTOUR_GITHUB_ACCESS")
                }
            } header: {
                Text("GitHub")
            } footer: {
                Text(githubFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Issue tracker", selection: Binding(
                    get: { preferences.resolvedTracker },
                    set: { preferences.storedTracker = $0 }
                )) {
                    Text(TrackerID.github.displayName).tag(TrackerID.github)
                    Text(jiraLabel).tag(TrackerID.jira)
                    Text(TrackerID.none.displayName).tag(TrackerID.none)
                }
                .pickerStyle(.inline)
                .disabled(preferences.isOverriddenByEnvironment("CONTOUR_TRACKER"))

                if preferences.isOverriddenByEnvironment("CONTOUR_TRACKER") {
                    overrideNotice("CONTOUR_TRACKER")
                }
            } header: {
                Text("Issue tracker")
            } footer: {
                Text("Used to ground the plain-language \"problem to be solved\" summary in what was actually asked for. A missing or unreachable issue never fails a review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ExternalTool.allCases, id: \.self) { tool in
                    ToolStatusRow(status: statuses[tool], tool: tool)
                }
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Re-check", systemImage: "arrow.clockwise")
                }
                .disabled(isProbing)
            } header: {
                Text("Detected tools")
            }
        }
        .formStyle(.grouped)
    }

    private var githubFooter: String { SettingsViewLogic.githubFooter(for: preferences.resolvedGitHubAccess) }

    private var jiraLabel: String { SettingsViewLogic.jiraLabel(jiraAvailable: preferences.jiraAvailable) }

    // MARK: - Window

    private var windowTab: some View {
        Form {
            Section {
                Toggle("Open in full screen", isOn: $preferences.opensInFullScreen)
            } header: {
                Text("Launch")
            } footer: {
                Text("When off, Contour reopens at its last size and position, beside whatever you opened the link from. When on, it takes over its own Space at launch. Applies the next time Contour opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Shared

    private func overrideNotice(_ variable: String) -> some View {
        Label(SettingsViewLogic.overrideNoticeText(for: variable), systemImage: "terminal")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private func refresh() async {
        isProbing = true
        defer { isProbing = false }
        let found = await probe.probeAll()
        statuses = found
        preferences.installedHarnesses = found.installedHarnesses
        preferences.jiraAvailable = found.jiraAvailable
    }
}

/// One detected-tool row, shared by Settings and the first-run wizard.
struct ToolStatusRow: View {
    let status: ToolStatus?
    let tool: ExternalTool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.displayName).font(.callout.weight(.medium))
                Text(status?.detail ?? "Checking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }

    private var symbol: String { SettingsViewLogic.symbol(for: status, tool: tool) }

    /// Optional tools that are simply absent are grey, not red: their absence is a
    /// feature Contour does without, not a failure.
    private var tint: Color { SettingsViewLogic.tint(for: status, tool: tool) }
}

/// The status-derivation and precedence-aware footer logic CLAUDE.md calls out for this
/// file, pulled out of `SettingsView`/`ToolStatusRow`'s bodies so it's directly testable
/// against plain `ToolStatus`/`ExternalTool`/`HarnessID` fixtures rather than through the
/// SwiftUI `body`.
enum SettingsViewLogic {
    /// The harness a picker row maps to.
    static func harnessTool(_ id: HarnessID) -> ExternalTool {
        switch id {
        case .pi: return .pi
        case .claude: return .claude
        }
    }

    /// A harness picker row's label: its name alone, "not installed", or its detected
    /// version, depending on what the probe found.
    static func label(for id: HarnessID, statuses: [ExternalTool: ToolStatus]) -> String {
        guard let status = statuses[harnessTool(id)] else { return id.displayName }
        guard status.isInstalled else { return "\(id.displayName) — not installed" }
        return status.version.map { "\(id.displayName) — \($0)" } ?? id.displayName
    }

    /// What each GitHub access mode means for the reviewer, shown under the picker.
    static func githubFooter(for mode: GitHubAccessMode) -> String {
        switch mode {
        case .auto:
            return "Uses gh when it's installed and signed in (private repos, 5000 requests/hour); otherwise the anonymous API, which reads public PRs with no setup at all."
        case .gh:
            return "Always uses gh. Public PRs will fail if gh isn't signed in."
        case .anonymous:
            return "Always uses the anonymous API: public PRs only, 60 requests/hour. Useful for checking that the no-setup path still works."
        }
    }

    /// The Jira picker row's label — plain when acli is available, else the reason it's
    /// disabled.
    static func jiraLabel(jiraAvailable: Bool) -> String {
        jiraAvailable ? TrackerID.jira.displayName : "Jira — acli not found"
    }

    /// The text shown under a picker whose choice is pinned by an environment variable,
    /// naming which one so a user staring at a disabled control knows why.
    static func overrideNoticeText(for variable: String) -> String {
        "Overridden by \(variable) in the environment."
    }

    /// A detected-tool row's glyph: unknown (still probing), usable, installed but not
    /// usable, or absent — red only when the tool is required.
    static func symbol(for status: ToolStatus?, tool: ExternalTool) -> String {
        guard let status else { return "circle.dotted" }
        if status.isUsable { return "checkmark.circle.fill" }
        if status.isInstalled { return "exclamationmark.triangle.fill" }
        return tool.isRequired ? "xmark.circle.fill" : "minus.circle"
    }

    /// Optional tools that are simply absent are grey, not red: their absence is a
    /// feature Contour does without, not a failure.
    static func tint(for status: ToolStatus?, tool: ExternalTool) -> Color {
        guard let status else { return .secondary }
        if status.isUsable { return .green }
        if status.isInstalled { return .orange }
        return tool.isRequired ? .red : .secondary
    }
}
