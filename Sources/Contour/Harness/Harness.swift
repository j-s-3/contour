import Foundation

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

    var installHint: String {
        switch self {
        case .pi: return "Install pi, then run `pi auth check --provider <name>`"
        case .claude: return "Install Claude Code, then run `claude` once to sign in"
        }
    }
}

enum HarnessEvent: Equatable, Sendable {
    case progress(String)
    case finalText(String)
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

protocol Harness: Sendable {
    var id: HarnessID { get }

    func arguments(prompt: String, contextFile: String, tier: AnalysisTier,
                   systemPrompt: String) throws -> [String]

    func conversationArguments(prompt: String, contextFile: String, tier: AnalysisTier,
                               systemPrompt: String) throws -> [String]

    func interpret(_ line: String) -> HarnessEvent?
}

extension Harness {
    var executable: String { id.executable }

    func conversationArguments(prompt: String, contextFile: String, tier: AnalysisTier,
                               systemPrompt: String) throws -> [String] {
        try arguments(prompt: prompt, contextFile: contextFile, tier: tier, systemPrompt: systemPrompt)
    }
}

enum HarnessFactory {
    static func make(_ id: HarnessID, contextDirectory: URL) -> any Harness {
        switch id {
        case .pi: return PiHarness()
        case .claude: return ClaudeHarness(contextDirectory: contextDirectory)
        }
    }
}

enum StreamLine {
    static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

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
