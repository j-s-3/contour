import Foundation

enum FlowNodeKind: String, Codable, Hashable, Sendable {
    case trigger
    case step
    case decision
    case outcome
    case external
    case datastore
    case subflow
}

enum FlowChange: String, Codable, Hashable, Sendable {
    case new
    case changed
    case existing
    case removed
}

extension FlowChange {
    func isVisible(in mode: DiagramMode) -> Bool {
        switch (self, mode) {
        case (.new, .before), (.removed, .after): return false
        default: return true
        }
    }
}

struct FlowBehaviorNode: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var label: String
    var kind: FlowNodeKind = .step
    var detail: String?
    var change: FlowChange = .existing
    var before: String?
    var after: String?
    var substeps: [String] = []
    var stepIds: [String] = []
    var componentId: String?
    var subflowId: String?
    var boundaryId: String?
    var decisionIds: [String] = []
    var refs: [CodeRef] = []
    var provenance: Provenance = .fact
    var confidence: Confidence?

    init(
        id: String, label: String, kind: FlowNodeKind = .step, detail: String? = nil,
        change: FlowChange = .existing, before: String? = nil, after: String? = nil,
        substeps: [String] = [], stepIds: [String] = [], componentId: String? = nil,
        subflowId: String? = nil, boundaryId: String? = nil, decisionIds: [String] = [],
        refs: [CodeRef] = [], provenance: Provenance = .fact, confidence: Confidence? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.detail = detail
        self.change = change
        self.before = before
        self.after = after
        self.substeps = substeps
        self.stepIds = stepIds
        self.componentId = componentId
        self.subflowId = subflowId
        self.boundaryId = boundaryId
        self.decisionIds = decisionIds
        self.refs = refs
        self.provenance = provenance
        self.confidence = confidence
    }
    enum CodingKeys: String, CodingKey {
        case id, label, kind, detail, change, before, after, substeps, stepIds, componentId,
            subflowId, boundaryId, decisionIds, refs, provenance, confidence
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
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

    var isUncertain: Bool { provenance == .interpretation && confidence != .high }
}

struct FlowBehaviorEdge: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(fromId)->\(toId)" }
    var fromId: String
    var toId: String
    var label: String?
    var flow: EdgeFlow = .sync
    var change: FlowChange = .existing

    init(fromId: String, toId: String, label: String? = nil, flow: EdgeFlow = .sync, change: FlowChange = .existing) {
        self.fromId = fromId
        self.toId = toId
        self.label = label
        self.flow = flow
        self.change = change
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

struct FlowBoundary: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var label: String
    var kind: BoundaryKind = .application

    init(id: String, label: String, kind: BoundaryKind = .application) {
        self.id = id
        self.label = label
        self.kind = kind
    }
    enum CodingKeys: String, CodingKey { case id, label, kind }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        kind = (try? c.decodeIfPresent(BoundaryKind.self, forKey: .kind)) ?? .application
    }
}

struct FlowBehavior: Codable, Hashable, Sendable {
    var summary: String?
    var changeSummary: String?
    var nodes: [FlowBehaviorNode] = []
    var edges: [FlowBehaviorEdge] = []
    var boundaries: [FlowBoundary] = []

    init(
        summary: String? = nil, changeSummary: String? = nil, nodes: [FlowBehaviorNode] = [],
        edges: [FlowBehaviorEdge] = [], boundaries: [FlowBoundary] = []
    ) {
        self.summary = summary
        self.changeSummary = changeSummary
        self.nodes = nodes
        self.edges = edges
        self.boundaries = boundaries
    }
    enum CodingKeys: String, CodingKey { case summary, changeSummary, nodes, edges, boundaries }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        changeSummary = try c.decodeIfPresent(String.self, forKey: .changeSummary)
        nodes =
            (try? c.decodeIfPresent([FailableDecode<FlowBehaviorNode>].self, forKey: .nodes))?.compactMap(\.value) ?? []
        let ids = Set(nodes.map(\.id))
        edges =
            ((try? c.decodeIfPresent([FailableDecode<FlowBehaviorEdge>].self, forKey: .edges))?.compactMap(\.value)
            ?? [])
            .filter { ids.contains($0.fromId) && ids.contains($0.toId) && $0.fromId != $0.toId }
        boundaries =
            (try? c.decodeIfPresent([FailableDecode<FlowBoundary>].self, forKey: .boundaries))?.compactMap(\.value)
            ?? []
    }

    func node(_ id: String?) -> FlowBehaviorNode? { nodes.first { $0.id == id } }
    func incoming(_ id: String) -> [FlowBehaviorEdge] { edges.filter { $0.toId == id } }
    func outgoing(_ id: String) -> [FlowBehaviorEdge] { edges.filter { $0.fromId == id } }

    var hasChange: Bool {
        nodes.contains { $0.change != .existing } || edges.contains { $0.change != .existing }
    }

    func visible(in mode: DiagramMode) -> FlowBehavior {
        var out = self
        out.nodes = nodes.filter { $0.change.isVisible(in: mode) }
        let ids = Set(out.nodes.map(\.id))
        out.edges = edges.filter { $0.change.isVisible(in: mode) && ids.contains($0.fromId) && ids.contains($0.toId) }
        return out
    }
}

struct FailableDecode<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

struct FlowAnchor: Codable, Hashable, Sendable {
    var flowId: String
    var nodeId: String

    init(flowId: String, nodeId: String) {
        self.flowId = flowId
        self.nodeId = nodeId
    }
}
