import SwiftUI

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

    private var tint: Color { SettingsViewLogic.tint(for: status, tool: tool) }
}

enum SettingsViewLogic {
    static func harnessTool(_ id: HarnessID) -> ExternalTool {
        switch id {
        case .pi: return .pi
        case .claude: return .claude
        }
    }

    static func label(for id: HarnessID, statuses: [ExternalTool: ToolStatus]) -> String {
        guard let status = statuses[harnessTool(id)] else { return id.displayName }
        guard status.isInstalled else { return "\(id.displayName) — not installed" }
        return status.version.map { "\(id.displayName) — \($0)" } ?? id.displayName
    }

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

    static func jiraLabel(jiraAvailable: Bool) -> String {
        jiraAvailable ? TrackerID.jira.displayName : "Jira — acli not found"
    }

    static func overrideNoticeText(for variable: String) -> String {
        "Overridden by \(variable) in the environment."
    }

    static func symbol(for status: ToolStatus?, tool: ExternalTool) -> String {
        guard let status else { return "circle.dotted" }
        if status.isUsable { return "checkmark.circle.fill" }
        if status.isInstalled { return "exclamationmark.triangle.fill" }
        return tool.isRequired ? "xmark.circle.fill" : "minus.circle"
    }

    static func tint(for status: ToolStatus?, tool: ExternalTool) -> Color {
        guard let status else { return .secondary }
        if status.isUsable { return .green }
        if status.isInstalled { return .orange }
        return tool.isRequired ? .red : .secondary
    }
}
