import Foundation

struct ClaudeHarness: Harness {
    let id: HarnessID = .claude

    let contextDirectory: URL

    init(contextDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        self.contextDirectory = contextDirectory
    }

    func arguments(prompt: String, contextFile: String, tier: AnalysisTier,
                   systemPrompt: String) throws -> [String] {
        var args: [String] = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--allowedTools", "Read,Grep,Glob",
            "--restricted",
            "--safe-mode",
            "--effort", tier.thinking,
            "--append-system-prompt", systemPrompt,
        ]
        if let modelPattern = tier.modelPattern {
            args += ["--model", modelPattern]
        }
        args.append(try promptWithContext(prompt: prompt, contextFile: contextFile))
        return args
    }

    func conversationArguments(prompt: String, contextFile: String, tier: AnalysisTier,
                               systemPrompt: String) throws -> [String] {
        var args = try arguments(prompt: prompt, contextFile: contextFile, tier: tier, systemPrompt: systemPrompt)
        if let verbose = args.firstIndex(of: "--verbose") {
            args.insert("--include-partial-messages", at: verbose + 1)
        }
        return args
    }

    private func promptWithContext(prompt: String, contextFile: String) throws -> String {
        let url = contextDirectory.appendingPathComponent(contextFile)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return prompt
        }
        return """
        <file name="\(contextFile)">
        \(contents)
        </file>

        \(prompt)
        """
    }

    func interpret(_ line: String) -> HarnessEvent? {
        guard let event = StreamLine.object(line),
              let type = event["type"] as? String
        else { return nil }

        switch type {
        case "assistant":
            guard let message = event["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { return nil }
            for block in content where (block["type"] as? String) == "tool_use" {
                guard let name = block["name"] as? String else { continue }
                let input = block["input"] as? [String: Any]
                return .progress(StreamLine.describeTool(
                    name: name,
                    path: (input?["file_path"] as? String) ?? (input?["path"] as? String),
                    pattern: input?["pattern"] as? String
                ))
            }
            return nil

        case "stream_event":
            guard let inner = event["event"] as? [String: Any],
                  (inner["type"] as? String) == "content_block_delta",
                  let delta = inner["delta"] as? [String: Any],
                  (delta["type"] as? String) == "text_delta",
                  let text = delta["text"] as? String, !text.isEmpty
            else { return nil }
            return .textDelta(text)

        case "result":
            guard (event["subtype"] as? String) == "success",
                  let text = event["result"] as? String,
                  !text.isEmpty
            else { return nil }
            return .finalText(text)

        default:
            return nil
        }
    }
}
