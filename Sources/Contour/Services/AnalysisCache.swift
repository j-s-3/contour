import Foundation

/// Persists a completed pipeline run keyed by (repo, PR number, headSha, baseSha, pipeline
/// version) so re-opening the same PR — the common case when a reviewer comes back to
/// finish a review — is instant instead of re-running six `pi` calls (§13).
///
/// Keyed by SHA rather than just PR number: if the PR gets new commits, headSha changes
/// and the cache misses correctly rather than showing stale analysis. Keyed by pipeline
/// version too: bumping `AnalysisPipeline.pipelineVersion` after a prompt/schema change
/// invalidates old cache entries rather than trying to decode a shape that no longer
/// matches.
///
/// Bypassed entirely under `CONTOUR_MOCK_ANALYSIS=1`: a mock run's graph is the canned
/// fixture, not an analysis of this PR, so writing it under the PR's real key would make
/// every later real load of that commit show the fixture. Reading is skipped too, so a
/// mock run always shows the fixtures rather than a real analysis cached earlier.
struct AnalysisCache {

    private struct CachedAnalysis: Codable {
        var graph: PRGraph
        var diff: String
        var pipelineVersion: Int
    }

    private let cacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Contour", isDirectory: true)
            .appendingPathComponent("analysis-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private func fileURL(owner: String, repo: String, number: Int, headSha: String, baseSha: String, pipelineVersion: Int) -> URL {
        let name = "\(owner)-\(repo)-\(number)-\(headSha)-\(baseSha)-v\(pipelineVersion).json"
        return cacheDir.appendingPathComponent(name)
    }

    func load(owner: String, repo: String, number: Int, headSha: String, baseSha: String, pipelineVersion: Int) -> (graph: PRGraph, diff: String)? {
        guard !MockAnalysisFixtures.isEnabled else { return nil }
        let url = fileURL(owner: owner, repo: repo, number: number, headSha: headSha, baseSha: baseSha, pipelineVersion: pipelineVersion)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let cached = try? JSONDecoder().decode(CachedAnalysis.self, from: data),
              cached.pipelineVersion == pipelineVersion
        else { return nil }
        return (cached.graph, cached.diff)
    }

    func save(owner: String, repo: String, number: Int, headSha: String, baseSha: String, pipelineVersion: Int, graph: PRGraph, diff: String) {
        guard !MockAnalysisFixtures.isEnabled else { return }
        let url = fileURL(owner: owner, repo: repo, number: number, headSha: headSha, baseSha: baseSha, pipelineVersion: pipelineVersion)
        let cached = CachedAnalysis(graph: graph, diff: diff, pipelineVersion: pipelineVersion)
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Used by the "Re-analyze (ignore cache)" command.
    func invalidate(owner: String, repo: String, number: Int, headSha: String, baseSha: String, pipelineVersion: Int) {
        let url = fileURL(owner: owner, repo: repo, number: number, headSha: headSha, baseSha: baseSha, pipelineVersion: pipelineVersion)
        try? FileManager.default.removeItem(at: url)
    }
}
