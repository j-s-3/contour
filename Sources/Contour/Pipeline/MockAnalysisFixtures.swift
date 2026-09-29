import Foundation

enum MockAnalysisFixtures {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["CONTOUR_MOCK_ANALYSIS"] == "1"
    }

    static let sourcePRURL = "https://github.com/sharkdp/bat/pull/3877"

    static func response(for stage: PipelineStage) -> [String: Any] {
        let json: String
        switch stage {
        case .behaviorChange: json = behaviorChangeJSON
        case .architecture: json = architectureJSON
        case .understanding: json = understandingJSON
        case .decisions: json = decisionsJSON
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
                    "BufRead::fill_buf",
                    "CONTENT_INSPECTION_LIMIT"
                  ],
                  "flowId": null,
                  "label": "Snapshot buffered first kilobyte",
                  "outcome": null,
                  "refs": [
                    {
                      "endLine": 275,
                      "path": "src/input.rs",
                      "startLine": 268
                    },
                    {
                      "endLine": 12,
                      "path": "src/input.rs",
                      "startLine": 12
                    }
                  ],
                  "tag": "afterOnly"
                },
                {
                  "componentIds": [
                    "BufRead::read_until"
                  ],
                  "flowId": null,
                  "label": "Read first line",
                  "outcome": null,
                  "refs": [
                    {
                      "endLine": 280,
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
                  "label": "Inspect larger prefix",
                  "outcome": null,
                  "refs": [
                    {
                      "endLine": 290,
                      "path": "src/input.rs",
                      "startLine": 282
                    }
                  ],
                  "tag": "afterOnly"
                },
                {
                  "componentIds": [],
                  "flowId": null,
                  "label": "Mark file as binary",
                  "outcome": "success",
                  "refs": [
                    {
                      "endLine": 2285,
                      "path": "tests/integration_tests.rs",
                      "startLine": 2267
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
                    "BufRead::read_until"
                  ],
                  "flowId": null,
                  "label": "Read first line",
                  "outcome": null,
                  "refs": [
                    {
                      "endLine": 280,
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
                  "label": "Inspect first line only",
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
                  "label": "Print binary bytes as text",
                  "outcome": "failure",
                  "refs": [],
                  "tag": "beforeOnly"
                }
              ],
              "consequence": {
                "confidence": "high",
                "provenance": "interpretation",
                "source": null,
                "text": "Files with a null byte in the first 1024 buffered bytes, even past the first line, now show as <BINARY> and aren't dumped to the terminal."
              },
              "humanQuestion": {
                "confidence": "medium",
                "provenance": "interpretation",
                "source": null,
                "text": "If the reader has buffered less than 1024 bytes, can binary content past the first line still be missed?"
              },
              "id": "binary-detection-beyond-first-line",
              "title": "Binary files are now recognized even when a line break comes before the first null byte",
              "why": {
                "confidence": null,
                "provenance": "claim",
                "source": "PR description, Root cause section",
                "text": "Author says the inspector checks up to 1024 bytes but bat passed only the first line, so encrypted data containing an early newline was classified as UTF-8."
              }
            }
          ]
        }
        """#

    private static let architectureJSON = #"""
        {
          "architecture": {
            "explanation": {
              "confidence": "high",
              "provenance": "interpretation",
              "source": null,
              "text": "The Input → Content Inspection → Printer pipeline keeps the same parts and connections. Content Inspection now receives up to 1 KB of already-buffered input instead of only the first line. The first line still goes on to the Printer unchanged."
            },
            "focusIds": [
              "content-inspection",
              "edge-input-inspection"
            ],
            "headline": "No structural change: binary sniffing now looks at a larger sample",
            "impact": "low"
          },
          "architectureImpact": {
            "confidence": "high",
            "provenance": "interpretation",
            "source": null,
            "text": "The Input → Content Inspection → Printer pipeline keeps the same parts and connections. Content Inspection now receives up to 1 KB of already-buffered input instead of only the first line. The first line still goes on to the Printer unchanged."
          },
          "boundaries": [
            {
              "componentIds": [
                "input-reading",
                "content-inspection",
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
              "delta": null,
              "filesChanged": 1,
              "id": "input-reading",
              "implementedBy": [
                "InputReader",
                "src/input.rs"
              ],
              "level": "system",
              "parentId": null,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 301,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 267
                }
              ],
              "summary": {
                "confidence": "high",
                "provenance": "interpretation",
                "source": null,
                "text": "Wraps file or stdin readers and yields lines to printing"
              },
              "title": "Input Reading"
            },
            {
              "changeKind": "changed",
              "delta": {
                "after": "buffered 1 KB sample",
                "before": "first line",
                "summary": {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "The sample passed to inspect_content_type is now a copy of up to CONTENT_INSPECTION_LIMIT (1024) buffered bytes, taken with fill_buf before read_until. It falls back to the first line when the first line is longer than that copy."
                }
              },
              "filesChanged": 1,
              "id": "content-inspection",
              "implementedBy": [
                "inspect_content_type",
                "CONTENT_INSPECTION_LIMIT",
                "content_inspector crate"
              ],
              "level": "system",
              "parentId": null,
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
                  "endLine": 353,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 344
                }
              ],
              "summary": {
                "confidence": "high",
                "provenance": "interpretation",
                "source": null,
                "text": "Determines whether input is text, UTF-16, or binary"
              },
              "title": "Content Inspection"
            },
            {
              "changeKind": "unchanged",
              "delta": null,
              "filesChanged": 0,
              "id": "printer",
              "implementedBy": [
                "src/printer.rs"
              ],
              "level": "system",
              "parentId": null,
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
                "confidence": "high",
                "provenance": "interpretation",
                "source": null,
                "text": "Renders content or a <BINARY> header based on content type"
              },
              "title": "Printer"
            },
            {
              "changeKind": "unchanged",
              "delta": null,
              "filesChanged": 0,
              "id": "terminal",
              "implementedBy": [],
              "level": "system",
              "parentId": null,
              "refs": [],
              "summary": {
                "confidence": "medium",
                "provenance": "interpretation",
                "source": null,
                "text": "User's output device that receives the rendered bytes"
              },
              "title": "Terminal"
            },
            {
              "changeKind": "changed",
              "delta": null,
              "filesChanged": 1,
              "id": "impl-try-new",
              "implementedBy": [
                "InputReader::try_new"
              ],
              "level": "implementation",
              "parentId": "input-reading",
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 301,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 267
                }
              ],
              "summary": {
                "confidence": null,
                "provenance": "fact",
                "source": null,
                "text": "Takes a snapshot of the buffered prefix without consuming it, then reads the first line"
              },
              "title": "InputReader::try_new"
            }
          ],
          "edges": [
            {
              "change": "changed",
              "decisionIds": [],
              "flow": "sync",
              "fromId": "input-reading",
              "id": "edge-input-inspection",
              "isTrustBoundary": false,
              "label": "buffered 1 KB sample",
              "note": "The sample now spans multiple lines, so NUL bytes after an early newline are detected.",
              "onCriticalPath": true,
              "previousLabel": "first line",
              "toId": "content-inspection"
            },
            {
              "change": "existing",
              "decisionIds": [],
              "flow": "sync",
              "fromId": "content-inspection",
              "id": "edge-inspection-printer",
              "isTrustBoundary": false,
              "label": "content type",
              "note": null,
              "onCriticalPath": true,
              "previousLabel": null,
              "toId": "printer"
            },
            {
              "change": "existing",
              "decisionIds": [],
              "flow": "sync",
              "fromId": "input-reading",
              "id": "edge-input-printer",
              "isTrustBoundary": false,
              "label": "lines",
              "note": null,
              "onCriticalPath": true,
              "previousLabel": null,
              "toId": "printer"
            },
            {
              "change": "existing",
              "decisionIds": [],
              "flow": "sync",
              "fromId": "printer",
              "id": "edge-printer-terminal",
              "isTrustBoundary": true,
              "label": "formatted output",
              "note": null,
              "onCriticalPath": true,
              "previousLabel": null,
              "toId": "terminal"
            }
          ]
        }
        """#

    private static let understandingJSON = #"""
        {
          "intent": {
            "confidence": null,
            "provenance": "claim",
            "source": "Title: 'Detect binary content beyond the first line'. Description: 'inspect up to the first 1024 already-buffered bytes before splitting out the first line'; 'preserve the reader's bytes, line boundaries, UTF-16 handling, and streaming behavior'; Root cause: 'content_inspector checks up to 1024 bytes for a NUL byte, but bat passed only the first line. Random or encrypted data can contain a newline before its first NUL byte, so the shortened sample was classified as UTF-8 and binary bytes were sent to the terminal.' Also: 'it does not add a post-line blocking read'; 'BOM detection still takes precedence... ZIP signature detection is also unchanged.' 'Fixes #3554.'",
            "text": "Make bat detect binary content that appears after the first line. Before this change, bat passed only the first line to content_inspector, so random or encrypted data with a newline before its first NUL byte was classified as UTF-8 and printed to the terminal. The PR instead inspects up to the first 1024 bytes that are already buffered, taken before the first line is split out. It aims to keep the reader's bytes and line boundaries, UTF-16/BOM handling, ZIP detection and streaming behavior unchanged, and to add no extra blocking read. Fixes #3554."
          },
          "howItWasSolved": {
            "confidence": "high",
            "provenance": "interpretation",
            "source": "src/input.rs:12-290",
            "text": "Before, bat decided whether a file was binary by looking only at its first line, which can be very short. Now it looks at up to the first 1,024 bytes of the file (roughly a page of text) that it has already loaded. A file that has a line break early on is still caught as binary, and the file's contents are shown exactly as before."
          },
          "problemToBeSolved": {
            "confidence": null,
            "provenance": "claim",
            "source": "#3554",
            "text": "When someone opened an encrypted (gpg) file with bat, the tool often didn't recognize it as binary, meaning non-text data. It printed the scrambled bytes to the screen as garbled symbols instead of showing nothing or labeling the file as binary. The reporter said this happened with most encrypted files, though not all."
          }
        }
        """#

    private static let decisionsJSON = #"""
        {
          "decisions": [
            {
              "alternatives": [
                {
                  "confidence": "low",
                  "provenance": "interpretation",
                  "source": null,
                  "text": "Keep first-line inspection and add a separate NUL scan over later lines as they stream. That would catch more cases, but the header would be decided late or would change mid-output."
                }
              ],
              "componentIds": [
                "content-inspection",
                "input-reading"
              ],
              "confidence": "high",
              "consequences": [
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "The boundary is tested: a NUL at byte 1023 gives BINARY and a NUL at byte 1024 gives UTF_8, so the limit is pinned exactly."
                },
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "ZIP-signature detection still uses starts_with on the sample, so it behaves the same with the longer prefix."
                }
              ],
              "decision": {
                "confidence": null,
                "provenance": "fact",
                "source": null,
                "text": "try_new now passes an `inspection_prefix` of up to CONTENT_INSPECTION_LIMIT (1024) bytes to inspect_content_type instead of `first_line`. The first line itself is still split out separately and stored in `first_line`."
              },
              "id": "inspect-multi-line-prefix",
              "level": "system",
              "options": [
                {
                  "chosen": false,
                  "detail": "previous behavior",
                  "label": "First line only"
                },
                {
                  "chosen": true,
                  "detail": "spans early newlines",
                  "label": "First 1 KB"
                }
              ],
              "question": "How much data should binary detection inspect?",
              "rationale": [
                {
                  "confidence": null,
                  "provenance": "claim",
                  "source": "PR description",
                  "text": "The author says content_inspector checks up to 1024 bytes for a NUL byte, but bat passed only the first line."
                },
                {
                  "confidence": "medium",
                  "provenance": "interpretation",
                  "source": null,
                  "text": "The 1024 constant appears chosen to match content_inspector's own scan window, so inspecting more bytes would add nothing."
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
                  "endLine": 355,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 344
                },
                {
                  "blobSha": null,
                  "endLine": 2285,
                  "path": "tests/integration_tests.rs",
                  "side": "head",
                  "startLine": 2267
                }
              ],
              "shape": "threshold",
              "title": "Inspect up to 1024 bytes across line boundaries instead of only the first line",
              "tradeoffs": [
                {
                  "chosenPosition": 0.8,
                  "dimensionA": "text-file permissiveness",
                  "dimensionB": "binary detection completeness",
                  "explanation": {
                    "confidence": "medium",
                    "provenance": "interpretation",
                    "source": null,
                    "text": "Any file with a NUL byte anywhere in its first 1024 bytes is now classified as binary, even if the NUL comes after several lines of text. Before this PR, only a NUL in the first line had that effect, so some mostly-text files that used to display may now show <BINARY>."
                  },
                  "prominence": "primary",
                  "refs": [
                    {
                      "blobSha": null,
                      "endLine": 290,
                      "path": "src/input.rs",
                      "side": "head",
                      "startLine": 268
                    },
                    {
                      "blobSha": null,
                      "endLine": 454,
                      "path": "src/input.rs",
                      "side": "head",
                      "startLine": 435
                    }
                  ]
                }
              ],
              "why": {
                "confidence": null,
                "provenance": "claim",
                "source": "PR description, 'Root cause' section",
                "text": "Encrypted or random data can hit a newline before its first NUL byte, so a first-line sample gets misread as UTF-8."
              }
            },
            {
              "alternatives": [
                {
                  "confidence": "medium",
                  "provenance": "interpretation",
                  "source": null,
                  "text": "Loop on read/fill until 1024 bytes or EOF. This gives a deterministic sample for files, but can block the first output on pipes and terminals."
                },
                {
                  "confidence": "low",
                  "provenance": "interpretation",
                  "source": null,
                  "text": "Read ahead only for ordinary files, where extra reads are cheap and non-blocking, and keep the buffered-only snapshot for stdin and custom readers."
                }
              ],
              "componentIds": [
                "input-reading",
                "content-inspection"
              ],
              "confidence": "high",
              "consequences": [
                {
                  "confidence": "medium",
                  "provenance": "interpretation",
                  "source": null,
                  "text": "For ordinary files wrapped in BufReader (default capacity is larger than 1024), the full 1 KB is usually available from the first fill, so detection is effectively complete in the common case."
                },
                {
                  "confidence": "medium",
                  "provenance": "interpretation",
                  "source": null,
                  "text": "How good the classification is now depends on how the reader happens to chunk its data, so the same bytes can classify differently through a file versus a pipe."
                }
              ],
              "decision": {
                "confidence": null,
                "provenance": "fact",
                "source": null,
                "text": "The prefix is taken with `reader.fill_buf()?` and copied (at most 1024 bytes) before read_until runs. No loop tops the buffer up to the limit."
              },
              "id": "use-already-buffered-bytes",
              "level": "system",
              "options": [
                {
                  "chosen": false,
                  "detail": "complete sample",
                  "label": "Read until 1 KB"
                },
                {
                  "chosen": true,
                  "detail": "never blocks extra",
                  "label": "Use what's buffered"
                }
              ],
              "question": "Should detection wait for more stream data?",
              "rationale": [
                {
                  "confidence": null,
                  "provenance": "claim",
                  "source": "PR description",
                  "text": "The author says the snapshot is non-consuming, so no bytes are lost or reordered, and it adds no post-line blocking read."
                },
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "The new test input_detection_does_not_read_twice uses a reader that returns WouldBlock on a second read, which enforces the single-read property."
                }
              ],
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 280,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 268
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
              "shape": "binary",
              "title": "Sample only what fill_buf already exposes; never read ahead to fill 1 KB",
              "tradeoffs": [
                {
                  "chosenPosition": 0.75,
                  "dimensionA": "detection completeness",
                  "dimensionB": "streaming responsiveness",
                  "explanation": {
                    "confidence": "medium",
                    "provenance": "interpretation",
                    "source": null,
                    "text": "If the first read returns fewer than 1024 bytes (a pipe, stdin, or a slow producer), the sample is cut short. A NUL arriving in a later chunk is then missed and the input is still treated as text. This avoids stalling interactive or streaming input, e.g. `tail -f | bat`, while bat waits for 1 KB."
                  },
                  "prominence": "primary",
                  "refs": [
                    {
                      "blobSha": null,
                      "endLine": 275,
                      "path": "src/input.rs",
                      "side": "head",
                      "startLine": 272
                    },
                    {
                      "blobSha": null,
                      "endLine": 479,
                      "path": "src/input.rs",
                      "side": "head",
                      "startLine": 456
                    }
                  ]
                }
              ],
              "why": {
                "confidence": null,
                "provenance": "claim",
                "source": "PR description and code comment at src/input.rs:268-271",
                "text": "A non-consuming fill_buf snapshot loses no bytes and adds no blocking read beyond what read_until already needs."
              }
            },
            {
              "alternatives": [
                {
                  "confidence": "low",
                  "provenance": "interpretation",
                  "source": null,
                  "text": "Concatenate the buffered prefix with the rest of the first line. That is harder, because read_until consumes the same bytes the snapshot already copied."
                }
              ],
              "componentIds": [
                "content-inspection"
              ],
              "confidence": "high",
              "consequences": [
                {
                  "confidence": "medium",
                  "provenance": "interpretation",
                  "source": null,
                  "text": "When the fallback triggers, bytes after the first line are again not inspected. The fix only helps when the reader's buffer covers the cross-line region."
                }
              ],
              "decision": {
                "confidence": null,
                "provenance": "fact",
                "source": null,
                "text": "If min(first_line.len(), 1024) is larger than inspection_prefix.len(), the prefix is replaced with the first line's first 1024 bytes."
              },
              "id": "fallback-to-longer-first-line",
              "level": "implementation",
              "options": [
                {
                  "chosen": false,
                  "detail": "simpler",
                  "label": "Always buffered prefix"
                },
                {
                  "chosen": true,
                  "detail": "no regression",
                  "label": "Longer of the two"
                }
              ],
              "question": "Which sample wins when the first line exceeds the buffer?",
              "rationale": [
                {
                  "confidence": "high",
                  "provenance": "interpretation",
                  "source": null,
                  "text": "This appears to guarantee the new sample is never shorter than the old first-line sample, so detection cannot get worse than before on small-buffer readers."
                }
              ],
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 288,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 282
                }
              ],
              "shape": "binary",
              "title": "Fall back to the first line when it is longer than the buffered snapshot",
              "tradeoffs": [],
              "why": {
                "confidence": null,
                "provenance": "claim",
                "source": "code comment at src/input.rs:282-283",
                "text": "The author says a custom BufRead may expose under 1024 bytes at a time, and this keeps the old behavior for long first lines."
              }
            },
            {
              "alternatives": [],
              "componentIds": [
                "input-reading"
              ],
              "confidence": "high",
              "consequences": [
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "Empty inputs keep content_type None, the same as before."
                }
              ],
              "decision": {
                "confidence": null,
                "provenance": "fact",
                "source": null,
                "text": "read_until runs only when `!inspection_prefix.is_empty()`. For empty input, first_line stays empty and inspect_content_type returns None."
              },
              "id": "skip-read-on-empty-input",
              "level": "implementation",
              "options": [
                {
                  "chosen": false,
                  "detail": "uniform path",
                  "label": "Always read first line"
                },
                {
                  "chosen": true,
                  "detail": "single EOF event",
                  "label": "Skip on empty buffer"
                }
              ],
              "question": "Should empty input trigger a second read attempt?",
              "rationale": [
                {
                  "confidence": "medium",
                  "provenance": "interpretation",
                  "source": null,
                  "text": "On an interactive terminal, an unconditional read_until after an empty fill_buf appears likely to need a second Ctrl-D from the user. The guard avoids that."
                },
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "The empty-content case in input_detection_does_not_read_twice expects None and would fail on a second read (WouldBlock), which pins this behavior."
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
              "shape": "binary",
              "title": "Skip read_until when the initial fill_buf returns nothing",
              "tradeoffs": [],
              "why": {
                "confidence": null,
                "provenance": "claim",
                "source": "PR description",
                "text": "The author says empty input is handled without requesting a second EOF event."
              }
            }
          ]
        }
        """#

    private static let flowsJSON = #"""
        {
          "entryPoints": [
            {
              "changeKind": "changed",
              "flowId": "flow-cli-file-binary-detection",
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
                  "endLine": 120,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 112
                },
                {
                  "blobSha": null,
                  "endLine": 242,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 216
                }
              ],
              "title": "bat <file> (CLI, ordinary file argument)"
            },
            {
              "changeKind": "changed",
              "flowId": "flow-cli-stdin-binary-detection",
              "id": "cli-bat-stdin",
              "kind": "CLI command",
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
              "title": "bat reading from stdin (CLI, no file / '-')"
            },
            {
              "changeKind": "touched",
              "flowId": null,
              "id": "pretty-printer-api",
              "kind": "public API",
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 345,
                  "path": "src/pretty_printer.rs",
                  "side": "head",
                  "startLine": 333
                },
                {
                  "blobSha": null,
                  "endLine": 249,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 244
                }
              ],
              "title": "PrettyPrinter::print (library API)"
            },
            {
              "changeKind": "touched",
              "flowId": null,
              "id": "lessopen-preprocessor",
              "kind": "plugin point",
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 156,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 150
                },
                {
                  "blobSha": null,
                  "endLine": 234,
                  "path": "src/lessopen.rs",
                  "side": "head",
                  "startLine": 203
                }
              ],
              "title": "LESSOPEN preprocessor output opened as input"
            }
          ],
          "flows": [
            {
              "entryPointId": "cli-bat-file",
              "id": "flow-cli-file-binary-detection",
              "steps": [
                {
                  "branches": [
                    "if input.is_stdin() -> print_input with io::stdin().lock(), else with io::empty() dummy stdin"
                  ],
                  "caution": null,
                  "changeKind": "unchanged",
                  "componentId": null,
                  "errorPaths": [
                    "print_input errors are passed to handle_error and set no_errors=false (controller.rs:121-135)"
                  ],
                  "externalCalls": [],
                  "id": "run-controller",
                  "index": 0,
                  "isAsyncBoundaryAfter": false,
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
                      "endLine": 120,
                      "path": "src/controller.rs",
                      "side": "head",
                      "startLine": 112
                    }
                  ],
                  "stateDelta": null,
                  "title": "CLI builds Controller and runs inputs"
                },
                {
                  "branches": [
                    "lessopen feature + use_lessopen -> preprocessor.open(...)",
                    "otherwise -> input.open(stdin, stdout_identifier)"
                  ],
                  "caution": null,
                  "changeKind": "unchanged",
                  "componentId": "input-reading",
                  "errorPaths": [
                    "open errors propagate via ?"
                  ],
                  "externalCalls": [],
                  "id": "print-input-open",
                  "index": 1,
                  "isAsyncBoundaryAfter": false,
                  "refs": [
                    {
                      "blobSha": null,
                      "endLine": 161,
                      "path": "src/controller.rs",
                      "side": "head",
                      "startLine": 149
                    }
                  ],
                  "stateDelta": "opened_input.reader.unbuffered set from config after open",
                  "title": "print_input opens the input (LESSOPEN or direct)"
                },
                {
                  "branches": [
                    "path is a directory -> error",
                    "stdout surely conflicts with input -> IO circle error"
                  ],
                  "caution": null,
                  "changeKind": "unchanged",
                  "componentId": "input-reading",
                  "errorPaths": [
                    "\"'<path>': <io error>\" on open failure",
                    "\"'<path>' is a directory.\"",
                    "\"IO circle detected...\""
                  ],
                  "externalCalls": [
                    "File::open",
                    "clircle::Identifier::try_from"
                  ],
                  "id": "open-ordinary-file",
                  "index": 2,
                  "isAsyncBoundaryAfter": false,
                  "refs": [
                    {
                      "blobSha": null,
                      "endLine": 242,
                      "path": "src/input.rs",
                      "side": "head",
                      "startLine": 216
                    }
                  ],
                  "stateDelta": "File -> BufReader<File> passed to InputReader::try_new",
                  "title": "Input::open opens the file, checks for directory/IO circle, and wraps it in BufReader"
                },
                {
                  "branches": [
                    "fill_buf returns empty slice at EOF -> inspection_prefix is empty"
                  ],
                  "caution": "The snapshot only covers the bytes returned by the first fill_buf. For readers that deliver short chunks, a NUL byte after that chunk but still within 1024 bytes would appear to go unseen (the comment on input.rs:282-283 acknowledges that readers may expose fewer bytes).",
                  "changeKind": "new",
                  "componentId": "input-reading",
                  "errorPaths": [
                    "fill_buf io::Error propagates via ? out of try_new"
                  ],
                  "externalCalls": [
                    "BufRead::fill_buf"
                  ],
                  "id": "snapshot-buffered-prefix",
                  "index": 3,
                  "isAsyncBoundaryAfter": false,
                  "refs": [
                    {
                      "blobSha": null,
                      "endLine": 275,
                      "path": "src/input.rs",
                      "side": "head",
                      "startLine": 267
                    }
                  ],
                  "stateDelta": "inspection_prefix = copy of buffered[..min(len, 1024)]; reader position is unchanged",
                  "title": "try_new captures up to CONTENT_INSPECTION_LIMIT (1024) bytes via fill_buf without consuming them"
                },
                {
                  "branches": [
                    "inspection_prefix empty -> skip read_until, first_line stays empty"
                  ],
                  "caution": null,
                  "changeKind": "changed",
                  "componentId": "input-reading",
                  "errorPaths": [
                    "read_until io::Error propagates via ?"
                  ],
                  "externalCalls": [
                    "BufRead::read_until"
                  ],
                  "id": "read-first-line",
                  "index": 4,
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
                  "stateDelta": "first_line = bytes up to and including the first '\\n' (served from the already-filled buffer)",
                  "title": "Read the first line only when the buffer is non-empty"
                },
                {
                  "branches": [
                    "first_line_prefix_len > inspection_prefix.len() -> replace prefix",
                    "otherwise keep the fill_buf snapshot"
                  ],
                  "caution": null,
                  "changeKind": "new",
                  "componentId": "content-inspection",
                  "errorPaths": [],
                  "externalCalls": [],
                  "id": "fallback-to-first-line",
                  "index": 5,
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
                  "stateDelta": "inspection_prefix replaced by first_line[..min(len,1024)] when that is longer",
                  "title": "If the first line is longer than the snapshot, inspect the first line prefix instead"
                },
                {
                  "branches": [
                    "empty prefix -> None",
                    "UTF_8 and starts with PK\\x03\\x04 / PK\\x05\\x06 / PK\\x07\\x08 -> BINARY",
                    "otherwise -> content_inspector result (BINARY, UTF_8, UTF_16LE, UTF_16BE, ...)"
                  ],
                  "caution": null,
                  "changeKind": "changed",
                  "componentId": "content-inspection",
                  "errorPaths": [],
                  "externalCalls": [
                    "content_inspector::inspect"
                  ],
                  "id": "inspect-content-type",
                  "index": 6,
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
                  "stateDelta": "content_type: Option<ContentType> is derived from inspection_prefix instead of first_line",
                  "title": "Classify the inspection prefix (content_inspector + ZIP signature)"
                },
                {
                  "branches": [
                    "UTF_16LE -> read_utf16_line(0x00, 0x0A)",
                    "UTF_16BE -> read_utf16_line(0x0A, 0x00)"
                  ],
                  "caution": null,
                  "changeKind": "unchanged",
                  "componentId": "input-reading",
                  "errorPaths": [
                    "read_utf16_line io::Error propagates via ?"
                  ],
                  "externalCalls": [],
                  "id": "utf16-first-line",
                  "index": 7,
                  "isAsyncBoundaryAfter": false,
                  "refs": [
                    {
                      "blobSha": null,
                      "endLine": 304,
                      "path": "src/input.rs",
                      "side": "head",
                      "startLine": 292
                    }
                  ],
                  "stateDelta": "InputReader { inner: Box<reader>, first_line, content_type, unbuffered: false }",
                  "title": "For UTF-16, extend first_line to the full UTF-16 line and build InputReader"
                },
                {
                  "branches": [
                    "loop_through -> SimplePrinter (content_type unused)",
                    "binary and !show_nonprintable and binary != AsText -> no syntax highlighter"
                  ],
                  "caution": null,
                  "changeKind": "touched",
                  "componentId": "printer",
                  "errorPaths": [
                    "get_syntax errors other than UndetectedSyntax are returned"
                  ],
                  "externalCalls": [],
                  "id": "printer-setup",
                  "index": 8,
                  "isAsyncBoundaryAfter": false,
                  "refs": [
                    {
                      "blobSha": null,
                      "endLine": 202,
                      "path": "src/controller.rs",
                      "side": "head",
                      "startLine": 192
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
                  "stateDelta": "printer.content_type = input.reader.content_type",
                  "title": "InteractivePrinter skips syntax matching for binary content"
                },
                {
                  "branches": [
                    "header disabled and BINARY -> '[bat warning]: Binary content ... will not be printed to the terminal'",
                    "header enabled and BINARY -> '   <BINARY>' mode suffix",
                    "print_line with BINARY/None and binary != AsText -> return without writing",
                    "show_nonprintable -> replace_nonprintable output"
                  ],
                  "caution": null,
                  "changeKind": "touched",
                  "componentId": "printer",
                  "errorPaths": [
                    "write errors propagate via ?"
                  ],
                  "externalCalls": [],
                  "id": "print-header-and-lines",
                  "index": 9,
                  "isAsyncBoundaryAfter": false,
                  "refs": [
                    {
                      "blobSha": null,
                      "endLine": 226,
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
                  "stateDelta": null,
                  "title": "Header shows <BINARY> (or a warning when there is no header), and binary lines are suppressed"
                }
              ],
              "storySteps": [
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "Open the file and wrap it in a buffered reader"
                },
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "Take a snapshot of up to 1024 already-buffered bytes"
                },
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "Read the first line without losing the snapshot"
                },
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "Classify content as binary, UTF-8, UTF-16, or empty"
                },
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "Print the header with a binary marker and skip binary lines"
                }
              ],
              "title": "bat <file> -> content type detected over a buffered prefix -> binary header/suppression"
            },
            {
              "entryPointId": "cli-bat-stdin",
              "id": "flow-cli-stdin-binary-detection",
              "steps": [
                {
                  "branches": [],
                  "caution": null,
                  "changeKind": "unchanged",
                  "componentId": null,
                  "errorPaths": [],
                  "externalCalls": [
                    "io::stdin().lock()"
                  ],
                  "id": "stdin-lock",
                  "index": 0,
                  "isAsyncBoundaryAfter": false,
                  "refs": [
                    {
                      "blobSha": null,
                      "endLine": 116,
                      "path": "src/controller.rs",
                      "side": "head",
                      "startLine": 115
                    }
                  ],
                  "stateDelta": null,
                  "title": "Controller passes io::stdin().lock() for the stdin input"
                },
                {
                  "branches": [
                    "stdout surely conflicts with stdin -> IO circle error"
                  ],
                  "caution": null,
                  "changeKind": "unchanged",
                  "componentId": "input-reading",
                  "errorPaths": [
                    "\"Stdin: Error identifying file\"",
                    "\"IO circle detected. The input from stdin is also an output...\""
                  ],
                  "externalCalls": [
                    "clircle::Identifier::try_from(Stdio::Stdin)"
                  ],
                  "id": "stdin-open",
                  "index": 1,
                  "isAsyncBoundaryAfter": false,
                  "refs": [
                    {
                      "blobSha": null,
                      "endLine": 213,
                      "path": "src/input.rs",
                      "side": "head",
                      "startLine": 199
                    }
                  ],
                  "stateDelta": "StdinLock (already BufRead) passed to InputReader::try_new without a BufReader wrapper",
                  "title": "Input::open StdIn checks for an IO circle and calls try_new on the StdinLock directly"
                },
                {
                  "branches": [
                    "empty stdin -> no read_until call; content_type None",
                    "first line longer than snapshot -> inspect first-line prefix"
                  ],
                  "caution": "With piped stdin, the first fill_buf can return a single short read. Cross-line detection then appears to cover only that chunk, not a full 1024 bytes, so a NUL arriving in a later write may still be missed.",
                  "changeKind": "changed",
                  "componentId": "content-inspection",
                  "errorPaths": [
                    "fill_buf/read_until io::Error propagates out of Input::open"
                  ],
                  "externalCalls": [
                    "StdinLock::fill_buf",
                    "content_inspector::inspect"
                  ],
                  "id": "stdin-snapshot-and-classify",
                  "index": 2,
                  "isAsyncBoundaryAfter": false,
                  "refs": [
                    {
                      "blobSha": null,
                      "endLine": 290,
                      "path": "src/input.rs",
                      "side": "head",
                      "startLine": 267
                    }
                  ],
                  "stateDelta": "content_type derived from min(first fill_buf chunk, 1024 bytes) or the first-line prefix, whichever is longer",
                  "title": "fill_buf snapshot, first-line read, fallback, and inspect_content_type"
                }
              ],
              "storySteps": [
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "Lock stdin and check for an input/output loop"
                },
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "Take a snapshot of whatever stdin has buffered, up to 1024 bytes"
                },
                {
                  "confidence": null,
                  "provenance": "fact",
                  "source": null,
                  "text": "Classify content and continue printing as for files"
                }
              ],
              "title": "bat (stdin) -> content type detected from the StdinLock buffer"
            }
          ]
        }
        """#

    private static let judgmentJSON = #"""
        {
          "architectureImpact": {
            "confidence": "high",
            "provenance": "interpretation",
            "text": "The Input → Content Inspection → Printer pipeline keeps the same parts and connections. Content Inspection now receives up to 1 KB of already-buffered input instead of only the first line. The first line still goes on to the Printer unchanged."
          },
          "changeMap": [
            {
              "filesChanged": 1,
              "name": "Input Reading / Content Inspection"
            },
            {
              "filesChanged": 1,
              "name": "Integration tests"
            },
            {
              "filesChanged": 1,
              "name": "Changelog"
            },
            {
              "filesChanged": 0,
              "name": "Printer"
            }
          ],
          "considerations": [
            {
              "assumptions": [
                "How much data a pipe delivers in its first read depends on the operating system and the producing program; this was not measured.",
                "It is assumed the standard buffered reader's default capacity exceeds 1024 bytes, so ordinary files supply a full sample."
              ],
              "category": "product-behavior",
              "confidence": "medium",
              "context": "bat decides once, before printing anything, whether an input is binary. It now examines up to the first kilobyte, but only the part that arrived in the first delivery of data. Files normally supply the full kilobyte at once. A pipe or custom stream may supply less, and later bytes are never examined.",
              "evidence": "InputReader::try_new takes the sample from a single reader.fill_buf() call, truncated to CONTENT_INSPECTION_LIMIT (src/input.rs:272-275), and never tops it up. The only fallback replaces the sample with the first line when that line is longer than the snapshot (src/input.rs:282-288), so bytes after the first newline are again unseen in that case. Stdin is passed as a StdinLock straight into try_new (src/controller.rs:115-116, src/input.rs:208-213); custom readers are wrapped in BufReader (src/input.rs:244-249), so a Read that returns small chunks yields a short sample. content_type is fixed at construction (src/input.rs:290, 298-303) and copied once into the printer (src/printer.rs:339); nothing re-inspects later lines. Counterevidence: ordinary files go through BufReader::new(file) (src/input.rs:241), and LESSOPEN piped output is a Cursor over already collected bytes (src/lessopen.rs:235), so both expose a full sample. Tests: input_detection_does_not_read_twice pins the single-read property with a reader that returns WouldBlock on a second read (src/input.rs:456-479), which would fail if a top-up loop were added unconditionally. No test covers a short first chunk followed by a NUL inside the first 1024 bytes; the new integration test uses a file (tests/integration_tests.rs:2267-2285) and filename_stdin_binary puts the NUL in the first byte (tests/integration_tests.rs:2465-2476). Possible alternatives: read ahead until 1024 bytes or EOF only for non-interactive inputs, or keep the current behavior and document it.",
              "flowAnchors": [
                {
                  "flowId": "flow-cli-stdin-binary-detection",
                  "nodeId": "stdin-snapshot-and-classify"
                },
                {
                  "flowId": "flow-cli-file-binary-detection",
                  "nodeId": "snapshot-buffered-prefix"
                }
              ],
              "headline": "Piped binary input can still display as text when data arrives slowly",
              "id": "short-first-delivery-misses-binary",
              "impact": "The same content can be hidden as binary when opened as a file yet printed raw to the terminal when piped, and the outcome can vary between runs with the producer's timing.",
              "judgment": "Should bat wait for more input before classifying a stream, or classify on whatever arrives first?",
              "judgmentType": "design-decision",
              "kind": "concern",
              "moreContext": null,
              "provenance": "interpretation",
              "refs": [
                {
                  "endLine": 290,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 267
                },
                {
                  "endLine": 213,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 208
                },
                {
                  "endLine": 249,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 244
                },
                {
                  "endLine": 479,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 456
                },
                {
                  "endLine": 116,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 115
                }
              ],
              "relatedIds": [
                "use-already-buffered-bytes",
                "fallback-to-longer-first-line",
                "content-inspection",
                "input-reading",
                "edge-input-inspection",
                "flow-cli-stdin-binary-detection"
              ],
              "tradeoff": "Waiting for a full kilobyte or end of input would make classification consistent, but would delay first output for slow or interactive streams. Using only what has arrived keeps streaming immediate but ties detection to delivery size."
            },
            {
              "assumptions": [
                "How common mostly-text files with a null byte in their first kilobyte are among bat users is unknown.",
                "That any null byte inside the inspected window yields a binary classification is inferred from the boundary test, not from the inspection library's source, which is outside this checkout."
              ],
              "category": "compatibility",
              "confidence": "medium",
              "context": "When bat classifies an input as binary, terminal output shows only a header marker or a warning and none of the content. Previously only a null byte in the first line triggered this. Now a null byte anywhere in the first kilobyte does, including in otherwise readable text such as logs or null-separated records.",
              "evidence": "The sample passed to inspect_content_type is now inspection_prefix (up to 1024 buffered bytes) instead of first_line (src/input.rs:272-290). The unit test binary_detection_scans_beyond_first_line_and_preserves_input asserts BINARY for a NUL at index 1023 on a later line and UTF_8 for a NUL at index 1024 (src/input.rs:434-454). The integration test classifies the readable content packet-header, newline, payload NUL bytes as BINARY (tests/integration_tests.rs:2267-2285), which is exactly a text-like file with one NUL on line 2. Once BINARY, InteractivePrinter::print_line returns without writing any line (src/printer.rs:664-669), the header shows the BINARY marker (src/printer.rs:515-521), or a warning is printed when the header is disabled (src/printer.rs:496-508), and syntax matching is skipped (src/printer.rs:271-281). Counterevidence and escape hatches: --binary=as-text and show_nonprintable (-A) bypass suppression (src/printer.rs:497-499, 656-667; src/bin/bat/app.rs:438-441), and pass-through output via SimplePrinter ignores content type entirely (src/printer.rs:136-184), selected when output is not interactive and color/decorations are not forced (src/bin/bat/app.rs:477-483). The changelog entry sits under Bugfixes and only mentions encrypted files (CHANGELOG.md:28).",
              "flowAnchors": [
                {
                  "flowId": "flow-cli-file-binary-detection",
                  "nodeId": "inspect-content-type"
                },
                {
                  "flowId": "flow-cli-file-binary-detection",
                  "nodeId": "print-header-and-lines"
                }
              ],
              "headline": "Text files with an early null byte are now hidden entirely",
              "id": "text-with-early-null-now-hidden",
              "impact": "Users who could read such files before will see no content until they pass an option to show binary data. The changelog lists this as a bug fix and does not mention the effect.",
              "judgment": "Should a mostly-text file with a null byte after its first line be hidden as binary by default?",
              "judgmentType": "compatibility-decision",
              "kind": "concern",
              "moreContext": null,
              "provenance": "interpretation",
              "refs": [
                {
                  "endLine": 290,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 272
                },
                {
                  "endLine": 454,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 434
                },
                {
                  "endLine": 521,
                  "path": "src/printer.rs",
                  "side": "head",
                  "startLine": 496
                },
                {
                  "endLine": 669,
                  "path": "src/printer.rs",
                  "side": "head",
                  "startLine": 664
                },
                {
                  "endLine": 2285,
                  "path": "tests/integration_tests.rs",
                  "side": "head",
                  "startLine": 2267
                },
                {
                  "endLine": 28,
                  "path": "CHANGELOG.md",
                  "side": "head",
                  "startLine": 28
                }
              ],
              "relatedIds": [
                "inspect-multi-line-prefix",
                "content-inspection",
                "printer",
                "edge-inspection-printer",
                "flow-cli-file-binary-detection"
              ],
              "tradeoff": "Treating any early null byte as binary keeps encrypted or random data off the terminal. It also hides mostly-text files that happen to contain one, which users could previously read without extra options."
            },
            {
              "assumptions": [
                "The retry behavior of the standard library's line read and the lack of retry in its buffered fill were taken from standard library documentation, not verified in this checkout.",
                "Whether interrupted reads actually reach bat on supported platforms was not tested."
              ],
              "category": "error-handling",
              "confidence": "low",
              "context": "Opening an input now performs one up-front read to take the detection sample. Based on standard library behavior, the earlier first-line read silently retried when a signal interrupted it, while the new read appears to report the interruption as an error. bat treats an initial read error as a failure to open that input.",
              "evidence": "The snapshot is taken with reader.fill_buf()? (src/input.rs:273), which propagates every io::Error, including ErrorKind::Interrupted. Before this PR the only initial read was reader.read_until (now src/input.rs:279), which the standard library documents as ignoring ErrorKind::Interrupted and retrying. Errors from try_new propagate out of Input::open (src/input.rs:212, 241, 248), and the existing test input_open_returns_initial_read_errors confirms initial read errors surface as open failures (src/input.rs:481-500); the controller then reports them per input (src/controller.rs:121-135). Counterevidence: a search of src and Cargo.toml found no signal-handler installation in bat itself, so the CLI is unlikely to see interrupted reads in practice; and read_line_unbuffered already calls fill_buf without a retry (src/input.rs:327-341), so there is precedent, though only in unbuffered mode. No test exercises an Interrupted error on the first read. Possible fix: retry the snapshot read while the error kind is Interrupted.",
              "flowAnchors": [
                {
                  "flowId": "flow-cli-file-binary-detection",
                  "nodeId": "snapshot-buffered-prefix"
                }
              ],
              "headline": "An interrupted first read may now fail the input instead of retrying",
              "id": "interrupted-initial-read-not-retried",
              "impact": "If an interruption lands during that first read, the input would be skipped with an error rather than displayed. This appears most likely for programs that embed bat as a library and install their own signal handlers.",
              "judgment": "Should an interrupted initial read be retried rather than reported as a failure for that input?",
              "judgmentType": "potential-problem",
              "kind": "concern",
              "moreContext": null,
              "provenance": "interpretation",
              "refs": [
                {
                  "endLine": 280,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 272
                },
                {
                  "endLine": 500,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 481
                },
                {
                  "endLine": 341,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 327
                }
              ],
              "relatedIds": [
                "use-already-buffered-bytes",
                "impl-try-new",
                "input-reading"
              ],
              "tradeoff": null
            }
          ],
          "implications": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "The same bytes can now be classified differently depending on whether they come from a file or arrive in small pieces through a pipe."
            },
            {
              "confidence": "high",
              "provenance": "interpretation",
              "source": null,
              "text": "Text files that embed a null byte after their first line, previously displayed in full, are now hidden unless the user opts into showing binary content."
            },
            {
              "confidence": "high",
              "provenance": "fact",
              "source": null,
              "text": "Piped or redirected output is unaffected, because the binary classification only influences decorated terminal output, not pass-through output."
            },
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Detection still appears to depend on a null byte showing up early, so a small share of encrypted files may still display as text."
            }
          ],
          "intent": {
            "provenance": "claim",
            "source": "Title: 'Detect binary content beyond the first line'. Description: 'inspect up to the first 1024 already-buffered bytes before splitting out the first line'; 'preserve the reader's bytes, line boundaries, UTF-16 handling, and streaming behavior'; Root cause: 'content_inspector checks up to 1024 bytes for a NUL byte, but bat passed only the first line. Random or encrypted data can contain a newline before its first NUL byte, so the shortened sample was classified as UTF-8 and binary bytes were sent to the terminal.' Also: 'it does not add a post-line blocking read'; 'BOM detection still takes precedence... ZIP signature detection is also unchanged.' 'Fixes #3554.'",
            "text": "Make bat detect binary content that appears after the first line. Before this change, bat passed only the first line to content_inspector, so random or encrypted data with a newline before its first NUL byte was classified as UTF-8 and printed to the terminal. The PR instead inspects up to the first 1024 bytes that are already buffered, taken before the first line is split out. It aims to keep the reader's bytes and line boundaries, UTF-16/BOM handling, ZIP detection and streaming behavior unchanged, and to add no extra blocking read. Fixes #3554."
          },
          "needsJudgment": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Whether stream input should be classified from only the first delivery of data, which appears to leave piped binary content past the first line undetected when that delivery is short."
            },
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Whether hiding mostly-text files that contain a null byte after the first line is the intended default, given the change is described only as a bug fix."
            },
            {
              "confidence": "low",
              "provenance": "interpretation",
              "source": null,
              "text": "Whether the new up-front read should tolerate interruption the way the earlier first-line read appears to have done."
            }
          ],
          "questions": [
            {
              "id": "content-inspector-criteria",
              "refs": [
                {
                  "endLine": 52,
                  "path": "Cargo.toml",
                  "side": "head",
                  "startLine": 52
                },
                {
                  "endLine": 355,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 344
                }
              ],
              "relatedIds": [
                "inspect-multi-line-prefix",
                "content-inspection"
              ],
              "text": "Could not read the content_inspector 0.2.4 source from this checkout (only the dependency declaration at Cargo.toml:52). Does it flag anything other than byte-order marks and null bytes, and is its scan window exactly 1024 bytes as the author states?"
            },
            {
              "id": "issue-3554-fully-resolved",
              "refs": [
                {
                  "endLine": 28,
                  "path": "CHANGELOG.md",
                  "side": "head",
                  "startLine": 28
                },
                {
                  "endLine": 2285,
                  "path": "tests/integration_tests.rs",
                  "side": "head",
                  "startLine": 2267
                }
              ],
              "relatedIds": [
                "inspect-multi-line-prefix"
              ],
              "text": "The changelog says this closes #3554, but the reporter's reproduction used real gpg output and no such sample is in the repo. Could not determine whether encrypted files lacking a null byte in the first kilobyte still display as text."
            },
            {
              "id": "pr-3763-interaction",
              "refs": [
                {
                  "endLine": 280,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 277
                }
              ],
              "relatedIds": [
                "impl-try-new",
                "input-reading"
              ],
              "text": "The author says PR #3763 changes the same initialization path to bound reads for newline-free binary files. Could not determine its status from this checkout; the first-line read here is still unbounded (src/input.rs:279). How will the two changes combine?"
            },
            {
              "id": "pipe-first-chunk-size",
              "refs": [
                {
                  "endLine": 213,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 208
                },
                {
                  "endLine": 275,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 272
                }
              ],
              "relatedIds": [
                "use-already-buffered-bytes",
                "flow-cli-stdin-binary-detection"
              ],
              "text": "Could not determine from the repo how large the first delivery of piped stdin typically is on supported platforms, and so how often cross-line detection is incomplete for pipes in practice."
            }
          ],
          "uncertainties": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "The inspection library's source is outside this checkout, so its 1024-byte scan window and the exact signals it treats as binary could not be read directly; the boundary test at src/input.rs:434-454 suggests the window is 1024 bytes."
            },
            {
              "confidence": "low",
              "provenance": "interpretation",
              "source": null,
              "text": "If detection relies only on a null byte, roughly 2 percent of uniformly random one-kilobyte samples would contain none, so some encrypted files would appear to remain undetected; this estimate was not verified against real encrypted files."
            },
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "No test covers the fallback where the first line is longer than the buffered snapshot, or a short first chunk followed by a null byte, so behavior on small-buffer readers appears unpinned."
            },
            {
              "confidence": "high",
              "provenance": "interpretation",
              "source": null,
              "text": "The author's reported validation results (455 tests passed, clippy and fmt clean) were not re-run here."
            }
          ]
        }
        """#
}
