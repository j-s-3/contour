import Foundation

/// Which AI CLI Contour drives. Contour holds no provider credentials of its own; it
/// shells out to a CLI the user has already installed and authenticated, and inherits
/// whatever model and provider that CLI is configured with.
enum HarnessID: String, Codable, CaseIterable, Sendable {
    case pi
    case claude

    var displayName: String {
        switch self {
        case .pi: return "pi"
        case .claude: return "Claude Code"
        }
    }

    var executable: String { rawValue }

    /// Where to point someone who doesn't have it installed.
    var installHint: String {
        switch self {
        case .pi: return "Install pi, then run `pi auth check --provider <name>`"
        case .claude: return "Install Claude Code, then run `claude` once to sign in"
        }
    }
}

/// The only two things Contour needs out of a harness's output stream.
enum HarnessEvent: Equatable, Sendable {
    /// A human-readable line describing what the model is doing right now, e.g.
    /// "reading OrderService.java". Surfaced live so the UI never shows a bare spinner.
    case progress(String)
    /// The stage's final assistant message, expected to contain the stage's JSON.
    case finalText(String)
    /// A fragment of assistant text as it is generated. Only emitted when the CLI was asked
    /// to stream (`conversationArguments`); analysis stages never see it. The authoritative
    /// answer is still `finalText` — deltas are a preview for contextual chat.
    case textDelta(String)
}

enum HarnessError: LocalizedError {
    case contextFileUnreadable(String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .contextFileUnreadable(let name, let underlying):
            return "Couldn't read the PR context file \(name): \(underlying.localizedDescription)"
        }
    }
}

/// One AI CLI, reduced to the two things that actually differ between them: how you
/// invoke it, and how you read its stream.
///
/// Everything a stage needs beyond this — the grounding system prompt, JSON extraction,
/// the mock short-circuit — is harness-independent and lives in `AnalysisService`.
protocol Harness: Sendable {
    var id: HarnessID { get }

    /// The full argv after the executable itself.
    ///
    /// - Parameter contextFile: the context file's name, relative to the checkout root.
    ///   How it reaches the model is the harness's business: pi attaches it, claude
    ///   inlines it. Both must deliver the same text.
    func arguments(prompt: String, contextFile: String, tier: AnalysisTier,
                   systemPrompt: String) throws -> [String]

    /// The argv for one contextual-chat turn. Same read-only, instruction-file-free
    /// hardening as `arguments`; the only difference a conformer may add is asking its CLI
    /// to stream text fragments so the answer can render as it is written.
    func conversationArguments(prompt: String, contextFile: String, tier: AnalysisTier,
                               systemPrompt: String) throws -> [String]

    /// Interpret one line of the CLI's output stream. Returns nil for anything Contour
    /// doesn't care about — heartbeats, hook chatter, rate-limit notices, malformed
    /// lines. Unknown events must never be treated as errors: both CLIs add event types
    /// over time, and a stage failing because its harness learned a new one would be a
    /// self-inflicted outage.
    func interpret(_ line: String) -> HarnessEvent?
}

extension Harness {
    var executable: String { id.executable }

    func conversationArguments(prompt: String, contextFile: String, tier: AnalysisTier,
                               systemPrompt: String) throws -> [String] {
        try arguments(prompt: prompt, contextFile: contextFile, tier: tier, systemPrompt: systemPrompt)
    }
}

/// Builds the concrete harness for a choice. Kept trivial on purpose: adding a third CLI
/// is a new conformer plus a case here, not a plugin system.
enum HarnessFactory {
    static func make(_ id: HarnessID, contextDirectory: URL) -> any Harness {
        switch id {
        case .pi: return PiHarness()
        case .claude: return ClaudeHarness(contextDirectory: contextDirectory)
        }
    }
}

// MARK: - Shared JSON helpers

/// Both CLIs stream newline-delimited JSON, so both conformers need the same tolerant
/// line decode.
enum StreamLine {
    static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    /// Turns a tool call into the progress line a reviewer sees. Both CLIs expose the same
    /// four read-only capabilities under different names and argument keys, so the
    /// vocabulary is normalized here rather than duplicated per conformer.
    static func describeTool(name: String, path: String?, pattern: String?) -> String {
        switch name.lowercased() {
        case "read":
            if let path { return "reading \(path)" }
        case "grep":
            if let pattern { return "searching for \(pattern)" }
        case "find", "glob":
            if let pattern { return "finding \(pattern)" }
        case "ls":
            if let path { return "listing \(path)" }
        default:
            break
        }
        return "using \(name)"
    }
}
