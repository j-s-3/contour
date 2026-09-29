import Foundation

struct PipelineProgressEntry: Identifiable, Sendable {
    let id = UUID()
    var stage: String
    var detail: String
}

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

    static let analysis: [PipelineStage] = [
        .behaviorChange, .understanding, .architecture, .decisions, .flows, .judgment,
    ]

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

    var checkoutFailureMessage: String {
        "\(failureHeadline). The repository couldn't be checked out, so there was nothing to analyze."
    }
}

enum StageStatus: Equatable, Sendable {
    case pending
    case running(detail: String?)
    case done
    case failed(String)
    case stale
    case stopped

    var isSettled: Bool {
        switch self {
        case .done, .failed, .stopped: return true
        case .pending, .running, .stale: return false
        }
    }

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

struct AnalysisState: Equatable, Sendable {
    var stages: [PipelineStage: StageStatus] = [:]
    var revalidatingFrom: String?
    var isComplete = false
    var fromCache = false

    func status(_ stage: PipelineStage) -> StageStatus { stages[stage] ?? .pending }

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

    var canStop: Bool { remainingCount > 0 }

    func retryStage(for section: ReviewSection) -> PipelineStage? {
        section.stages.first { status($0).canRetry }
    }

    static func stopping(_ statuses: [PipelineStage: StageStatus]) -> [PipelineStage: StageStatus] {
        var changes: [PipelineStage: StageStatus] = [:]
        for stage in PipelineStage.allCases where !(statuses[stage] ?? .pending).isSettled {
            changes[stage] = stage == .ticket ? .done : .stopped
        }
        return changes
    }
}
