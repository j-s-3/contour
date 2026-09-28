import Foundation
import Testing
@testable import Contour

/// `AnalysisMetrics` is local-only latency instrumentation (`metrics.jsonl` beside the
/// analysis cache, nothing sent anywhere). The existing suite only exercised
/// prShell/rawDiff/whatChanged/beforeAfter/usefulOverview being marked once each — this
/// pins the remaining milestones, the "a stopped stage never counts" exclusion, the file
/// destination, and the actual append-to-disk behavior.
struct AnalysisMetricsTests {

    @Test func everyMilestoneHasANonEmptyLabel() {
        for milestone in LatencyMilestone.allCases {
            #expect(!milestone.label.isEmpty)
        }
        #expect(LatencyMilestone.usefulOverview.label == "Useful overview")
        #expect(LatencyMilestone.fullAnalysis.label == "Full analysis")
    }

    @Test func firstDecisionArchitectureFlowsAndFullAnalysisMilestonesAreDerived() {
        let start = Date(timeIntervalSince1970: 2000)
        var metrics = AnalysisMetrics(pr: "x", startedAt: start)
        var state = AnalysisState()
        let graph = ContourSampleData.publishTriggeredReindex

        metrics.update(state: state, graph: graph, diffAvailable: true, at: start.addingTimeInterval(3))
        #expect(metrics.elapsed(.firstDecision) == 3, "the sample graph already has decisions")

        state.stages[.architecture] = .done
        state.stages[.flows] = .done
        metrics.update(state: state, graph: graph, diffAvailable: true, at: start.addingTimeInterval(6))
        #expect(metrics.elapsed(.architecture) == 6)
        #expect(metrics.elapsed(.flows) == 6)

        for stage in PipelineStage.analysis { state.stages[stage] = .done }
        state.isComplete = true
        metrics.update(state: state, graph: graph, diffAvailable: true, at: start.addingTimeInterval(10))
        #expect(metrics.elapsed(.fullAnalysis) == 10)
    }

    /// A stopped stage wasn't given the chance to finish, so it must not count toward the
    /// overview milestone even though `isSettled` is true for it.
    @Test func aStoppedStageNeverCountsTowardUsefulOverview() {
        let start = Date(timeIntervalSince1970: 3000)
        var metrics = AnalysisMetrics(pr: "x", startedAt: start)
        var state = AnalysisState()
        state.stages[.behaviorChange] = .stopped
        state.stages[.understanding] = .stopped
        metrics.update(state: state, graph: nil, diffAvailable: false, at: start.addingTimeInterval(1))
        #expect(metrics.elapsed(.usefulOverview) == nil)
        #expect(metrics.elapsed(.whatChanged) == nil)
    }

    @Test func appendWritesOneJSONLinePerCallToTheSameFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("metrics.jsonl")
        let metrics = AnalysisMetrics(pr: "acme/repo#1", startedAt: Date(timeIntervalSince1970: 0))

        metrics.append(to: url)
        metrics.append(to: url)

        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.contains("acme/repo#1") })
    }

    @Test func fileURLPointsAtMetricsJSONLUnderContourSupport() {
        #expect(AnalysisMetrics.fileURL.lastPathComponent == "metrics.jsonl")
        #expect(AnalysisMetrics.fileURL.pathComponents.contains("Contour"))
    }
}
