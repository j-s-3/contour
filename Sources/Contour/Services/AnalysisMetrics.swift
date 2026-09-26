import Foundation

/// The moments that matter when a PR opens, measured from the moment the reviewer asked
/// for it. The one to optimize is `usefulOverview` — when the reviewer can start thinking
/// about the PR — not `fullAnalysis`.
enum LatencyMilestone: String, CaseIterable, Codable, Sendable {
    case prShell
    case rawDiff
    case whatChanged
    case beforeAfter
    case firstDecision
    case usefulOverview
    case architecture
    case flows
    case fullAnalysis

    var label: String {
        switch self {
        case .prShell: return "PR shell"
        case .rawDiff: return "Raw diff"
        case .whatChanged: return "What changed"
        case .beforeAfter: return "Before / after"
        case .firstDecision: return "First decision"
        case .usefulOverview: return "Useful overview"
        case .architecture: return "Architecture"
        case .flows: return "Flows"
        case .fullAnalysis: return "Full analysis"
        }
    }
}

/// Latency of one PR open, plus whether the reviewer started working before the analysis
/// finished — the signal that progressive opening is actually being used rather than
/// waited out. Kept locally only (`metrics.jsonl` beside the analysis cache); nothing is
/// sent anywhere.
struct AnalysisMetrics: Codable, Sendable {
    var pr: String
    var startedAt: Date
    var fromCache = false
    /// Seconds from `startedAt`, keyed by `LatencyMilestone.rawValue`.
    var milestones: [String: Double] = [:]
    var reviewerEngagedBeforeComplete = false

    init(pr: String, startedAt: Date = .now) {
        self.pr = pr
        self.startedAt = startedAt
    }

    func elapsed(_ milestone: LatencyMilestone) -> Double? { milestones[milestone.rawValue] }

    /// Records a milestone the first time it's reached; later calls are ignored.
    mutating func mark(_ milestone: LatencyMilestone, at now: Date = .now) {
        guard milestones[milestone.rawValue] == nil else { return }
        milestones[milestone.rawValue] = now.timeIntervalSince(startedAt)
    }

    /// Derives every milestone the analysis state and graph now satisfy.
    mutating func update(state: AnalysisState, graph: PRGraph?, diffAvailable: Bool, at now: Date = .now) {
        if graph != nil { mark(.prShell, at: now) }
        if diffAvailable { mark(.rawDiff, at: now) }
        let understanding = state.status(.understanding) == .done
        let behavior = state.status(.behaviorChange) == .done
        if understanding || behavior { mark(.whatChanged, at: now) }
        if behavior { mark(.beforeAfter, at: now) }
        if graph?.decisions.isEmpty == false { mark(.firstDecision, at: now) }
        // What changed, before/after and why are on screen — or couldn't be, and the
        // Overview is as useful as it's going to get.
        if state.status(.behaviorChange).isSettled && state.status(.understanding).isSettled {
            mark(.usefulOverview, at: now)
        }
        if state.status(.architecture) == .done { mark(.architecture, at: now) }
        if state.status(.flows) == .done { mark(.flows, at: now) }
        if state.isComplete { mark(.fullAnalysis, at: now) }
    }

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Contour", isDirectory: true)
            .appendingPathComponent("metrics.jsonl")
    }

    /// Appends this record as one JSON line. Best-effort: metrics must never break a review.
    func append(to url: URL = AnalysisMetrics.fileURL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(self) else { return }
        line.append(0x0A)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }
}
