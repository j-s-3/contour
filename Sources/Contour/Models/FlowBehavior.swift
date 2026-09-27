import Foundation

// MARK: - A flow as runtime behavior (§4.6)
//
// A flow answers "what happens when this is triggered?" at the level an engineer would draw
// on a whiteboard: a trigger, 4-8 processing stages, the branches execution can take, what it
// ends in, and the systems and async boundaries it crosses. It is temporal (what happens over
// time), where Architecture is structural (what the parts are).
//
// The implementation-level `FlowStep`s stay on `FlowNode` as evidence underneath the stages;
// a stage names the steps it summarizes. Graphs from before this model have no `behavior`,
// and `PRGraph.behavior(for:)` condenses one from their story steps instead.

/// What a stage in a behavior diagram is, which picks its shape.
enum FlowNodeKind: String, Codable, Hashable, Sendable {
    /// What starts the flow ("bat opens a file", "User uploads an asset").
    case trigger
    /// A processing stage.
    case step
    /// A branch point, labeled as the question it asks ("What is it?").
    case decision
    /// Where a path ends: the resulting behavior ("Render content", "Show <BINARY>").
    case outcome
    /// A call into a system outside the one being reviewed.
    case external
    /// A write to, or read from, persistent storage.
    case datastore
    /// A shared behavior several flows converge on; `subflowId` names the flow it expands to.
    case subflow
}

/// How this PR changed a stage or connection.
enum FlowChange: String, Codable, Hashable, Sendable {
    case new       // only happens after this PR
    case changed   // happens before and after, differently — `before`/`after` say how
    case existing  // unchanged context, drawn quietly
    case removed   // only happened before this PR
}

extension FlowChange {
    /// Whether an element with this change exists in a snapshot.
    func isVisible(in mode: DiagramMode) -> Bool {
        switch (self, mode) {
        case (.new, .before), (.removed, .after): return false
        default: return true
        }
    }
}

/// One stage of a behavior diagram. The label is a short whiteboard phrase, never a method name;
/// the detail sentence, sub-steps, and implementation are drill-down.
struct FlowBehaviorNode: Codable, Hashable, Sendable, Identifiable {
    var id: String
    /// 2-5 words, e.g. "Inspect content sample".
    var label: String
    var kind: FlowNodeKind = .step
    /// One or two sentences on what happens here, shown when the stage is selected.
    var detail: String?
    var change: FlowChange = .existing
    /// For a changed stage: what it did before and does now, a few words each
    /// ("first line" → "up to 1 KB").
    var before: String?
    var after: String?
    /// The next level down: 2-5 short sub-steps this stage breaks into.
    var substeps: [String] = []
    /// The implementation `FlowStep`s this stage summarizes.
    var stepIds: [String] = []
    var componentId: String?
    /// For a `.subflow` stage: the flow it expands into.
    var subflowId: String?
    /// The system boundary it runs inside, if the flow draws boundaries.
    var boundaryId: String?
    /// Reviewed decisions that materially shape behavior at this point.
    var decisionIds: [String] = []
    var refs: [CodeRef] = []
    /// Provenance is surfaced only when a stage is inferred rather than traced
    /// ("? Likely retries here"); traced stages carry `.fact` and show nothing.
    var provenance: Provenance = .fact
    var confidence: Confidence?

    init(id: String, label: String, kind: FlowNodeKind = .step, detail: String? = nil,
         change: FlowChange = .existing, before: String? = nil, after: String? = nil,
         substeps: [String] = [], stepIds: [String] = [], componentId: String? = nil,
         subflowId: String? = nil, boundaryId: String? = nil, decisionIds: [String] = [],
         refs: [CodeRef] = [], provenance: Provenance = .fact, confidence: Confidence? = nil) {
        self.id = id; self.label = label; self.kind = kind; self.detail = detail
        self.change = change; self.before = before; self.after = after
        self.substeps = substeps; self.stepIds = stepIds; self.componentId = componentId
        self.subflowId = subflowId; self.boundaryId = boundaryId; self.decisionIds = decisionIds
        self.refs = refs; self.provenance = provenance; self.confidence = confidence
    }
    enum CodingKeys: String, CodingKey {
        case id, label, kind, detail, change, before, after, substeps, stepIds, componentId,
             subflowId, boundaryId, decisionIds, refs, provenance, confidence
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        // Unrecognized enum strings degrade to the plain case rather than dropping the stage.
        kind = (try? c.decodeIfPresent(FlowNodeKind.self, forKey: .kind)) ?? .step
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        change = (try? c.decodeIfPresent(FlowChange.self, forKey: .change)) ?? .existing
        before = try c.decodeIfPresent(String.self, forKey: .before)
        after = try c.decodeIfPresent(String.self, forKey: .after)
        substeps = (try? c.decodeIfPresent([String].self, forKey: .substeps)) ?? []
        stepIds = (try? c.decodeIfPresent([String].self, forKey: .stepIds)) ?? []
        componentId = try c.decodeIfPresent(String.self, forKey: .componentId)
        subflowId = try c.decodeIfPresent(String.self, forKey: .subflowId)
        boundaryId = try c.decodeIfPresent(String.self, forKey: .boundaryId)
        decisionIds = (try? c.decodeIfPresent([String].self, forKey: .decisionIds)) ?? []
        refs = (try? c.decodeIfPresent([CodeRef].self, forKey: .refs)) ?? []
        provenance = (try? c.decodeIfPresent(Provenance.self, forKey: .provenance)) ?? .fact
        confidence = try? c.decodeIfPresent(Confidence.self, forKey: .confidence)
    }

    /// Worth a visible "?" — the stage was inferred, not traced in the code.
    var isUncertain: Bool { provenance == .interpretation && confidence != .high }
}

/// A connection between two stages, in the direction execution travels.
struct FlowBehaviorEdge: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(fromId)->\(toId)" }
    var fromId: String
    var toId: String
    /// A branch condition ("Text", "Binary", "Empty"). Nil on an unconditional step.
    var label: String?
    /// `.async` for a queued/event/callback hop, drawn dashed.
    var flow: EdgeFlow = .sync
    var change: FlowChange = .existing

    init(fromId: String, toId: String, label: String? = nil, flow: EdgeFlow = .sync, change: FlowChange = .existing) {
        self.fromId = fromId; self.toId = toId; self.label = label; self.flow = flow; self.change = change
    }
    enum CodingKeys: String, CodingKey { case fromId, toId, label, flow, change }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fromId = try c.decode(String.self, forKey: .fromId)
        toId = try c.decode(String.self, forKey: .toId)
        let raw = try c.decodeIfPresent(String.self, forKey: .label)?.trimmingCharacters(in: .whitespaces)
        label = raw?.isEmpty == false ? raw : nil
        flow = (try? c.decodeIfPresent(EdgeFlow.self, forKey: .flow)) ?? .sync
        change = (try? c.decodeIfPresent(FlowChange.self, forKey: .change)) ?? .existing
    }
}

/// A system the flow runs inside or calls into, drawn as a container around its stages.
struct FlowBoundary: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var label: String
    /// `.external` and `.trust` draw as outside systems; `.datastore` as storage.
    var kind: BoundaryKind = .application

    init(id: String, label: String, kind: BoundaryKind = .application) {
        self.id = id; self.label = label; self.kind = kind
    }
    enum CodingKeys: String, CodingKey { case id, label, kind }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        kind = (try? c.decodeIfPresent(BoundaryKind.self, forKey: .kind)) ?? .application
    }
}

/// The behavioral model of one flow.
struct FlowBehavior: Codable, Hashable, Sendable {
    /// One or two plain sentences telling the story of the flow, as said at a whiteboard.
    var summary: String?
    /// One sentence on how this PR changed the flow. Nil when it didn't.
    var changeSummary: String?
    var nodes: [FlowBehaviorNode] = []
    var edges: [FlowBehaviorEdge] = []
    var boundaries: [FlowBoundary] = []

    init(summary: String? = nil, changeSummary: String? = nil, nodes: [FlowBehaviorNode] = [],
         edges: [FlowBehaviorEdge] = [], boundaries: [FlowBoundary] = []) {
        self.summary = summary; self.changeSummary = changeSummary
        self.nodes = nodes; self.edges = edges; self.boundaries = boundaries
    }
    enum CodingKeys: String, CodingKey { case summary, changeSummary, nodes, edges, boundaries }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        changeSummary = try c.decodeIfPresent(String.self, forKey: .changeSummary)
        // One malformed stage or edge drops itself, never the whole diagram.
        nodes = (try? c.decodeIfPresent([FailableDecode<FlowBehaviorNode>].self, forKey: .nodes))?.compactMap(\.value) ?? []
        let ids = Set(nodes.map(\.id))
        edges = ((try? c.decodeIfPresent([FailableDecode<FlowBehaviorEdge>].self, forKey: .edges))?.compactMap(\.value) ?? [])
            .filter { ids.contains($0.fromId) && ids.contains($0.toId) && $0.fromId != $0.toId }
        boundaries = (try? c.decodeIfPresent([FailableDecode<FlowBoundary>].self, forKey: .boundaries))?.compactMap(\.value) ?? []
    }

    func node(_ id: String?) -> FlowBehaviorNode? { nodes.first { $0.id == id } }
    func incoming(_ id: String) -> [FlowBehaviorEdge] { edges.filter { $0.toId == id } }
    func outgoing(_ id: String) -> [FlowBehaviorEdge] { edges.filter { $0.fromId == id } }

    /// Whether anything in the flow is different after this PR.
    var hasChange: Bool {
        nodes.contains { $0.change != .existing } || edges.contains { $0.change != .existing }
    }

    /// The snapshot a mode shows: Before drops what's new, After drops what's removed, Delta
    /// keeps everything. Edges survive only when both ends do.
    func visible(in mode: DiagramMode) -> FlowBehavior {
        var out = self
        out.nodes = nodes.filter { $0.change.isVisible(in: mode) }
        let ids = Set(out.nodes.map(\.id))
        out.edges = edges.filter { $0.change.isVisible(in: mode) && ids.contains($0.fromId) && ids.contains($0.toId) }
        return out
    }
}

/// Decodes one element of an array, yielding nil instead of failing the array.
struct FailableDecode<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// A point in a flow's behavior diagram: the address a review question is anchored to.
struct FlowAnchor: Codable, Hashable, Sendable {
    var flowId: String
    var nodeId: String

    init(flowId: String, nodeId: String) { self.flowId = flowId; self.nodeId = nodeId }
}
