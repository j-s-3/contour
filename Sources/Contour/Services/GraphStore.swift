import Foundation
import Observation

/// Where one PR session currently sits in the pipeline. Drives the loading/empty/error
/// states the design doc calls out in §4 (progress with real substeps, not a spinner).
enum SessionPhase: Equatable {
    case idle
    case running(stage: PipelineStage)
    case ready
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
    /// Tradeoffs live inside their decision, so this opens the owning decision.
    case tradeoffDetail(String)
    case flowDetail(String)
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
    var phase: SessionPhase = .idle
    private(set) var progressLog: [PipelineProgressEntry] = []

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
        runTask?.cancel()
        phase = .running(stage: .fetching)
        progressLog = []
        graph = nil
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

        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await pipeline.run(prURL: prURL, forceRefresh: forceRefresh) { [weak self] stage, entry in
                    Task { @MainActor [weak self] in
                        self?.phase = .running(stage: stage)
                        self?.progressLog.append(entry)
                    }
                }
                await MainActor.run {
                    self.graph = result.graph
                    self.checkout = result.checkout
                    self.diffText = result.diff
                    self.phase = .ready
                }
            } catch {
                await MainActor.run {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Navigation

    func navigate(to target: NavigationTarget) {
        guard target != current else { return }
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
        conversations.open(subject)
    }

    @MainActor
    func send(_ text: String, in conversation: Conversation) {
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
        case .tradeoffDetail(let id): return .tradeoff(id)
        case .flowDetail(let id): return .flow(id)
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
        guard var g = graph, let idx = g.decisions.firstIndex(where: { $0.id == id }) else { return }
        g.decisions[idx].reviewerState = (g.decisions[idx].reviewerState == state) ? .unreviewed : state
        graph = g
    }

    func setReviewerNote(_ note: String, forDecision id: String) {
        guard var g = graph, let idx = g.decisions.firstIndex(where: { $0.id == id }) else { return }
        g.decisions[idx].reviewerNote = note
        graph = g
    }
}
