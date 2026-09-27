import Foundation

/// One line of the technical log kept behind "Show log" (§4.1, "real substeps"). It is no
/// longer what the reviewer stares at while a PR opens — that is the review itself filling
/// in — but it stays available for diagnosing stalls and failed model calls.
struct PipelineProgressEntry: Identifiable, Sendable {
    let id = UUID()
    var stage: String
    var detail: String
}

/// Every step the pipeline takes, in the order the Details rail draws them. The first four
/// are plumbing; the rest are model calls, each producing one slice of the graph.
enum PipelineStage: String, CaseIterable, Codable, Sendable {
    case fetching = "Fetching PR"
    case checkingOut = "Checking out repository"
    case cacheCheck = "Checking cache"
    case ticket = "Checking issue tracker"
    case behaviorChange = "Identifying behavior change"
    case understanding = "Understanding intent"
    case architecture = "Analyzing architecture"
    case decisions = "Extracting decisions"
    case flows = "Tracing flows"
    case judgment = "Identifying what needs judgment"

    /// The stages that call a model and write a slice of the graph. These are the ones that
    /// run in the background after the PR opens, and the ones that can fail independently.
    static let analysis: [PipelineStage] = [.behaviorChange, .understanding, .architecture, .decisions, .flows, .judgment]

    var shortLabel: String {
        switch self {
        case .fetching: return "Fetch"
        case .checkingOut: return "Checkout"
        case .cacheCheck: return "Cache"
        case .ticket: return "Issue"
        case .behaviorChange: return "Behavior"
        case .understanding: return "Intent"
        case .architecture: return "Architecture"
        case .decisions: return "Decisions"
        case .flows: return "Flows"
        case .judgment: return "Judgment"
        }
    }
}

extension PipelineStage {
    /// What a failed stage didn't manage, in the reviewer's terms rather than the pipeline's.
    var failureHeadline: String {
        switch self {
        case .fetching: return "Couldn't fetch the PR"
        case .checkingOut: return "Couldn't check out the repository"
        case .cacheCheck: return "Couldn't read the saved analysis"
        case .ticket: return "Couldn't look up the linked issue"
        case .behaviorChange: return "Couldn't work out the behavior change"
        case .understanding: return "Couldn't work out what the change is for"
        case .architecture: return "Couldn't map the architecture"
        case .decisions: return "Couldn't identify the decisions"
        case .flows: return "Couldn't trace the flows"
        case .judgment: return "Couldn't find what needs judgment"
        }
    }

    /// The reviewer-facing message for this stage failing with `error` — "Couldn't map the
    /// architecture. The model's answer wasn't readable." Nothing here quotes the raw
    /// response or stderr; those stay in the technical log.
    func failureMessage(for error: Error) -> String {
        "\(failureHeadline). \(Self.failureReason(error))"
    }

    static func failureReason(_ error: Error) -> String {
        switch error {
        case let error as AnalysisServiceError: return error.reviewerReason
        case is StageDecodingError: return "The model's answer wasn't in the expected shape."
        case is HarnessError: return "The PR's details couldn't be handed to the model."
        default: return "Something went wrong while it ran."
        }
    }

    /// For every analysis stage left without a result when the checkout itself failed.
    var checkoutFailureMessage: String {
        "\(failureHeadline). The repository couldn't be checked out, so there was nothing to analyze."
    }
}

/// Where one stage is. `stale` is a slice carried over from an analysis of an earlier
/// revision of the same PR: shown so the reviewer isn't staring at nothing, marked so it's
/// never mistaken for a conclusion about the current code. `stopped` is a stage the
/// reviewer stopped before it finished: whatever it had on screen stays, and it waits for
/// its own Retry rather than resuming by itself.
enum StageStatus: Equatable, Sendable {
    case pending
    /// `detail` is the latest meaningful progress ("2 found so far"), not a tool-call trace.
    case running(detail: String?)
    case done
    case failed(String)
    case stale
    case stopped

    /// Nothing more will happen to this stage unless the reviewer asks for it.
    var isSettled: Bool {
        switch self {
        case .done, .failed, .stopped: return true
        case .pending, .running, .stale: return false
        }
    }

    /// Failed or stopped: the section offers Retry.
    var canRetry: Bool {
        switch self {
        case .failed, .stopped: return true
        case .pending, .running, .done, .stale: return false
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var failure: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// What the reviewer sees in the sidebar and the analysis popover: review sections, not
/// pipeline mechanics. Each groups the stage(s) that produce it.
enum ReviewSection: String, CaseIterable, Identifiable, Sendable {
    case context
    case whatChanged
    case decisions
    case architecture
    case flows
    case questions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .context: return "PR context"
        case .whatChanged: return "What changed"
        case .decisions: return "Decisions"
        case .architecture: return "Architecture"
        case .flows: return "Flows"
        case .questions: return "Review questions"
        }
    }

    /// Present-tense wording for while it's being produced — what the analysis is doing
    /// for the reviewer, never which stage is running.
    var workingLabel: String {
        switch self {
        case .context: return "Reading the PR…"
        case .whatChanged: return "Understanding the change…"
        case .decisions: return "Identifying choices…"
        case .architecture: return "Mapping system change…"
        case .flows: return "Tracing runtime behavior…"
        case .questions: return "Looking for what needs judgment…"
        }
    }

    var stages: [PipelineStage] {
        switch self {
        case .context: return [.fetching, .checkingOut, .ticket]
        case .whatChanged: return [.behaviorChange, .understanding]
        case .decisions: return [.decisions]
        case .architecture: return [.architecture]
        case .flows: return [.flows]
        case .questions: return [.judgment]
        }
    }
}

/// The analysis state of one open PR: every stage's status plus the technical log. Pure
/// value type so views can read it and tests can build one directly.
struct AnalysisState: Equatable, Sendable {
    var stages: [PipelineStage: StageStatus] = [:]
    /// Set while carried-over slices from an earlier revision are on screen.
    var revalidatingFrom: String?
    /// Every analysis stage settled at least once, successfully or not.
    var isComplete = false
    var fromCache = false

    func status(_ stage: PipelineStage) -> StageStatus { stages[stage] ?? .pending }

    /// A section is as far along as its least-finished stage; any failure wins so the
    /// reviewer sees it. A stage resumed after a stop reads as running, not stopped.
    func sectionStatus(_ section: ReviewSection) -> StageStatus {
        let statuses = section.stages.map(status)
        if let failed = statuses.first(where: { $0.failure != nil }) { return failed }
        if statuses.allSatisfy({ $0 == .done }) { return .done }
        if let running = statuses.first(where: \.isRunning) { return running }
        if statuses.contains(.stopped) { return .stopped }
        if statuses.contains(.stale) { return .stale }
        return .pending
    }

    var remainingCount: Int {
        PipelineStage.analysis.filter { !status($0).isSettled }.count
    }

    var failedSections: [ReviewSection] {
        ReviewSection.allCases.filter { sectionStatus($0).failure != nil }
    }

    var stoppedSections: [ReviewSection] {
        ReviewSection.allCases.filter { sectionStatus($0) == .stopped }
    }

    /// Some analysis is still to come, so "Stop analysis" has something to stop.
    var canStop: Bool { remainingCount > 0 }

    /// The stage a section's Retry re-runs: its first failed or stopped one. The context
    /// section's plumbing stages aren't analysis, so retrying one reopens the whole PR.
    func retryStage(for section: ReviewSection) -> PipelineStage? {
        section.stages.first { status($0).canRetry }
    }

    /// What stopping changes: every stage that hasn't settled, including ones that never
    /// started, becomes stopped. Landed stages keep their `done` and failures their message.
    /// The issue lookup is the exception — it's best-effort and never a section of its own,
    /// so it's simply over; resuming Understanding looks the issue up again.
    static func stopping(_ statuses: [PipelineStage: StageStatus]) -> [PipelineStage: StageStatus] {
        var changes: [PipelineStage: StageStatus] = [:]
        for stage in PipelineStage.allCases where !(statuses[stage] ?? .pending).isSettled {
            changes[stage] = stage == .ticket ? .done : .stopped
        }
        return changes
    }
}
