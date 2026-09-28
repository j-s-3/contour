import Testing
import Foundation
@testable import Contour

/// `ReviewContextMenuLogic`'s "which items, how many" selection is the menu-enablement
/// logic CLAUDE.md calls out for this file; `GraphStore.canSubmitReview`/
/// `.reviewUnavailableReason` (tied to `Services/PRReview.swift`) are the other half,
/// already plain functions needing no production change.
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
}
