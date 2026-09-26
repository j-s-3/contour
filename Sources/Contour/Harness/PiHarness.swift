import Foundation

/// Drives `pi`.
///
/// Stream shape (`--mode json`): newline-delimited events, of which two matter —
/// `tool_execution_start` carries `toolName` plus an `args` object, and `message_end`
/// carries the authoritative final message for a role.
struct PiHarness: Harness {
    let id: HarnessID = .pi

    func arguments(prompt: String, contextFile: String, tier: AnalysisTier,
                   systemPrompt: String) throws -> [String] {
        var args: [String] = [
            "--mode", "json",
            "--no-session",
            "--tools", "read,grep,find,ls",
            // The checkout is the PR under review: untrusted content. Refuse to load any
            // AGENTS.md/CLAUDE.md, extension, or skill it ships, since those would arrive
            // as *instructions* and so slip past the <UNTRUSTED_PR_CONTENT> wrapper that
            // only covers PR prose.
            "--no-context-files",
            "--no-extensions",
            "--no-skills",
            "--thinking", tier.thinking,
            "--append-system-prompt", systemPrompt,
        ]
        if let modelPattern = tier.modelPattern {
            args += ["--model", modelPattern]
        }
        // `@file` must be its own argv token — pi resolves it by scanning the raw argument
        // for a leading "@", so a combined "@file\n\nrest of prompt" string is parsed as
        // one (nonexistent) path containing everything after the "@". Two separate
        // positional arguments after `-p` make pi attach the file, then append the prompt
        // text to the same first message.
        args += ["-p", "@\(contextFile)", prompt]
        return args
    }

    func interpret(_ line: String) -> HarnessEvent? {
        guard let event = StreamLine.object(line),
              let type = event["type"] as? String
        else { return nil }

        switch type {
        case "tool_execution_start":
            guard let toolName = event["toolName"] as? String else { return nil }
            let args = event["args"] as? [String: Any]
            return .progress(StreamLine.describeTool(
                name: toolName,
                path: args?["path"] as? String,
                pattern: args?["pattern"] as? String
            ))

        // pi streams by default in json mode: `message_update` wraps the provider's own
        // event, and text arrives as `text_delta` fragments.
        case "message_update":
            guard let inner = event["assistantMessageEvent"] as? [String: Any],
                  (inner["type"] as? String) == "text_delta",
                  let text = inner["delta"] as? String, !text.isEmpty
            else { return nil }
            return .textDelta(text)

        case "message_end":
            guard let message = event["message"] as? [String: Any],
                  (message["role"] as? String) == "assistant",
                  let content = message["content"] as? [[String: Any]]
            else { return nil }
            // Filter on block type rather than taking the last block: a thinking block
            // carries a null `text` and can sit after the real answer.
            let texts = content.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }
            guard let text = texts.last, !text.isEmpty else { return nil }
            return .finalText(text)

        default:
            return nil
        }
    }
}
