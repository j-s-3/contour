import Foundation

struct StageDecodingError: LocalizedError {
    var stageLabel: String
    var underlying: Error
    var rawJSON: String

    var errorDescription: String? {
        "\(stageLabel) stage returned JSON that didn't decode: \(Self.describe(underlying))\n\nRaw response (truncated):\n\(rawJSON.prefix(2000))"
    }

    private static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return "\(error)" }
        switch decodingError {
        case .keyNotFound(let key, let ctx):
            return "missing required key \"\(key.stringValue)\" at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let ctx):
            return "expected \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)"
        case .valueNotFound(let type, let ctx):
            return "null where \(type) was required at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let ctx):
            return "corrupted data at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)"
        @unknown default:
            return "\(decodingError)"
        }
    }
}

enum StageDecoding {
    static func decode<T: Decodable>(_ type: T.Type, stageLabel: String = "stage", from object: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 JSON>"
            throw StageDecodingError(stageLabel: stageLabel, underlying: error, rawJSON: raw)
        }
    }

    struct BehaviorChangeResult: Decodable, Sendable {
        var behaviorChanges: [BehaviorChange]

        enum CodingKeys: String, CodingKey { case behaviorChanges }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            behaviorChanges = try c.decodeIfPresent([BehaviorChange].self, forKey: .behaviorChanges) ?? []
        }
    }

    struct ArchitectureResult: Decodable, Sendable {
        var components: [ComponentNode]
        var edges: [ArchitectureEdge]
        var boundaries: [SystemBoundary]
        var architectureImpact: Statement?
        var architecture: ArchitectureAssessment?

        enum CodingKeys: String, CodingKey { case components, edges, boundaries, architectureImpact, architecture }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            components = try c.decodeIfPresent([ComponentNode].self, forKey: .components) ?? []
            edges = try c.decodeIfPresent([ArchitectureEdge].self, forKey: .edges) ?? []
            boundaries = try c.decodeIfPresent([SystemBoundary].self, forKey: .boundaries) ?? []
            architectureImpact = try c.decodeIfPresent(Statement.self, forKey: .architectureImpact)
            architecture = (try? c.decodeIfPresent(ArchitectureAssessment.self, forKey: .architecture)) ?? nil
            if architectureImpact == nil { architectureImpact = architecture?.explanation }
        }
    }

    struct DecisionsResult: Decodable, Sendable {
        var decisions: [DecisionNode]

        enum CodingKeys: String, CodingKey { case decisions }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            decisions = try c.decodeIfPresent([DecisionNode].self, forKey: .decisions) ?? []
        }
    }

    struct FlowsResult: Decodable, Sendable {
        var entryPoints: [EntryPointNode]
        var flows: [FlowNode]

        enum CodingKeys: String, CodingKey { case entryPoints, flows }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            entryPoints = try c.decodeIfPresent([EntryPointNode].self, forKey: .entryPoints) ?? []
            flows = try c.decodeIfPresent([FlowNode].self, forKey: .flows) ?? []
        }
    }

    struct JudgmentResult: Decodable, Sendable {
        var considerations: [Consideration]
        var needsJudgment: [Statement]
        var uncertainties: [Statement]
        var questions: [QuestionNode]
        var changeMap: [ChangeMapEntry]?

        enum CodingKeys: String, CodingKey { case considerations, needsJudgment, uncertainties, questions, changeMap }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            considerations = try c.decodeIfPresent([Consideration].self, forKey: .considerations) ?? []
            needsJudgment = try c.decodeIfPresent([Statement].self, forKey: .needsJudgment) ?? []
            uncertainties = try c.decodeIfPresent([Statement].self, forKey: .uncertainties) ?? []
            questions = try c.decodeIfPresent([QuestionNode].self, forKey: .questions) ?? []
            changeMap = try c.decodeIfPresent([ChangeMapEntry].self, forKey: .changeMap)
        }
    }

    struct UnderstandingResult: Decodable, Sendable {
        var intent: Statement
        var problemToBeSolved: Statement?
        var howItWasSolved: Statement?
    }
}
