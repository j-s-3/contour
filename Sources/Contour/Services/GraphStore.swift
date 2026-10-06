import Foundation
import Observation

enum SessionPhase: Equatable {
    case idle
    case opening
    case review
    case failed(String)
}

enum StackLayerStatus: Equatable {
    case cached
}

enum NavigationTarget: Hashable {
    case summary
    case architecture
    case decisions
    case flows
    case files
    case diff
    case diffLocation(CodeRef)
    case decisionDetail(String)
    case consideration(String)
    case componentDetail(String)
    case edgeDetail(String)
    case flowDetail(String)
    case flowNodeDetail(flowId: String, nodeId: String)
    case evidence(CodeRef)

    var showsDiagram: Bool {
        switch self {
        case .architecture, .componentDetail, .edgeDetail, .flows, .flowDetail, .flowNodeDetail: return true
        default: return false
        }
    }
}

@Observable
@MainActor
final class GraphStore {
    private(set) var graph: PRGraph?
    private(set) var checkout: RepoCheckout?
    private(set) var diffText: String?
    private(set) var diffFiles: [DiffFile] = []
    private(set) var phase: SessionPhase = .idle
    private(set) var progressLog: [PipelineProgressEntry] = []
    private(set) var analysis = AnalysisState()
    private(set) var metrics: AnalysisMetrics?
    private(set) var stack: PRStack?
    private(set) var stackAnalysis: [Int: StackLayerStatus] = [:]
    private var metricsSaved = false
    private var pipeline: AnalysisPipeline?

    private(set) var path: [NavigationTarget] = [.summary]
    private var forwardStack: [NavigationTarget] = []

    var current: NavigationTarget { path.last ?? .summary }

    typealias PipelineFactory = @MainActor (HarnessID, TrackerID, GitHubAccessMode) -> AnalysisPipeline
    typealias ReviewSubmitter = @MainActor (String, PRReview.Verdict, String) async throws -> Void

    init(
        phase: SessionPhase = .idle,
        review: PRReview.State = .idle,
        preferences: Preferences = .shared,
        makePipeline: @escaping PipelineFactory = { AnalysisPipeline(harnessID: $0, trackerID: $1, githubAccess: $2) },
        metricsURL: URL = AnalysisMetrics.fileURL,
        submitReview: @escaping ReviewSubmitter = { try await PRReview.submit(prURL: $0, verdict: $1, comment: $2) },
        canUseGitHubCLI: Bool = GraphStore.ghAvailable
    ) {
        self.phase = phase
        self.review = review
        self.preferences = preferences
        self.makePipeline = makePipeline
        self.metricsURL = metricsURL
        self.reviewSubmitter = submitReview
        self.canUseGitHubCLI = canUseGitHubCLI
    }

    private var runTask: Task<Void, Never>?

    private let preferences: Preferences
    private let makePipeline: PipelineFactory
    private let metricsURL: URL
    private let reviewSubmitter: ReviewSubmitter
    let canUseGitHubCLI: Bool

    private(set) var lastPRURL: String?

    private(set) var review: PRReview.State = .idle

    private(set) var harnessID: HarnessID?

    let conversations = ConversationStore()

    var focusedSubject: ReviewSubject?

    var diagramMode: DiagramMode = .delta

    @MainActor
    func load(prURL: String, forceRefresh: Bool = false) {
        endAnalysis()
        phase = .opening
        progressLog = []
        graph = nil
        checkout = nil
        diffText = nil
        diffFiles = []
        analysis = AnalysisState()
        metrics = AnalysisMetrics(pr: prURL)
        metricsSaved = false
        path = [.summary]
        forwardStack = []
        lastPRURL = prURL
        review = .idle
        conversations.reset()
        focusedSubject = nil
        diagramMode = .delta
        stack = nil
        stackAnalysis = [:]

        guard let harnessID = preferences.resolvedHarness else {
            phase = .failed(
                """
                No AI harness selected. Install pi or Claude Code, then pick one in             Settings (⌘,).
                """)
            return
        }
        self.harnessID = harnessID
        let pipeline = makePipeline(
            harnessID, preferences.resolvedTracker, preferences.resolvedGitHubAccess)

        self.pipeline = pipeline

        runTask = Task { @MainActor [weak self] in
            await pipeline.start(prURL: prURL, forceRefresh: forceRefresh)
            for await event in pipeline.events {
                guard let self, !Task.isCancelled else { return }
                self.handle(event)
            }
        }
    }

    var hasOpenPR: Bool { phase != .idle }

    var pullRequestURL: URL? {
        guard hasOpenPR else { return nil }
        return ReviewActions(graph: graph, prURL: lastPRURL).pullRequestURL
    }

    @MainActor
    func reopen() {
        guard let lastPRURL else { return close() }
        load(prURL: lastPRURL)
    }

    @MainActor
    func close() {
        endAnalysis()
        phase = .idle
    }

    var canOpenNextLayer: Bool { stack?.layer(offset: 1) != nil }
    var canOpenPreviousLayer: Bool { stack?.layer(offset: -1) != nil }

    @MainActor
    func openLayer(_ layer: StackLayer) {
        noteEngagement()
        load(prURL: layer.url)
    }

    @MainActor
    func openNextLayer() {
        guard let next = stack?.layer(offset: 1) else { return }
        openLayer(next)
    }

    @MainActor
    func openPreviousLayer() {
        guard let previous = stack?.layer(offset: -1) else { return }
        openLayer(previous)
    }

    @MainActor
    func submitReview(_ verdict: PRReview.Verdict, comment: String = "") {
        guard canSubmitReview(verdict), PRReview.isReady(verdict, comment: comment),
            let url = pullRequestWebURL
        else { return }
        review = .submitting(verdict)
        Task { @MainActor in
            do {
                try await reviewSubmitter(url.absoluteString, verdict, comment)
                guard pullRequestWebURL == url else { return }
                review = .submitted(verdict)
            } catch {
                guard pullRequestWebURL == url else { return }
                review = .failed(verdict, error.localizedDescription)
            }
        }
    }

    func dismissReviewFailure() {
        if case .failed = review { review = .idle }
    }

    @MainActor
    func retry(_ stage: PipelineStage) {
        guard let pipeline, checkout != nil else { return reopen() }
        Task { await pipeline.retry(stage) }
    }

    var canStopAnalysis: Bool { phase == .review && pipeline != nil && analysis.canStop }

    @MainActor
    func stopAnalysis() {
        guard canStopAnalysis, let pipeline else { return }
        Task { await pipeline.stop() }
    }

    @MainActor
    private func endAnalysis() {
        saveMetrics()
        runTask?.cancel()
        runTask = nil
        if let pipeline { Task { await pipeline.cancel() } }
        pipeline = nil
    }

    @MainActor
    func handle(_ event: PipelineEvent) {
        switch event {
        case .log(let entry):
            progressLog.append(entry)
        case .status(let stage, let status):
            analysis.stages[stage] = status
            if status.isRunning, PipelineStage.analysis.contains(stage) { analysis.isComplete = false }
        case .graph(let snapshot):
            graph = snapshot.carryingReviewerState(from: graph)
            if phase == .opening { phase = .review }
        case .diff(let diff):
            diffText = diff
            diffFiles = UnifiedDiff.parse(diff)
        case .checkout(let checkout):
            self.checkout = checkout
        case .stack(let found, let cached):
            stack = found
            stackAnalysis = Dictionary(uniqueKeysWithValues: cached.map { ($0, StackLayerStatus.cached) })
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
                progressLog.append(
                    PipelineProgressEntry(
                        stage: PipelineStage.checkingOut.rawValue,
                        detail: "failed: \(message)"))
                for stage in PipelineStage.analysis where analysis.status(stage) != .done {
                    analysis.stages[stage] = .failed(stage.checkoutFailureMessage)
                }
                analysis.isComplete = true
            }
        }
        metrics?.update(state: analysis, graph: graph, diffAvailable: diffText != nil)
        if analysis.isComplete { saveMetrics() }
    }

    private func noteEngagement() {
        guard phase == .review, !analysis.isComplete else { return }
        metrics?.reviewerEngagedBeforeComplete = true
    }

    private func saveMetrics() {
        guard let metrics, !metricsSaved, metrics.elapsed(.prShell) != nil else { return }
        metricsSaved = true
        metrics.append(to: metricsURL)
    }

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

    @MainActor
    func ask(about subject: ReviewSubject) {
        noteEngagement()
        conversations.open(subject)
    }

    @MainActor
    func toggleConversations() {
        if conversations.isPresented {
            conversations.close()
        } else if conversations.active != nil {
            conversations.isPresented = true
        } else {
            ask(about: subjectForCurrentLocation)
        }
    }

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

    var subjectForCurrentLocation: ReviewSubject {
        if let focusedSubject { return focusedSubject }
        switch current {
        case .componentDetail(let id): return .component(id)
        case .edgeDetail(let id): return .relationship(id)
        case .decisionDetail(let id): return .decision(id)
        case .consideration(let id): return .consideration(id)
        case .flowDetail(let id): return .flow(id)
        case .flowNodeDetail(let flowId, let nodeId): return .flowNode(flowId: flowId, nodeId: nodeId)
        case .evidence(let ref), .diffLocation(let ref): return .codeRef(ref)
        default:
            if let change = graph?.dominantBehaviorChange { return .behaviorChange(change.id) }
            return .pullRequest
        }
    }

    var canGoBack: Bool { path.count > 1 }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func setReviewerState(_ state: ReviewerState, forDecision id: String) {
        noteEngagement()
        guard var g = graph, let idx = g.decisions.firstIndex(where: { $0.id == id }) else { return }
        g.decisions[idx].reviewerState = (g.decisions[idx].reviewerState == state) ? .unreviewed : state
        graph = g
    }

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
