import SwiftUI

@MainActor
@Observable
final class WelcomeWizardModel {
    let preferences: Preferences
    var step: Int
    var statuses: [ExternalTool: ToolStatus] = [:]
    var isProbing = true
    var urlText: String

    private let probe: EnvironmentProbe
    private let onFinish: (String?) -> Void

    init(
        preferences: Preferences = .shared, probe: EnvironmentProbe = EnvironmentProbe(), step: Int = 0,
        urlText: String = "", onFinish: @escaping (String?) -> Void
    ) {
        self.preferences = preferences
        self.probe = probe
        self.step = step
        self.urlText = urlText
        self.onFinish = onFinish
    }

    var needsHarnessChoice: Bool {
        WelcomeWizardLogic.needsHarnessChoice(installedHarnesses: preferences.installedHarnesses)
    }

    var blocker: String? {
        WelcomeWizardLogic.blocker(
            statuses: statuses, installedHarnesses: preferences.installedHarnesses,
            resolvedHarness: preferences.resolvedHarness
        )
    }

    var readySummary: String {
        WelcomeWizardLogic.readySummary(
            resolvedHarness: preferences.resolvedHarness, ghUsable: statuses[.gh]?.isUsable == true,
            resolvedTracker: preferences.resolvedTracker
        )
    }

    func goBack() { step -= 1 }

    func goForward() { step += 1 }

    func finish() {
        guard WelcomeWizardLogic.canFinish(urlText: urlText) else { return }
        preferences.hasCompletedOnboarding = true
        onFinish(urlText.isEmpty ? nil : urlText)
    }

    func refresh() async {
        isProbing = true
        defer { isProbing = false }
        let found = await probe.probeAll()
        statuses = found
        preferences.installedHarnesses = found.installedHarnesses
        preferences.jiraAvailable = found.jiraAvailable
    }
}

struct WelcomeWizard: View {
    @State private var model: WelcomeWizardModel

    init(model: WelcomeWizardModel) {
        _model = State(initialValue: model)
    }

    init(onFinish: @escaping (String?) -> Void) {
        self.init(model: WelcomeWizardModel(onFinish: onFinish))
    }

    private var preferences: Preferences { model.preferences }
    private var step: Int { model.step }
    private var statuses: [ExternalTool: ToolStatus] { model.statuses }
    private var isProbing: Bool { model.isProbing }
    private var needsHarnessChoice: Bool { model.needsHarnessChoice }
    private var blocker: String? { model.blocker }
    private var readySummary: String { model.readySummary }
    private var urlText: String { model.urlText }
    private func finish() { model.finish() }
    private func refresh() async { await model.refresh() }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 620, minHeight: 520)
        .task { await refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch WelcomeWizardLogic.pane(forStep: step) {
        case .intro: introPane
        case .environment: environmentPane
        case .firstPR: firstPRPane
        }
    }

    private var introPane: some View {
        VStack(spacing: 0) {
            Spacer()
            ContourMarkView()
                .frame(height: ContourMarkView.heroHeight)
            Text("Contour")
                .font(.system(size: 28, weight: .semibold))
                .padding(.top, 22)
            Text("Understand the change, not just the diff.")
                .font(.title3)
                .padding(.top, 10)
            Text(
                """
                Contour reads a pull request, checks it out locally, and works out \
                what changed and why — the decisions made, the tradeoffs taken, the flows \
                affected — so review is about judgment rather than re-reading every line.

                Every statement is tagged as observed fact, author claim, or AI \
                interpretation, so you always know what's grounded in the code.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
            .padding(.top, 18)
            Spacer()
            Spacer().frame(height: 40)
        }
    }

    private var environmentPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What's on this machine")
                    .font(.title2.weight(.semibold))
                Text(
                    "Contour drives tools you've already installed and signed in to. It stores no credentials of its own."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ExternalTool.allCases, id: \.self) { tool in
                        VStack(alignment: .leading, spacing: 3) {
                            ToolStatusRow(status: statuses[tool], tool: tool)
                            Text(tool.role)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 26)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if needsHarnessChoice {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Which harness should Contour use?")
                        .font(.callout.weight(.medium))
                    Picker(
                        "",
                        selection: Binding(
                            get: { preferences.resolvedHarness },
                            set: { preferences.storedHarness = $0 }
                        )
                    ) {
                        ForEach(preferences.installedHarnesses, id: \.self) { id in
                            Text(id.displayName).tag(Optional(id))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if preferences.jiraAvailable {
                Toggle(
                    "Use Jira for issue lookup instead of GitHub issues",
                    isOn: Binding(
                        get: { preferences.resolvedTracker == .jira },
                        set: { preferences.storedTracker = $0 ? .jira : .github }
                    )
                )
                .font(.callout)
            }

            HStack {
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Re-check", systemImage: "arrow.clockwise")
                }
                .disabled(isProbing)
                if isProbing { ProgressView().controlSize(.small) }
                Spacer()
            }

            if let blocker {
                Label(blocker, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var firstPRPane: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Ready").font(.title2.weight(.semibold))
            Text(readySummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            TextField("https://github.com/owner/repo/pull/123", text: $model.urlText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 420)
                .onSubmit(finish)

            Text("Public pull requests work with no further setup. You can change any of this later in Settings (⌘,).")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { model.goBack() }
            }
            Spacer()
            Text("\(step + 1) of 3")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            if step < 2 {
                Button("Continue") { model.goForward() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(WelcomeWizardLogic.continueDisabled(step: step, blocker: blocker))
            } else {
                Button(WelcomeWizardLogic.finishButtonTitle(urlText: urlText), action: finish)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(!WelcomeWizardLogic.canFinish(urlText: urlText))
            }
        }
    }
}

enum WelcomeWizardLogic {
    enum Pane: Equatable {
        case intro, environment, firstPR
    }

    static func pane(forStep step: Int) -> Pane {
        switch step {
        case 0: return .intro
        case 1: return .environment
        default: return .firstPR
        }
    }

    static func needsHarnessChoice(installedHarnesses: [HarnessID]) -> Bool {
        installedHarnesses.count > 1
    }

    static func blocker(
        statuses: [ExternalTool: ToolStatus], installedHarnesses: [HarnessID], resolvedHarness: HarnessID?
    ) -> String? {
        if statuses[.git]?.isInstalled == false {
            return "git is required — Contour checks the PR out locally so analysis reads real code."
        }
        if installedHarnesses.isEmpty {
            return "No AI harness found. Install pi or Claude Code, then re-check."
        }
        if resolvedHarness == nil {
            return "Pick a harness to continue."
        }
        return nil
    }

    static func readySummary(resolvedHarness: HarnessID?, ghUsable: Bool, resolvedTracker: TrackerID) -> String {
        let harness = resolvedHarness?.displayName ?? "no harness"
        let github = ghUsable ? "gh (public and private PRs)" : "anonymous API (public PRs)"
        return
            "Analyzing with \(harness), reading GitHub via \(github), and looking up issues in \(resolvedTracker.displayName)."
    }

    static func canFinish(urlText: String) -> Bool {
        urlText.isEmpty || GitHubService.normalize(urlText) != nil
    }

    static func continueDisabled(step: Int, blocker: String?) -> Bool {
        step == 1 && blocker != nil
    }

    static func finishButtonTitle(urlText: String) -> String {
        urlText.isEmpty ? "Finish" : "Open PR"
    }
}
