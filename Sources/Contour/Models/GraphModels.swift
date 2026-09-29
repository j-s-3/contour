import Foundation

enum Provenance: String, Codable, Hashable, Sendable {
    case fact
    case claim
    case interpretation
}

enum Confidence: String, Codable, Hashable, Sendable, Comparable {
    case low, medium, high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
    static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rank < rhs.rank }
}

struct Statement: Codable, Hashable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var text: String
    var provenance: Provenance
    var confidence: Confidence?
    var source: String?

    enum CodingKeys: String, CodingKey { case text, provenance, confidence, source }

    init(text: String, provenance: Provenance, confidence: Confidence? = nil, source: String? = nil) {
        self.text = text
        self.provenance = provenance
        self.confidence = confidence
        self.source = source
    }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        provenance = try c.decode(Provenance.self, forKey: .provenance)
        confidence = try c.decodeIfPresent(Confidence.self, forKey: .confidence)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        id = UUID().uuidString
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(provenance, forKey: .provenance)
        try c.encodeIfPresent(confidence, forKey: .confidence)
        try c.encodeIfPresent(source, forKey: .source)
    }
}

enum RefSide: String, Codable, Hashable, Sendable { case head, base }

struct CodeRef: Codable, Hashable, Sendable, Identifiable {
    var path: String
    var startLine: Int
    var endLine: Int
    var blobSha: String?
    var side: RefSide

    var id: String { "\(side.rawValue):\(path):\(startLine)-\(endLine)" }
    var display: String { "\(path):\(startLine)-\(endLine)" }

    init(path: String, startLine: Int, endLine: Int, blobSha: String? = nil, side: RefSide = .head) {
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
        self.blobSha = blobSha
        self.side = side
    }
    enum CodingKeys: String, CodingKey { case path, startLine, endLine, blobSha, side }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        startLine = try c.decodeIfPresent(Int.self, forKey: .startLine) ?? 1
        endLine = try c.decodeIfPresent(Int.self, forKey: .endLine) ?? startLine
        blobSha = try c.decodeIfPresent(String.self, forKey: .blobSha)
        side = try c.decodeIfPresent(RefSide.self, forKey: .side) ?? .head
    }
}

enum ChangeKind: String, Codable, Hashable, Sendable {
    case new, changed, touched, unchanged
    case removed
}

enum EdgeFlow: String, Codable, Hashable, Sendable {
    case sync
    case async
}

enum EdgeChange: String, Codable, Hashable, Sendable {
    case new
    case changed
    case existing
    case removed
}

enum ArchPresence: String, Codable, Hashable, Sendable {
    case before, after, both
}

struct ArchitectureEdge: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var fromId: String
    var toId: String
    var label: String
    var previousLabel: String?
    var flow: EdgeFlow = .sync
    var change: EdgeChange = .existing
    var isTrustBoundary: Bool = false
    var onCriticalPath: Bool = false
    var decisionIds: [String] = []
    var note: String?

    var presence: ArchPresence {
        switch change {
        case .new: return .after
        case .removed: return .before
        case .changed, .existing: return .both
        }
    }

    init(
        id: String = UUID().uuidString, fromId: String, toId: String, label: String,
        flow: EdgeFlow = .sync, change: EdgeChange = .existing, isTrustBoundary: Bool = false,
        onCriticalPath: Bool = false, decisionIds: [String] = [], note: String? = nil,
        previousLabel: String? = nil
    ) {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.label = label
        self.previousLabel = previousLabel
        self.flow = flow
        self.change = change
        self.isTrustBoundary = isTrustBoundary
        self.onCriticalPath = onCriticalPath
        self.decisionIds = decisionIds
        self.note = note
    }
    enum CodingKeys: String, CodingKey {
        case id, fromId, toId, label, previousLabel, flow, change, isTrustBoundary, onCriticalPath, decisionIds, note
    }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        fromId = try c.decode(String.self, forKey: .fromId)
        toId = try c.decode(String.self, forKey: .toId)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        previousLabel = (try? c.decodeIfPresent(String.self, forKey: .previousLabel)).flatMap {
            $0?.isEmpty == false ? $0 : nil
        }
        flow = try c.decodeIfPresent(EdgeFlow.self, forKey: .flow) ?? .sync
        change = try c.decodeIfPresent(EdgeChange.self, forKey: .change) ?? .existing
        isTrustBoundary = try c.decodeIfPresent(Bool.self, forKey: .isTrustBoundary) ?? false
        onCriticalPath = try c.decodeIfPresent(Bool.self, forKey: .onCriticalPath) ?? false
        decisionIds = try c.decodeIfPresent([String].self, forKey: .decisionIds) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

enum BoundaryKind: String, Codable, Hashable, Sendable {
    case application, process, service, datastore, external, trust, network, asyncBoundary

    var label: String {
        switch self {
        case .application: return "Application"
        case .process: return "Process"
        case .service: return "Service"
        case .datastore: return "Datastore"
        case .external: return "External"
        case .trust: return "Trust boundary"
        case .network: return "Network"
        case .asyncBoundary: return "Async"
        }
    }
}

struct SystemBoundary: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var label: String
    var kind: BoundaryKind = .application
    var componentIds: [String] = []

    init(id: String = UUID().uuidString, label: String, kind: BoundaryKind = .application, componentIds: [String] = [])
    {
        self.id = id
        self.label = label
        self.kind = kind
        self.componentIds = componentIds
    }
    enum CodingKeys: String, CodingKey { case id, label, kind, componentIds }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        kind = try c.decodeIfPresent(BoundaryKind.self, forKey: .kind) ?? .application
        componentIds = try c.decodeIfPresent([String].self, forKey: .componentIds) ?? []
    }
}

enum ArchitecturalImpact: String, Codable, Hashable, Sendable, CaseIterable {
    case none
    case low
    case moderate
    case significant

    var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .significant: return "Significant"
        }
    }
}

struct ArchitectureAssessment: Codable, Hashable, Sendable {
    var impact: ArchitecturalImpact
    var headline: String
    var explanation: Statement?
    var focusIds: [String] = []

    init(impact: ArchitecturalImpact, headline: String, explanation: Statement? = nil, focusIds: [String] = []) {
        self.impact = impact
        self.headline = headline
        self.explanation = explanation
        self.focusIds = focusIds
    }
    enum CodingKeys: String, CodingKey { case impact, headline, explanation, focusIds }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        impact = (try? c.decodeIfPresent(ArchitecturalImpact.self, forKey: .impact)) ?? .low
        headline = try c.decodeIfPresent(String.self, forKey: .headline) ?? ""
        explanation = try? c.decodeIfPresent(Statement.self, forKey: .explanation)
        focusIds = (try? c.decodeIfPresent([String].self, forKey: .focusIds)) ?? []
    }
}

struct ResponsibilityDelta: Codable, Hashable, Sendable {
    var before: String?
    var after: String?
    var summary: Statement?

    init(before: String? = nil, after: String? = nil, summary: Statement? = nil) {
        self.before = before
        self.after = after
        self.summary = summary
    }
    enum CodingKeys: String, CodingKey { case before, after, summary }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        before = (try? c.decodeIfPresent(String.self, forKey: .before)).flatMap { $0?.isEmpty == false ? $0 : nil }
        after = (try? c.decodeIfPresent(String.self, forKey: .after)).flatMap { $0?.isEmpty == false ? $0 : nil }
        summary = try? c.decodeIfPresent(Statement.self, forKey: .summary)
    }
}

enum AbstractionLevel: String, Codable, Comparable, Hashable, Sendable, CaseIterable {
    case behavior
    case system
    case component
    case implementation

    private var rank: Int {
        switch self {
        case .behavior: return 0
        case .system: return 1
        case .component: return 2
        case .implementation: return 3
        }
    }

    static func < (lhs: AbstractionLevel, rhs: AbstractionLevel) -> Bool { lhs.rank < rhs.rank }

    var label: String {
        switch self {
        case .behavior: return "Behavior"
        case .system: return "System"
        case .component: return "Component"
        case .implementation: return "Implementation"
        }
    }
}

enum ReviewerState: String, Codable, Hashable, Sendable, CaseIterable {
    case unreviewed, accepted, questioned, discuss

    var label: String {
        switch self {
        case .unreviewed: return "Unreviewed"
        case .accepted: return "Looks good"
        case .questioned: return "Questioned"
        case .discuss: return "Needs discussion"
        }
    }
}

enum ReviewSignificance: String, Codable, Hashable, Sendable, Comparable {
    case high
    case medium
    case low

    private var rank: Int {
        switch self {
        case .high: return 2
        case .medium: return 1
        case .low: return 0
        }
    }

    static func < (lhs: ReviewSignificance, rhs: ReviewSignificance) -> Bool { lhs.rank < rhs.rank }

    var raised: ReviewSignificance { self == .low ? .medium : .high }
}

enum DecisionImpact: String, Codable, Hashable, Sendable, CaseIterable {
    case correctness, security, dataIntegrity, reliability, concurrency, performance,
        scalability, compatibility, failureBehavior, operability, maintainability,
        userBehavior, architecture, evolution, complexity

    var label: String {
        switch self {
        case .dataIntegrity: return "data integrity"
        case .failureBehavior: return "failure behavior"
        case .userBehavior: return "user-visible behavior"
        case .evolution: return "future evolution"
        default: return rawValue
        }
    }

    init?(lenient raw: String) {
        let key = raw.lowercased().filter(\.isLetter)
        let aliases: [String: DecisionImpact] = [
            "userbehavior": .userBehavior, "uservisiblebehavior": .userBehavior, "ux": .userBehavior,
            "failuresemantics": .failureBehavior, "errorhandling": .failureBehavior,
            "architecturalconstraints": .architecture, "futureevolution": .evolution,
            "backwardscompatibility": .compatibility, "backwardcompatibility": .compatibility,
        ]
        guard let match = Self.allCases.first(where: { $0.rawValue.lowercased() == key }) ?? aliases[key] else {
            return nil
        }
        self = match
    }
}

enum ReviewPlacement: String, Codable, Hashable, Sendable {
    case review
    case other
}

enum DecisionShape: String, Codable, Hashable, Sendable {
    case binary
    case threshold
    case options
    case beforeAfter
}

struct DecisionOption: Codable, Hashable, Sendable {
    var label: String
    var detail: String?
    var chosen: Bool = false

    init(label: String, detail: String? = nil, chosen: Bool = false) {
        self.label = label
        self.detail = detail
        self.chosen = chosen
    }
    enum CodingKeys: String, CodingKey { case label, detail, chosen }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        chosen = try c.decodeIfPresent(Bool.self, forKey: .chosen) ?? false
    }
}

enum BehaviorStageTag: String, Codable, Hashable, Sendable {
    case beforeOnly
    case afterOnly
    case both
}

enum BehaviorOutcome: String, Codable, Hashable, Sendable {
    case success
    case failure
}

struct BehaviorStage: Codable, Hashable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var label: String
    var tag: BehaviorStageTag
    var componentIds: [String] = []
    var flowId: String?
    var refs: [CodeRef] = []
    var outcome: BehaviorOutcome?

    init(
        id: String = UUID().uuidString, label: String, tag: BehaviorStageTag,
        componentIds: [String] = [], flowId: String? = nil, refs: [CodeRef] = [],
        outcome: BehaviorOutcome? = nil
    ) {
        self.id = id
        self.label = label
        self.tag = tag
        self.componentIds = componentIds
        self.flowId = flowId
        self.refs = refs
        self.outcome = outcome
    }
    enum CodingKeys: String, CodingKey { case id, label, tag, componentIds, flowId, refs, outcome }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        label = try c.decode(String.self, forKey: .label)
        tag = try c.decodeIfPresent(BehaviorStageTag.self, forKey: .tag) ?? .both
        componentIds = try c.decodeIfPresent([String].self, forKey: .componentIds) ?? []
        flowId = try c.decodeIfPresent(String.self, forKey: .flowId)
        refs = try c.decodeIfPresent([CodeRef].self, forKey: .refs) ?? []
        outcome = (try? c.decodeIfPresent(BehaviorOutcome.self, forKey: .outcome)) ?? nil
    }
}

struct BehaviorChange: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var before: [BehaviorStage] = []
    var after: [BehaviorStage] = []
    var why: Statement?
    var consequence: Statement?
    var humanQuestion: Statement?

    init(
        id: String, title: String, before: [BehaviorStage] = [], after: [BehaviorStage] = [],
        why: Statement? = nil, consequence: Statement? = nil, humanQuestion: Statement? = nil
    ) {
        self.id = id
        self.title = title
        self.before = before
        self.after = after
        self.why = why
        self.consequence = consequence
        self.humanQuestion = humanQuestion
    }
    enum CodingKeys: String, CodingKey { case id, title, before, after, why, consequence, humanQuestion }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decode(String.self, forKey: .title)
        before = try c.decodeIfPresent([BehaviorStage].self, forKey: .before) ?? []
        after = try c.decodeIfPresent([BehaviorStage].self, forKey: .after) ?? []
        why = try c.decodeIfPresent(Statement.self, forKey: .why)
        consequence = try c.decodeIfPresent(Statement.self, forKey: .consequence)
        humanQuestion = try c.decodeIfPresent(Statement.self, forKey: .humanQuestion)
    }
}

struct ComponentNode: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var changeKind: ChangeKind
    var summary: Statement?
    var refs: [CodeRef] = []
    var decisionIds: [String] = []
    var flowIds: [String] = []
    var dependsOnIds: [String] = []
    var isTrustBoundaryEdge: Bool = false
    var filesChanged: Int = 0
    var level: AbstractionLevel = .system
    var implementedBy: [String] = []
    var parentId: String?
    var delta: ResponsibilityDelta?

    init(
        id: String, title: String, changeKind: ChangeKind, summary: Statement? = nil,
        refs: [CodeRef] = [], decisionIds: [String] = [], flowIds: [String] = [],
        dependsOnIds: [String] = [], isTrustBoundaryEdge: Bool = false, filesChanged: Int = 0,
        level: AbstractionLevel = .system, implementedBy: [String] = [],
        parentId: String? = nil, delta: ResponsibilityDelta? = nil
    ) {
        self.parentId = parentId
        self.delta = delta
        self.id = id
        self.title = title
        self.changeKind = changeKind
        self.summary = summary
        self.refs = refs
        self.decisionIds = decisionIds
        self.flowIds = flowIds
        self.dependsOnIds = dependsOnIds
        self.isTrustBoundaryEdge = isTrustBoundaryEdge
        self.filesChanged = filesChanged
        self.level = level
        self.implementedBy = implementedBy
    }
    enum CodingKeys: String, CodingKey {
        case id, title, changeKind, summary, refs, decisionIds, flowIds, dependsOnIds, isTrustBoundaryEdge,
            filesChanged, level, implementedBy, parentId, delta
    }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        changeKind = try c.decodeIfPresent(ChangeKind.self, forKey: .changeKind) ?? .touched
        summary = try c.decodeIfPresent(Statement.self, forKey: .summary)
        refs = try c.decodeIfPresent([CodeRef].self, forKey: .refs) ?? []
        decisionIds = try c.decodeIfPresent([String].self, forKey: .decisionIds) ?? []
        flowIds = try c.decodeIfPresent([String].self, forKey: .flowIds) ?? []
        dependsOnIds = try c.decodeIfPresent([String].self, forKey: .dependsOnIds) ?? []
        isTrustBoundaryEdge = try c.decodeIfPresent(Bool.self, forKey: .isTrustBoundaryEdge) ?? false
        filesChanged = try c.decodeIfPresent(Int.self, forKey: .filesChanged) ?? 0
        level = try c.decodeIfPresent(AbstractionLevel.self, forKey: .level) ?? .system
        implementedBy = try c.decodeIfPresent([String].self, forKey: .implementedBy) ?? []
        parentId = (try? c.decodeIfPresent(String.self, forKey: .parentId)).flatMap { $0?.isEmpty == false ? $0 : nil }
        delta = try? c.decodeIfPresent(ResponsibilityDelta.self, forKey: .delta)
    }
}

struct DecisionNode: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var decision: Statement
    var rationale: [Statement] = []
    var alternatives: [Statement] = []
    var consequences: [Statement] = []
    var confidence: Confidence
    var refs: [CodeRef] = []
    var tradeoffs: [DecisionTradeoff] = []
    var componentIds: [String] = []
    var reviewerState: ReviewerState = .unreviewed
    var reviewerNote: String = ""
    var level: AbstractionLevel = .system
    var significance: ReviewSignificance?
    var impacts: [DecisionImpact] = []
    var significanceReason: String?
    var reviewerPlacement: ReviewPlacement?
    var question: String?
    var options: [DecisionOption] = []
    var shape: DecisionShape?
    var why: Statement?

    init(
        id: String, title: String, decision: Statement, rationale: [Statement] = [],
        alternatives: [Statement] = [], consequences: [Statement] = [], confidence: Confidence,
        refs: [CodeRef] = [], tradeoffs: [DecisionTradeoff] = [], componentIds: [String] = [],
        reviewerState: ReviewerState = .unreviewed, reviewerNote: String = "",
        level: AbstractionLevel = .system, question: String? = nil, options: [DecisionOption] = [],
        shape: DecisionShape? = nil, why: Statement? = nil, significance: ReviewSignificance? = nil,
        impacts: [DecisionImpact] = [], significanceReason: String? = nil,
        reviewerPlacement: ReviewPlacement? = nil
    ) {
        self.id = id
        self.title = title
        self.decision = decision
        self.rationale = rationale
        self.alternatives = alternatives
        self.consequences = consequences
        self.confidence = confidence
        self.refs = refs
        self.tradeoffs = tradeoffs
        self.componentIds = componentIds
        self.reviewerState = reviewerState
        self.reviewerNote = reviewerNote
        self.level = level
        self.question = question
        self.options = options
        self.shape = shape
        self.why = why
        self.significance = significance
        self.impacts = impacts
        self.significanceReason = significanceReason
        self.reviewerPlacement = reviewerPlacement
    }
    enum CodingKeys: String, CodingKey {
        case id, title, decision, rationale, alternatives, consequences, confidence, refs,
            tradeoffs, componentIds, reviewerState, reviewerNote, level, question, options, shape, why,
            significance, impacts, significanceReason, reviewerPlacement
    }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        decision = try c.decode(Statement.self, forKey: .decision)
        rationale = try c.decodeIfPresent([Statement].self, forKey: .rationale) ?? []
        alternatives = try c.decodeIfPresent([Statement].self, forKey: .alternatives) ?? []
        consequences = try c.decodeIfPresent([Statement].self, forKey: .consequences) ?? []
        confidence = try c.decodeIfPresent(Confidence.self, forKey: .confidence) ?? .medium
        refs = try c.decodeIfPresent([CodeRef].self, forKey: .refs) ?? []
        tradeoffs =
            ((try? c.decodeIfPresent([LenientDecodable<DecisionTradeoff>].self, forKey: .tradeoffs)) ?? nil)?
            .compactMap(\.value) ?? []
        componentIds = try c.decodeIfPresent([String].self, forKey: .componentIds) ?? []
        reviewerState = try c.decodeIfPresent(ReviewerState.self, forKey: .reviewerState) ?? .unreviewed
        reviewerNote = try c.decodeIfPresent(String.self, forKey: .reviewerNote) ?? ""
        level = try c.decodeIfPresent(AbstractionLevel.self, forKey: .level) ?? .system
        question = try c.decodeIfPresent(String.self, forKey: .question)
        options = (try? c.decodeIfPresent([DecisionOption].self, forKey: .options)) ?? []
        shape = (try? c.decodeIfPresent(DecisionShape.self, forKey: .shape)) ?? nil
        why = try? c.decodeIfPresent(Statement.self, forKey: .why)
        significance = (try? c.decodeIfPresent(ReviewSignificance.self, forKey: .significance)) ?? nil
        impacts =
            ((try? c.decodeIfPresent([String].self, forKey: .impacts)) ?? nil)?
            .compactMap(DecisionImpact.init(lenient:)) ?? []
        significanceReason = (try? c.decodeIfPresent(String.self, forKey: .significanceReason))
            .flatMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        reviewerPlacement = (try? c.decodeIfPresent(ReviewPlacement.self, forKey: .reviewerPlacement)) ?? nil
    }
}

enum TradeoffProminence: String, Codable, Hashable, Sendable {
    case primary
    case secondary
}

struct LenientDecodable<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
}

struct DecisionTradeoff: Codable, Hashable, Sendable {
    var dimensionA: String
    var dimensionB: String
    var chosenPosition: Double = 0.5
    var explanation: Statement?
    var prominence: TradeoffProminence = .primary
    var refs: [CodeRef] = []

    init(
        dimensionA: String, dimensionB: String, chosenPosition: Double = 0.5, explanation: Statement? = nil,
        prominence: TradeoffProminence = .primary, refs: [CodeRef] = []
    ) {
        self.dimensionA = dimensionA
        self.dimensionB = dimensionB
        self.chosenPosition = chosenPosition
        self.explanation = explanation
        self.prominence = prominence
        self.refs = refs
    }
    enum CodingKeys: String, CodingKey { case dimensionA, dimensionB, chosenPosition, explanation, prominence, refs }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dimensionA = try c.decode(String.self, forKey: .dimensionA)
        dimensionB = try c.decode(String.self, forKey: .dimensionB)
        let position = (try? c.decodeIfPresent(Double.self, forKey: .chosenPosition)) ?? nil
        chosenPosition = min(max(position ?? 0.5, 0), 1)
        explanation = try? c.decodeIfPresent(Statement.self, forKey: .explanation)
        prominence = (try? c.decodeIfPresent(TradeoffProminence.self, forKey: .prominence)) ?? .primary
        refs = (try? c.decodeIfPresent([CodeRef].self, forKey: .refs)) ?? []
    }

    var chosenDimension: String { chosenPosition >= 0.5 ? dimensionB : dimensionA }
    var otherDimension: String { chosenPosition >= 0.5 ? dimensionA : dimensionB }
}

struct FlowStep: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var index: Int
    var title: String
    var componentId: String?
    var refs: [CodeRef] = []
    var stateDelta: String?
    var branches: [String] = []
    var externalCalls: [String] = []
    var errorPaths: [String] = []
    var changeKind: ChangeKind = .unchanged
    var isAsyncBoundaryAfter: Bool = false
    var caution: String?

    init(
        id: String, index: Int, title: String, componentId: String? = nil, refs: [CodeRef] = [],
        stateDelta: String? = nil, branches: [String] = [], externalCalls: [String] = [],
        errorPaths: [String] = [], changeKind: ChangeKind = .unchanged,
        isAsyncBoundaryAfter: Bool = false, caution: String? = nil
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.componentId = componentId
        self.refs = refs
        self.stateDelta = stateDelta
        self.branches = branches
        self.externalCalls = externalCalls
        self.errorPaths = errorPaths
        self.changeKind = changeKind
        self.isAsyncBoundaryAfter = isAsyncBoundaryAfter
        self.caution = caution
    }
    enum CodingKeys: String, CodingKey {
        case id, index, title, componentId, refs, stateDelta, branches, externalCalls, errorPaths,
            changeKind, isAsyncBoundaryAfter, caution
    }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        title = try c.decode(String.self, forKey: .title)
        componentId = try c.decodeIfPresent(String.self, forKey: .componentId)
        refs = try c.decodeIfPresent([CodeRef].self, forKey: .refs) ?? []
        stateDelta = try c.decodeIfPresent(String.self, forKey: .stateDelta)
        branches = try c.decodeIfPresent([String].self, forKey: .branches) ?? []
        externalCalls = try c.decodeIfPresent([String].self, forKey: .externalCalls) ?? []
        errorPaths = try c.decodeIfPresent([String].self, forKey: .errorPaths) ?? []
        changeKind = try c.decodeIfPresent(ChangeKind.self, forKey: .changeKind) ?? .unchanged
        isAsyncBoundaryAfter = try c.decodeIfPresent(Bool.self, forKey: .isAsyncBoundaryAfter) ?? false
        caution = try c.decodeIfPresent(String.self, forKey: .caution)
    }
}

struct FlowNode: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var steps: [FlowStep] = []
    var entryPointId: String?
    var storySteps: [Statement] = []
    var behavior: FlowBehavior?

    init(
        id: String, title: String, steps: [FlowStep] = [], entryPointId: String? = nil, storySteps: [Statement] = [],
        behavior: FlowBehavior? = nil
    ) {
        self.id = id
        self.title = title
        self.steps = steps
        self.entryPointId = entryPointId
        self.storySteps = storySteps
        self.behavior = behavior
    }
    enum CodingKeys: String, CodingKey { case id, title, steps, entryPointId, storySteps, behavior }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        steps = try c.decodeIfPresent([FlowStep].self, forKey: .steps) ?? []
        entryPointId = try c.decodeIfPresent(String.self, forKey: .entryPointId)
        storySteps = try c.decodeIfPresent([Statement].self, forKey: .storySteps) ?? []
        behavior = (try? c.decodeIfPresent(FlowBehavior.self, forKey: .behavior)) ?? nil
        if behavior?.nodes.isEmpty == true { behavior = nil }
    }
}

struct EntryPointNode: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var kind: String
    var changeKind: ChangeKind
    var refs: [CodeRef] = []
    var flowId: String?
    var triggersLabel: String?

    init(
        id: String, title: String, kind: String, changeKind: ChangeKind, refs: [CodeRef] = [], flowId: String? = nil,
        triggersLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.changeKind = changeKind
        self.refs = refs
        self.flowId = flowId
        self.triggersLabel = triggersLabel
    }
    enum CodingKeys: String, CodingKey { case id, title, kind, changeKind, refs, flowId, triggersLabel }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "unknown"
        changeKind = try c.decodeIfPresent(ChangeKind.self, forKey: .changeKind) ?? .touched
        refs = try c.decodeIfPresent([CodeRef].self, forKey: .refs) ?? []
        flowId = try c.decodeIfPresent(String.self, forKey: .flowId)
        triggersLabel = try c.decodeIfPresent(String.self, forKey: .triggersLabel)
    }
}

struct QuestionNode: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var text: String
    var relatedIds: [String] = []
    var refs: [CodeRef] = []

    enum CodingKeys: String, CodingKey { case id, text, relatedIds, refs }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try c.decode(String.self, forKey: .text)
        relatedIds = try c.decodeIfPresent([String].self, forKey: .relatedIds) ?? []
        refs = try c.decodeIfPresent([CodeRef].self, forKey: .refs) ?? []
    }
}

enum ConsiderationKind: String, Codable, Hashable, Sendable {
    case concern
    case question
}

enum ConsiderationCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case errorHandling = "error-handling"
    case testCoverage = "test-coverage"
    case compatibility
    case reliability
    case scaling
    case security
    case architecture
    case productBehavior = "product-behavior"

    var label: String {
        switch self {
        case .errorHandling: return "Error handling"
        case .testCoverage: return "Test coverage"
        case .compatibility: return "Compatibility"
        case .reliability: return "Reliability"
        case .scaling: return "Scaling"
        case .security: return "Security"
        case .architecture: return "Architecture"
        case .productBehavior: return "Product behavior"
        }
    }

    static func lenientKey(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "behaviour", with: "behavior")
            .split(whereSeparator: { !$0.isLetter })
            .joined(separator: "-")
    }

    init?(lenient raw: String) {
        let key = Self.lenientKey(raw)
        switch key {
        case "performance", "scalability": self = .scaling
        case "tests", "testing", "test": self = .testCoverage
        case "behavior", "product": self = .productBehavior
        default:
            guard let match = Self(rawValue: key) else { return nil }
            self = match
        }
    }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let category = Self(lenient: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown category \(raw)"))
        }
        self = category
    }
}

enum JudgmentType: String, Codable, Hashable, Sendable, CaseIterable {
    case potentialProblem = "potential-problem"
    case confirmIntent = "confirm-intent"
    case designDecision = "design-decision"
    case compatibilityDecision = "compatibility-decision"
    case operationalRisk = "operational-risk"
    case securityDecision = "security-decision"
    case unclearRequirement = "unclear-requirement"
    case externalDependency = "external-dependency"

    var label: String {
        switch self {
        case .potentialProblem: return "Potential problem"
        case .confirmIntent: return "Confirm intent"
        case .designDecision: return "Design decision"
        case .compatibilityDecision: return "Compatibility decision"
        case .operationalRisk: return "Operational risk"
        case .securityDecision: return "Security decision"
        case .unclearRequirement: return "Unclear requirement"
        case .externalDependency: return "External dependency"
        }
    }

    init?(lenient raw: String) {
        let key = ConsiderationCategory.lenientKey(raw)
        switch key {
        case "bug", "defect", "problem", "risk-of-defect": self = .potentialProblem
        case "intent", "intentional", "confirm", "confirm-intended-behavior": self = .confirmIntent
        case "tradeoff", "trade-off", "architectural-tradeoff", "design": self = .designDecision
        case "compatibility", "compatibility-constraint": self = .compatibilityDecision
        case "operational", "operations", "operability": self = .operationalRisk
        case "security": self = .securityDecision
        case "requirement", "unclear", "open-question": self = .unclearRequirement
        case "dependency", "cross-product-dependency", "cross-team-dependency": self = .externalDependency
        default:
            guard let match = Self(rawValue: key) else { return nil }
            self = match
        }
    }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let type = Self(lenient: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown judgment type \(raw)"))
        }
        self = type
    }
}

struct Consideration: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var category: ConsiderationCategory?
    var judgmentType: JudgmentType?
    var headline: String
    var impact: String
    var decision: String?
    var kind: ConsiderationKind = .concern
    var provenance: Provenance = .interpretation
    var confidence: Confidence?
    var evidence: String?
    var relatedIds: [String] = []
    var refs: [CodeRef] = []
    var flowAnchors: [FlowAnchor] = []

    init(
        id: String, category: ConsiderationCategory? = nil, judgmentType: JudgmentType? = nil, headline: String,
        impact: String,
        decision: String? = nil, kind: ConsiderationKind = .concern,
        provenance: Provenance = .interpretation, confidence: Confidence? = nil,
        evidence: String? = nil, relatedIds: [String] = [], refs: [CodeRef] = [],
        flowAnchors: [FlowAnchor] = []
    ) {
        self.id = id
        self.category = category
        self.judgmentType = judgmentType
        self.headline = headline
        self.impact = impact
        self.decision = decision
        self.kind = kind
        self.provenance = provenance
        self.confidence = confidence
        self.evidence = evidence
        self.relatedIds = relatedIds
        self.refs = refs
        self.flowAnchors = flowAnchors
    }
    enum CodingKeys: String, CodingKey {
        case id, category, judgmentType, headline, impact, decision, kind, provenance, confidence, evidence, relatedIds,
            refs, flowAnchors
    }
    private enum LegacyKeys: String, CodingKey { case question, detail, explanation }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        category = try? c.decodeIfPresent(ConsiderationCategory.self, forKey: .category)
        judgmentType = try? c.decodeIfPresent(JudgmentType.self, forKey: .judgmentType)
        if let headline = try c.decodeIfPresent(String.self, forKey: .headline) {
            self.headline = Self.plainProse(headline)
        } else {
            headline = Self.plainProse(try legacy.decode(String.self, forKey: .question))
        }
        impact = Self.plainProse(
            try c.decodeIfPresent(String.self, forKey: .impact)
                ?? legacy.decodeIfPresent(String.self, forKey: .detail) ?? "")
        decision = Self.nonEmpty(try c.decodeIfPresent(String.self, forKey: .decision).map(Self.plainProse))
        kind = (try? c.decodeIfPresent(ConsiderationKind.self, forKey: .kind)) ?? .concern
        provenance = (try? c.decodeIfPresent(Provenance.self, forKey: .provenance)) ?? .interpretation
        confidence = try? c.decodeIfPresent(Confidence.self, forKey: .confidence)
        evidence =
            try c.decodeIfPresent(String.self, forKey: .evidence)
            ?? legacy.decodeIfPresent(String.self, forKey: .explanation)
        relatedIds = try c.decodeIfPresent([String].self, forKey: .relatedIds) ?? []
        refs = try c.decodeIfPresent([CodeRef].self, forKey: .refs) ?? []
        flowAnchors =
            (try? c.decodeIfPresent([FailableDecode<FlowAnchor>].self, forKey: .flowAnchors))?.compactMap(\.value) ?? []
    }

    static func plainProse(_ text: String) -> String {
        text.replacingOccurrences(of: "`", with: "")
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var reviewerAsk: String { decision ?? headline }

    var contextLabel: String? {
        let parts = [category?.label, judgmentType?.label].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var briefing: String {
        [headline, impact, decision.map { "Decision: \($0)" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".") || $0.hasSuffix("?") ? $0 : $0 + "." }
            .joined(separator: " ")
    }
}

struct ChangeMapEntry: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var filesChanged: Int

    init(name: String, filesChanged: Int) {
        self.name = name
        self.filesChanged = filesChanged
    }
    enum CodingKeys: String, CodingKey { case name, filesChanged }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        filesChanged = try c.decodeIfPresent(Int.self, forKey: .filesChanged) ?? 0
    }
}

struct PRSummary: Codable, Hashable, Sendable {
    var repo: String
    var number: Int
    var title: String
    var author: String
    var state: String
    var branch: String
    var baseBranch: String
    var headSha: String
    var baseSha: String
    var intent: Statement
    var filesChanged: Int
    var additions: Int
    var deletions: Int
    var changeMap: [ChangeMapEntry] = []
    var architectureImpact: Statement?
    var needsJudgment: [Statement] = []
    var uncertainties: [Statement] = []
    var ticket: TicketInfo?
    var problemToBeSolved: Statement?
    var howItWasSolved: Statement?
    var considerations: [Consideration]?
    var glance: PRGlance?
}

struct PRGraph: Codable, Hashable, Sendable {
    var pr: PRSummary
    var components: [ComponentNode] = []
    var decisions: [DecisionNode] = []
    var flows: [FlowNode] = []
    var entryPoints: [EntryPointNode] = []
    var questions: [QuestionNode] = []
    var behaviorChanges: [BehaviorChange] = []
    var architectureEdges: [ArchitectureEdge] = []
    var boundaries: [SystemBoundary] = []
    var architecture: ArchitectureAssessment?
    var refChecks: [String: RefCheck]?

    var refCheckTotal: RefCheck? {
        refChecks.map { $0.values.reduce(RefCheck(), +) }
    }

    func component(_ id: String?) -> ComponentNode? { components.first { $0.id == id } }
    func decision(_ id: String?) -> DecisionNode? { decisions.first { $0.id == id } }
    func flow(_ id: String?) -> FlowNode? { flows.first { $0.id == id } }
    func entryPoint(_ id: String?) -> EntryPointNode? { entryPoints.first { $0.id == id } }

    var dominantBehaviorChange: BehaviorChange? { behaviorChanges.first }

    func decisions(affecting componentId: String) -> [DecisionNode] {
        decisions.filter { $0.componentIds.contains(componentId) }
    }
    func flows(traversing componentId: String) -> [FlowNode] {
        flows.filter { flow in flow.steps.contains { $0.componentId == componentId } }
    }

    func implementationComponents(for systemComponentId: String) -> [ComponentNode] {
        guard let system = component(systemComponentId) else { return [] }
        let byName = components.filter { impl in
            impl.level >= .component
                && system.implementedBy.contains { $0.caseInsensitiveCompare(impl.title) == .orderedSame }
        }
        if !byName.isEmpty { return byName }
        return components.filter { $0.dependsOnIds.contains(systemComponentId) && $0.level >= .component }
    }

    func reviewProgress(discussed: Set<String> = []) -> (reviewed: Int, total: Int) {
        let items = thingsToThinkAbout
        return (items.filter { isResolved($0, discussed: discussed) }.count, items.count)
    }

    func isResolved(_ item: Consideration, discussed: Set<String>) -> Bool {
        let decision = decision(reviewDecisionId(for: item))
        if let decision, decision.reviewerState != .unreviewed { return true }
        let judgedOnDecision = decision.map(isToReview) ?? false
        return !judgedOnDecision && discussed.contains(item.id)
    }

    var resolvedEdges: [ArchitectureEdge] {
        if !architectureEdges.isEmpty { return architectureEdges }
        var out: [ArchitectureEdge] = []
        for c in components {
            for dep in c.dependsOnIds where component(dep) != nil {
                let change: EdgeChange =
                    (c.changeKind == .new || component(dep)?.changeKind == .new)
                    ? .new : ((c.changeKind == .changed) ? .changed : .existing)
                out.append(
                    ArchitectureEdge(
                        id: "\(c.id)->\(dep)", fromId: c.id, toId: dep, label: "depends on",
                        flow: .sync, change: change, isTrustBoundary: c.isTrustBoundaryEdge
                    ))
            }
        }
        return out
    }

    func decisions(forEdge edge: ArchitectureEdge) -> [DecisionNode] {
        if !edge.decisionIds.isEmpty {
            return decisions.filter { edge.decisionIds.contains($0.id) }
        }
        return decisions.filter { $0.componentIds.contains(edge.fromId) && $0.componentIds.contains(edge.toId) }
    }
}
