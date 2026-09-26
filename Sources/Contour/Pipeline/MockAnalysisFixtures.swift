import Foundation

/// Canned per-stage responses used when `CONTOUR_MOCK_ANALYSIS=1` is set, so a reviewer
/// can exercise every lens of the app without waiting on a full run of real harness calls
/// (§10). This is deliberately scoped to the *analysis* stages only — the GitHub fetch and
/// the local checkout still run for real, so the code viewer/Evidence lens still has real
/// files to show. Only the AI-produced JSON that would normally take minutes is
/// short-circuited.
///
/// GENERATED — do not hand-edit. These are captured verbatim from a real pipeline run
/// against a small public PR, sharkdp/bat#3877 ("Detect binary content beyond the first
/// line"), which closes GitHub issue #3554. Capturing rather than authoring is the point:
/// hand-written fixtures drift from what the models actually emit, and that drift is the
/// failure these fixtures exist to catch. The PR closes an issue on purpose, so the
/// fixture exercises the GitHub issue-tracker path alongside the graph.
///
/// Regenerate with `scripts/regenerate-fixtures.py`; see its docstring for the capture
/// command.
enum MockAnalysisFixtures {

    /// `true` when the pipeline should skip real harness invocations and return canned
    /// JSON instead. Checked once per stage call rather than cached, so tests can flip the
    /// environment mid-run if ever needed.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["CONTOUR_MOCK_ANALYSIS"] == "1"
    }

    static func response(for stage: PipelineStage) -> [String: Any] {
        let json: String
        switch stage {
        case .behaviorChange: json = behaviorChangeJSON
        case .architecture: json = architectureJSON
        case .intent: json = intentJSON
        case .eli5: json = eli5JSON
        case .decisions: json = decisionsJSON
        case .tradeoffs: json = tradeoffsJSON
        case .flows: json = flowsJSON
        case .judgment: json = judgmentJSON
        default: json = "{}"
        }
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    private static let behaviorChangeJSON = #"""
    {
      "behaviorChanges": [
        {
          "after": [
            {
              "componentIds": [
                "InputReader::try_new"
              ],
              "flowId": null,
              "label": "Open input stream",
              "outcome": null,
              "refs": [
                {
                  "endLine": 267,
                  "path": "src/input.rs",
                  "startLine": 267
                }
              ],
              "tag": "both"
            },
            {
              "componentIds": [
                "fill_buf",
                "CONTENT_INSPECTION_LIMIT"
              ],
              "flowId": null,
              "label": "Snapshot buffered first kilobyte",
              "outcome": null,
              "refs": [
                {
                  "endLine": 12,
                  "path": "src/input.rs",
                  "startLine": 12
                },
                {
                  "endLine": 275,
                  "path": "src/input.rs",
                  "startLine": 272
                }
              ],
              "tag": "afterOnly"
            },
            {
              "componentIds": [
                "read_until"
              ],
              "flowId": null,
              "label": "Read first line",
              "outcome": null,
              "refs": [
                {
                  "endLine": 288,
                  "path": "src/input.rs",
                  "startLine": 277
                }
              ],
              "tag": "both"
            },
            {
              "componentIds": [
                "inspect_content_type"
              ],
              "flowId": null,
              "label": "Inspect larger sample",
              "outcome": null,
              "refs": [
                {
                  "endLine": 290,
                  "path": "src/input.rs",
                  "startLine": 290
                }
              ],
              "tag": "afterOnly"
            },
            {
              "componentIds": [],
              "flowId": null,
              "label": "Mark file binary",
              "outcome": "success",
              "refs": [
                {
                  "endLine": 452,
                  "path": "src/input.rs",
                  "startLine": 436
                }
              ],
              "tag": "afterOnly"
            }
          ],
          "before": [
            {
              "componentIds": [
                "InputReader::try_new"
              ],
              "flowId": null,
              "label": "Open input stream",
              "outcome": null,
              "refs": [
                {
                  "endLine": 267,
                  "path": "src/input.rs",
                  "startLine": 267
                }
              ],
              "tag": "both"
            },
            {
              "componentIds": [
                "read_until"
              ],
              "flowId": null,
              "label": "Read first line only",
              "outcome": null,
              "refs": [
                {
                  "endLine": 281,
                  "path": "src/input.rs",
                  "startLine": 278
                }
              ],
              "tag": "beforeOnly"
            },
            {
              "componentIds": [
                "inspect_content_type"
              ],
              "flowId": null,
              "label": "Inspect first line",
              "outcome": null,
              "refs": [
                {
                  "endLine": 290,
                  "path": "src/input.rs",
                  "startLine": 290
                }
              ],
              "tag": "beforeOnly"
            },
            {
              "componentIds": [],
              "flowId": null,
              "label": "Print binary as text",
              "outcome": "failure",
              "refs": [],
              "tag": "beforeOnly"
            }
          ],
          "consequence": {
            "confidence": "high",
            "provenance": "interpretation",
            "source": null,
            "text": "Encrypted or random files that used to dump raw bytes to the terminal now show a <BINARY> header, as long as the NUL falls in the buffered first 1024 bytes."
          },
          "humanQuestion": {
            "confidence": "medium",
            "provenance": "interpretation",
            "source": null,
            "text": "Is it acceptable that readers buffering under 1024 bytes still inspect only the first line?"
          },
          "id": "binary-detection-beyond-first-line",
          "title": "Files with a line break before their first null byte are now detected as binary",
          "why": {
            "confidence": null,
            "provenance": "claim",
            "source": "PR description, Root cause",
            "text": "Author says bat only checked the first line, so encrypted data with a newline before its first NUL got treated as UTF-8 text."
          }
        }
      ]
    }
    """#

    private static let architectureJSON = #"""
    {
      "architectureImpact": {
        "confidence": "high",
        "provenance": "interpretation",
        "source": null,
        "text": "Detection still happens in the same place: InputReader initialization. What changed is the sample it looks at. The reader now peeks at up to 1024 buffered bytes before splitting out the first line, so a newline early in the data no longer cuts detection short. The data flow to the printer appears to be unchanged, and so do the reads: no extra blocking read is added and no bytes are consumed."
      },
      "boundaries": [
        {
          "componentIds": [
            "input-reader",
            "content-inspector",
            "utf16-decoder",
            "printer"
          ],
          "id": "bat-process",
          "kind": "process",
          "label": "bat process"
        },
        {
          "componentIds": [
            "terminal"
          ],
          "id": "terminal-ext",
          "kind": "external",
          "label": "Terminal"
        }
      ],
      "components": [
        {
          "changeKind": "unchanged",
          "dependsOnIds": [],
          "filesChanged": 0,
          "id": "input-source",
          "implementedBy": [
            "BufRead reader passed to InputReader::try_new"
          ],
          "isTrustBoundaryEdge": false,
          "level": "system",
          "refs": [
            {
              "blobSha": null,
              "endLine": 281,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 267
            }
          ],
          "summary": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "try_new takes a generic BufRead reader and calls fill_buf() on it without consuming, then calls read_until for the first line."
          },
          "title": "Input Source (file / stdin reader)"
        },
        {
          "changeKind": "changed",
          "dependsOnIds": [],
          "filesChanged": 1,
          "id": "input-reader",
          "implementedBy": [
            "InputReader::try_new",
            "src/input.rs"
          ],
          "isTrustBoundaryEdge": false,
          "level": "system",
          "refs": [
            {
              "blobSha": null,
              "endLine": 12,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 12
            },
            {
              "blobSha": null,
              "endLine": 296,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 267
            }
          ],
          "summary": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "It now builds an inspection prefix of up to CONTENT_INSPECTION_LIMIT (1024) bytes from the buffered data. If the first line is longer than that prefix, it uses the first line instead. The first line is still read separately."
          },
          "title": "Input Reader Initialization"
        },
        {
          "changeKind": "touched",
          "dependsOnIds": [],
          "filesChanged": 0,
          "id": "content-inspector",
          "implementedBy": [
            "inspect_content_type",
            "content_inspector crate"
          ],
          "isTrustBoundaryEdge": false,
          "level": "system",
          "refs": [
            {
              "blobSha": null,
              "endLine": 351,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 344
            }
          ],
          "summary": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "It classifies a byte sample as BINARY, UTF-8, or UTF-16, and it also checks for a ZIP signature. The sample it receives is now the multi-line prefix, not just the first line."
          },
          "title": "Content Type Detection"
        },
        {
          "changeKind": "unchanged",
          "dependsOnIds": [],
          "filesChanged": 0,
          "id": "utf16-decoder",
          "implementedBy": [
            "read_utf16_line"
          ],
          "isTrustBoundaryEdge": false,
          "level": "system",
          "refs": [
            {
              "blobSha": null,
              "endLine": 296,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 292
            }
          ],
          "summary": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "Runs only when the detected content type is UTF_16LE or UTF_16BE. The PR author says BOM detection still takes precedence."
          },
          "title": "UTF-16 Line Reader"
        },
        {
          "changeKind": "unchanged",
          "dependsOnIds": [],
          "filesChanged": 0,
          "id": "printer",
          "implementedBy": [
            "src/printer.rs"
          ],
          "isTrustBoundaryEdge": false,
          "level": "system",
          "refs": [
            {
              "blobSha": null,
              "endLine": 516,
              "path": "src/printer.rs",
              "side": "head",
              "startLine": 497
            },
            {
              "blobSha": null,
              "endLine": 665,
              "path": "src/printer.rs",
              "side": "head",
              "startLine": 665
            }
          ],
          "summary": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "Uses content_type to print the <BINARY> header and to handle binary input."
          },
          "title": "Printer / Terminal Output"
        },
        {
          "changeKind": "unchanged",
          "dependsOnIds": [],
          "filesChanged": 0,
          "id": "terminal",
          "implementedBy": [],
          "isTrustBoundaryEdge": false,
          "level": "system",
          "refs": [],
          "summary": {
            "confidence": null,
            "provenance": "claim",
            "source": "PR description",
            "text": "The PR author says binary bytes were previously sent to the terminal when the first line had no NUL byte."
          },
          "title": "User Terminal"
        }
      ],
      "edges": [
        {
          "change": "new",
          "decisionIds": [],
          "flow": "sync",
          "fromId": "input-reader",
          "id": "reader-peeks-buffer",
          "isTrustBoundary": false,
          "label": "peeks buffered prefix (fill_buf, non-consuming)",
          "note": "NEW: up to 1024 bytes are captured before the first line is split out",
          "onCriticalPath": true,
          "toId": "input-source"
        },
        {
          "change": "changed",
          "decisionIds": [],
          "flow": "sync",
          "fromId": "input-source",
          "id": "reader-reads-line",
          "isTrustBoundary": false,
          "label": "supplies first line (read_until)",
          "note": "Skipped when the buffer is empty",
          "onCriticalPath": true,
          "toId": "input-reader"
        },
        {
          "change": "changed",
          "decisionIds": [],
          "flow": "sync",
          "fromId": "input-reader",
          "id": "reader-inspects",
          "isTrustBoundary": false,
          "label": "classifies multi-line prefix",
          "note": "Sample was the first line; it is now up to 1024 buffered bytes",
          "onCriticalPath": true,
          "toId": "content-inspector"
        },
        {
          "change": "existing",
          "decisionIds": [],
          "flow": "sync",
          "fromId": "input-reader",
          "id": "reader-utf16",
          "isTrustBoundary": false,
          "label": "delegates UTF-16 line reads",
          "note": null,
          "onCriticalPath": false,
          "toId": "utf16-decoder"
        },
        {
          "change": "existing",
          "decisionIds": [],
          "flow": "sync",
          "fromId": "input-reader",
          "id": "reader-to-printer",
          "isTrustBoundary": false,
          "label": "provides content_type",
          "note": null,
          "onCriticalPath": true,
          "toId": "printer"
        },
        {
          "change": "existing",
          "decisionIds": [],
          "flow": "sync",
          "fromId": "printer",
          "id": "printer-to-terminal",
          "isTrustBoundary": true,
          "label": "writes output / <BINARY> header",
          "note": null,
          "onCriticalPath": true,
          "toId": "terminal"
        }
      ]
    }
    """#

    private static let intentJSON = #"""
    {
      "intent": {
        "confidence": null,
        "provenance": "claim",
        "source": "PR title: 'Detect binary content beyond the first line'. Summary: 'inspect up to the first 1024 already-buffered bytes before splitting out the first line' and 'preserve the reader's bytes, line boundaries, UTF-16 handling, and streaming behavior'. Root cause: 'content_inspector checks up to 1024 bytes for a NUL byte, but bat passed only the first line. Random or encrypted data can contain a newline before its first NUL byte, so the shortened sample was classified as UTF-8 and binary bytes were sent to the terminal.' Also: 'Fixes #3554.'",
        "text": "Make bat detect binary content that appears after the first line. Before content_inspector splits out the first line, bat should pass it up to the first 1024 bytes already in the buffer. That way, binary data with an early newline, such as encrypted or random data, is no longer treated as UTF-8 text and sent to the terminal. The change should keep the reader's bytes, line boundaries, UTF-16/BOM handling, ZIP detection and streaming behavior as they were. Fixes #3554."
      }
    }
    """#

    private static let eli5JSON = #"""
    {
      "howItWasSolved": {
        "confidence": "high",
        "provenance": "interpretation",
        "source": "src/input.rs:12, src/input.rs:267-290",
        "text": "Before, bat decided whether a file was text or binary by looking only at its first line. Now it looks at up to the first 1,024 bytes (roughly the first 1 KB), so binary data that shows up after an early line break is still caught. The file's content and how it is displayed are otherwise unchanged."
      },
      "problemToBeSolved": {
        "confidence": null,
        "provenance": "claim",
        "source": "#3554",
        "text": "Opening an encrypted file (for example, one made with the GPG encryption tool) in bat often did not flag it as binary, meaning raw non-text data. Instead, bat printed garbled symbols to the terminal, when it should have shown nothing or labeled the file as binary. The reporter said this happened with most, but not all, of their encrypted files."
      }
    }
    """#

    private static let decisionsJSON = #"""
    {
      "decisions": [
        {
          "alternatives": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Read and inspect several lines, or keep reading lines until 1024 bytes have been seen. This would work with any BufRead buffer size, but it would consume input and need extra buffering or replay logic in InputReader."
            },
            {
              "confidence": "low",
              "provenance": "interpretation",
              "source": null,
              "text": "Use a different binary heuristic, such as the share of non-printable bytes, instead of relying only on content_inspector's NUL/BOM check. That could catch encrypted data with no NUL in the first 1 KiB, but it would be a bigger change in behavior."
            }
          ],
          "componentIds": [
            "input-reader",
            "content-inspector"
          ],
          "confidence": "high",
          "consequences": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Files that have a NUL byte after the first line but within the first 1024 bytes now appear to be classified as BINARY. Text-like files that were printed before, such as logs with stray NULs, could now show the <BINARY> header instead of their content."
            },
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "The wider sample now also feeds the UTF-16 BOM check and the ZIP-signature check in inspect_content_type. The ZIP check is a starts_with test, so it seems unaffected. The author says BOM detection still takes precedence, so UTF-16 handling does not change."
            },
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "The 1024 constant duplicates content_inspector's internal scan limit. If the crate changes its limit, bat's sample size won't follow automatically."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "InputReader::try_new now copies up to CONTENT_INSPECTION_LIMIT (1024) bytes from reader.fill_buf() before read_until splits out the first line. It passes that prefix to inspect_content_type in place of first_line. Because fill_buf does not consume anything, first_line and later read_line calls still get the same bytes as before."
          },
          "id": "inspect-buffered-prefix-not-first-line",
          "level": "system",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description, 'Root cause' section",
              "text": "The author says content_inspector checks up to 1024 bytes for a NUL byte, but bat only passed it the first line. Random or encrypted data can contain a newline before its first NUL, so the short sample was classified as UTF-8 and binary bytes were sent to the terminal (issue #3554)."
            },
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description; src/input.rs:434-454",
              "text": "The author says the snapshot 'is non-consuming, so no bytes are lost or reordered'. The unit test binary_detection_scans_beyond_first_line_and_preserves_input replays all lines and checks they match the original content."
            }
          ],
          "refs": [
            {
              "blobSha": null,
              "endLine": 12,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 12
            },
            {
              "blobSha": null,
              "endLine": 296,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 267
            },
            {
              "blobSha": null,
              "endLine": 361,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 344
            },
            {
              "blobSha": null,
              "endLine": 454,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 434
            },
            {
              "blobSha": null,
              "endLine": 2285,
              "path": "tests/integration_tests.rs",
              "side": "head",
              "startLine": 2267
            }
          ],
          "title": "Classify content from the first 1024 buffered bytes instead of only the first line"
        },
        {
          "alternatives": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Keep calling read until 1024 bytes or EOF. Detection would be deterministic for pipes, but a partially filled interactive or network stream could block until more data arrives."
            }
          ],
          "componentIds": [
            "input-reader",
            "input-source"
          ],
          "confidence": "high",
          "consequences": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Detection is best-effort and depends on how much the first read returns. With stdin pipes or custom readers that deliver small chunks, a NUL past the first chunk (and past the first line) is still missed."
            },
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "For ordinary files wrapped in BufReader::new (default buffer is larger than 1 KiB), the full 1024-byte window will usually be available."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "The prefix comes from a single fill_buf() call. The first call triggers one underlying read (the same read that read_until would have done anyway). The code does not loop to fill 1024 bytes, so the sample is whatever that first read returned, capped at 1024."
          },
          "id": "no-extra-blocking-read",
          "level": "system",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description; src/input.rs:268-271",
              "text": "The author says it 'does not add a post-line blocking read' and keeps 'streaming behavior'. The code comment says it does not 'perform an additional read beyond the one read_until needs anyway'."
            },
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "This appears to protect interactive or slow stdin (try_new is called directly on stdin). There, waiting for 1 KiB before showing the first line would stall output."
            }
          ],
          "refs": [
            {
              "blobSha": null,
              "endLine": 280,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 267
            },
            {
              "blobSha": null,
              "endLine": 249,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 208
            },
            {
              "blobSha": null,
              "endLine": 479,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 456
            }
          ],
          "title": "Inspect only what is already buffered; never read more just to reach 1024 bytes"
        },
        {
          "alternatives": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Always use the fill_buf snapshot. That is simpler, but it would regress against the old behavior when a small-buffer reader has a long first line, because the sample would be shorter than before."
            }
          ],
          "componentIds": [
            "input-reader",
            "content-inspector"
          ],
          "confidence": "high",
          "consequences": [
            {
              "confidence": "high",
              "provenance": "interpretation",
              "source": null,
              "text": "The sample is never shorter than it was before this PR, so the change seems unable to reduce detection coverage. Both sources start at the same byte, so the replacement is a superset."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "After read_until, if the first line (capped at 1024 bytes) is longer than the buffered snapshot, the inspection prefix is replaced with the first line's first 1024 bytes."
          },
          "id": "fallback-to-longer-first-line",
          "level": "implementation",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "src/input.rs:282-283",
              "text": "The code comment says a custom BufRead may expose fewer than 1024 bytes at a time, and this keeps 'the old behavior for long first lines in that case'."
            }
          ],
          "refs": [
            {
              "blobSha": null,
              "endLine": 290,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 282
            }
          ],
          "title": "Use the first line if it is longer than the buffered prefix"
        },
        {
          "alternatives": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Call read_until unconditionally, as before. This is simpler, but it adds a read after EOF was already seen."
            }
          ],
          "componentIds": [
            "input-reader",
            "input-source"
          ],
          "confidence": "high",
          "consequences": [
            {
              "confidence": "high",
              "provenance": "interpretation",
              "source": null,
              "text": "For empty input, try_new makes exactly one underlying read. Readers where a second read blocks or fails are now safe during initialization."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "read_until for the first line only runs when the fill_buf snapshot is non-empty. With empty input, first_line stays empty and inspect_content_type returns None."
          },
          "id": "skip-read-on-empty-input",
          "level": "implementation",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description; src/input.rs:456-479",
              "text": "The author says 'Empty input is handled without requesting a second EOF event.' The test input_detection_does_not_read_twice uses a reader that returns WouldBlock on any second read, and checks both non-empty and empty inputs."
            },
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "An empty fill_buf means EOF was already seen. A second read on stdin or a tty would ask for EOF again (for example, a second Ctrl-D). This appears to be the hazard being avoided."
            }
          ],
          "refs": [
            {
              "blobSha": null,
              "endLine": 280,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 277
            },
            {
              "blobSha": null,
              "endLine": 479,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 456
            }
          ],
          "title": "Skip read_until when the initial buffer is empty"
        }
      ]
    }
    """#

    private static let tradeoffsJSON = #"""
    {
      "tradeoffs": [
        {
          "chosen": "up to 1024 buffered bytes",
          "decisionIds": [
            "inspect-buffered-prefix-not-first-line"
          ],
          "explanation": {
            "confidence": "high",
            "provenance": "interpretation",
            "source": null,
            "text": "Before this change, bat only inspected the first line, so a newline before the first NUL made binary data look like text. Now try_new snapshots up to 1024 bytes from fill_buf() before read_until splits out the first line (lines 272-275), and passes that snapshot to inspect_content_type (line 290). This catches binary content like encrypted files, as the regression tests show. The likely cost is that a file with a plain-text first line and a NUL somewhere in the first 1024 bytes will now be classified as binary when it used to be treated as text. The code shows the classification input got wider; how often real text files contain an early NUL isn't something the repo can tell us."
          },
          "id": "inspection-sample-scope",
          "poleA": "first line only",
          "poleAWeight": 0.85,
          "poleB": "up to 1024 buffered bytes",
          "refs": [
            {
              "blobSha": null,
              "endLine": 290,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 267
            },
            {
              "blobSha": null,
              "endLine": 355,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 344
            },
            {
              "blobSha": null,
              "endLine": 454,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 434
            }
          ],
          "title": "What bytes get inspected"
        },
        {
          "chosen": "inspect what's buffered",
          "decisionIds": [
            "no-extra-blocking-read"
          ],
          "explanation": {
            "confidence": "high",
            "provenance": "interpretation",
            "source": null,
            "text": "The code calls fill_buf() once and keeps whatever that returns, up to 1024 bytes (lines 272-275). It never loops to fill a full 1024-byte sample. The code comment says this avoids 'an additional read beyond the one read_until needs anyway' (lines 268-271). The test input_detection_does_not_read_twice uses a reader that returns WouldBlock on its second read, which locks this behavior in (lines 456-479). This appears to favor streaming and interactive inputs (pipes, slow stdin) that must not stall. The cost is that when the first read returns only a few bytes, the sample may be much shorter than 1024. A NUL just past that point would then go undetected, so binary detection depends on how the source happens to chunk its data."
          },
          "id": "no-extra-blocking-read",
          "poleA": "always fill 1024 bytes",
          "poleAWeight": 0.9,
          "poleB": "inspect what's buffered",
          "refs": [
            {
              "blobSha": null,
              "endLine": 275,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 268
            },
            {
              "blobSha": null,
              "endLine": 479,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 456
            }
          ],
          "title": "Detection completeness vs. no extra blocking"
        },
        {
          "chosen": "preserve old behavior",
          "decisionIds": [
            "fallback-to-longer-first-line"
          ],
          "explanation": {
            "confidence": "medium",
            "provenance": "interpretation",
            "source": null,
            "text": "If the first line read by read_until is longer than the buffered snapshot, the snapshot is thrown away and replaced by the first line's first 1024 bytes (lines 284-288). The code comment says this keeps 'the old behavior for long first lines' for BufRead implementations that expose fewer than 1024 bytes at a time (lines 282-283). This appears to guarantee the sample is never shorter than what bat inspected before, at the cost of a second branch and two possible sample sources. The fallback replaces the snapshot rather than merging the two. That seems fine because the snapshot is a prefix of the same stream, and so a prefix of the longer first line."
          },
          "id": "fallback-to-longer-first-line",
          "poleA": "single sample source",
          "poleAWeight": 0.75,
          "poleB": "preserve old behavior",
          "refs": [
            {
              "blobSha": null,
              "endLine": 290,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 282
            }
          ],
          "title": "Fallback to first line when buffer is short"
        },
        {
          "chosen": "avoid second EOF read",
          "decisionIds": [
            "skip-read-on-empty-input"
          ],
          "explanation": {
            "confidence": "medium",
            "provenance": "interpretation",
            "source": null,
            "text": "read_until is called only when fill_buf() returned a non-empty buffer (lines 277-280). When the buffer is empty, first_line stays empty and inspect_content_type returns None (lines 345-347). The PR description says this means empty input is 'handled without requesting a second EOF event'. The empty-content case in the one-read test covers it (line 475). The benefit is probably for interactive or streaming sources, where a second read after EOF could block or need another Ctrl-D. The cost is a small special case in initialization instead of calling read_until every time."
          },
          "id": "skip-read-on-empty-input",
          "poleA": "uniform read path",
          "poleAWeight": 0.8,
          "poleB": "avoid second EOF read",
          "refs": [
            {
              "blobSha": null,
              "endLine": 280,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 277
            },
            {
              "blobSha": null,
              "endLine": 347,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 344
            },
            {
              "blobSha": null,
              "endLine": 478,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 475
            }
          ],
          "title": "Skip read_until on empty initial buffer"
        }
      ]
    }
    """#

    private static let flowsJSON = #"""
    {
      "entryPoints": [
        {
          "changeKind": "touched",
          "flowId": "flow-file-binary-detection",
          "id": "cli-bat-file",
          "kind": "CLI command",
          "refs": [
            {
              "blobSha": null,
              "endLine": 292,
              "path": "src/bin/bat/main.rs",
              "side": "head",
              "startLine": 285
            },
            {
              "blobSha": null,
              "endLine": 243,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 216
            }
          ],
          "title": "bat <file> (CLI, ordinary file input)"
        },
        {
          "changeKind": "touched",
          "flowId": "flow-stdin-binary-detection",
          "id": "cli-bat-stdin",
          "kind": "CLI command",
          "refs": [
            {
              "blobSha": null,
              "endLine": 120,
              "path": "src/controller.rs",
              "side": "head",
              "startLine": 112
            },
            {
              "blobSha": null,
              "endLine": 213,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 199
            }
          ],
          "title": "bat (CLI, reading stdin)"
        },
        {
          "changeKind": "touched",
          "flowId": null,
          "id": "lessopen-preprocessor",
          "kind": "CLI command",
          "refs": [
            {
              "blobSha": null,
              "endLine": 129,
              "path": "src/lessopen.rs",
              "side": "head",
              "startLine": 124
            },
            {
              "blobSha": null,
              "endLine": 206,
              "path": "src/lessopen.rs",
              "side": "head",
              "startLine": 203
            }
          ],
          "title": "bat with LESSOPEN preprocessing enabled"
        },
        {
          "changeKind": "touched",
          "flowId": null,
          "id": "pretty-printer-input-from-reader",
          "kind": "public API",
          "refs": [
            {
              "blobSha": null,
              "endLine": 110,
              "path": "src/pretty_printer.rs",
              "side": "head",
              "startLine": 101
            },
            {
              "blobSha": null,
              "endLine": 249,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 244
            }
          ],
          "title": "PrettyPrinter::input_from_reader / input_from_bytes (library API)"
        },
        {
          "changeKind": "changed",
          "flowId": "flow-file-binary-detection",
          "id": "input-reader-try-new",
          "kind": "public API",
          "refs": [
            {
              "blobSha": null,
              "endLine": 304,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 267
            }
          ],
          "title": "InputReader::try_new (crate-internal reader initialization)"
        }
      ],
      "flows": [
        {
          "entryPointId": "cli-bat-file",
          "id": "flow-file-binary-detection",
          "steps": [
            {
              "branches": [
                "path is a directory -> error \"is a directory\"",
                "stdout surely conflicts with input -> IO circle error",
                "lessopen feature enabled and use_lessopen -> preprocessor.open instead"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "input-source",
              "errorPaths": [
                "File::open error mapped to \"'<path>': <err>\"",
                "try_new io::Error propagated via ?"
              ],
              "externalCalls": [
                "File::open",
                "clircle::Identifier::try_from"
              ],
              "id": "open-ordinary-file",
              "index": 0,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 160,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 141
                },
                {
                  "blobSha": null,
                  "endLine": 243,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 216
                }
              ],
              "stateDelta": "File handle wrapped in std BufReader (default capacity) and passed to InputReader::try_new",
              "title": "Open file and wrap in BufReader"
            },
            {
              "branches": [],
              "caution": "The prefix only covers whatever a single fill_buf returns. For a pipe or terminal stdin that delivers a short first chunk, a NUL byte arriving in a later chunk within the first 1024 bytes is still missed.",
              "changeKind": "new",
              "componentId": "input-reader",
              "errorPaths": [
                "fill_buf io::Error returned from try_new"
              ],
              "externalCalls": [
                "BufRead::fill_buf"
              ],
              "id": "snapshot-buffered-prefix",
              "index": 1,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 275,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 268
                },
                {
                  "blobSha": null,
                  "endLine": 12,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 12
                }
              ],
              "stateDelta": "inspection_prefix = copy of up to CONTENT_INSPECTION_LIMIT (1024) bytes from the reader's internal buffer; reader position not advanced",
              "title": "Snapshot buffered prefix via fill_buf"
            },
            {
              "branches": [
                "inspection_prefix empty (EOF) -> read_until not called, first_line stays empty"
              ],
              "caution": null,
              "changeKind": "changed",
              "componentId": "input-reader",
              "errorPaths": [
                "read_until io::Error returned from try_new"
              ],
              "externalCalls": [
                "BufRead::read_until"
              ],
              "id": "read-first-line",
              "index": 2,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 280,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 277
                }
              ],
              "stateDelta": "first_line = bytes up to and including first b'\\n' (or EOF); consumed from reader",
              "title": "Read first line (skipped on empty input)"
            },
            {
              "branches": [
                "first line longer than buffered snapshot -> use first-line bytes instead",
                "otherwise -> keep fill_buf snapshot"
              ],
              "caution": null,
              "changeKind": "new",
              "componentId": "input-reader",
              "errorPaths": [],
              "externalCalls": [],
              "id": "fallback-to-first-line",
              "index": 3,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 288,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 282
                }
              ],
              "stateDelta": "If first_line.len().min(1024) > inspection_prefix.len(), inspection_prefix is replaced by first_line[..min(len,1024)]",
              "title": "Fall back to first-line prefix if it is longer than the snapshot"
            },
            {
              "branches": [
                "empty prefix -> None",
                "UTF_8 + PK\\x03\\x04 / PK\\x05\\x06 / PK\\x07\\x08 prefix -> BINARY"
              ],
              "caution": null,
              "changeKind": "changed",
              "componentId": "content-inspector",
              "errorPaths": [],
              "externalCalls": [
                "content_inspector::inspect"
              ],
              "id": "inspect-content-type",
              "index": 4,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 290,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 290
                },
                {
                  "blobSha": null,
                  "endLine": 361,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 344
                }
              ],
              "stateDelta": "content_type: None (empty), Some(BINARY/UTF_8/UTF_16LE/UTF_16BE); UTF_8 upgraded to BINARY when a ZIP signature prefix is present",
              "title": "Classify content type"
            },
            {
              "branches": [
                "UTF_16LE -> read_utf16_line(0x00, 0x0A)",
                "UTF_16BE -> read_utf16_line(0x0A, 0x00)"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "utf16-decoder",
              "errorPaths": [
                "io::Error from read_utf16_line propagated"
              ],
              "externalCalls": [
                "BufRead::read_until"
              ],
              "id": "utf16-first-line",
              "index": 5,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 303,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 292
                },
                {
                  "blobSha": null,
                  "endLine": 379,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 363
                }
              ],
              "stateDelta": "For UTF-16 LE/BE, first_line is extended until a 2-byte newline; InputReader built with unbuffered=false",
              "title": "Extend first line for UTF-16 inputs"
            },
            {
              "branches": [
                "binary and not show_nonprintable and binary != AsText -> skip syntax matching",
                "loop_through -> SimplePrinter"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "printer",
              "errorPaths": [
                "get_syntax errors other than UndetectedSyntax propagated"
              ],
              "externalCalls": [],
              "id": "printer-setup",
              "index": 6,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 202,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 161
                },
                {
                  "blobSha": null,
                  "endLine": 281,
                  "path": "src/printer.rs",
                  "side": "head",
                  "startLine": 270
                },
                {
                  "blobSha": null,
                  "endLine": 339,
                  "path": "src/printer.rs",
                  "side": "head",
                  "startLine": 334
                }
              ],
              "stateDelta": "is_printing_binary computed from content_type; InteractivePrinter stores content_type",
              "title": "Printer decides whether to syntax-match"
            },
            {
              "branches": [
                "header style disabled + BINARY -> '[bat warning]: Binary content ... will not be printed' message",
                "header enabled -> mode tag <BINARY>/<UTF-16LE>/<UTF-16BE>/<EMPTY>",
                "show_nonprintable -> replace_nonprintable rendering"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "terminal",
              "errorPaths": [
                "write errors propagated as Result"
              ],
              "externalCalls": [
                "writeln! to OutputHandle"
              ],
              "id": "print-header-and-lines",
              "index": 7,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 247,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 222
                },
                {
                  "blobSha": null,
                  "endLine": 521,
                  "path": "src/printer.rs",
                  "side": "head",
                  "startLine": 496
                },
                {
                  "blobSha": null,
                  "endLine": 669,
                  "path": "src/printer.rs",
                  "side": "head",
                  "startLine": 664
                }
              ],
              "stateDelta": "Header shows \"   <BINARY>\" suffix; print_line returns early for BINARY content unless binary=AsText",
              "title": "Print header / warning and suppress binary lines"
            }
          ],
          "storySteps": [
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Open the file and check for IO cycles"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Peek at the first buffered chunk of up to 1024 bytes"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Split out the first line for syntax detection"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Classify content as binary, UTF-8, UTF-16 or empty"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Print header with <BINARY> tag and skip binary lines"
            }
          ],
          "title": "bat <file> -> content type detection -> header / line suppression"
        },
        {
          "entryPointId": "cli-bat-stdin",
          "id": "flow-stdin-binary-detection",
          "steps": [
            {
              "branches": [
                "stdout surely conflicts with stdin -> IO circle error"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "input-source",
              "errorPaths": [
                "Identifier error -> \"Stdin: Error identifying file\""
              ],
              "externalCalls": [
                "io::stdin().lock()",
                "clircle::Identifier::try_from(Stdio::Stdin)"
              ],
              "id": "stdin-open",
              "index": 0,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 116,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 115
                },
                {
                  "blobSha": null,
                  "endLine": 213,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 199
                }
              ],
              "stateDelta": "io::stdin().lock() passed directly (no extra BufReader) to InputReader::try_new",
              "title": "Open stdin input"
            },
            {
              "branches": [],
              "caution": "fill_buf blocks until the first read returns and captures only that chunk. With a slow pipe, binary bytes that arrive after the first chunk but within the first 1024 bytes are not inspected.",
              "changeKind": "new",
              "componentId": "input-reader",
              "errorPaths": [
                "io::Error propagated"
              ],
              "externalCalls": [
                "StdinLock::fill_buf (blocking read)"
              ],
              "id": "stdin-fill-buf",
              "index": 1,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 275,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 272
                }
              ],
              "stateDelta": "inspection_prefix = up to 1024 bytes of the first stdin read, not consumed",
              "title": "Snapshot stdin buffer"
            },
            {
              "branches": [
                "empty stdin -> no read_until, content_type None"
              ],
              "caution": null,
              "changeKind": "changed",
              "componentId": "content-inspector",
              "errorPaths": [
                "io::Error propagated"
              ],
              "externalCalls": [
                "BufRead::read_until",
                "content_inspector::inspect"
              ],
              "id": "stdin-read-first-line",
              "index": 2,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 290,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 277
                }
              ],
              "stateDelta": "first_line consumed; content_type computed from the larger of the snapshot or the first-line prefix",
              "title": "Read first line and classify"
            },
            {
              "branches": [
                "unbuffered -> read_line_unbuffered using fill_buf/consume",
                "UTF-16 -> read_utf16_line"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "input-reader",
              "errorPaths": [
                "io::Error propagated to printer loop"
              ],
              "externalCalls": [
                "BufRead::fill_buf",
                "BufRead::consume",
                "BufRead::read_until"
              ],
              "id": "stdin-unbuffered-flag",
              "index": 3,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 161,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 161
                },
                {
                  "blobSha": null,
                  "endLine": 341,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 306
                }
              ],
              "stateDelta": "reader.unbuffered set from config after try_new returns; later read_line calls return first_line first, then read via read_until or read_line_unbuffered",
              "title": "Apply unbuffered setting after detection"
            }
          ],
          "storySteps": [
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Lock stdin and check for IO cycles"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Peek at whatever data the first stdin read delivered"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Split out the first line"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Classify content and switch to unbuffered mode if configured"
            }
          ],
          "title": "bat (stdin) -> content type detection on piped data"
        }
      ]
    }
    """#

    private static let judgmentJSON = #"""
    {
      "changeMap": [
        {
          "filesChanged": 1,
          "name": "Input Reader Initialization"
        },
        {
          "filesChanged": 1,
          "name": "Integration tests"
        },
        {
          "filesChanged": 1,
          "name": "Changelog"
        }
      ],
      "considerations": [
        {
          "confidence": "medium",
          "detail": "The same bytes can be flagged as binary from a file but printed as text from a slow pipe.",
          "explanation": "try_new calls fill_buf() once and keeps whatever that single read returned, capped at 1024 bytes (src/input.rs:272-275). There is no loop to fill the sample. Files are wrapped in std BufReader (src/input.rs:241) and stdin is io::stdin().lock() (src/controller.rs:116), so both usually get a full buffer on the first read. A pipe, though, returns only what the writer has flushed so far. Take a producer that writes a short first chunk with a newline, then the NUL-bearing bytes: the sample is short, and if read_until can take the whole first line from that chunk, the fallback at lines 284-288 never widens it. The NUL is then missed. As a result, `bat file` and `producer | bat` can disagree on the same content. This appears to be a deliberate trade to avoid blocking; the author says it 'does not add a post-line blocking read'. The reviewer should decide whether the nondeterminism is acceptable or should at least be documented. One alternative is to keep reading until 1024 bytes or EOF only for non-interactive sources. That brings back the blocking risk the author was avoiding. LESSOPEN output is not affected, because the preprocessor output is collected in full before it is wrapped (src/lessopen.rs:140-151, 203-205).",
          "id": "stdin-chunking-nondeterminism",
          "kind": "concern",
          "provenance": "interpretation",
          "question": "Is binary detection that depends on pipe chunking acceptable?",
          "refs": [
            {
              "endLine": 288,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 268
            },
            {
              "endLine": 116,
              "path": "src/controller.rs",
              "side": "head",
              "startLine": 116
            },
            {
              "endLine": 206,
              "path": "src/lessopen.rs",
              "side": "head",
              "startLine": 203
            }
          ],
          "relatedIds": [
            "no-extra-blocking-read",
            "flow-stdin-binary-detection",
            "input-reader"
          ]
        },
        {
          "confidence": "medium",
          "detail": "Output that used to print may now be silently replaced by a <BINARY> header.",
          "explanation": "Before this PR, a file whose first line was clean UTF-8 was classified UTF_8 even if a NUL appeared a few lines later. Now any NUL in the buffered first 1024 bytes makes content_inspector return BINARY (src/input.rs:290, 344-354). The printer then skips those lines unless --binary=as-text is set (src/printer.rs:496-521, 664-669). Examples that could flip are logs with NUL padding from a crash or truncated write, and text files with stray embedded NULs. The escape hatches already exist: BinaryBehavior::AsText (src/bin/bat/app.rs:439) and -A. The reviewer should judge whether this user-visible change needs more than the Bugfixes CHANGELOG line, for example a note that points users to --binary=as-text.",
          "id": "text-with-early-nul-now-suppressed",
          "kind": "concern",
          "provenance": "interpretation",
          "question": "Are text files with a NUL in the first 1 KiB now hidden by default?",
          "refs": [
            {
              "endLine": 355,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 344
            },
            {
              "endLine": 521,
              "path": "src/printer.rs",
              "side": "head",
              "startLine": 496
            },
            {
              "endLine": 441,
              "path": "src/bin/bat/app.rs",
              "side": "head",
              "startLine": 437
            }
          ],
          "relatedIds": [
            "inspect-buffered-prefix-not-first-line",
            "printer",
            "content-inspector"
          ]
        },
        {
          "confidence": "high",
          "detail": "The branch for pipes with short first reads is not covered by any test in this PR.",
          "explanation": "The branch at src/input.rs:284-288 replaces the snapshot with the first line when the line is longer than what fill_buf exposed. The new unit tests both hand try_new a reader whose first fill_buf returns the whole content: `&content[..]` in the first test, and a single OneRead chunk in the second (src/input.rs:440, 476). So first_line.len() is never larger than inspection_prefix.len(), and the fallback never runs. The integration test uses a regular file (tests/integration_tests.rs:2267-2285). A test with a Read that returns data in small chunks, for example BufReader::with_capacity(4, ...) or a chunked mock, would cover both the fallback and a cross-line case under short reads. Note that input_detection_does_not_read_twice would also appear to pass against the pre-PR code. It guards against future regressions (a naive 'fill to 1024' loop) rather than showing the fix works.",
          "id": "fallback-branch-untested",
          "kind": "concern",
          "provenance": "interpretation",
          "question": "Should the short-buffer fallback path have its own test?",
          "refs": [
            {
              "endLine": 288,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 282
            },
            {
              "endLine": 479,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 434
            },
            {
              "endLine": 2285,
              "path": "tests/integration_tests.rs",
              "side": "head",
              "startLine": 2267
            }
          ],
          "relatedIds": [
            "fallback-to-longer-first-line",
            "input-reader"
          ]
        },
        {
          "confidence": "medium",
          "detail": "About 2% of random 1 KiB samples contain no NUL, so some encrypted files will still print.",
          "explanation": "Detection still relies entirely on content_inspector finding a NUL (or a BOM or ZIP signature) in the sample (src/input.rs:344-354). For uniformly random bytes, the chance that 1024 bytes contain no 0x00 is (255/256)^1024 ≈ 1.8%. Before, with only the first line sampled (about 256 random bytes on average before a newline), the chance of missing the NUL was far higher, around 37% for a 256-byte sample. That matches the reporter's 'most, but not all' observation. The PR seems to lower the miss rate a lot without removing it, yet the changelog says 'Closes #3554'. The reviewer may want to decide whether the issue should stay open or be tracked separately, for example with a non-printable-ratio heuristic. The repo cannot show how content_inspector 0.2.4 scans internally, because the crate source was outside the readable workspace.",
          "id": "residual-miss-rate-encrypted",
          "kind": "question",
          "provenance": "interpretation",
          "question": "Is a NUL-only heuristic enough to close the encrypted-file issue?",
          "refs": [
            {
              "endLine": 355,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 344
            },
            {
              "endLine": 52,
              "path": "Cargo.toml",
              "side": "head",
              "startLine": 52
            }
          ],
          "relatedIds": [
            "inspect-buffered-prefix-not-first-line",
            "content-inspector"
          ]
        },
        {
          "confidence": "low",
          "detail": "The constant silently duplicates content_inspector's internal limit and will drift if the crate changes.",
          "explanation": "CONTENT_INSPECTION_LIMIT is hard-coded to 1024 (src/input.rs:12), based on the author's statement that content_inspector checks up to 1024 bytes. If a future content_inspector scans more, bat would still pass only 1024 bytes. If it scans less, the extra copy does nothing. The cost is low, but a comment linking the value to the pinned crate version (0.2.4, Cargo.toml:52) would make the coupling explicit.",
          "id": "duplicated-1024-limit",
          "kind": "concern",
          "provenance": "interpretation",
          "question": "Should the 1024 limit be tied to the crate's actual scan size?",
          "refs": [
            {
              "endLine": 12,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 12
            },
            {
              "endLine": 52,
              "path": "Cargo.toml",
              "side": "head",
              "startLine": 52
            }
          ],
          "relatedIds": [
            "inspect-buffered-prefix-not-first-line"
          ]
        }
      ],
      "needsJudgment": [
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": null,
          "text": "Whether it is acceptable that binary classification can depend on how a streaming source chunks its first read. A single fill_buf() (src/input.rs:272-275) means pipes with short initial writes may still get only a first-line sample, while the same content from a file is flagged BINARY."
        },
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": null,
          "text": "Whether the user-visible change is acceptable: UTF-8 files with any NUL in the first 1 KiB are now suppressed as <BINARY> by default. Examples are logs with NUL padding or files with stray NULs. The only mitigation is the existing --binary=as-text flag (src/printer.rs:664-669)."
        },
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": null,
          "text": "Whether 'Closes #3554' is accurate, given that a NUL-only heuristic still appears to miss roughly 2% of uniformly random 1 KiB prefixes."
        },
        {
          "confidence": "high",
          "provenance": "interpretation",
          "source": null,
          "text": "Whether the new tests are sufficient. The fallback branch (src/input.rs:284-288) appears to have no test exercising it, and input_detection_does_not_read_twice appears to pass against the pre-PR implementation too."
        }
      ],
      "questions": [
        {
          "id": "content-inspector-scan-limit",
          "refs": [
            {
              "endLine": 52,
              "path": "Cargo.toml",
              "side": "head",
              "startLine": 52
            },
            {
              "endLine": 12,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 12
            }
          ],
          "relatedIds": [
            "inspect-buffered-prefix-not-first-line",
            "content-inspector"
          ],
          "text": "Does content_inspector 0.2.4 actually cap its NUL scan at exactly 1024 bytes, and does it check BOMs before NULs? The crate source was not readable from this checkout."
        },
        {
          "id": "stdin-cross-line-coverage",
          "refs": [
            {
              "endLine": 2285,
              "path": "tests/integration_tests.rs",
              "side": "head",
              "startLine": 2267
            },
            {
              "endLine": 116,
              "path": "src/controller.rs",
              "side": "head",
              "startLine": 116
            }
          ],
          "relatedIds": [
            "flow-stdin-binary-detection",
            "no-extra-blocking-read"
          ],
          "text": "Is there any intended test coverage for the stdin or pipe path with a NUL after the first line? The only integration regression test (tests/integration_tests.rs:2267-2285) reads a regular file."
        },
        {
          "id": "pr-3763-interaction",
          "refs": [
            {
              "endLine": 304,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 267
            }
          ],
          "relatedIds": [
            "input-reader"
          ],
          "text": "The author says PR #3763 changes the same initialization path to bound reads for newline-free binaries. I could not verify from this checkout whether it has merged or how the two changes would combine."
        }
      ],
      "uncertainties": [
        {
          "confidence": "high",
          "provenance": "interpretation",
          "source": null,
          "text": "I could not inspect content_inspector 0.2.4's source (it is outside the restricted workspace). The claims that it scans at most 1024 bytes and that BOM detection takes precedence over NUL detection rest on the PR author's description, not on code I read."
        },
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": null,
          "text": "How often real pipe producers deliver a short first chunk that ends after a newline but before a NUL inside the first 1 KiB. This depends on the OS and the producer and cannot be determined from the repo."
        },
        {
          "confidence": "low",
          "provenance": "interpretation",
          "source": null,
          "text": "Whether any downstream library users call PrettyPrinter::input_from_reader with readers whose BufReader wrapper gets tiny initial reads. That would make the fallback path the common case for them."
        }
      ]
    }
    """#
}
