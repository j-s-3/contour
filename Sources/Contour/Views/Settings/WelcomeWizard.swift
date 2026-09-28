import SwiftUI

/// First-run setup. Three panes: what Contour does, what it found on this machine, and
/// the first PR URL.
///
/// The middle pane is the point of the wizard. Contour drives external CLIs, so what's
/// installed determines what works, and discovering that mid-pipeline — minutes into a
/// run — is the failure mode this exists to prevent.
struct WelcomeWizard: View {
    @State private var preferences = Preferences.shared
    @State private var step = 0
    @State private var statuses: [ExternalTool: ToolStatus] = [:]
    @State private var isProbing = true
    @State private var urlText = ""

    private let probe = EnvironmentProbe()

    /// Called with the first PR URL once setup is done, so the wizard hands straight off
    /// to a real review rather than dead-ending on a "you're all set" screen.
    var onFinish: (String?) -> Void

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
        switch step {
        case 0: introPane
        case 1: environmentPane
        default: firstPRPane
        }
    }

    // MARK: - Pane 1

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
            Text("""
                 Contour reads a pull request, checks it out locally, and works out \
                 what changed and why — the decisions made, the tradeoffs taken, the flows \
                 affected — so review is about judgment rather than re-reading every line.

                 Every statement is tagged as observed fact, author claim, or AI \
                 interpretation, so you always know what's grounded in the code.
                 """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .padding(.top, 18)
            Spacer()
            Spacer().frame(height: 40)
        }
    }

    // MARK: - Pane 2

    private var environmentPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What's on this machine")
                    .font(.title2.weight(.semibold))
                Text("Contour drives tools you've already installed and signed in to. It stores no credentials of its own.")
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
                    Picker("", selection: Binding(
                        get: { preferences.resolvedHarness },
                        set: { preferences.storedHarness = $0 }
                    )) {
                        ForEach(preferences.installedHarnesses, id: \.self) { id in
                            Text(id.displayName).tag(Optional(id))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if preferences.jiraAvailable {
                Toggle("Use Jira for issue lookup instead of GitHub issues", isOn: Binding(
                    get: { preferences.resolvedTracker == .jira },
                    set: { preferences.storedTracker = $0 ? .jira : .github }
                ))
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

    /// Only ask when the answer isn't already determined: nothing stored, and more than
    /// one harness to choose between.
    private var needsHarnessChoice: Bool {
        WelcomeWizardLogic.needsHarnessChoice(installedHarnesses: preferences.installedHarnesses)
    }

    /// The two things that genuinely prevent a review from running.
    private var blocker: String? {
        WelcomeWizardLogic.blocker(
            statuses: statuses, installedHarnesses: preferences.installedHarnesses,
            resolvedHarness: preferences.resolvedHarness
        )
    }

    // MARK: - Pane 3

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

            TextField("https://github.com/owner/repo/pull/123", text: $urlText)
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

    private var readySummary: String {
        WelcomeWizardLogic.readySummary(
            resolvedHarness: preferences.resolvedHarness, ghUsable: statuses[.gh]?.isUsable == true,
            resolvedTracker: preferences.resolvedTracker
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Spacer()
            Text("\(step + 1) of 3")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            if step < 2 {
                Button("Continue") { step += 1 }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(step == 1 && blocker != nil)
            } else {
                Button(urlText.isEmpty ? "Finish" : "Open PR", action: finish)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(!urlText.isEmpty && GitHubService.normalize(urlText) == nil)
            }
        }
    }

    private func finish() {
        guard WelcomeWizardLogic.canFinish(urlText: urlText) else { return }
        preferences.hasCompletedOnboarding = true
        onFinish(urlText.isEmpty ? nil : urlText)
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

/// The step-validation and precedence-derivation logic CLAUDE.md calls out for this file,
/// pulled out of `WelcomeWizard`'s body so it's directly testable against simulated
/// `EnvironmentProbe`/`Preferences` results rather than the SwiftUI `body`.
enum WelcomeWizardLogic {
    /// Only ask when the answer isn't already determined: nothing stored, and more than
    /// one harness to choose between.
    static func needsHarnessChoice(installedHarnesses: [HarnessID]) -> Bool {
        installedHarnesses.count > 1
    }

    /// The two things that genuinely prevent a review from running.
    static func blocker(statuses: [ExternalTool: ToolStatus], installedHarnesses: [HarnessID], resolvedHarness: HarnessID?) -> String? {
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

    /// The closing pane's one-sentence summary of what Contour is set up to do.
    static func readySummary(resolvedHarness: HarnessID?, ghUsable: Bool, resolvedTracker: TrackerID) -> String {
        let harness = resolvedHarness?.displayName ?? "no harness"
        let github = ghUsable ? "gh (public and private PRs)" : "anonymous API (public PRs)"
        return "Analyzing with \(harness), reading GitHub via \(github), and looking up issues in \(resolvedTracker.displayName)."
    }

    /// The URL field is optional — empty is fine — but a non-empty value must be a PR link.
    static func canFinish(urlText: String) -> Bool {
        urlText.isEmpty || GitHubService.normalize(urlText) != nil
    }
}
