import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct WelcomeWizardRenderTests {
    private final class Finished: @unchecked Sendable {
        var value: String??
    }

    private func preferences(harnesses: [HarnessID] = [], jira: Bool = false) -> Preferences {
        let defaults = UserDefaults(suiteName: "contour.tests.\(UUID().uuidString)")!
        let prefs = Preferences(defaults: defaults, environment: [:])
        prefs.installedHarnesses = harnesses
        prefs.jiraAvailable = jira
        return prefs
    }

    private func probe(installed: Set<String>) -> EnvironmentProbe {
        EnvironmentProbe(
            operations: EnvironmentProbeOperations(
                which: { installed.contains($0) ? "/usr/bin/\($0)" : nil },
                run: { _, _ in "1.0\nextra" }
            ))
    }

    private func model(
        step: Int = 0, urlText: String = "", prefs: Preferences? = nil, installed: Set<String> = [],
        finished: Finished = Finished()
    ) -> WelcomeWizardModel {
        WelcomeWizardModel(
            preferences: prefs ?? preferences(), probe: probe(installed: installed), step: step, urlText: urlText,
            onFinish: { finished.value = .some($0) })
    }

    private func render<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    @Test func everyStepLaysOutItsPane() {
        for step in 0...2 {
            let size = render(WelcomeWizard(model: model(step: step)))
            #expect(size.width > 0 && size.height > 0)
        }
    }

    @Test func publicInitBuildsTheIntroStep() {
        _ = render(WelcomeWizard(onFinish: { _ in }))
    }

    @Test func environmentPaneLaysOutWithHarnessChoiceJiraToggleAndBlocker() async {
        let prefs = preferences(harnesses: [.pi, .claude], jira: true)
        let m = model(step: 1, prefs: prefs, installed: ["git", "pi", "claude", "acli"])
        _ = render(WelcomeWizard(model: m))
        await m.refresh()
        _ = render(WelcomeWizard(model: m))
        prefs.installedHarnesses = []
        _ = render(WelcomeWizard(model: m))
    }

    @Test func firstPRPaneLaysOutWithAndWithoutAURL() {
        _ = render(WelcomeWizard(model: model(step: 2)))
        _ = render(WelcomeWizard(model: model(step: 2, urlText: "https://github.com/acme/shop/pull/1")))
        _ = render(WelcomeWizard(model: model(step: 2, urlText: "not a pr")))
    }

    @Test func navigationMovesBetweenSteps() {
        let m = model()
        m.goForward()
        m.goForward()
        #expect(m.step == 2)
        m.goBack()
        #expect(m.step == 1)
    }

    @Test func refreshRecordsProbeResultsIntoStatusesAndPreferences() async {
        let prefs = preferences()
        let m = model(prefs: prefs, installed: ["git", "claude", "acli"])
        #expect(m.isProbing)
        await m.refresh()
        #expect(!m.isProbing)
        #expect(m.statuses[.git]?.isInstalled == true)
        #expect(prefs.installedHarnesses == [.claude])
        #expect(prefs.jiraAvailable)
        #expect(m.blocker == nil)
        #expect(m.readySummary.contains("Claude Code"))
        #expect(!m.needsHarnessChoice)
    }

    @Test func finishWithBlankURLCompletesOnboardingWithNil() {
        let prefs = preferences()
        let finished = Finished()
        let m = model(prefs: prefs, finished: finished)
        m.finish()
        #expect(prefs.hasCompletedOnboarding)
        #expect(finished.value == .some(nil))
    }

    @Test func finishWithValidURLPassesItThrough() {
        let finished = Finished()
        let url = "https://github.com/acme/shop/pull/1"
        model(urlText: url, finished: finished).finish()
        #expect(finished.value == .some(url))
    }

    @Test func finishIgnoresAnInvalidURL() {
        let prefs = preferences()
        let finished = Finished()
        model(urlText: "nonsense", prefs: prefs, finished: finished).finish()
        #expect(!prefs.hasCompletedOnboarding)
        #expect(finished.value == nil)
    }
}
