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
          "changeMap": [
            {
              "filesChanged": 1,
              "name": "Input Reading"
            },
            {
              "filesChanged": 1,
              "name": "Content Inspection"
            },
            {
              "filesChanged": 1,
              "name": "InputReader::try_new"
            },
            {
              "filesChanged": 0,
              "name": "Printer"
            },
            {
              "filesChanged": 0,
              "name": "Terminal"
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
              "category": "reliability",
              "confidence": "medium",
              "decision": "Is best-effort detection on piped or streamed input acceptable for this fix?",
              "evidence": "try_new copies only what the first `reader.fill_buf()?` returns, capped at CONTENT_INSPECTION_LIMIT (src/input.rs:272-275). Nothing loops to top the buffer up to 1024 bytes. For ordinary files, Input::open wraps the File in BufReader::new (src/input.rs:241), whose default capacity is larger than 1 KB, so a single fill usually covers the whole window. For stdin, the StdinLock goes straight to try_new (src/input.rs:208-212), so the sample is whatever one read(2) on the pipe returned. The only fallback is when the first line is longer than the snapshot (src/input.rs:284-288); then the first line is inspected, as before. The code comment at src/input.rs:282-283 says readers 'may expose less than 1024 bytes at a time'. LESSOPEN piped output is not affected, because it is collected fully into a Cursor first (src/lessopen.rs:234-235). The test input_detection_does_not_read_twice (src/input.rs:456-479) pins the no-extra-read property: its reader returns WouldBlock on a second read. So topping up to 1 KB would be a deliberate reversal of the design. A middle option is to top up only while more data is immediately available, or only for ordinary files, where an extra read cannot block.",
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
              "headline": "Piped input may still show binary data when it arrives in small pieces",
              "id": "piped-input-detection-depends-on-chunking",
              "impact": "If `gpg -d … | bat` or another slow producer sends a short first chunk, a null byte in a later chunk goes unseen. The garbled output from #3554 can then still reach the terminal, and the same bytes can be classified differently through a pipe than from a file.",
              "judgmentType": "design-decision",
              "kind": "concern",
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
                  "startLine": 199
                },
                {
                  "endLine": 479,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 456
                },
                {
                  "endLine": 239,
                  "path": "src/lessopen.rs",
                  "side": "head",
                  "startLine": 233
                }
              ],
              "relatedIds": [
                "use-already-buffered-bytes",
                "content-inspection",
                "edge-input-inspection",
                "flow-cli-stdin-binary-detection"
              ]
            },
            {
              "category": "product-behavior",
              "confidence": "medium",
              "decision": "Should one null byte in the first kilobyte suppress an otherwise readable file?",
              "evidence": "inspect_content_type now receives up to 1024 bytes across lines instead of only first_line (src/input.rs:290, 344-355). A BINARY result means the header shows '   <BINARY>' (src/printer.rs:515-516), or, with headers off, a '[bat warning]: Binary content ... will not be printed' message (src/printer.rs:496-508). Every line is then dropped unless binary behavior is AsText (src/printer.rs:664-669). Piped output is unaffected because loop_through uses SimplePrinter, which ignores content_type (src/controller.rs:192-193). Before this PR, only a NUL in the first line triggered this, so the set of files hidden on the terminal has grown. The boundary test (src/input.rs:434-454) and the integration test header_binary_with_null_after_first_line (tests/integration_tests.rs:2267-2285) confirm the new classification but do not cover a text-dominant file. This matches content_inspector's own heuristic (any NUL in the window means binary), so it is probably intended, but it is a user-visible change the reviewer should accept explicitly.",
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
              "headline": "Text files with a stray null byte early on are now hidden entirely",
              "id": "mostly-text-files-now-hidden",
              "impact": "A log or config file whose line 3 contains one null byte used to display normally. Now bat shows only a `<BINARY>` header or a warning and prints none of its lines on the terminal, unless the user passes `-A` or `--binary=as-text`.",
              "judgmentType": "confirm-intent",
              "kind": "concern",
              "provenance": "interpretation",
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
                  "endLine": 669,
                  "path": "src/printer.rs",
                  "side": "head",
                  "startLine": 664
                },
                {
                  "endLine": 193,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 192
                }
              ],
              "relatedIds": [
                "inspect-multi-line-prefix",
                "printer",
                "edge-input-inspection",
                "flow-cli-file-binary-detection"
              ]
            },
            {
              "category": "compatibility",
              "confidence": "medium",
              "decision": "Should these two input-setup changes be sequenced and reviewed together?",
              "evidence": "The PR description says: 'PR #3763 changes the same input initialization path for a distinct issue (#2262: bounding reads for newline-free binary files). If it merges first, this PR will need a small rebase.' In this checkout, try_new still calls an unbounded `reader.read_until(b'\\n', &mut first_line)` after the snapshot (src/input.rs:277-280), so a binary file with no newline is still read fully into memory to form first_line. Issue #2262 is unchanged by this PR. CHANGELOG.md mentions neither #3763 nor #2262 (only line 28 for this PR), which suggests #3763 has not merged. After a rebase, the detection sample (snapshot) and the line boundary (first_line) must still come from separate reads, or the #3554 regression can return.",
              "flowAnchors": [
                {
                  "flowId": "flow-cli-file-binary-detection",
                  "nodeId": "read-first-line"
                }
              ],
              "headline": "A pending PR reworks the same file-opening step",
              "id": "overlap-with-pending-bounded-read-pr",
              "impact": "If #3763, which caps how much of a newline-free binary file is read up front, merges after this PR, the two changes to input setup must be reconciled. A careless rebase could reintroduce first-line-only detection, or unbounded reads.",
              "judgmentType": "external-dependency",
              "kind": "question",
              "provenance": "claim",
              "refs": [
                {
                  "endLine": 290,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 272
                },
                {
                  "endLine": 28,
                  "path": "CHANGELOG.md",
                  "side": "head",
                  "startLine": 28
                }
              ],
              "relatedIds": [
                "use-already-buffered-bytes",
                "impl-try-new",
                "input-reading"
              ]
            },
            {
              "category": "test-coverage",
              "confidence": "medium",
              "decision": "Should the small-chunk reader case be covered before merge?",
              "evidence": "The fallback at src/input.rs:284-288 replaces inspection_prefix with first_line[..min(len,1024)] only when the first line is longer than the fill_buf snapshot. The new tests use &[u8] (src/input.rs:440, 452), which exposes all bytes at once, and a BufReader over a single short read (src/input.rs:475-478). Neither produces a first line longer than the snapshot, so the fallback branch never runs. The existing UTF-16 tests (src/input.rs:500 onward) also use full in-memory slices. One possible test: a BufReader::with_capacity(4, ...) over content whose first line holds a NUL after byte 4, asserting BINARY. Another: a reader that returns 1-byte chunks with a NUL on line 2, documenting the known limit from the first consideration.",
              "flowAnchors": [
                {
                  "flowId": "flow-cli-file-binary-detection",
                  "nodeId": "fallback-to-first-line"
                }
              ],
              "headline": "The small-buffer fallback path has no test",
              "id": "short-buffer-fallback-untested",
              "impact": "The branch that falls back to old behavior for readers exposing little data at a time is never run by tests. A future change could make such readers classify worse than before, and nothing would catch it.",
              "judgmentType": "potential-problem",
              "kind": "concern",
              "provenance": "fact",
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
                }
              ],
              "relatedIds": [
                "fallback-to-longer-first-line",
                "impl-try-new"
              ]
            }
          ],
          "needsJudgment": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Whether best-effort, chunk-dependent binary detection for stdin and pipes is acceptable, given that issue #3554 (encrypted data) is often reached through `gpg -d | bat`-style pipelines."
            },
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Whether hiding all terminal output for mostly-text files that have one NUL within the first 1024 bytes (but after line 1) is an acceptable user-visible behavior change."
            }
          ],
          "questions": [
            {
              "id": "content-inspector-window",
              "refs": [
                {
                  "endLine": 12,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 12
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
              "text": "Could not confirm from the checkout that content_inspector 0.2.4 limits its NUL scan to 1024 bytes. If its window is larger or smaller, CONTENT_INSPECTION_LIMIT (src/input.rs:12) would either over-cap the sample or add nothing."
            },
            {
              "id": "pr-3763-status",
              "refs": [
                {
                  "endLine": 304,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 267
                }
              ],
              "relatedIds": [
                "use-already-buffered-bytes",
                "impl-try-new"
              ],
              "text": "Could not determine the status of PR #3763, which per the author changes the same try_new initialization path, or how the two changes will be reconciled."
            }
          ],
          "uncertainties": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "The claim that content_inspector 0.2.4 (Cargo.toml:52) scans at most 1024 bytes could not be verified, because the crate source is outside the checkout. The PR's CONTENT_INSPECTION_LIMIT appears chosen to match it."
            },
            {
              "confidence": "low",
              "provenance": "interpretation",
              "source": null,
              "text": "Whether PR #3763 is still open or has merged elsewhere could not be determined. CHANGELOG.md does not mention it, which suggests it has not merged."
            }
          ]
        }
        """#
}
