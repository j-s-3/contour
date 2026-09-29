import Foundation

struct AnalysisCache {
    struct RecentPR: Codable, Equatable, Identifiable {
        var url: String
        var repo: String
        var number: Int
        var title: String
        var lastOpened: Date

        var id: String { "\(repo)#\(number)" }
    }

    static let recentCapacity = 20

    struct Entry: Sendable {
        var graph: PRGraph
        var diff: String
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

    func invalidate(owner: String, repo: String, number: Int, headSha: String, baseSha: String, pipelineVersion: Int) {
        let url = fileURL(owner: owner, repo: repo, number: number, headSha: headSha, baseSha: baseSha, pipelineVersion: pipelineVersion)
        try? FileManager.default.removeItem(at: url)
    }

    private var recentURL: URL { cacheDir.appendingPathComponent("recent-prs.json") }

    func recordOpened(url: String, repo: String, number: Int, title: String, at date: Date = Date()) {
        guard !MockAnalysisFixtures.isEnabled else { return }
        let opened = RecentPR(url: url, repo: repo, number: number, title: title, lastOpened: date)
        var recents = readRecents().filter { $0.id != opened.id }
        recents.insert(opened, at: 0)
        guard let data = try? JSONEncoder().encode(Array(recents.prefix(Self.recentCapacity))) else { return }
        try? data.write(to: recentURL, options: .atomic)
    }

    func recentPRs(limit: Int = AnalysisCache.recentCapacity) -> [RecentPR] {
        guard !MockAnalysisFixtures.isEnabled else { return [] }
        return Array(readRecents().sorted { $0.lastOpened > $1.lastOpened }.prefix(limit))
    }

    private func readRecents() -> [RecentPR] {
        guard let data = try? Data(contentsOf: recentURL),
              let recents = try? JSONDecoder().decode([RecentPR].self, from: data)
        else { return [] }
        return recents
    }

    private func decode(_ url: URL, pipelineVersion: Int) -> Entry? {
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedAnalysis.self, from: data),
              cached.pipelineVersion == pipelineVersion
        else { return nil }
        let stages = cached.completedStages.map(Set.init) ?? Set(PipelineStage.analysis)
        return Entry(graph: cached.graph, diff: cached.diff, completedStages: stages)
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
