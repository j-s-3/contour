import Foundation

// MARK: - Provenance primitives (the trust spine, §15)

/// Where a statement's truth comes from. Rendered with distinct color/iconography
/// everywhere in the UI — never blended together.
enum Provenance: String, Codable, Hashable, Sendable {
    case fact             // directly observable from repo/diff
    case claim            // stated by the PR author (description, commit, comment)
    case interpretation   // AI-derived; must be hedged in its own text
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

/// The atomic unit of every claim the app displays. See design doc §11 and §15.
/// Note: `id` is deliberately excluded from the wire format — the AI never assigns
/// identity to a Statement, only to the nodes that own one.
struct Statement: Codable, Hashable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var text: String
    var provenance: Provenance
    var confidence: Confidence?
    var source: String?

    enum CodingKeys: String, CodingKey { case text, provenance, confidence, source }

    init(text: String, provenance: Provenance, confidence: Confidence? = nil, source: String? = nil) {
        self.text = text; self.provenance = provenance; self.confidence = confidence; self.source = source
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        provenance = try c.decode(Provenance.self, forKey: .provenance)
        confidence = try c.decodeIfPresent(Confidence.self, forKey: .confidence)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(provenance, forKey: .provenance)
        try c.encodeIfPresent(confidence, forKey: .confidence)
        try c.encodeIfPresent(source, forKey: .source)
    }
}

// MARK: - Code evidence

enum RefSide: String, Codable, Hashable, Sendable { case head, base }

/// A pointer into real source. The terminal leaf of every concept in the graph (§11).
struct CodeRef: Codable, Hashable, Sendable, Identifiable {
    var path: String
    var startLine: Int
    var endLine: Int
    var blobSha: String?
    var side: RefSide

    var id: String { "\(side.rawValue):\(path):\(startLine)-\(endLine)" }
    var display: String { "\(path):\(startLine)-\(endLine)" }

    init(path: String, startLine: Int, endLine: Int, blobSha: String? = nil, side: RefSide = .head) {
        self.path = path; self.startLine = startLine; self.endLine = endLine
        self.blobSha = blobSha; self.side = side
    }
    enum CodingKeys: String, CodingKey { case path, startLine, endLine, blobSha, side }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        startLine = try c.decodeIfPresent(Int.self, forKey: .startLine) ?? 1
        endLine = try c.decodeIfPresent(Int.self, forKey: .endLine) ?? startLine
        blobSha = try c.decodeIfPresent(String.self, forKey: .blobSha)
        side = try c.decodeIfPresent(RefSide.self, forKey: .side) ?? .head
    }
}

// MARK: - Change classification shared by components / entry points / flow steps

enum ChangeKind: String, Codable, Hashable, Sendable {
    case new, changed, touched, unchanged
    /// Only architecture parts use this: a responsibility the PR takes out of the system.
    case removed
}

// MARK: - Architecture as a whiteboard drawing (§4.3)
//
// Architecture is the handful of boxes a staff engineer would draw to explain where a change
// sits: conceptual parts ("Content Inspection", not `InputReader::try_new`), each with a
// one-line responsibility, joined by edges that say what crosses them ("bytes", "content
// type"). The changed files and call graph are evidence for that drawing, never the drawing.
// A part may contain parts (`ComponentNode.parentId`), which is how the reviewer zooms from
// system to subsystem; implementation-level nodes and code refs sit below that.
//
// Most PRs change little about this structure, and saying so is the point: the delta is
// carried by `ArchitectureAssessment` (how much the structure changed, in words),
// `ResponsibilityDelta` (what a part now does differently) and `ArchitectureEdge.change` /
// `previousLabel` (what now crosses a boundary). Edges and boundaries are separate from
// nodes so a PR can change a relationship without touching either endpoint.

/// Whether a relationship is synchronous (solid arrow, on the caller's critical path) or
/// asynchronous/queued (dashed arrow, decoupled). This is the one architectural fact a
/// reviewer most wants at a glance — did new work land on the request's critical path?
enum EdgeFlow: String, Codable, Hashable, Sendable {
    case sync
    case async
}

/// Change classification carried by an *edge*, so the diagram can emphasize the
/// architectural delta (a newly-introduced interaction) and fade unchanged context.
enum EdgeChange: String, Codable, Hashable, Sendable {
    case new       // interaction introduced by this PR — the delta the eye should go to
    case changed   // interaction existed but its shape/semantics changed
    case existing  // unchanged context — renders faint
    case removed   // interaction deleted by this PR — before-only, struck through
}

/// Which snapshot an element belongs to, for the Before / After / Delta modes.
enum ArchPresence: String, Codable, Hashable, Sendable {
    case before, after, both
}

/// A directed edge between two `ComponentNode`s, labeled with what crosses it — data, an
/// event, a request ("bytes", "content type", "order event"). Direction is the direction of
/// travel (from → to), so the layout reads left-to-right along it. Edges may join parts
/// inside different parents; a zoomed-out diagram lifts them to the visible ancestors.
struct ArchitectureEdge: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var fromId: String
    var toId: String
    /// What crosses the edge, e.g. "buffered bytes", "content type". Older graphs carry a
    /// verb ("triggers") instead. Never a class/method name.
    var label: String
    /// What crossed before this PR, when that changed ("first line" → now "buffered sample").
    var previousLabel: String?
    var flow: EdgeFlow = .sync
    var change: EdgeChange = .existing
    /// True when this edge crosses a security/trust boundary (into another process, a
    /// queue, an external service, or a privilege boundary).
    var isTrustBoundary: Bool = false
    /// True when this edge sits on a user-facing or operationally important critical path
    /// (e.g. the synchronous upload path). Combined with `change == .new` this is the
    /// "new work on the critical path" case the redesign most wants to surface.
    var onCriticalPath: Bool = false
    /// Decisions this relationship embodies — the bridge from architecture to review
    /// judgment ("run this synchronously after upload?").
    var decisionIds: [String] = []
    /// Optional one-line annotation shown on the edge, e.g. "NEW WORK ON CRITICAL PATH".
    var note: String?

    /// Which Before/After snapshot this edge belongs to, derived from its change kind.
    var presence: ArchPresence {
        switch change {
        case .new: return .after
        case .removed: return .before
        case .changed, .existing: return .both
        }
    }

    init(id: String = UUID().uuidString, fromId: String, toId: String, label: String,
         flow: EdgeFlow = .sync, change: EdgeChange = .existing, isTrustBoundary: Bool = false,
         onCriticalPath: Bool = false, decisionIds: [String] = [], note: String? = nil,
         previousLabel: String? = nil) {
        self.id = id; self.fromId = fromId; self.toId = toId; self.label = label
        self.previousLabel = previousLabel
        self.flow = flow; self.change = change; self.isTrustBoundary = isTrustBoundary
        self.onCriticalPath = onCriticalPath; self.decisionIds = decisionIds; self.note = note
    }
    enum CodingKeys: String, CodingKey {
        case id, fromId, toId, label, previousLabel, flow, change, isTrustBoundary, onCriticalPath, decisionIds, note
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        fromId = try c.decode(String.self, forKey: .fromId)
        toId = try c.decode(String.self, forKey: .toId)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        previousLabel = (try? c.decodeIfPresent(String.self, forKey: .previousLabel)).flatMap { $0?.isEmpty == false ? $0 : nil }
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

/// A named grouping drawn as a container behind the nodes it holds — the application
/// process, an external service, a datastore, a trust boundary. Only boundaries relevant
/// to understanding the PR should be emitted.
struct SystemBoundary: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var label: String
    var kind: BoundaryKind = .application
    var componentIds: [String] = []

    init(id: String = UUID().uuidString, label: String, kind: BoundaryKind = .application, componentIds: [String] = []) {
        self.id = id; self.label = label; self.kind = kind; self.componentIds = componentIds
    }
    enum CodingKeys: String, CodingKey { case id, label, kind, componentIds }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        kind = try c.decodeIfPresent(BoundaryKind.self, forKey: .kind) ?? .application
        componentIds = try c.decodeIfPresent([String].self, forKey: .componentIds) ?? []
    }
}

/// How much a PR changes the system's structure. Words, not a score: "low" means the boxes
/// and arrows are the same and something about one of them moved.
enum ArchitecturalImpact: String, Codable, Hashable, Sendable, CaseIterable {
    /// Same parts, same relationships, same information crossing them.
    case none
    /// Same parts and relationships; a responsibility or what crosses one boundary changed.
    case low
    /// A relationship or part added, removed, or moved.
    case moderate
    /// The shape of the system changed — new work on a critical path, a new boundary crossed.
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

/// The architecture stage's answer to "what did this PR change about the structure?" — the
/// first thing the Architecture lens says, above the diagram.
struct ArchitectureAssessment: Codable, Hashable, Sendable {
    var impact: ArchitecturalImpact
    /// One short line, e.g. "No structural change" or "Publishing now reindexes search".
    var headline: String
    /// One to three sentences naming the relationship or responsibility that changed.
    var explanation: Statement?
    /// The part and relationship ids where the change lives, most important first.
    var focusIds: [String] = []

    init(impact: ArchitecturalImpact, headline: String, explanation: Statement? = nil, focusIds: [String] = []) {
        self.impact = impact; self.headline = headline; self.explanation = explanation; self.focusIds = focusIds
    }
    enum CodingKeys: String, CodingKey { case impact, headline, explanation, focusIds }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        impact = (try? c.decodeIfPresent(ArchitecturalImpact.self, forKey: .impact)) ?? .low
        headline = try c.decodeIfPresent(String.self, forKey: .headline) ?? ""
        explanation = try? c.decodeIfPresent(Statement.self, forKey: .explanation)
        focusIds = (try? c.decodeIfPresent([String].self, forKey: .focusIds)) ?? []
    }
}

/// What a part does differently after this PR, as two short phrases ("first line" →
/// "buffered sample") plus one sentence for the inspector.
struct ResponsibilityDelta: Codable, Hashable, Sendable {
    var before: String?
    var after: String?
    var summary: Statement?

    init(before: String? = nil, after: String? = nil, summary: Statement? = nil) {
        self.before = before; self.after = after; self.summary = summary
    }
    enum CodingKeys: String, CodingKey { case before, after, summary }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        before = (try? c.decodeIfPresent(String.self, forKey: .before)).flatMap { $0?.isEmpty == false ? $0 : nil }
        after = (try? c.decodeIfPresent(String.self, forKey: .after)).flatMap { $0?.isEmpty == false ? $0 : nil }
        summary = try? c.decodeIfPresent(Statement.self, forKey: .summary)
    }
}

// MARK: - Abstraction levels (Behavior → System → Components → Implementation → Code)
//
// The reviewer's mental model is a strict hierarchy, never bottom-up. Every major node
// carries an explicit level so views can filter/zoom instead of dumping everything at
// once. Lower rawValue = higher (more conceptual) in the hierarchy.
enum AbstractionLevel: String, Codable, Comparable, Hashable, Sendable, CaseIterable {
    // String-backed, not Int-backed: every prompt asks `pi` for a level as a string label
    // ("behavior"/"system"/"component"/"implementation", per PromptBuilder), and a real
    // response confirmed it comes back that way (`"level":"system"`). An Int raw value
    // decodes fine against `pi`'s own JSON.encode round-trip in tests but throws a
    // typeMismatch the first time it meets a real string from the model — exactly the kind
    // of mismatch this type exists to prevent everywhere else in this file.
    case behavior
    case system
    case component
    case implementation

    /// Ordering for the Comparable conformance (lower = higher/more conceptual), independent
    /// of the raw string so callers can't rely on rawValue for sort order by accident.
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

// MARK: - Reviewer state on decisions (§4.4)

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

// MARK: - Review significance (§4.4)
//
// Where human judgment adds the most value, assessed independently of abstraction level:
// an implementation-level choice about retries or transaction boundaries can matter more
// than an architectural-looking one about where a helper lives. Significance decides what
// Decisions asks the reviewer to judge; `AbstractionLevel` only says what kind of choice it is.

/// How much a decision deserves the reviewer's conscious agreement before approving.
/// Internal ranking only — never shown as a score.
enum ReviewSignificance: String, Codable, Hashable, Sendable, Comparable {
    /// Getting it wrong could materially hurt correctness, data, reliability, compatibility…
    /// A strong engineer would want to stop and consciously agree with it.
    case high
    /// Real but contained consequences — worth knowing, not worth stopping for.
    case medium
    /// Local, easily reversed, or with no material consequence identified.
    case low

    private var rank: Int {
        switch self {
        case .high: return 2
        case .medium: return 1
        case .low: return 0
        }
    }

    static func < (lhs: ReviewSignificance, rhs: ReviewSignificance) -> Bool { lhs.rank < rhs.rank }

    /// One step more significant, for a signal (like an Overview concern) that raises it.
    var raised: ReviewSignificance { self == .low ? .medium : .high }
}

/// What a decision could affect if it's wrong. A decision names the one to three that
/// explain its significance.
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

    /// Tolerates the spellings a model writes: "data integrity", "data-integrity",
    /// "dataIntegrity", "Failure behavior".
    init?(lenient raw: String) {
        let key = raw.lowercased().filter(\.isLetter)
        let aliases: [String: DecisionImpact] = [
            "userbehavior": .userBehavior, "uservisiblebehavior": .userBehavior, "ux": .userBehavior,
            "failuresemantics": .failureBehavior, "errorhandling": .failureBehavior,
            "architecturalconstraints": .architecture, "futureevolution": .evolution,
            "backwardscompatibility": .compatibility, "backwardcompatibility": .compatibility
        ]
        guard let match = Self.allCases.first(where: { $0.rawValue.lowercased() == key }) ?? aliases[key] else { return nil }
        self = match
    }
}

/// The reviewer's own call on where a decision belongs, overriding the analysis. The AI
/// proposes the review surface; the human controls it.
enum ReviewPlacement: String, Codable, Hashable, Sendable {
    /// Added to Decisions to Review by the reviewer.
    case review
    /// Marked "Not worth reviewing" by the reviewer.
    case other
}

// MARK: - A decision as the question it answered (§4.4)
//
// The Decisions lens is where the reviewer makes judgments, so a decision is drawn as the
// question the engineer had to answer, the options on the table, and which one this PR
// took — not as a paragraph describing the implementation.

/// How the options of a decision are best drawn. Not every choice is a two-sided spectrum.
enum DecisionShape: String, Codable, Hashable, Sendable {
    /// Two approaches: A ○────● B.
    case binary
    /// An ordered scale (sizes, limits, strictness): 1 line ── 256B ── 1KB ● ── 4KB.
    case threshold
    /// Three or more unordered alternatives, drawn as a radio list.
    case options
    /// An architectural change: the structure before (the first option) and after (the
    /// second, chosen), each label a short chain like "Reader → Inspector", drawn as two
    /// tiny diagrams.
    case beforeAfter
}

/// One option on the table for a decision. `label` is a short noun phrase ("First 1 KB",
/// "Use what's buffered"); `detail` is the property it buys, in a few words
/// ("non-blocking streaming").
struct DecisionOption: Codable, Hashable, Sendable {
    var label: String
    var detail: String?
    var chosen: Bool = false

    init(label: String, detail: String? = nil, chosen: Bool = false) {
        self.label = label; self.detail = detail; self.chosen = chosen
    }
    enum CodingKeys: String, CodingKey { case label, detail, chosen }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        chosen = try c.decodeIfPresent(Bool.self, forKey: .chosen) ?? false
    }
}

// MARK: - Behavior change (the hero of Summary — "what does the system do differently now")
//
// This is the top of the hierarchy: a before/after pipeline of short, present-tense,
// scannable stage labels, tagged so the UI can render them as a compact branching
// diagram rather than prose. Everything else in the graph is reachable as a drill-down
// from this node.

enum BehaviorStageTag: String, Codable, Hashable, Sendable {
    case beforeOnly
    case afterOnly
    case both
}

/// How a pipeline ends, when the ending is the point — "Server rejects the request" before,
/// "Start session" after. Only a pipeline's final stage normally carries one; every other
/// stage leaves it nil and renders as a plain step.
enum BehaviorOutcome: String, Codable, Hashable, Sendable {
    case success
    case failure
}

/// One box in the before/after pipeline diagram. Label is deliberately short (2-5 words,
/// present tense, e.g. "Publish page") — class/method names belong in `componentIds`/
/// `refs`, never in the label itself.
struct BehaviorStage: Codable, Hashable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var label: String
    var tag: BehaviorStageTag
    var componentIds: [String] = []
    var flowId: String?
    var refs: [CodeRef] = []
    var outcome: BehaviorOutcome?

    init(id: String = UUID().uuidString, label: String, tag: BehaviorStageTag,
         componentIds: [String] = [], flowId: String? = nil, refs: [CodeRef] = [],
         outcome: BehaviorOutcome? = nil) {
        self.id = id; self.label = label; self.tag = tag
        self.componentIds = componentIds; self.flowId = flowId; self.refs = refs
        self.outcome = outcome
    }
    enum CodingKeys: String, CodingKey { case id, label, tag, componentIds, flowId, refs, outcome }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        label = try c.decode(String.self, forKey: .label)
        tag = try c.decodeIfPresent(BehaviorStageTag.self, forKey: .tag) ?? .both
        componentIds = try c.decodeIfPresent([String].self, forKey: .componentIds) ?? []
        flowId = try c.decodeIfPresent(String.self, forKey: .flowId)
        refs = try c.decodeIfPresent([CodeRef].self, forKey: .refs) ?? []
        // An unrecognized outcome string degrades to a plain step rather than failing the
        // whole behavior change.
        outcome = (try? c.decodeIfPresent(BehaviorOutcome.self, forKey: .outcome)) ?? nil
    }
}

/// "What does the system do differently now" — the single most important thing about a
/// PR, rendered as a before/after stage pipeline plus why/consequence/human-question, in
/// under ~20 seconds. This is the hero of Summary; everything else is drill-down from it.
struct BehaviorChange: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var before: [BehaviorStage] = []
    var after: [BehaviorStage] = []
    // Only the dominant behaviorChanges entry is required (by the prompt) to carry these —
    // a secondary, less-important entry may omit all three, so decoding must not hard-fail
    // when they're missing (same "honest truncation" rule as everywhere else in this file).
    var why: Statement?
    var consequence: Statement?
    var humanQuestion: Statement?

    init(id: String, title: String, before: [BehaviorStage] = [], after: [BehaviorStage] = [],
         why: Statement? = nil, consequence: Statement? = nil, humanQuestion: Statement? = nil) {
        self.id = id; self.title = title; self.before = before; self.after = after
        self.why = why; self.consequence = consequence; self.humanQuestion = humanQuestion
    }
    enum CodingKeys: String, CodingKey { case id, title, before, after, why, consequence, humanQuestion }
    init(from decoder: Decoder) throws {
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

// MARK: - Graph node types (§3, §11)
//
// Every node type below is decoded from AI-produced JSON that will, in practice,
// sometimes omit fields that have a natural empty default (an empty `refs` array, no
// `dependsOnIds`, etc). Swift's synthesized Decodable treats every stored property as
// required regardless of its default value, so each type provides its own lenient
// init(from:) — decodeIfPresent with a fallback — while keeping a normal memberwise
// init for constructing nodes directly (mock data, tests, pipeline synthesis) and
// relying on synthesized Encodable for the outbound direction, which needs no leniency.

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
    /// Conceptual level of this node. The architecture graph's default rendering only
    /// shows `.system`-level nodes; `.implementation` nodes (real classes/files) become
    /// inspector content rather than graph boxes.
    var level: AbstractionLevel = .system
    /// Free-text names of the classes/files that realize this conceptual responsibility
    /// (e.g. ["SearchIndexCoordinator", "PagePublisher"]). Populated on
    /// `.system`-level nodes; empty on `.implementation`-level nodes, which *are* the
    /// implementation.
    var implementedBy: [String] = []
    /// The part this one sits inside, for zooming from system to subsystem. Nil for the
    /// top-level boxes of the drawing.
    var parentId: String?
    /// What this part does differently after the PR. Nil when it's unchanged context.
    var delta: ResponsibilityDelta?

    init(id: String, title: String, changeKind: ChangeKind, summary: Statement? = nil,
         refs: [CodeRef] = [], decisionIds: [String] = [], flowIds: [String] = [],
         dependsOnIds: [String] = [], isTrustBoundaryEdge: Bool = false, filesChanged: Int = 0,
         level: AbstractionLevel = .system, implementedBy: [String] = [],
         parentId: String? = nil, delta: ResponsibilityDelta? = nil) {
        self.parentId = parentId; self.delta = delta
        self.id = id; self.title = title; self.changeKind = changeKind; self.summary = summary
        self.refs = refs; self.decisionIds = decisionIds; self.flowIds = flowIds
        self.dependsOnIds = dependsOnIds; self.isTrustBoundaryEdge = isTrustBoundaryEdge
        self.filesChanged = filesChanged
        self.level = level; self.implementedBy = implementedBy
    }
    enum CodingKeys: String, CodingKey {
        case id, title, changeKind, summary, refs, decisionIds, flowIds, dependsOnIds, isTrustBoundaryEdge, filesChanged, level, implementedBy, parentId, delta
    }
    init(from decoder: Decoder) throws {
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
    /// What this choice traded, most prominent first. Empty when the choice had no
    /// meaningful tradeoff — one is never manufactured just because the schema allows it.
    var tradeoffs: [DecisionTradeoff] = []
    var componentIds: [String] = []
    var reviewerState: ReviewerState = .unreviewed
    var reviewerNote: String = ""
    /// The kind of choice this is — product behavior, system, component or implementation.
    /// Descriptive only: it never decides whether the reviewer is asked to judge it
    /// (`significance` does).
    var level: AbstractionLevel = .system
    /// How much this deserves the reviewer's conscious judgment. Nil on graphs from before
    /// significance was assessed; `PRGraph.significance(of:)` infers it for those.
    var significance: ReviewSignificance?
    /// What getting this wrong would affect, most relevant first.
    var impacts: [DecisionImpact] = []
    /// One sentence on why the decision does, or doesn't, need the reviewer's attention
    /// ("Classification can vary with how the stream is chunked.").
    var significanceReason: String?
    /// The reviewer moved this decision in or out of Decisions to Review.
    var reviewerPlacement: ReviewPlacement?
    /// The decision phrased as the question the engineer had to answer ("How much data
    /// should binary detection inspect?"). Nil on graphs from before the Decisions redesign;
    /// `PRGraph.brief(for:)` falls back to `title`.
    var question: String?
    /// The options that were on the table, exactly one `chosen`. Empty on older graphs.
    var options: [DecisionOption] = []
    var shape: DecisionShape?
    /// Why this side was chosen, in at most two short lines. The full reasoning stays in
    /// `rationale`.
    var why: Statement?

    init(id: String, title: String, decision: Statement, rationale: [Statement] = [],
         alternatives: [Statement] = [], consequences: [Statement] = [], confidence: Confidence,
         refs: [CodeRef] = [], tradeoffs: [DecisionTradeoff] = [], componentIds: [String] = [],
         reviewerState: ReviewerState = .unreviewed, reviewerNote: String = "",
         level: AbstractionLevel = .system, question: String? = nil, options: [DecisionOption] = [],
         shape: DecisionShape? = nil, why: Statement? = nil, significance: ReviewSignificance? = nil,
         impacts: [DecisionImpact] = [], significanceReason: String? = nil,
         reviewerPlacement: ReviewPlacement? = nil) {
        self.id = id; self.title = title; self.decision = decision; self.rationale = rationale
        self.alternatives = alternatives; self.consequences = consequences; self.confidence = confidence
        self.refs = refs; self.tradeoffs = tradeoffs; self.componentIds = componentIds
        self.reviewerState = reviewerState; self.reviewerNote = reviewerNote
        self.level = level
        self.question = question; self.options = options; self.shape = shape; self.why = why
        self.significance = significance; self.impacts = impacts
        self.significanceReason = significanceReason; self.reviewerPlacement = reviewerPlacement
    }
    enum CodingKeys: String, CodingKey {
        case id, title, decision, rationale, alternatives, consequences, confidence, refs,
             tradeoffs, componentIds, reviewerState, reviewerNote, level, question, options, shape, why,
             significance, impacts, significanceReason, reviewerPlacement
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        decision = try c.decode(Statement.self, forKey: .decision)
        rationale = try c.decodeIfPresent([Statement].self, forKey: .rationale) ?? []
        alternatives = try c.decodeIfPresent([Statement].self, forKey: .alternatives) ?? []
        consequences = try c.decodeIfPresent([Statement].self, forKey: .consequences) ?? []
        confidence = try c.decodeIfPresent(Confidence.self, forKey: .confidence) ?? .medium
        refs = try c.decodeIfPresent([CodeRef].self, forKey: .refs) ?? []
        // A malformed tradeoff drops that one tradeoff, never the decision around it.
        tradeoffs = ((try? c.decodeIfPresent([LenientDecodable<DecisionTradeoff>].self, forKey: .tradeoffs)) ?? nil)?
            .compactMap(\.value) ?? []
        componentIds = try c.decodeIfPresent([String].self, forKey: .componentIds) ?? []
        reviewerState = try c.decodeIfPresent(ReviewerState.self, forKey: .reviewerState) ?? .unreviewed
        reviewerNote = try c.decodeIfPresent(String.self, forKey: .reviewerNote) ?? ""
        level = try c.decodeIfPresent(AbstractionLevel.self, forKey: .level) ?? .system
        question = try c.decodeIfPresent(String.self, forKey: .question)
        options = (try? c.decodeIfPresent([DecisionOption].self, forKey: .options)) ?? []
        // An unrecognized shape degrades to one inferred from the options.
        shape = (try? c.decodeIfPresent(DecisionShape.self, forKey: .shape)) ?? nil
        why = try? c.decodeIfPresent(Statement.self, forKey: .why)
        // An unrecognized significance is treated as unassessed, and falls back to inference.
        significance = (try? c.decodeIfPresent(ReviewSignificance.self, forKey: .significance)) ?? nil
        impacts = ((try? c.decodeIfPresent([String].self, forKey: .impacts)) ?? nil)?
            .compactMap(DecisionImpact.init(lenient:)) ?? []
        significanceReason = (try? c.decodeIfPresent(String.self, forKey: .significanceReason))
            .flatMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        reviewerPlacement = (try? c.decodeIfPresent(ReviewPlacement.self, forKey: .reviewerPlacement)) ?? nil
    }
}

/// How much a tradeoff matters to the decision that made it. A decision usually has at most
/// one primary tradeoff — the tension that makes it worth reviewing — which is drawn on the
/// decision itself. Secondary tradeoffs are real but smaller, and wait in the drill-down.
enum TradeoffProminence: String, Codable, Hashable, Sendable {
    case primary
    case secondary
}

/// Decodes one element of an array, yielding nil instead of failing the whole array.
struct LenientDecodable<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// What a decision gave up to get what it chose — a property of the decision, never a
/// review object of its own. A tradeoff exists because a decision was made, so it lives
/// inside that decision and is judged along with it.
struct DecisionTradeoff: Codable, Hashable, Sendable {
    /// Short phrase naming the quality on one side, e.g. "detection completeness".
    var dimensionA: String
    /// Short phrase naming the quality on the other side, e.g. "streaming behavior".
    var dimensionB: String
    /// Where the choice landed: 0 = fully `dimensionA`, 1 = fully `dimensionB` — drawn as a
    /// point on a line rather than explained in a paragraph.
    var chosenPosition: Double = 0.5
    var explanation: Statement?
    var prominence: TradeoffProminence = .primary
    var refs: [CodeRef] = []

    init(dimensionA: String, dimensionB: String, chosenPosition: Double = 0.5, explanation: Statement? = nil,
         prominence: TradeoffProminence = .primary, refs: [CodeRef] = []) {
        self.dimensionA = dimensionA; self.dimensionB = dimensionB; self.chosenPosition = chosenPosition
        self.explanation = explanation; self.prominence = prominence; self.refs = refs
    }
    enum CodingKeys: String, CodingKey { case dimensionA, dimensionB, chosenPosition, explanation, prominence, refs }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dimensionA = try c.decode(String.self, forKey: .dimensionA)
        dimensionB = try c.decode(String.self, forKey: .dimensionB)
        let position = (try? c.decodeIfPresent(Double.self, forKey: .chosenPosition)) ?? nil
        chosenPosition = min(max(position ?? 0.5, 0), 1)
        explanation = try? c.decodeIfPresent(Statement.self, forKey: .explanation)
        prominence = (try? c.decodeIfPresent(TradeoffProminence.self, forKey: .prominence)) ?? .primary
        refs = (try? c.decodeIfPresent([CodeRef].self, forKey: .refs)) ?? []
    }

    /// Which side the choice leans toward, for "why this side?".
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

    init(id: String, index: Int, title: String, componentId: String? = nil, refs: [CodeRef] = [],
         stateDelta: String? = nil, branches: [String] = [], externalCalls: [String] = [],
         errorPaths: [String] = [], changeKind: ChangeKind = .unchanged,
         isAsyncBoundaryAfter: Bool = false, caution: String? = nil) {
        self.id = id; self.index = index; self.title = title; self.componentId = componentId
        self.refs = refs; self.stateDelta = stateDelta; self.branches = branches
        self.externalCalls = externalCalls; self.errorPaths = errorPaths; self.changeKind = changeKind
        self.isAsyncBoundaryAfter = isAsyncBoundaryAfter; self.caution = caution
    }
    enum CodingKeys: String, CodingKey {
        case id, index, title, componentId, refs, stateDelta, branches, externalCalls, errorPaths,
             changeKind, isAsyncBoundaryAfter, caution
    }
    init(from decoder: Decoder) throws {
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
    /// Implementation-level detail — class/method-level steps. This is what a reviewer
    /// sees after clicking a story step or hitting a "show implementation" affordance,
    /// never the default view.
    var steps: [FlowStep] = []
    var entryPointId: String?
    /// Story-level steps: 3-6 short present-tense labels ("Publish page", "Save revision",
    /// "Rebuild search entry", ...) that render first — the default view of a flow.
    var storySteps: [Statement] = []
    /// The flow as runtime behavior — trigger, stages, branches, boundaries, and what this PR
    /// changed. Nil on graphs from before the Flows redesign; `PRGraph.behavior(for:)`
    /// condenses one from `storySteps` for those.
    var behavior: FlowBehavior?

    init(id: String, title: String, steps: [FlowStep] = [], entryPointId: String? = nil, storySteps: [Statement] = [],
         behavior: FlowBehavior? = nil) {
        self.id = id; self.title = title; self.steps = steps; self.entryPointId = entryPointId
        self.storySteps = storySteps; self.behavior = behavior
    }
    enum CodingKeys: String, CodingKey { case id, title, steps, entryPointId, storySteps, behavior }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        steps = try c.decodeIfPresent([FlowStep].self, forKey: .steps) ?? []
        entryPointId = try c.decodeIfPresent(String.self, forKey: .entryPointId)
        storySteps = try c.decodeIfPresent([Statement].self, forKey: .storySteps) ?? []
        // A malformed behavior model falls back to the condensed one, never drops the flow.
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
    /// e.g. "Search reindex" — a short label for what this trigger causes,
    /// used by the "what causes this?" diagram without requiring a flow lookup.
    var triggersLabel: String?

    init(id: String, title: String, kind: String, changeKind: ChangeKind, refs: [CodeRef] = [], flowId: String? = nil, triggersLabel: String? = nil) {
        self.id = id; self.title = title; self.kind = kind; self.changeKind = changeKind
        self.refs = refs; self.flowId = flowId; self.triggersLabel = triggersLabel
    }
    enum CodingKeys: String, CodingKey { case id, title, kind, changeKind, refs, flowId, triggersLabel }
    init(from decoder: Decoder) throws {
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

    init(id: String, text: String, relatedIds: [String] = [], refs: [CodeRef] = []) {
        self.id = id; self.text = text; self.relatedIds = relatedIds; self.refs = refs
    }
    enum CodingKeys: String, CodingKey { case id, text, relatedIds, refs }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try c.decode(String.self, forKey: .text)
        relatedIds = try c.decodeIfPresent([String].self, forKey: .relatedIds) ?? []
        refs = try c.decodeIfPresent([CodeRef].self, forKey: .refs) ?? []
    }
}

// MARK: - Things to think about (the reviewer's judgment, as questions)

/// Whether an item is a judgment call the reviewer should weigh (a concern or decision) or
/// something the analysis could not establish (an open question). The Overview renders both
/// in one list; this only picks a subtle glyph.
enum ConsiderationKind: String, Codable, Hashable, Sendable {
    case concern
    case question
}

/// One "thing to think about": a question a staff engineer would put to the reviewer, plus
/// one short sentence of why it matters. Deliberately tiny — it must be understood in about
/// five seconds. Everything longer (`explanation`, evidence, related nodes) is drill-down.
struct Consideration: Codable, Hashable, Sendable, Identifiable {
    var id: String
    /// Phrased as a question, roughly a dozen words.
    var question: String
    /// One short sentence of context.
    var detail: String
    var kind: ConsiderationKind = .concern
    var provenance: Provenance = .interpretation
    var confidence: Confidence?
    /// Longer reasoning, shown only on expansion or in contextual chat.
    var explanation: String?
    /// Decision/component/flow ids this item concerns.
    var relatedIds: [String] = []
    var refs: [CodeRef] = []
    /// The exact points in flow diagrams where this matters, so the question can be shown
    /// where it happens in the runtime behavior. Empty on older graphs; `PRGraph.anchors(for:)`
    /// infers a point from `relatedIds` for those.
    var flowAnchors: [FlowAnchor] = []

    init(id: String, question: String, detail: String, kind: ConsiderationKind = .concern,
         provenance: Provenance = .interpretation, confidence: Confidence? = nil,
         explanation: String? = nil, relatedIds: [String] = [], refs: [CodeRef] = [],
         flowAnchors: [FlowAnchor] = []) {
        self.id = id; self.question = question; self.detail = detail; self.kind = kind
        self.provenance = provenance; self.confidence = confidence; self.explanation = explanation
        self.relatedIds = relatedIds; self.refs = refs; self.flowAnchors = flowAnchors
    }
    enum CodingKeys: String, CodingKey {
        case id, question, detail, kind, provenance, confidence, explanation, relatedIds, refs, flowAnchors
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        question = try c.decode(String.self, forKey: .question)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        kind = (try? c.decodeIfPresent(ConsiderationKind.self, forKey: .kind)) ?? .concern
        provenance = (try? c.decodeIfPresent(Provenance.self, forKey: .provenance)) ?? .interpretation
        confidence = try? c.decodeIfPresent(Confidence.self, forKey: .confidence)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation)
        relatedIds = try c.decodeIfPresent([String].self, forKey: .relatedIds) ?? []
        refs = try c.decodeIfPresent([CodeRef].self, forKey: .refs) ?? []
        flowAnchors = (try? c.decodeIfPresent([FailableDecode<FlowAnchor>].self, forKey: .flowAnchors))?.compactMap(\.value) ?? []
    }
}

struct ChangeMapEntry: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var filesChanged: Int

    init(name: String, filesChanged: Int) { self.name = name; self.filesChanged = filesChanged }
    enum CodingKeys: String, CodingKey { case name, filesChanged }
    init(from decoder: Decoder) throws {
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
    /// Short, question-shaped review items from the judgment stage. Optional so graphs
    /// produced before it existed still decode; `PRGraph.thingsToThinkAbout` falls back to
    /// `needsJudgment`/`uncertainties` for those.
    var considerations: [Consideration]?
    /// CI, review and thread state for the Overview's facts line. Optional so graphs saved
    /// before it existed still decode; `refreshMetadata` fills it in on the next open.
    var glance: PRGlance?
}

/// The full knowledge graph for one PR. This is what the pipeline assembles (from
/// per-stage AI results plus raw GitHub facts) and GraphStore holds. Every lens in the
/// UI is a query over this single structure — never a separate document per lens.
struct PRGraph: Codable, Hashable, Sendable {
    var pr: PRSummary
    var components: [ComponentNode] = []
    var decisions: [DecisionNode] = []
    var flows: [FlowNode] = []
    var entryPoints: [EntryPointNode] = []
    var questions: [QuestionNode] = []
    /// The top of the hierarchy: "what does the system do differently now." Usually one
    /// dominant entry (`dominantBehaviorChange`), but a PR can surface several distinct
    /// behavior changes.
    var behaviorChanges: [BehaviorChange] = []
    /// Directed, labeled architecture relationships — the redesigned Architecture view's
    /// primary content. When empty (old cached graphs, a model that hasn't produced them
    /// yet), `resolvedEdges` falls back to synthesizing plain edges from `dependsOnIds`.
    var architectureEdges: [ArchitectureEdge] = []
    /// System/trust/datastore boundaries to draw as containers behind the nodes.
    var boundaries: [SystemBoundary] = []
    /// How much this PR changes the structure, in words. Nil on graphs from before the
    /// Architecture redesign; `pr.architectureImpact` still carries their prose.
    var architecture: ArchitectureAssessment?

    func component(_ id: String?) -> ComponentNode? { components.first { $0.id == id } }
    func decision(_ id: String?) -> DecisionNode? { decisions.first { $0.id == id } }
    func flow(_ id: String?) -> FlowNode? { flows.first { $0.id == id } }
    func entryPoint(_ id: String?) -> EntryPointNode? { entryPoints.first { $0.id == id } }

    /// The single clearest behavior change, if there is one — the hero of Summary.
    var dominantBehaviorChange: BehaviorChange? { behaviorChanges.first }

    func decisions(affecting componentId: String) -> [DecisionNode] {
        decisions.filter { $0.componentIds.contains(componentId) }
    }
    func flows(traversing componentId: String) -> [FlowNode] {
        flows.filter { flow in flow.steps.contains { $0.componentId == componentId } }
    }

    /// Components implementing a given `.system`-level node, resolved by matching
    /// `implementedBy` free-text names against implementation-level component titles when
    /// possible, falling back to `dependsOnIds` for AI-linked implementation nodes.
    func implementationComponents(for systemComponentId: String) -> [ComponentNode] {
        guard let system = component(systemComponentId) else { return [] }
        let byName = components.filter { impl in
            impl.level >= .component && system.implementedBy.contains { $0.caseInsensitiveCompare(impl.title) == .orderedSame }
        }
        if !byName.isEmpty { return byName }
        return components.filter { $0.dependsOnIds.contains(systemComponentId) && $0.level >= .component }
    }

    /// How many of the decisions to review — the ones Decisions shows by default — the
    /// reviewer has consciously judged. Other decisions can still be marked, but they don't
    /// count: this measures judgment, not coverage.
    var reviewProgress: (reviewed: Int, total: Int) {
        let judged = decisionsToReview
        return (judged.filter { $0.reviewerState != .unreviewed }.count, judged.count)
    }

    /// The architecture edges to render. Prefers the rich labeled edges; when none were
    /// produced, degrades gracefully by synthesizing an edge per `dependsOnIds` link so a
    /// pre-redesign graph still draws a (labeled "depends on") diagram rather than nothing.
    var resolvedEdges: [ArchitectureEdge] {
        if !architectureEdges.isEmpty { return architectureEdges }
        var out: [ArchitectureEdge] = []
        for c in components {
            for dep in c.dependsOnIds where component(dep) != nil {
                let change: EdgeChange = (c.changeKind == .new || component(dep)?.changeKind == .new)
                    ? .new : ((c.changeKind == .changed) ? .changed : .existing)
                out.append(ArchitectureEdge(
                    id: "\(c.id)->\(dep)", fromId: c.id, toId: dep, label: "depends on",
                    flow: .sync, change: change, isTrustBoundary: c.isTrustBoundaryEdge
                ))
            }
        }
        return out
    }

    /// Decisions embodied by a relationship. Prefers explicit `edge.decisionIds`; when the
    /// architecture stage didn't link any (decisions are extracted in a later stage), falls
    /// back to decisions whose `componentIds` span both endpoints — a decision about this
    /// very interaction.
    func decisions(forEdge edge: ArchitectureEdge) -> [DecisionNode] {
        if !edge.decisionIds.isEmpty {
            return decisions.filter { edge.decisionIds.contains($0.id) }
        }
        return decisions.filter { $0.componentIds.contains(edge.fromId) && $0.componentIds.contains(edge.toId) }
    }
}
