import Testing
@testable import Contour

/// Guards against the mock fixtures (used for `CONTOUR_MOCK_ANALYSIS=1` manual testing,
/// see `MockAnalysisFixtures`) silently drifting out of sync with the real stage schemas
/// in `StageDecoding` — a shape mismatch here would otherwise only surface as a confusing
/// decode error the next time someone actually flips the env var on.
struct MockAnalysisFixturesTests {

    @Test func allStagesDecodeCleanly() throws {
        let behavior = MockAnalysisFixtures.response(for: .behaviorChange)
        _ = try StageDecoding.decode(StageDecoding.BehaviorChangeResult.self, from: behavior)

        let architecture = MockAnalysisFixtures.response(for: .architecture)
        let arch = try StageDecoding.decode(StageDecoding.ArchitectureResult.self, from: architecture)
        #expect(!arch.components.isEmpty)

        let understanding = try StageDecoding.decode(
            StageDecoding.UnderstandingResult.self, from: MockAnalysisFixtures.response(for: .understanding)
        )
        #expect(!understanding.intent.text.isEmpty)
        #expect(understanding.problemToBeSolved != nil)
        #expect(understanding.howItWasSolved != nil)

        let decisions = MockAnalysisFixtures.response(for: .decisions)
        let dec = try StageDecoding.decode(StageDecoding.DecisionsResult.self, from: decisions)
        #expect(!dec.decisions.isEmpty)

        let flows = MockAnalysisFixtures.response(for: .flows)
        let flowsResult = try StageDecoding.decode(StageDecoding.FlowsResult.self, from: flows)
        #expect(!flowsResult.flows.isEmpty)
        #expect(!flowsResult.entryPoints.isEmpty)

        let judgment = MockAnalysisFixtures.response(for: .judgment)
        _ = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: judgment)
    }

    /// Every componentId/decisionId/flowId/entryPointId referenced by one stage's
    /// fixture must actually exist among the IDs another stage's fixture defines — otherwise
    /// the synthetic graph would silently render dangling cross-links, defeating the whole
    /// point of a realistic manual-testing fixture (§6, cross-linking).
    @Test func crossLinkedIdsResolve() throws {
        let arch = try StageDecoding.decode(
            StageDecoding.ArchitectureResult.self, from: MockAnalysisFixtures.response(for: .architecture)
        )
        let decisions = try StageDecoding.decode(
            StageDecoding.DecisionsResult.self, from: MockAnalysisFixtures.response(for: .decisions)
        )
        let flows = try StageDecoding.decode(
            StageDecoding.FlowsResult.self, from: MockAnalysisFixtures.response(for: .flows)
        )

        let componentIds = Set(arch.components.map(\.id))
        let decisionIds = Set(decisions.decisions.map(\.id))
        let flowIds = Set(flows.flows.map(\.id))

        for component in arch.components {
            for id in component.decisionIds { #expect(decisionIds.contains(id), "component \(component.id) references missing decision \(id)") }
            for id in component.dependsOnIds { #expect(componentIds.contains(id), "component \(component.id) depends on missing component \(id)") }
        }
        for decision in decisions.decisions {
            for id in decision.componentIds { #expect(componentIds.contains(id), "decision \(decision.id) references missing component \(id)") }
        }
        for entryPoint in flows.entryPoints {
            if let flowId = entryPoint.flowId { #expect(flowIds.contains(flowId), "entry point \(entryPoint.id) references missing flow \(flowId)") }
        }
        for flow in flows.flows {
            for step in flow.steps {
                if let componentId = step.componentId { #expect(componentIds.contains(componentId), "flow step \(step.id) references missing component \(componentId)") }
            }
        }

        // Edges and boundaries must reference real parts, and every edge must say what crosses
        // it. A PR is not required to add a relationship: most change none.
        #expect(!arch.edges.isEmpty, "architecture fixture should define labeled edges")
        for component in arch.components {
            if let parent = component.parentId { #expect(componentIds.contains(parent), "component \(component.id) has missing parent \(parent)") }
        }
        for edge in arch.edges {
            #expect(componentIds.contains(edge.fromId), "edge \(edge.id) has missing fromId \(edge.fromId)")
            #expect(componentIds.contains(edge.toId), "edge \(edge.id) has missing toId \(edge.toId)")
            #expect(!edge.label.isEmpty, "edge \(edge.id) has no relationship label")
            for id in edge.decisionIds { #expect(decisionIds.contains(id), "edge \(edge.id) references missing decision \(id)") }
        }
        for boundary in arch.boundaries {
            for id in boundary.componentIds { #expect(componentIds.contains(id), "boundary \(boundary.id) references missing component \(id)") }
        }
    }
}
