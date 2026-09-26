import Foundation

/// Persists pipeline output keyed by (repo, PR number, headSha, baseSha, pipeline version)
/// so re-opening the same PR — the common case when a reviewer comes back to finish a
/// review — is instant instead of re-running every model call (§13).
///
/// Keyed by SHA rather than just PR number: if the PR gets new commits, headSha changes
/// and the exact lookup misses correctly rather than showing stale analysis as current.
/// `latestRevision` is the deliberate, labeled exception: it finds the newest analysis of an
/// *earlier* head so the review can open on it, marked as from a previous revision, while
/// the current one is produced. Keyed by pipeline version too: bumping
/// `AnalysisPipeline.pipelineVersion` after a prompt/schema change invalidates old entries
/// rather than trying to decode a shape that no longer matches.
///
/// Entries are written as each stage lands, not only at the end, and record which stages
/// they hold — so a run interrupted halfway (the app quit, a stage failed) resumes with
/// only the missing stages rather than starting over.
///
/// Bypassed entirely under `CONTOUR_MOCK_ANALYSIS=1`: a mock run's graph is the canned
/// fixture, not an analysis of this PR, so writing it under the PR's real key would make
/// every later real load of that commit show the fixture. Reading is skipped too, so a
/// mock run always shows the fixtures rather than a real analysis cached earlier.
struct AnalysisCache {

    struct Entry {
        var graph: PRGraph
        var diff: String
        /// The analysis stages this entry's graph holds output for.
        var completedStages: Set<PipelineStage>
    }

    private struct CachedAnalysis: Codable {
        var graph: PRGraph
        var diff: String
        var pipelineVersion: Int
        var completedStages: [PipelineStage]?
    }

    private let cacheDir: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Contour", isDirectory: true)
            .appendingPathComponent("analysis-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cacheDir = base
    }

    private func fileURL(owner: String, repo: String, number: Int, headSha: String, baseSha: String, pipelineVersion: Int) -> URL {
        let name = "\(owner)-\(repo)-\(number)-\(headSha)-\(baseSha)-v\(pipelineVersion).json"
        return cacheDir.appendingPathComponent(name)
    }

    func load(owner: String, repo: String, number: Int, headSha: String, baseSha: String, pipelineVersion: Int) -> Entry? {
        guard !MockAnalysisFixtures.isEnabled else { return nil }
        let url = fileURL(owner: owner, repo: repo, number: number, headSha: headSha, baseSha: baseSha, pipelineVersion: pipelineVersion)
        return decode(url, pipelineVersion: pipelineVersion)
    }

    /// The most recently written analysis of this PR at any head other than `excludingHead`.
    /// The repo and number are checked against the decoded graph, not just the filename, so
    /// `a-b/c` and `a/b-c` can never be confused.
    func latestRevision(owner: String, repo: String, number: Int, excludingHead headSha: String, pipelineVersion: Int) -> Entry? {
        guard !MockAnalysisFixtures.isEnabled else { return nil }
        let prefix = "\(owner)-\(repo)-\(number)-"
        let suffix = "-v\(pipelineVersion).json"
        let candidates = ((try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.lastPathComponent.hasSuffix(suffix)
                && !$0.lastPathComponent.hasPrefix(prefix + headSha + "-") }
            .sorted { modified($0) > modified($1) }
        for url in candidates {
            guard let entry = decode(url, pipelineVersion: pipelineVersion),
                  entry.graph.pr.repo == "\(owner)/\(repo)", entry.graph.pr.number == number,
                  entry.graph.pr.headSha != headSha, !entry.completedStages.isEmpty
            else { continue }
            return entry
        }
        return nil
    }

    func save(owner: String, repo: String, number: Int, headSha: String, baseSha: String, pipelineVersion: Int,
              graph: PRGraph, diff: String, completedStages: Set<PipelineStage>) {
        guard !MockAnalysisFixtures.isEnabled else { return }
        let url = fileURL(owner: owner, repo: repo, number: number, headSha: headSha, baseSha: baseSha, pipelineVersion: pipelineVersion)
        let ordered = PipelineStage.analysis.filter(completedStages.contains)
        let cached = CachedAnalysis(graph: graph, diff: diff, pipelineVersion: pipelineVersion, completedStages: ordered)
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Used by the "Re-analyze (ignore cache)" command.
    func invalidate(owner: String, repo: String, number: Int, headSha: String, baseSha: String, pipelineVersion: Int) {
        let url = fileURL(owner: owner, repo: repo, number: number, headSha: headSha, baseSha: baseSha, pipelineVersion: pipelineVersion)
        try? FileManager.default.removeItem(at: url)
    }

    private func decode(_ url: URL, pipelineVersion: Int) -> Entry? {
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedAnalysis.self, from: data),
              cached.pipelineVersion == pipelineVersion
        else { return nil }
        // An entry without a stage list predates partial saves, so it was a complete run.
        let stages = cached.completedStages.map(Set.init) ?? Set(PipelineStage.analysis)
        return Entry(graph: cached.graph, diff: cached.diff, completedStages: stages)
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
