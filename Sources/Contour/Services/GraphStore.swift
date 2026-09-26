import Foundation
import Observation

/// Where one PR session is. There is no "analyzing" phase: the review opens as soon as the
/// PR itself has been fetched (`review`), and analysis fills it in from there — its
/// progress lives in `GraphStore.analysis`, per stage, not here.
enum SessionPhase: Equatable {
    case idle
    /// Fetching the PR: the only wait before the review window appears.
    case opening
    case review
    /// Nothing to review at all — the PR couldn't be fetched.
    case failed(String)
}

/// The semantic navigation stack from §5 — "the reviewer should never lose their place
/// in the conceptual review merely because they inspected some code." Each entry is a
/// lens plus enough state to restore selection when popped back to.
enum NavigationTarget: Hashable {
    case summary
    case architecture
    case decisions
    case flows
    case files
    case diff
    case decisionDetail(String)
    /// An Overview "thing to think about", reviewed on the decision it belongs to.
    case consideration(String)
    case componentDetail(String)
    case edgeDetail(String)
    case flowDetail(String)
    /// A stage of a flow, selected in the Flows lens.
    case flowNodeDetail(flowId: String, nodeId: String)
    case evidence(CodeRef)
}

/// Holds one PR's knowledge graph plus all reviewer-session state (selection stack,
/// reviewer marks, progress log). This is the single source of truth the whole UI reads
/// (§12 "GraphStore, single source of truth").
@Observable
final class GraphStore {
    private(set) var graph: PRGraph?
    private(set) var checkout: RepoCheckout?
    private(set) var diffText: String?
    private(set) var phase: SessionPhase = .idle
    private(set) var progressLog: [PipelineProgressEntry] = []
    /// Per-stage progress of the analysis filling in the open review.
    private(set) var analysis = AnalysisState()
    private(set) var metrics: AnalysisMetrics?
    private var metricsSaved = false
    private var pipeline: AnalysisPipeline?

    /// Semantic navigation history, browser-stack style. `path.last` is what's rendered;
    /// `forwardStack` holds anything popped by `goBack()` so `goForward()` can restore it.
    /// Pushing a new target via `navigate(to:)` clears any forward history, same as a browser.
    private(set) var path: [NavigationTarget] = [.summary]
    private var forwardStack: [NavigationTarget] = []

    var current: NavigationTarget { path.last ?? .summary }

    private var runTask: Task<Void, Never>?

    /// Read once per load rather than held, so a change in Settings takes effect on the
    /// next PR without needing to rebuild the store.
    @MainActor
    private var preferences: Preferences { Preferences.shared }

    private(set) var lastPRURL: String?

    /// The harness this PR was analyzed with. Contextual chat reuses it so a conversation
    /// never talks to a different model than the one that built the review.
    private(set) var harnessID: HarnessID?

    /// Every contextual conversation for this PR (§ contextual chat).
    let conversations = ConversationStore()

    /// What "Ask about this" (⌘⇧A) means with nothing right-clicked: the element the
    /// current lens has selected, published by that lens.
    var focusedSubject: ReviewSubject?

    /// MainActor-isolated because it reads `Preferences`, which is UI-owned observable
    /// state. Every caller is a view action, so this costs nothing.
    @MainActor
    func load(prURL: String, forceRefresh: Bool = false) {
        stopAnalysis()
        phase = .opening
        progressLog = []
        graph = nil
        checkout = nil
        diffText = nil
        analysis = AnalysisState()
        metrics = AnalysisMetrics(pr: prURL)
        metricsSaved = false
        path = [.summary]
        forwardStack = []
        lastPRURL = prURL
        conversations.reset()
        focusedSubject = nil

        // Contour can't analyze anything without a harness. This is the one hard
        // requirement, and it fails here with an actionable message rather than several
        // minutes into the run.
        guard let harnessID = preferences.resolvedHarness else {
            phase = .failed("""
            No AI harness selected. Install pi or Claude Code, then pick one in             Settings (⌘,).
            """)
            return
        }
        self.harnessID = harnessID
        let pipeline = AnalysisPipeline(
            harnessID: harnessID,
            trackerID: preferences.resolvedTracker,
            githubAccess: preferences.resolvedGitHubAccess
        )

        self.pipeline = pipeline

        // One consumer, on the main actor, in the order the pipeline emitted — so a status
        // can never be overtaken by an older one, and every snapshot lands whole.
        runTask = Task { @MainActor [weak self] in
            await pipeline.start(prURL: prURL, forceRefresh: forceRefresh)
            for await event in pipeline.events {
                guard let self, !Task.isCancelled else { return }
                self.handle(event)
            }
        }
    }

    /// Opens the last PR again from scratch — what "Try again" means when opening it
    /// failed, so the reviewer never has to find and paste the URL a second time.
    @MainActor
    func reopen() {
        guard let lastPRURL else { return close() }
        load(prURL: lastPRURL)
    }

    /// Leaves the current PR: stops its analysis and returns to the URL prompt. The
    /// prompt is pre-filled with `lastPRURL`, which survives the close.
    @MainActor
    func close() {
        stopAnalysis()
        phase = .idle
    }

    /// Re-runs one failed section. Without a checkout nothing can be re-run in place (the
    /// failure was upstream of every stage), so the whole PR is reopened instead.
    @MainActor
    func retry(_ stage: PipelineStage) {
        guard let pipeline, checkout != nil else { return reopen() }
        Task { await pipeline.retry(stage) }
    }

    @MainActor
    private func stopAnalysis() {
        saveMetrics()
        runTask?.cancel()
        runTask = nil
        if let pipeline { Task { await pipeline.cancel() } }
        pipeline = nil
    }

    @MainActor
    private func handle(_ event: PipelineEvent) {
        switch event {
        case .log(let entry):
            progressLog.append(entry)
        case .status(let stage, let status):
            analysis.stages[stage] = status
            // A retried stage reopens an analysis that had finished.
            if status.isRunning, PipelineStage.analysis.contains(stage) { analysis.isComplete = false }
        case .graph(let snapshot):
            graph = snapshot.carryingReviewerState(from: graph)
            if phase == .opening { phase = .review }
        case .diff(let diff):
            diffText = diff
        case .checkout(let checkout):
            self.checkout = checkout
        case .revalidating(let head):
            analysis.revalidatingFrom = head
        case .fromCache:
            analysis.fromCache = true
            metrics?.fromCache = true
        case .complete:
            analysis.isComplete = true
        case .fatal(let message):
            if graph == nil {
                phase = .failed(message)
            } else {
                // The PR is on screen but couldn't be checked out: keep the shell and the
                // raw diff, and say why each section is empty.
                for stage in PipelineStage.analysis where analysis.status(stage) != .done {
                    analysis.stages[stage] = .failed(message)
                }
                analysis.isComplete = true
            }
        }
        metrics?.update(state: analysis, graph: graph, diffAvailable: diffText != nil)
        if analysis.isComplete { saveMetrics() }
    }

    /// Records whether the reviewer started working before the analysis finished — the
    /// measure of whether progressive opening is used rather than waited out.
    private func noteEngagement() {
        guard phase == .review, !analysis.isComplete else { return }
        metrics?.reviewerEngagedBeforeComplete = true
    }

    private func saveMetrics() {
        guard let metrics, !metricsSaved, metrics.elapsed(.prShell) != nil else { return }
        metricsSaved = true
        metrics.append()
    }

    // MARK: - Navigation

    func navigate(to target: NavigationTarget) {
        guard target != current else { return }
        noteEngagement()
        path.append(target)
        forwardStack.removeAll()
    }

    func goBack() {
        guard path.count > 1 else { return }
        forwardStack.append(path.removeLast())
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        path.append(next)
    }

    // MARK: - Contextual chat

    @MainActor
    func ask(about subject: ReviewSubject) {
        noteEngagement()
        conversations.open(subject)
    }

    /// Opens the subject's thread and asks a specific question in it straight away — for
    /// menu items like "Why did the PR choose this side?".
    @MainActor
    func ask(_ question: String, about subject: ReviewSubject) {
        let conversation = conversations.open(subject)
        send(question, in: conversation)
    }

    @MainActor
    func send(_ text: String, in conversation: Conversation) {
        noteEngagement()
        guard let graph else { return }
        conversations.send(text, in: conversation, graph: graph, checkout: checkout, harnessID: harnessID)
    }

    /// The subject implied by where the reviewer is, for ⌘⇧A with nothing selected.
    var subjectForCurrentLocation: ReviewSubject {
        if let focusedSubject { return focusedSubject }
        switch current {
        case .componentDetail(let id): return .component(id)
        case .edgeDetail(let id): return .relationship(id)
        case .decisionDetail(let id): return .decision(id)
        case .consideration(let id): return .consideration(id)
        case .flowDetail(let id): return .flow(id)
        case .flowNodeDetail(let flowId, let nodeId): return .flowNode(flowId: flowId, nodeId: nodeId)
        case .evidence(let ref): return .codeRef(ref)
        default:
            if let change = graph?.dominantBehaviorChange { return .behaviorChange(change.id) }
            return .pullRequest
        }
    }

    var canGoBack: Bool { path.count > 1 }
    var canGoForward: Bool { !forwardStack.isEmpty }

    // MARK: - Reviewer actions (§4.4 accept/question/discuss)

    func setReviewerState(_ state: ReviewerState, forDecision id: String) {
        noteEngagement()
        guard var g = graph, let idx = g.decisions.firstIndex(where: { $0.id == id }) else { return }
        g.decisions[idx].reviewerState = (g.decisions[idx].reviewerState == state) ? .unreviewed : state
        graph = g
    }

    /// "Add to review" / "Not worth reviewing": the reviewer overriding which decisions the
    /// analysis asked them to judge.
    func setToReview(_ toReview: Bool, forDecision id: String) {
        noteEngagement()
        guard var g = graph else { return }
        g.setToReview(toReview, forDecision: id)
        graph = g
    }

    func setReviewerNote(_ note: String, forDecision id: String) {
        guard var g = graph, let idx = g.decisions.firstIndex(where: { $0.id == id }) else { return }
        g.decisions[idx].reviewerNote = note
        graph = g
    }
}
