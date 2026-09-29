struct PiHarness: Harness {
    let id: HarnessID = .pi

    func arguments(
        prompt: String, contextFile: String, tier: AnalysisTier,
        systemPrompt: String
    ) throws -> [String] {
        var args: [String] = [
            "--mode", "json",
            "--no-session",
            "--tools", "read,grep,find,ls",
            "--no-context-files",
            "--no-extensions",
            "--no-skills",
            "--thinking", tier.thinking,
            "--append-system-prompt", systemPrompt,
        ]
        if let modelPattern = tier.modelPattern {
            args += ["--model", modelPattern]
        }
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
            return .progress(
                StreamLine.describeTool(
                    name: toolName,
                    path: args?["path"] as? String,
                    pattern: args?["pattern"] as? String
                ))

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
