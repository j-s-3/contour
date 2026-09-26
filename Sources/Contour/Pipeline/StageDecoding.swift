import Foundation

/// Per-stage response shapes, decoded from the `[String: Any]` an AnalysisService call
/// returns. Kept distinct from the graph's own node types so a stage can return a partial
/// or slightly-off shape without corrupting the whole PRGraph — decoding failures for one
/// stage become an Uncertainty rather than crashing the pipeline (§14 "honest truncation").
///
/// Every array field here uses a lenient custom decode. This was not optional: on a real,
/// large PR, `pi` sometimes emits `"entryPoints": null` (or similar) to mean "found none"
/// rather than `"entryPoints": []`. Swift's synthesized `Decodable` treats an explicit JSON
/// `null` against a non-optional `[T]` as `DecodingError.valueNotFound`, whose
/// `localizedDescription` is the unhelpful "The data couldn't be read because it is
/// missing." — exactly the crash this lenient decoding exists to prevent.
/// Thrown instead of a bare `DecodingError` so a decode failure tells you which stage and
/// which field broke, rather than Foundation's generic (and famously unhelpful)
/// "The data couldn't be read because it isn't in the correct format."
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

    /// - Parameter stageLabel: human-readable stage name, folded into any thrown error so
    ///   a decode failure is diagnosable from the UI's error screen alone, without needing
    ///   to reproduce the `pi` call by hand.
    static func decode<T: Decodable>(_ type: T.Type, stageLabel: String = "stage", from object: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 JSON>"
            throw StageDecodingError(stageLabel: stageLabel, underlying: error, rawJSON: raw)
        }
    }

    struct BehaviorChangeResult: Decodable {
        var behaviorChanges: [BehaviorChange]

        enum CodingKeys: String, CodingKey { case behaviorChanges }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            behaviorChanges = try c.decodeIfPresent([BehaviorChange].self, forKey: .behaviorChanges) ?? []
        }
    }

    struct ArchitectureResult: Decodable {
        var components: [ComponentNode]
        var edges: [ArchitectureEdge]
        var boundaries: [SystemBoundary]
        var architectureImpact: Statement?

        enum CodingKeys: String, CodingKey { case components, edges, boundaries, architectureImpact }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            components = try c.decodeIfPresent([ComponentNode].self, forKey: .components) ?? []
            edges = try c.decodeIfPresent([ArchitectureEdge].self, forKey: .edges) ?? []
            boundaries = try c.decodeIfPresent([SystemBoundary].self, forKey: .boundaries) ?? []
            architectureImpact = try c.decodeIfPresent(Statement.self, forKey: .architectureImpact)
        }
    }

    struct IntentResult: Decodable {
        var intent: Statement
    }

    struct DecisionsResult: Decodable {
        var decisions: [DecisionNode]

        enum CodingKeys: String, CodingKey { case decisions }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            decisions = try c.decodeIfPresent([DecisionNode].self, forKey: .decisions) ?? []
        }
    }

    struct FlowsResult: Decodable {
        var entryPoints: [EntryPointNode]
        var flows: [FlowNode]

        enum CodingKeys: String, CodingKey { case entryPoints, flows }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            entryPoints = try c.decodeIfPresent([EntryPointNode].self, forKey: .entryPoints) ?? []
            flows = try c.decodeIfPresent([FlowNode].self, forKey: .flows) ?? []
        }
    }

    struct JudgmentResult: Decodable {
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

    /// §ELI5 feature: the two human-friendly briefs surfaced at the top of the summary.
    struct ELI5Result: Decodable {
        var problemToBeSolved: Statement
        var howItWasSolved: Statement
    }
}
