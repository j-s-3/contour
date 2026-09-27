import Foundation

/// A local, on-disk checkout of a PR's head and base, ready for `pi` to read directly.
/// This is the "code stays local" guarantee from §16 — the app never sends whole-file
/// contents anywhere itself; only `pi`'s own tool calls touch these files, and only to
/// build grounded analysis.
struct RepoCheckout: Sendable {
    var rootDir: URL          // the git working tree, checked out at headSha
    var headSha: String
    var baseSha: String
    var symbolIndexPath: URL? // populated post-MVP (§7)
}

enum RepoContextError: LocalizedError {
    case gitFailed(String)
    var errorDescription: String? {
        switch self { case .gitFailed(let m): return m }
    }
}

/// Acquires repo context per design doc §9: clone/fetch, then a real checkout at the PR's
/// head SHA so `pi` reasons over actual files rather than diff hunks alone. Cached on disk
/// keyed by owner/repo/headSha so re-opening a PR is instant (§13).
struct RepoContextService {

    private let cacheRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Contour", isDirectory: true)
            .appendingPathComponent("repos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    /// Ensures a local working tree exists at `headSha` with `baseSha` reachable for diffing.
    /// Reuses an existing checkout if the head SHA already matches (cache hit, §13).
    func checkout(_ context: RawPRContext) async throws -> RepoCheckout {
        let dir = cacheRoot
            .appendingPathComponent("\(context.owner)-\(context.repo)", isDirectory: true)

        let alreadyExists = FileManager.default.fileExists(atPath: dir.path)
        if !alreadyExists {
            try FileManager.default.createDirectory(at: dir.parent, withIntermediateDirectories: true)
            // Plain `git clone`, not `gh repo clone`: git's credential helper -- which
            // `gh` installs when it authenticates -- already covers private repos, so one
            // path serves both public and private and Contour needs no `gh` here at all.
            //
            // Clone the base repo (not the fork) so the base ref is always present; the
            // head ref is fetched separately below, which also covers cross-repo PRs.
            _ = try await Shell.run("git", [
                "clone", "https://github.com/\(context.owner)/\(context.repo).git", dir.path
            ])
        }

        let currentHead = try? await Shell.run("git", ["rev-parse", "HEAD"], cwd: dir)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if currentHead != context.headSha {
            // Fetch the PR head via GitHub's synthetic refs/pull/<n>/head ref, which works
            // for same-repo and cross-repo/fork PRs alike and survives the source branch
            // being deleted after merge (common post-merge cleanup).
            _ = try await Shell.run("git", ["fetch", "origin",
                "refs/pull/\(context.number)/head:refs/pr/\(context.number)/head"
            ], cwd: dir)

            // Best-effort: make sure the base commit is present too. A plain branch-name
            // fetch is expected to fail often, since base branches get deleted post-merge
            // — not fatal, since the initial full clone of the default branch usually
            // already has the base commit as an ancestor. Only fall back to fetching by
            // SHA (which GitHub allows for still-reachable commits) if the branch fetch
            // failed and the object still isn't local.
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

    /// Reads exact lines from a file in the checkout, with a few lines of surrounding
    /// context, for the code viewer (§7). `side: .base` reads the pre-PR blob via
    /// `git show <baseSha>:<path>` rather than the working tree.
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

    /// Async like `readLines` (nonisolated + `async` hops off the main actor on its own),
    /// so a large file opened from `CodeViewerView`'s "Open whole file" never blocks the UI
    /// thread the way a synchronous call from a `Task` on the main actor would.
    func readWholeFile(in checkout: RepoCheckout, path: String) async throws -> String {
        try String(contentsOf: checkout.rootDir.appendingPathComponent(path), encoding: .utf8)
    }
}

private extension URL {
    var parent: URL { deletingLastPathComponent() }
}
