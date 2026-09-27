import XCTest
import CoreGraphics
import Foundation
@testable import Contour

/// Micro-benchmarks for the costs issue #63 raised: nothing else in the app is bounded by
/// PR size the way `PromptBuilder` bounds the prompt (§14). These print timings for diff
/// parsing, streaming extraction, architecture layout, and graph (de)serialization on
/// inputs sized well past a normal PR, so a regression that turns one of these
/// superlinear shows up as a number here instead of only as a slow app on a huge PR.
///
/// Run with `swift test --filter BenchmarkTests`. Every input is generated deterministically
/// (a seeded PRNG, no real randomness) so a run is reproducible without checking in fixture
/// files. Thresholds are deliberately loose: these exist to print timings and catch
/// algorithmic blowups (quadratic-or-worse), not to enforce a millisecond budget that would
/// flake on a slower machine.
final class BenchmarkTests: XCTestCase {

    // MARK: - Deterministic input generation

    /// A tiny seeded PRNG (splitmix64), so every benchmark's input is the same across runs
    /// and machines.
    private struct SeededGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func nextInt(_ bound: Int) -> Int {
            guard bound > 0 else { return 0 }
            return Int(next() % UInt64(bound))
        }
    }

    private static func chunk(_ text: String, size: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if current.utf8.count >= size {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - UnifiedDiff parsing

    private static func makeLargeDiff(files: Int, linesPerHunk: Int, seed: UInt64) -> String {
        var rng = SeededGenerator(seed: seed)
        var out = ""
        for f in 0..<files {
            let path = "src/module\(f)/file\(f).swift"
            var body: [String] = []
            var oldCount = 0, newCount = 0
            for l in 0..<linesPerHunk {
                switch rng.nextInt(10) {
                case 0:
                    body.append("+    let added\(l) = \(l)")
                    newCount += 1
                case 1:
                    body.append("-    let removed\(l) = \(l)")
                    oldCount += 1
                default:
                    body.append("     let context\(l) = \(l)")
                    oldCount += 1; newCount += 1
                }
            }
            out += "diff --git a/\(path) b/\(path)\n"
            out += "index 0000000..0000001 100644\n"
            out += "--- a/\(path)\n"
            out += "+++ b/\(path)\n"
            out += "@@ -1,\(oldCount) +1,\(newCount) @@ func f\(f)()\n"
            out += body.joined(separator: "\n") + "\n"
        }
        return out
    }

    /// ~40,000 lines across 500 files — tens of thousands of lines, well past a normal PR.
    func testUnifiedDiffParsingOnATensOfThousandsOfLinesDiff() {
        let diff = Self.makeLargeDiff(files: 500, linesPerHunk: 80, seed: 1)
        measure {
            _ = UnifiedDiff.parse(diff)
        }
    }

    // MARK: - StreamingArrayExtractor

    private static func makeStreamedArrayJSON(preambleWords: Int, elementCount: Int, key: String, seed: UInt64) -> String {
        var rng = SeededGenerator(seed: seed)
        let words = ["alpha", "beta", "gamma", "delta", "epsilon", "reads", "writes", "checks", "component", "value"]
        var preamble = ""
        for _ in 0..<preambleWords { preamble += words[rng.nextInt(words.count)] + " " }
        var elements: [String] = []
        for i in 0..<elementCount {
            elements.append(#"{"id": "e\#(i)", "title": "Element number \#(i) with some longer descriptive prose."}"#)
        }
        return #"{"reasoning": "\#(preamble)", "\#(key)": ["# + elements.joined(separator: ", ") + "]}"
    }

    /// Words only — no quote, colon or bracket anywhere — so `"key": [` never matches. This
    /// is the worst case the fix targets: the key never appears, so every fragment used to
    /// re-decode and re-search the *whole* accumulated buffer from scratch (quadratic in
    /// stream length); now each fragment only extends the search by its own size plus a
    /// small fixed overlap.
    private static func makeNoKeyStream(sizeBytes: Int, seed: UInt64) -> String {
        var rng = SeededGenerator(seed: seed)
        let words = ["alpha", "beta", "gamma", "delta", "epsilon", "quick", "brown", "fox", "jumps", "lazy", "value", "component"]
        var out = ""
        out.reserveCapacity(sizeBytes)
        while out.utf8.count < sizeBytes {
            out += words[rng.nextInt(words.count)]
            out += " "
        }
        return out
    }

    /// The key appears almost immediately.
    func testStreamingArrayExtractorWithKeyPresentEarly() {
        let json = Self.makeStreamedArrayJSON(preambleWords: 20, elementCount: 3000, key: "decisions", seed: 11)
        let fragments = Self.chunk(json, size: 512)
        measure {
            var extractor = StreamingArrayExtractor(key: "decisions")
            for fragment in fragments { _ = extractor.consume(fragment) }
        }
    }

    /// A few hundred KB of unrelated prose before the key finally appears — the case the
    /// incremental scan matters most for: without it, every one of the hundreds of
    /// fragments making up that preamble re-scans it from the start.
    func testStreamingArrayExtractorWithKeyPresentLate() {
        let json = Self.makeStreamedArrayJSON(preambleWords: 50_000, elementCount: 200, key: "decisions", seed: 12)
        let fragments = Self.chunk(json, size: 512)
        measure {
            var extractor = StreamingArrayExtractor(key: "decisions")
            for fragment in fragments { _ = extractor.consume(fragment) }
        }
    }

    /// The acceptance criterion in issue #63: a 5 MB stream, fed in small fragments, that
    /// never contains the key. Measured with `measure` for a timing.
    func testStreamingArrayExtractorOnAFiveMegabyteStreamWithNoKeyMeasured() {
        let stream = Self.makeNoKeyStream(sizeBytes: 5_000_000, seed: 13)
        let fragments = Self.chunk(stream, size: 1024)
        measure {
            var extractor = StreamingArrayExtractor(key: "decisions")
            for fragment in fragments { _ = extractor.consume(fragment) }
        }
    }

    /// Same case, run once (not `measure`'s ten iterations) with smaller fragments and a
    /// generous absolute wall-clock bound instead of a tight one. A regression back to the
    /// old whole-buffer-per-fragment behavior would take dramatically longer than this on
    /// any machine — easily minutes rather than seconds — so this is a robust linearity
    /// check without being a flaky one.
    func testStreamingArrayExtractorOnAFiveMegabyteStreamWithNoKeyIsLinear() {
        let stream = Self.makeNoKeyStream(sizeBytes: 5_000_000, seed: 14)
        let fragments = Self.chunk(stream, size: 128)
        let start = Date()
        var extractor = StreamingArrayExtractor(key: "decisions")
        for fragment in fragments { _ = extractor.consume(fragment) }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 30, "5 MB with no key took \(elapsed)s — looks superlinear again")
    }

    // MARK: - GraphLayoutEngine

    private static func makeLayoutInput(
        nodeCount: Int, seed: UInt64
    ) -> (nodes: [GraphLayoutEngine.NodeSpec], edges: [GraphLayoutEngine.EdgeSpec], groups: [GraphLayoutEngine.GroupSpec]) {
        var rng = SeededGenerator(seed: seed)
        let nodes = (0..<nodeCount).map { i in
            GraphLayoutEngine.NodeSpec(id: "n\(i)", size: CGSize(width: 224, height: CGFloat(70 + rng.nextInt(60))))
        }
        var edges: [GraphLayoutEngine.EdgeSpec] = []
        // A DAG: every node after the first points back to an earlier one, so there's
        // always a path in and never a cycle to unwind.
        for i in 1..<nodeCount {
            let target = rng.nextInt(i)
            edges.append(.init(id: "e\(i)", fromId: "n\(target)", toId: "n\(i)",
                               labelSize: CGSize(width: CGFloat(40 + rng.nextInt(80)), height: 20)))
        }
        // A handful of extra cross edges, the way a real architecture graph has some parts
        // depended on by several others.
        for i in 0..<(nodeCount / 4) {
            let a = rng.nextInt(nodeCount), b = rng.nextInt(nodeCount)
            guard a != b else { continue }
            edges.append(.init(id: "x\(i)", fromId: "n\(a)", toId: "n\(b)", labelSize: CGSize(width: 60, height: 20)))
        }
        let groupCount = max(1, nodeCount / 20)
        let groups = (0..<groupCount).map { g in
            GraphLayoutEngine.GroupSpec(id: "g\(g)", memberIds: stride(from: g, to: nodeCount, by: groupCount).map { "n\($0)" })
        }
        return (nodes, edges, groups)
    }

    func testGraphLayoutAt50Nodes() {
        let (nodes, edges, groups) = Self.makeLayoutInput(nodeCount: 50, seed: 21)
        measure {
            _ = GraphLayoutEngine.layout(nodes: nodes, edges: edges, groups: groups)
        }
    }

    func testGraphLayoutAt150Nodes() {
        let (nodes, edges, groups) = Self.makeLayoutInput(nodeCount: 150, seed: 22)
        measure {
            _ = GraphLayoutEngine.layout(nodes: nodes, edges: edges, groups: groups)
        }
    }

    func testGraphLayoutAt300Nodes() {
        let (nodes, edges, groups) = Self.makeLayoutInput(nodeCount: 300, seed: 23)
        measure {
            _ = GraphLayoutEngine.layout(nodes: nodes, edges: edges, groups: groups)
        }
    }

    // MARK: - StageDecoding

    private struct ArchitecturePayload: Encodable {
        var components: [ComponentNode]
        var edges: [ArchitectureEdge]
        var boundaries: [SystemBoundary]
    }

    private static func makeArchitectureObject(componentCount: Int, edgeCount: Int, boundaryCount: Int, seed: UInt64) -> [String: Any] {
        var rng = SeededGenerator(seed: seed)
        let kinds: [ChangeKind] = [.new, .changed, .touched, .unchanged]
        let components = (0..<componentCount).map { i -> ComponentNode in
            ComponentNode(
                id: "c\(i)", title: "Component \(i)", changeKind: kinds[rng.nextInt(kinds.count)],
                summary: Statement(text: "Handles responsibility \(i) of the system.", provenance: .interpretation, confidence: .medium),
                refs: [CodeRef(path: "src/file\(i % 50).swift", startLine: i + 1, endLine: i + 21)]
            )
        }
        let edges = (0..<edgeCount).map { i -> ArchitectureEdge in
            let from = rng.nextInt(componentCount), to = rng.nextInt(componentCount)
            return ArchitectureEdge(id: "e\(i)", fromId: "c\(from)", toId: "c\(to)", label: "payload \(i)")
        }
        let boundaries = (0..<boundaryCount).map { i -> SystemBoundary in
            SystemBoundary(id: "b\(i)", label: "Boundary \(i)", componentIds: (0..<10).map { "c\(($0 + i * 10) % componentCount)" })
        }
        let data = try! JSONEncoder().encode(ArchitecturePayload(components: components, edges: edges, boundaries: boundaries))
        return (try! JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Shape and rough size of a real `architecture` stage response, scaled up to the
    /// 100–300 component range §14's cost concerns name.
    func testStageDecodingArchitectureResultOnALargeGraph() {
        let object = Self.makeArchitectureObject(componentCount: 300, edgeCount: 450, boundaryCount: 40, seed: 31)
        measure {
            _ = try? StageDecoding.decode(StageDecoding.ArchitectureResult.self, stageLabel: "architecture", from: object)
        }
    }

    // MARK: - AnalysisCache

    private static func benchmarkContext(head: String = "bench-head") -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/bench/pull/1", owner: "acme", repo: "bench", number: 1,
            title: "Benchmark PR", body: "", author: "someone", state: "OPEN", headRefName: "bench",
            baseRefName: "main", headSha: head, baseSha: "base1", isCrossRepository: false,
            headCloneURL: "https://github.com/acme/bench.git", additions: 0, deletions: 0, changedFiles: 0,
            files: [], commits: [], comments: [], reviews: [], diff: ""
        )
    }

    private static func makeLargeGraph(componentCount: Int, decisionCount: Int, flowCount: Int, seed: UInt64) -> PRGraph {
        var rng = SeededGenerator(seed: seed)
        var graph = PRGraph.shell(from: benchmarkContext())
        graph.components = (0..<componentCount).map { i in
            ComponentNode(id: "c\(i)", title: "Component \(i)", changeKind: .changed,
                          summary: Statement(text: "Does thing \(i).", provenance: .interpretation, confidence: .medium),
                          refs: [CodeRef(path: "src/file\(i % 50).swift", startLine: i + 1, endLine: i + 21)])
        }
        graph.architectureEdges = (0..<(componentCount * 2)).map { i in
            let from = rng.nextInt(componentCount), to = rng.nextInt(componentCount)
            return ArchitectureEdge(id: "e\(i)", fromId: "c\(from)", toId: "c\(to)", label: "data \(i)")
        }
        graph.boundaries = (0..<max(1, componentCount / 15)).map { i in
            SystemBoundary(id: "b\(i)", label: "Boundary \(i)", componentIds: (0..<10).map { "c\(($0 + i * 10) % componentCount)" })
        }
        graph.decisions = (0..<decisionCount).map { i in
            DecisionNode(id: "d\(i)", title: "Decision \(i)",
                        decision: Statement(text: "Chose option \(i).", provenance: .fact),
                        confidence: .high,
                        refs: [CodeRef(path: "src/file\(i % 50).swift", startLine: i + 1, endLine: i + 5)],
                        componentIds: ["c\(rng.nextInt(componentCount))"])
        }
        graph.flows = (0..<flowCount).map { i in
            FlowNode(id: "f\(i)", title: "Flow \(i)", steps: (0..<5).map { s in
                FlowStep(id: "f\(i)-s\(s)", index: s, title: "Step \(s)", componentId: "c\(rng.nextInt(componentCount))",
                        refs: [CodeRef(path: "src/file\(i % 50).swift", startLine: s + 1, endLine: s + 3)])
            })
        }
        return graph
    }

    /// A save/load round trip through disk (what reopening a PR does — §13), at a graph
    /// size scaled up to §14's 100–300 component range plus a proportional number of
    /// decisions and flows.
    func testAnalysisCacheRoundTripsALargeGraph() {
        let cache = AnalysisCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("contour-benchmark-cache-\(UUID().uuidString)", isDirectory: true))
        let ctx = Self.benchmarkContext()
        let graph = Self.makeLargeGraph(componentCount: 300, decisionCount: 150, flowCount: 60, seed: 41)
        measure {
            cache.save(owner: "acme", repo: "bench", number: 1, headSha: ctx.headSha, baseSha: ctx.baseSha, pipelineVersion: 1,
                       graph: graph, diff: "placeholder diff", completedStages: Set(PipelineStage.analysis))
            _ = cache.load(owner: "acme", repo: "bench", number: 1, headSha: ctx.headSha, baseSha: ctx.baseSha, pipelineVersion: 1)
        }
    }
}
