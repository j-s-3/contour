import Foundation

struct RepoCheckout: Sendable {
    var rootDir: URL
    var headSha: String
    var baseSha: String
    var symbolIndexPath: URL?
}

enum RepoContextError: LocalizedError {
    case gitFailed(String)
    var errorDescription: String? {
        switch self { case .gitFailed(let m): return m }
    }
}

struct RepoContextService {
    private let cacheRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Contour", isDirectory: true)
            .appendingPathComponent("repos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    func checkout(_ context: RawPRContext) async throws -> RepoCheckout {
        let dir = cacheRoot
            .appendingPathComponent("\(context.owner)-\(context.repo)", isDirectory: true)

        let alreadyExists = FileManager.default.fileExists(atPath: dir.path)
        if !alreadyExists {
            try FileManager.default.createDirectory(at: dir.parent, withIntermediateDirectories: true)
            _ = try await Shell.run("git", [
                "clone", "https://github.com/\(context.owner)/\(context.repo).git", dir.path
            ])
        }

        let currentHead = try? await Shell.run("git", ["rev-parse", "HEAD"], cwd: dir)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if currentHead != context.headSha {
            _ = try await Shell.run("git", ["fetch", "origin",
                "refs/pull/\(context.number)/head:refs/pr/\(context.number)/head"
            ], cwd: dir)

            do {
                _ = try await Shell.run("git", ["fetch", "origin", context.baseRefName], cwd: dir)
            } catch {
                let hasBase = (try? await Shell.run("git", ["cat-file", "-e", context.baseSha], cwd: dir)) != nil
                if !hasBase {
                    _ = try? await Shell.run("git", ["fetch", "origin", context.baseSha], cwd: dir)
                }
            }

            _ = try await Shell.run("git", ["checkout", "--force", "refs/pr/\(context.number)/head"], cwd: dir)
        }

        return RepoCheckout(rootDir: dir, headSha: context.headSha, baseSha: context.baseSha, symbolIndexPath: nil)
    }

    func readLines(
        in checkout: RepoCheckout,
        path: String,
        startLine: Int,
        endLine: Int,
        contextLines: Int = 6,
        side: RefSide = .head
    ) async throws -> (lines: [(number: Int, text: String)], refStart: Int, refEnd: Int) {
        let content: String
        switch side {
        case .head:
            content = try String(contentsOf: checkout.rootDir.appendingPathComponent(path), encoding: .utf8)
        case .base:
            content = try await Shell.run("git", ["show", "\(checkout.baseSha):\(path)"], cwd: checkout.rootDir)
        }
        let allLines = content.components(separatedBy: "\n")
        let lo = max(1, startLine - contextLines)
        let hi = min(allLines.count, endLine + contextLines)
        var out: [(Int, String)] = []
        for n in lo...max(lo, hi) where n <= allLines.count {
            out.append((n, allLines[n - 1]))
        }
        return (out, startLine, endLine)
    }

    func readWholeFile(in checkout: RepoCheckout, path: String) async throws -> String {
        try String(contentsOf: checkout.rootDir.appendingPathComponent(path), encoding: .utf8)
    }
}

private extension URL {
    var parent: URL { deletingLastPathComponent() }
}
