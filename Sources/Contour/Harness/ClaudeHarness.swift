import Foundation

/// Drives `claude` (Claude Code) in non-interactive print mode.
///
/// Stream shape (`--output-format stream-json --verbose`): newline-delimited events, of
/// which two matter — `assistant` events whose message content holds `tool_use` blocks,
/// and a single `result` event carrying the final text. Hook lifecycle and rate-limit
/// events interleave with those and are ignored.
struct ClaudeHarness: Harness {
    let id: HarnessID = .claude

    /// The checkout root, used to resolve the context file for inlining. Defaults to the
    /// process working directory, which is what the harness is launched with; injected
    /// explicitly by the pipeline (and by tests) so it never depends on ambient state.
    let contextDirectory: URL

    init(contextDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        self.contextDirectory = contextDirectory
    }

    func arguments(prompt: String, contextFile: String, tier: AnalysisTier,
                   systemPrompt: String) throws -> [String] {
        var args: [String] = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",                       // required for stream-json under --print
            "--allowedTools", "Read,Grep,Glob",
            // The checkout is the PR under review: untrusted content. --safe-mode disables
            // CLAUDE.md, skills, plugins, hooks, MCP servers and custom agents it might
            // ship, all of which would otherwise be loaded as *instructions*. --restricted
            // drops the command-running tools and WebFetch and confines file tools to the
            // working directory.
            //
            // --bare would also disable CLAUDE.md discovery, but it forces
            // ANTHROPIC_API_KEY-only auth and so breaks anyone signed in through a
            // subscription. These two flags get the same hardening without touching auth.
            "--restricted",
            "--safe-mode",
            "--effort", tier.thinking,
            "--append-system-prompt", systemPrompt,
        ]
        if let modelPattern = tier.modelPattern {
            args += ["--model", modelPattern]
        }
        // claude has no `@file` convention, so the context file's contents are inlined
        // ahead of the stage prompt. The model must end up with the same text pi's
        // attachment produces; only the delivery differs.
        args.append(try promptWithContext(prompt: prompt, contextFile: contextFile))
        return args
    }

    private func promptWithContext(prompt: String, contextFile: String) throws -> String {
        let url = contextDirectory.appendingPathComponent(contextFile)
        // A missing context file is not fatal: the stage prompt alone still describes the
        // work, and the model can read the checkout. Failing here would turn a degraded
        // run into no run at all.
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
            // Only the first tool_use per event is reported: these events carry one tool
            // call in practice, and a progress line is a status hint, not an audit log.
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

        case "result":
            // Errors surface as an empty/failed stage upstream; the subtype is checked so a
            // failure result isn't mistaken for a real answer.
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
