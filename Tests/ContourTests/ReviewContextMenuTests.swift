import Testing
import Foundation
import SwiftUI
import AppKit
@testable import Contour

/// `ReviewContextMenuLogic`'s "which items, how many" selection is the menu-enablement
/// logic CLAUDE.md calls out for this file; `GraphStore.canSubmitReview`/
/// `.reviewUnavailableReason` (tied to `Services/PRReview.swift`) are the other half,
/// already plain functions needing no production change.
///
/// Follow-up (issue #117 reopened at 23.83%): pulled the rest of `ReviewContextMenuModifier`'s
/// button-visibility/label decisions (`showsTradeoffQuestion`, `detailButton`, `diffRef`,
/// `showInCodeTitle`, `codeRefMenuItems`) into `ReviewContextMenuLogic` the same way #171 did
/// for the related-item menus, and added coverage for `ReviewActions`'s remaining branch and
/// the `GraphStore` extension members this file also defines (`pullRequestWebURL`,
/// `copyReviewSummary`, `openOnGitHub`'s no-op guard, the shortcut constants). `NSPasteboard`
/// writes are driven for real, following `PRSessionCommandsTests`' precedent; `NSWorkspace
/// .shared.open` is only ever exercised past its nil guard, for the same reason that suite
/// gives (it would launch a real browser from CI). `.serialized` because `NSPasteboard
/// .general` is a process-wide resource, like that suite's.
@Suite(.serialized)
struct ReviewContextMenuTests {

    private func minimalGraph(components: [ComponentNode] = [], decisions: [DecisionNode] = [],
                               flows: [FlowNode] = [], headSha: String = "h", baseSha: String = "b") -> PRGraph {
        let pr = PRSummary(
            repo: "acme/shop", number: 7, title: "t", author: "a", state: "OPEN",
            branch: "feature", baseBranch: "main", headSha: headSha, baseSha: baseSha,
            intent: Statement(text: "x", provenance: .fact), filesChanged: 1, additions: 1, deletions: 1
        )
        return PRGraph(pr: pr, components: components, decisions: decisions, flows: flows)
    }

    private func resolved(kind: SubjectKind, componentIds: [String] = [], decisionIds: [String] = [],
                           flowIds: [String] = [], refs: [CodeRef] = []) -> ResolvedSubject {
        ResolvedSubject(subject: .pullRequest, kind: kind, title: "T", lineage: [], summary: [], detail: "",
                        componentIds: componentIds, decisionIds: decisionIds, flowIds: flowIds, refs: refs)
    }

    // MARK: - ReviewContextMenuLogic.architectureParts

    @Test func architectureExcludesComponentRelationshipAndPullRequestKinds() {
        let graph = minimalGraph(components: [ComponentNode(id: "c", title: "C", changeKind: .unchanged)])
        for kind: SubjectKind in [.component, .relationship, .pullRequest] {
            #expect(ReviewContextMenuLogic.architectureParts(for: resolved(kind: kind, componentIds: ["c"]), in: graph).isEmpty)
        }
    }

    @Test func architecturePartsResolvesEveryComponentIdThatExistsAndDeduplicates() {
        let graph = minimalGraph(components: [
            ComponentNode(id: "a", title: "A", changeKind: .unchanged),
            ComponentNode(id: "b", title: "B", changeKind: .unchanged),
        ])
        let subject = resolved(kind: .decision, componentIds: ["a", "a", "b", "missing"])
        #expect(Set(ReviewContextMenuLogic.architectureParts(for: subject, in: graph).map(\.id)) == ["a", "b"])
    }

    // MARK: - ReviewContextMenuLogic.relatedDecisions

    @Test func relatedDecisionsExcludesDecisionAndTradeoffKinds() {
        let graph = minimalGraph(decisions: [
            DecisionNode(id: "d", title: "D", decision: Statement(text: "x", provenance: .fact), confidence: .high),
        ])
        for kind: SubjectKind in [.decision, .tradeoff] {
            #expect(ReviewContextMenuLogic.relatedDecisions(for: resolved(kind: kind, decisionIds: ["d"]), in: graph).isEmpty)
        }
    }

    @Test func relatedDecisionsResolvesEveryDecisionIdThatExists() {
        let graph = minimalGraph(decisions: [
            DecisionNode(id: "d", title: "D", decision: Statement(text: "x", provenance: .fact), confidence: .high),
        ])
        let subject = resolved(kind: .component, decisionIds: ["d", "missing"])
        #expect(ReviewContextMenuLogic.relatedDecisions(for: subject, in: graph).map(\.id) == ["d"])
    }

    // MARK: - ReviewContextMenuLogic.relatedFlows

    @Test func relatedFlowsExcludesFlowAndFlowStepKinds() {
        let graph = minimalGraph(flows: [FlowNode(id: "f", title: "F")])
        for kind: SubjectKind in [.flow, .flowStep] {
            #expect(ReviewContextMenuLogic.relatedFlows(for: resolved(kind: kind, flowIds: ["f"]), in: graph).isEmpty)
        }
    }

    @Test func relatedFlowsResolvesEveryFlowIdThatExists() {
        let graph = minimalGraph(flows: [FlowNode(id: "f", title: "F")])
        let subject = resolved(kind: .component, flowIds: ["f", "missing"])
        #expect(ReviewContextMenuLogic.relatedFlows(for: subject, in: graph).map(\.id) == ["f"])
    }

    // MARK: - ReviewContextMenuLogic.githubURL

    @Test func menuGithubURLPrefersALinePermalinkOverThePullRequestFallback() {
        let actions = ReviewActions(graph: minimalGraph(), prURL: "https://github.com/acme/shop/pull/7")
        let subject = resolved(kind: .code, refs: [CodeRef(path: "a.swift", startLine: 1, endLine: 1)])
        #expect(ReviewContextMenuLogic.githubURL(for: subject, actions: actions)?.absoluteString.hasSuffix("#L1") == true)
    }

    @Test func menuGithubURLFallsBackToThePullRequestWhenThereIsNoRef() {
        let actions = ReviewActions(graph: minimalGraph(), prURL: "https://github.com/acme/shop/pull/7")
        #expect(ReviewContextMenuLogic.githubURL(for: resolved(kind: .decision), actions: actions)?.absoluteString
                == "https://github.com/acme/shop/pull/7")
    }

    // MARK: - ReviewActions.repoWebBase

    @Test func repoWebBaseStripsThePullSuffixFromTheOpenedURL() {
        let actions = ReviewActions(graph: nil, prURL: "https://github.example.com/acme/widgets/pull/42")
        #expect(actions.repoWebBase == "https://github.example.com/acme/widgets")
    }

    @Test func repoWebBaseFallsBackToGitHubFromTheGraphWithNoOpenedURL() {
        let actions = ReviewActions(graph: minimalGraph(), prURL: nil)
        #expect(actions.repoWebBase == "https://github.com/acme/shop")
    }

    @Test func repoWebBaseIsNilWithNeitherAURLNorAGraph() {
        #expect(ReviewActions(graph: nil, prURL: nil).repoWebBase == nil)
    }

    // MARK: - ReviewActions.githubURL(for:)

    @Test func githubURLForRefUsesTheHeadOrBaseShaAccordingToTheRefsSide() {
        let actions = ReviewActions(graph: minimalGraph(headSha: "headsha", baseSha: "basesha"), prURL: nil)
        let headRef = CodeRef(path: "a.swift", startLine: 3, endLine: 3, side: .head)
        let baseRef = CodeRef(path: "a.swift", startLine: 3, endLine: 3, side: .base)
        #expect(actions.githubURL(for: headRef)?.absoluteString.contains("/blob/headsha/") == true)
        #expect(actions.githubURL(for: baseRef)?.absoluteString.contains("/blob/basesha/") == true)
    }

    @Test func githubURLForRefUsesARangeWhenTheLinesDiffer() {
        let actions = ReviewActions(graph: minimalGraph(), prURL: nil)
        let ref = CodeRef(path: "a.swift", startLine: 10, endLine: 20)
        #expect(actions.githubURL(for: ref)?.absoluteString.hasSuffix("#L10-L20") == true)
    }

    @Test func githubURLForRefIsNilWithoutAGraphOrOpenedURL() {
        let actions = ReviewActions(graph: nil, prURL: nil)
        #expect(actions.githubURL(for: CodeRef(path: "a.swift", startLine: 1, endLine: 1)) == nil)
    }

    // MARK: - GraphStore.canSubmitReview / reviewUnavailableReason

    /// Only the branches independent of whether `gh` is actually installed on the machine
    /// running the test are asserted here, same constraint as `ReviewRequestsTests`.
    @MainActor
    @Test func canSubmitReviewIsFalseWithNoGraphLoaded() {
        #expect(!GraphStore().canSubmitReview(.approve))
        #expect(!GraphStore().canSubmitReview(.requestChanges))
    }

    @MainActor
    @Test func reviewUnavailableReasonNamesTheMissingPRWithNoGraphLoaded() {
        #expect(GraphStore().reviewUnavailableReason(.approve) == "No pull request is open")
    }

    /// With a graph loaded, `canSubmitReview` reduces to `PRReview.canReview`; asserted by
    /// recomputing the same inputs rather than a hardcoded bool, since whether `gh` is on
    /// the CI runner's PATH isn't something this suite controls.
    @MainActor
    @Test func canSubmitReviewWithAGraphMatchesPRReviewCanReviewForBothVerdicts() {
        let store = GraphStore()
        store.handle(.graph(minimalGraph()))
        for verdict: PRReview.Verdict in [.approve, .requestChanges] {
            #expect(store.canSubmitReview(verdict) == PRReview.canReview(prState: "OPEN", ghAvailable: GraphStore.ghAvailable))
        }
    }

    /// Same machine-independence concern as above: with a graph loaded and no review
    /// submitted yet, the reason is either the "no gh" message or nil (an open PR, reviewable),
    /// never the "no pull request"/"not open" messages, which is itself worth pinning.
    @MainActor
    @Test func reviewUnavailableReasonWithAnOpenGraphNeverBlamesTheMissingOrClosedPR() {
        let store = GraphStore()
        store.handle(.graph(minimalGraph()))
        let reason = store.reviewUnavailableReason(.approve)
        if GraphStore.ghAvailable {
            #expect(reason == nil)
        } else {
            #expect(reason == "Reviewing needs the GitHub CLI — install gh and run `gh auth login`")
        }
    }

    // MARK: - ReviewContextMenuLogic.showsTradeoffQuestion

    @Test func showsTradeoffQuestionOnlyForTradeoffKind() {
        #expect(ReviewContextMenuLogic.showsTradeoffQuestion(for: .tradeoff))
        for kind: SubjectKind in [.decision, .component, .flow, .code] {
            #expect(!ReviewContextMenuLogic.showsTradeoffQuestion(for: kind))
        }
    }

    // MARK: - ReviewContextMenuLogic.detailButton

    @Test func detailButtonIsNilForATradeoffEvenWithADetailTarget() {
        let subject = ResolvedSubject(subject: .pullRequest, kind: .tradeoff, title: "T", lineage: [],
                                       summary: [], detail: "", detailTarget: .summary)
        #expect(ReviewContextMenuLogic.detailButton(for: subject) == nil)
    }

    @Test func detailButtonIsNilWithoutADetailTarget() {
        let subject = ResolvedSubject(subject: .pullRequest, kind: .decision, title: "T", lineage: [],
                                       summary: [], detail: "", detailTarget: nil)
        #expect(ReviewContextMenuLogic.detailButton(for: subject) == nil)
    }

    @Test func detailButtonLabelsCodeAsShowInCodeAndEverythingElseAsOpenDetails() {
        let code = ResolvedSubject(subject: .pullRequest, kind: .code, title: "T", lineage: [],
                                    summary: [], detail: "", detailTarget: .summary)
        let decision = ResolvedSubject(subject: .pullRequest, kind: .decision, title: "T", lineage: [],
                                        summary: [], detail: "", detailTarget: .decisionDetail("d"))
        #expect(ReviewContextMenuLogic.detailButton(for: code)?.label == "Show in code")
        #expect(ReviewContextMenuLogic.detailButton(for: code)?.target == .summary)
        #expect(ReviewContextMenuLogic.detailButton(for: decision)?.label == "Open details")
        #expect(ReviewContextMenuLogic.detailButton(for: decision)?.target == .decisionDetail("d"))
    }

    // MARK: - ReviewContextMenuLogic.diffRef

    @Test func diffRefIsTheRefOnlyForACodeKindResolvedFromACodeRefSubject() {
        let ref = CodeRef(path: "a.swift", startLine: 4, endLine: 4)
        let codeSubject = resolved(kind: .code)
        #expect(ReviewContextMenuLogic.diffRef(for: codeSubject, subject: .codeRef(ref)) == ref)
    }

    @Test func diffRefIsNilForANonCodeKindEvenFromACodeRefSubject() {
        let ref = CodeRef(path: "a.swift", startLine: 4, endLine: 4)
        let decisionSubject = resolved(kind: .decision)
        #expect(ReviewContextMenuLogic.diffRef(for: decisionSubject, subject: .codeRef(ref)) == nil)
    }

    @Test func diffRefIsNilForACodeKindNotResolvedFromACodeRefSubject() {
        let codeSubject = resolved(kind: .code)
        #expect(ReviewContextMenuLogic.diffRef(for: codeSubject, subject: .decision("d")) == nil)
    }

    // MARK: - ReviewContextMenuLogic.showInCodeTitle

    @Test func showInCodeTitleIsShowEvidenceForATradeoffAndShowInCodeOtherwise() {
        #expect(ReviewContextMenuLogic.showInCodeTitle(for: .tradeoff) == "Show Evidence")
        #expect(ReviewContextMenuLogic.showInCodeTitle(for: .decision) == "Show in Code")
        #expect(ReviewContextMenuLogic.showInCodeTitle(for: .code) == "Show in Code")
    }

    // MARK: - ReviewContextMenuLogic.codeRefMenuItems

    @Test func codeRefMenuItemsCapsAtTwelveRefsToKeepTheSubmenuUsable() {
        let refs = (0..<20).map { CodeRef(path: "a.swift", startLine: $0, endLine: $0) }
        let subject = resolved(kind: .decision, refs: refs)
        #expect(ReviewContextMenuLogic.codeRefMenuItems(for: subject).count == 12)
        #expect(ReviewContextMenuLogic.codeRefMenuItems(for: subject).map(\.startLine) == Array(0..<12))
    }

    @Test func codeRefMenuItemsPassesThroughFewerThanTwelveRefsUnchanged() {
        let refs = [CodeRef(path: "a.swift", startLine: 1, endLine: 1), CodeRef(path: "a.swift", startLine: 2, endLine: 2)]
        let subject = resolved(kind: .decision, refs: refs)
        #expect(ReviewContextMenuLogic.codeRefMenuItems(for: subject) == refs)
    }

    // MARK: - ReviewActions.pullRequestURL (graph fallback, no opened URL)

    @Test func pullRequestURLFallsBackToTheGraphsRepoAndNumberWithNoOpenedURL() {
        let actions = ReviewActions(graph: minimalGraph(), prURL: nil)
        #expect(actions.pullRequestURL?.absoluteString == "https://github.com/acme/shop/pull/7")
    }

    @Test func pullRequestURLIsNilWithNeitherAURLNorAGraph() {
        #expect(ReviewActions(graph: nil, prURL: nil).pullRequestURL == nil)
    }

    // MARK: - Keyboard shortcuts

    /// Pins the exact shortcuts CLAUDE.md and this file's own doc comments name: ⌘⇧A for
    /// "Ask about this…", ⌘⇧O for "Open on GitHub".
    @Test func askShortcutIsCommandShiftA() {
        #expect(AskShortcut.key == KeyEquivalent("a"))
        #expect(AskShortcut.modifiers == [.command, .shift])
    }

    @Test func openOnGitHubShortcutIsCommandShiftO() {
        #expect(OpenOnGitHubShortcut.key == KeyEquivalent("o"))
        #expect(OpenOnGitHubShortcut.modifiers == [.command, .shift])
    }

    // MARK: - GraphStore.pullRequestWebURL / copyReviewSummary / openOnGitHub

    @MainActor
    @Test func pullRequestWebURLIsNilWithNoGraphLoaded() {
        #expect(GraphStore().pullRequestWebURL == nil)
    }

    @MainActor
    @Test func pullRequestWebURLFallsBackToTheGraphsRepoWithNoLastPRURL() {
        let store = GraphStore()
        store.handle(.graph(minimalGraph()))
        #expect(store.pullRequestWebURL?.absoluteString == "https://github.com/acme/shop/pull/7")
    }

    @MainActor
    @Test func copyReviewSummaryWithNoGraphLeavesThePasteboardAlone() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("unrelated", forType: .string)

        GraphStore().copyReviewSummary()

        #expect(pasteboard.string(forType: .string) == "unrelated")
    }

    @MainActor
    @Test func copyReviewSummaryWithAGraphPutsItsMarkdownOnThePasteboard() {
        let graph = minimalGraph()
        let store = GraphStore()
        store.handle(.graph(graph))

        store.copyReviewSummary()

        #expect(NSPasteboard.general.string(forType: .string) == graph.reviewSummaryMarkdown)
    }

    /// `openOnGitHub()` is only exercised past its nil guard here — calling it for real with
    /// a graph loaded would invoke `NSWorkspace.shared.open` and launch a browser from CI,
    /// the same caution `PRSessionCommandsTests` documents for the equivalent method there.
    @MainActor
    @Test func openOnGitHubDoesNothingWithNoGraphLoaded() {
        GraphStore().openOnGitHub()
    }
}
