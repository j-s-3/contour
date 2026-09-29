import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
@Suite(.serialized)
struct ContentViewActionsTests {

    private func reviewStore() -> GraphStore {
        let store = GraphStore(phase: .opening)
        store.handle(.graph(ContourSampleData.publishTriggeredReindex))
        return store
    }

    private func session() -> PRSessionActions {
        PRSessionActions(hasOpenPR: false, pullRequestURL: nil, openDifferent: {}, close: {})
    }

    @Test func loadRecordsTheRequestedPullRequestAndOpens() {
        let store = GraphStore()
        ContentViewActions(store: store).load("not-a-pull-request")
        #expect(store.lastPRURL == "not-a-pull-request")
        #expect(store.phase != .idle)
        store.close()
        #expect(store.phase == .idle)
    }

    @Test func closeAndReopenReturnToTheStartScreenWithoutAPreviousURL() {
        let store = reviewStore()
        let actions = ContentViewActions(store: store)
        actions.reopen()
        #expect(store.phase == .idle)
        store.handle(.graph(ContourSampleData.publishTriggeredReindex))
        actions.close()
        #expect(store.phase == .idle)
    }

    @Test func backAndForwardWalkTheNavigationStack() {
        let store = reviewStore()
        let actions = ContentViewActions(store: store)
        actions.navigate(.decisions)
        #expect(store.current == .decisions)
        actions.goBack()
        #expect(store.current == .summary)
        actions.goForward()
        #expect(store.current == .decisions)
        actions.navigateAction(.flows)()
        #expect(store.current == .flows)
        let ref = CodeRef(path: "a.swift", startLine: 1, endLine: 2)
        actions.openEvidence(ref)
        #expect(store.current == .evidence(ref))
    }

    @Test func copyingTheSummaryPutsMarkdownOnThePasteboard() {
        let store = reviewStore()
        NSPasteboard.general.clearContents()
        ContentViewActions(store: store).copyReviewSummary()
        #expect(NSPasteboard.general.string(forType: .string)?.isEmpty == false)
    }

    @Test func openingOnGitHubWithoutALinkDoesNothing() {
        let store = GraphStore()
        let actions = ContentViewActions(store: store)
        actions.openOnGitHub()
        actions.openOnGitHub(session())()
        actions.copyLink(session())()
        #expect(store.pullRequestWebURL == nil)
    }

    @Test func stoppingAndRetryingWithoutAPipelineFallBackSafely() {
        let store = reviewStore()
        let actions = ContentViewActions(store: store)
        actions.stopAnalysis()
        #expect(store.phase == .review)
        actions.retryAction(.decisions)()
        #expect(store.phase == .idle)
        store.handle(.graph(ContourSampleData.publishTriggeredReindex))
        actions.retry(.flows)
        #expect(store.phase == .idle)
    }

    @Test func submittingAReviewWithoutAPullRequestLinkLeavesTheReviewIdle() {
        let store = GraphStore()
        let actions = ContentViewActions(store: store)
        actions.approve()
        actions.requestChanges("please fix")
        #expect(store.review == .idle)
    }

    @Test func togglingConversationsOpensThenClosesTheInspector() {
        let store = reviewStore()
        let actions = ContentViewActions(store: store)
        actions.toggleConversations()
        #expect(store.conversations.isPresented)
        actions.toggleConversations()
        #expect(!store.conversations.isPresented)
    }

    @Test func conversationsBindingReadsAndWritesTheInspectorState() {
        let store = reviewStore()
        let binding = ContentViewActions(store: store).conversationsPresented()
        #expect(!binding.wrappedValue)
        binding.wrappedValue = true
        #expect(store.conversations.isPresented)
        #expect(binding.wrappedValue)
    }

    @Test func askActionOpensAThreadAboutThePullRequest() {
        let store = GraphStore()
        ContentViewActions(store: store).askAction("Why?")()
        #expect(store.conversations.active?.subject == .pullRequest)
    }

    @Test func decisionEditsReachTheStoreThroughTheActions() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.decisions = [
            DecisionNode(id: "d1", title: "D1", decision: Statement(text: "x", provenance: .fact), confidence: .high)
        ]
        let store = GraphStore(phase: .opening)
        store.handle(.graph(graph))
        let actions = ContentViewActions(store: store)
        actions.setReviewerState("d1", .accepted)
        actions.setReviewerNote("d1", "looks fine")
        actions.setToReview("d1", false)
        let unplaced = store.graph?.decisions.first?.reviewerPlacement
        actions.setToReview("d1", true)
        let placed = store.graph?.decisions.first?.reviewerPlacement
        let decision = store.graph?.decisions.first
        #expect(decision?.reviewerState == .accepted)
        #expect(decision?.reviewerNote == "looks fine")
        #expect(unplaced != placed)
    }

    @Test func turnOnSetsTheFlag() {
        var flag = false
        let binding = Binding(get: { flag }, set: { flag = $0 })
        ContentViewActions(store: GraphStore()).turnOn(binding)()
        #expect(flag)
    }

    @Test func openDifferentClosesTheSessionAndRequestsFocus() {
        let store = reviewStore()
        var focus = 0
        let binding = Binding(get: { focus }, set: { focus = $0 })
        ContentViewActions(store: store).openDifferent(focusRequest: binding)()
        #expect(store.phase == .idle)
        #expect(focus == 1)
    }

    @Test func finishingOnboardingClearsTheFlagAndOpensTheFirstPullRequest() {
        let store = GraphStore()
        var needsOnboarding = true
        let binding = Binding(get: { needsOnboarding }, set: { needsOnboarding = $0 })
        let finish = ContentViewActions(store: store).finishOnboarding(binding)
        finish(nil)
        #expect(!needsOnboarding)
        #expect(store.lastPRURL == nil)
        finish("not-a-pull-request")
        #expect(store.lastPRURL == "not-a-pull-request")
        store.close()
    }

    @Test func openingALinkIgnoresDuringOnboardingAndNonPullRequestLinks() throws {
        let pullRequest = try #require(URL(string: "https://github.com/octo/repo/pull/7"))
        let other = try #require(URL(string: "https://example.com/nothing"))
        let store = GraphStore()
        let actions = ContentViewActions(store: store)
        actions.openLink(needsOnboarding: true)(pullRequest)
        actions.openLink(needsOnboarding: false)(other)
        #expect(store.lastPRURL == nil)
    }

    @Test func requestChangesSheetIsTitledForThePullRequest() {
        let graph = ContourSampleData.publishTriggeredReindex
        let sheet = ContentViewActions(store: GraphStore()).requestChangesSheet(for: graph)()
        #expect(sheet.title == "Request changes on \(graph.pr.repo) #\(graph.pr.number)")
        sheet.onSubmit("comment")
    }

    @Test func reviewFailureBindingIsPresentedOnlyWhileFailedAndDismissesTheFailure() {
        let store = GraphStore(phase: .opening, review: .failed(.approve, "nope"))
        let binding = ContentViewActions(store: store).reviewFailurePresented()
        #expect(binding.wrappedValue)
        binding.wrappedValue = true
        #expect(store.review == .failed(.approve, "nope"))
        binding.wrappedValue = false
        #expect(store.review == .idle)
        #expect(!binding.wrappedValue)
    }

    @Test func acknowledgeChangesNothing() {
        let store = reviewStore()
        ContentViewActions(store: store).acknowledge()
        #expect(store.phase == .review)
    }
}
