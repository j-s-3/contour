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
              "label": "Snapshot first 1024 buffered bytes",
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
                  "startLine": 268
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
                  "endLine": 289,
                  "path": "src/input.rs",
                  "startLine": 276
                }
              ],
              "tag": "both"
            },
            {
              "componentIds": [
                "inspect_content_type"
              ],
              "flowId": null,
              "label": "Inspect buffered prefix",
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
              "label": "Show binary header",
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
                "read_until"
              ],
              "flowId": null,
              "label": "Read first line",
              "outcome": null,
              "refs": [
                {
                  "endLine": 290,
                  "path": "src/input.rs",
                  "startLine": 267
                }
              ],
              "tag": "both"
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
            "text": "Encrypted or random files with an early newline now get a <BINARY> header rather than dumping raw bytes to the terminal."
          },
          "humanQuestion": {
            "confidence": "medium",
            "provenance": "interpretation",
            "source": null,
            "text": "Does detection stay correct when the reader buffers fewer than 1024 bytes at first?"
          },
          "id": "binary-detection-beyond-first-line",
          "title": "Files with a NUL byte after the first line break are now detected as binary",
          "why": {
            "confidence": null,
            "provenance": "claim",
            "source": "PR description, Root cause",
            "text": "Author: bat passed only the first line to a 1024-byte NUL check, so encrypted data with early newlines was classified as UTF-8."
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
        "text": "The content-type check now looks at up to 1024 bytes that are already buffered, taken without consuming them before the first line is split out. Before, it only looked at the first line. So binary data with an early newline, such as encrypted files, appears to be caught before it reaches the terminal. The stream, line boundaries and UTF-16 handling are unchanged."
      },
      "boundaries": [
        {
          "componentIds": [
            "input-reader",
            "content-classifier",
            "line-reader",
            "printer"
          ],
          "id": "bat-process",
          "kind": "application",
          "label": "bat process"
        }
      ],
      "components": [
        {
          "changeKind": "unchanged",
          "dependsOnIds": [],
          "filesChanged": 0,
          "id": "input-source",
          "implementedBy": [
            "BufRead reader"
          ],
          "isTrustBoundaryEdge": false,
          "level": "system",
          "refs": [
            {
              "blobSha": null,
              "endLine": 267,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 267
            }
          ],
          "summary": {
            "confidence": null,
            "provenance": "fact",
            "source": "src/input.rs",
            "text": "Byte stream wrapped in a BufRead that InputReader::try_new takes as its argument."
          },
          "title": "Input Source (file / stdin)"
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
              "endLine": 296,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 267
            }
          ],
          "summary": {
            "confidence": null,
            "provenance": "fact",
            "source": "src/input.rs",
            "text": "Before read_until pulls out the first line, it now copies up to 1024 bytes that are already buffered, using fill_buf, which does not consume them. If a custom reader buffers less, it falls back to the first line."
          },
          "title": "Input Reader initialization"
        },
        {
          "changeKind": "touched",
          "dependsOnIds": [],
          "filesChanged": 0,
          "id": "content-classifier",
          "implementedBy": [
            "inspect_content_type",
            "content_inspector crate"
          ],
          "isTrustBoundaryEdge": false,
          "level": "system",
          "refs": [
            {
              "blobSha": null,
              "endLine": 352,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 344
            }
          ],
          "summary": {
            "confidence": null,
            "provenance": "fact",
            "source": "src/input.rs",
            "text": "Uses content_inspector to classify bytes as UTF-8, UTF-16 or BINARY, and adds a check for the ZIP signature. It now gets the wider prefix instead of only the first line."
          },
          "title": "Content Type Classifier"
        },
        {
          "changeKind": "unchanged",
          "dependsOnIds": [],
          "filesChanged": 0,
          "id": "line-reader",
          "implementedBy": [
            "InputReader::read_line",
            "read_utf16_line"
          ],
          "isTrustBoundaryEdge": false,
          "level": "system",
          "refs": [
            {
              "blobSha": null,
              "endLine": 316,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 292
            }
          ],
          "summary": {
            "confidence": null,
            "provenance": "fact",
            "source": "src/input.rs",
            "text": "Replays the first line and then streams the remaining lines, handling UTF-16 by content type."
          },
          "title": "Line Reader / UTF-16 decoding"
        },
        {
          "changeKind": "unchanged",
          "dependsOnIds": [],
          "filesChanged": 0,
          "id": "printer",
          "implementedBy": [
            "printer"
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
            "confidence": "medium",
            "provenance": "interpretation",
            "source": null,
            "text": "Shows a <BINARY> header rather than writing the raw bytes, as the integration test expects."
          },
          "title": "Printer / Terminal Output"
        }
      ],
      "edges": [
        {
          "change": "new",
          "decisionIds": [],
          "flow": "sync",
          "fromId": "input-reader",
          "id": "peek-buffer",
          "isTrustBoundary": false,
          "label": "peeks buffered prefix (fill_buf)",
          "note": "NEW: non-consuming snapshot of up to 1024 bytes",
          "onCriticalPath": true,
          "toId": "input-source"
        },
        {
          "change": "changed",
          "decisionIds": [],
          "flow": "sync",
          "fromId": "input-source",
          "id": "read-first-line",
          "isTrustBoundary": false,
          "label": "supplies first line (read_until)",
          "note": "Skipped on empty input",
          "onCriticalPath": true,
          "toId": "input-reader"
        },
        {
          "change": "changed",
          "decisionIds": [],
          "flow": "sync",
          "fromId": "input-reader",
          "id": "classify",
          "isTrustBoundary": false,
          "label": "classifies prefix",
          "note": "Input is now up to 1024 bytes instead of only the first line",
          "onCriticalPath": true,
          "toId": "content-classifier"
        },
        {
          "change": "existing",
          "decisionIds": [],
          "flow": "sync",
          "fromId": "input-reader",
          "id": "stream-lines",
          "isTrustBoundary": false,
          "label": "streams lines",
          "note": null,
          "onCriticalPath": true,
          "toId": "line-reader"
        },
        {
          "change": "existing",
          "decisionIds": [],
          "flow": "sync",
          "fromId": "line-reader",
          "id": "render",
          "isTrustBoundary": false,
          "label": "feeds content + type",
          "note": null,
          "onCriticalPath": true,
          "toId": "printer"
        }
      ]
    }
    """#

    private static let intentJSON = #"""
    {
      "intent": {
        "confidence": null,
        "provenance": "claim",
        "source": "Title: \"Detect binary content beyond the first line\"; Description: \"inspect up to the first 1024 already-buffered bytes before splitting out the first line\", \"preserve the reader's bytes, line boundaries, UTF-16 handling, and streaming behavior\", Root cause: \"content_inspector checks up to 1024 bytes for a NUL byte, but bat passed only the first line. Random or encrypted data can contain a newline before its first NUL byte, so the shortened sample was classified as UTF-8 and binary bytes were sent to the terminal.\" \"Fixes #3554.\"",
        "text": "The PR makes bat detect binary content beyond the first line. Before splitting out the first line, it inspects up to the first 1024 bytes that are already buffered. The goal is that files such as encrypted or random data, which may have a newline before their first NUL byte, are classified as binary rather than UTF-8 text. It aims to keep the reader's bytes, line boundaries, UTF-16/BOM handling and streaming behavior unchanged, without adding an extra blocking read. It fixes #3554."
      }
    }
    """#

    private static let eli5JSON = #"""
    {
      "howItWasSolved": {
        "confidence": "high",
        "provenance": "interpretation",
        "source": "src/input.rs:12-290",
        "text": "Before, bat decided whether a file was text by looking only at its first line. Now it looks at up to the first 1,024 bytes the file has already supplied, so a line break early in an encrypted file no longer hides the signs that the file is binary. The file's content is still shown unchanged when it really is text."
      },
      "problemToBeSolved": {
        "confidence": null,
        "provenance": "claim",
        "source": "#3554",
        "text": "When users opened some encrypted files in bat, it didn't recognize them as binary (non-text) files. Instead it printed garbled symbols to the terminal, and this happened with most of the encrypted files the reporter tried."
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
              "text": "Scan further than 1 KB, or call content_inspector repeatedly as lines stream in. That would catch NULs that appear later, but it would mean buffering or reclassifying mid-stream after the header has already been printed."
            },
            {
              "confidence": "low",
              "provenance": "interpretation",
              "source": null,
              "text": "Keep the first-line sample and add a separate heuristic such as file extension or a GPG/PGP magic check. That would be narrower and would not change the result for text files with stray NULs."
            }
          ],
          "componentIds": [
            "input-reader",
            "content-classifier"
          ],
          "confidence": "high",
          "consequences": [
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "The classification (and so whether bytes are printed to the terminal) now depends on bytes beyond the first newline. The integration test header_binary_with_null_after_first_line checks that a file with 'packet-header\\n' followed by a NUL renders as <BINARY>."
            },
            {
              "confidence": "high",
              "provenance": "interpretation",
              "source": null,
              "text": "The first_line buffer and the inspection sample are now separate. Line-splitting and replay behavior appear unaffected, as the replay assertion in binary_detection_scans_beyond_first_line_and_preserves_input suggests."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "A new constant CONTENT_INSPECTION_LIMIT = 1024 is added. try_new now passes an inspection_prefix of up to 1024 bytes to inspect_content_type instead of passing first_line. The first_line buffer is still split at the first newline and replayed unchanged by read_line."
          },
          "id": "inspect-first-kb-not-first-line",
          "level": "system",
          "options": [
            {
              "chosen": false,
              "detail": "previous behavior",
              "label": "First line only"
            },
            {
              "chosen": true,
              "detail": "matches inspector's window",
              "label": "Up to first 1 KB"
            }
          ],
          "question": "How much data should binary detection inspect?",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description",
              "text": "Author: 'content_inspector checks up to 1024 bytes for a NUL byte, but bat passed only the first line. Random or encrypted data can contain a newline before its first NUL byte, so the shortened sample was classified as UTF-8 and binary bytes were sent to the terminal.'"
            },
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description, 'Compatibility' section",
              "text": "Author states that BOM detection still takes precedence, so UTF-16 handling is unchanged, and that ZIP signature detection is unchanged. In the code, has_zip_signature still uses starts_with on the sample, and UTF-16 line reading still runs only when the inspector reports UTF_16LE/BE."
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
              "endLine": 304,
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
          "title": "Classify content from up to the first 1024 bytes instead of only the first line",
          "tradeoffs": [
            {
              "chosenPosition": 0.2,
              "dimensionA": "binary detection sensitivity",
              "dimensionB": "text-with-stray-NUL tolerance",
              "explanation": {
                "confidence": "medium",
                "provenance": "interpretation",
                "source": null,
                "text": "Mostly-text inputs that have a NUL byte on line 2 or later, within the first 1 KB, now appear to be classified as BINARY. With the header style they show a <BINARY> marker, and without it the printer shows a 'will not be printed to the terminal' warning instead of the content. Such files were previously shown as text."
              },
              "prominence": "primary",
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 516,
                  "path": "src/printer.rs",
                  "side": "head",
                  "startLine": 496
                },
                {
                  "blobSha": null,
                  "endLine": 290,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 290
                }
              ]
            }
          ],
          "why": {
            "confidence": null,
            "provenance": "claim",
            "source": "PR description, 'Root cause' section",
            "text": "content_inspector scans up to 1024 bytes, so a newline early in random or encrypted data made bat mislabel it as UTF-8."
          }
        },
        {
          "alternatives": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Loop on read() until 1024 bytes or EOF, e.g. with Read::take plus a peek buffer. Classification would then be deterministic regardless of chunking, but first output could be delayed on slow pipes."
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
              "text": "For files opened with the default BufReader, the first fill usually exposes well over 1 KB, so the full window is likely available. For pipes and custom readers, the result appears to depend on how much the first read() delivers."
            },
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description, 'Compatibility' section",
              "text": "The author notes that open PR #3763 changes the same initialization path, to bound reads for newline-free binary files, and that this PR may need a rebase if #3763 merges first."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "try_new calls reader.fill_buf() once and copies up to 1024 of the exposed bytes into inspection_prefix without consuming them. It then runs read_until to split out the first line as before."
          },
          "id": "non-blocking-buffered-snapshot",
          "level": "system",
          "options": [
            {
              "chosen": false,
              "detail": "deterministic classification",
              "label": "Read until 1 KB or EOF"
            },
            {
              "chosen": true,
              "detail": "no extra blocking read",
              "label": "Use what's buffered"
            }
          ],
          "question": "Should detection wait for more stream data before classifying?",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description; src/input.rs:268-271",
              "text": "Author: 'The snapshot is non-consuming, so no bytes are lost or reordered, and it does not add a post-line blocking read.' The code comment says the same: 'does not consume input or perform an additional read beyond the one read_until needs anyway.'"
            },
            {
              "confidence": "high",
              "provenance": "interpretation",
              "source": null,
              "text": "The input_detection_does_not_read_twice test uses a reader that returns WouldBlock on its second read(). This suggests the author wanted a guarantee that initialization never issues a second read, keeping streaming/stdin behavior unchanged."
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
              "endLine": 479,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 456
            },
            {
              "blobSha": null,
              "endLine": 249,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 236
            }
          ],
          "shape": "binary",
          "title": "Sample only the already-buffered prefix via fill_buf rather than reading until 1 KB",
          "tradeoffs": [
            {
              "chosenPosition": 0.75,
              "dimensionA": "detection completeness",
              "dimensionB": "streaming latency",
              "explanation": {
                "confidence": "medium",
                "provenance": "interpretation",
                "source": null,
                "text": "If the first read() returns fewer than 1024 bytes, detection only sees that chunk. This can happen with stdin pipes, slow producers, or custom readers. A NUL that arrives in a later chunk would go unnoticed and the input would still be treated as text. In return, interactive or streaming input (e.g. tail -f | bat) is not held up waiting for more data."
              },
              "prominence": "primary",
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
              ]
            }
          ],
          "why": {
            "confidence": null,
            "provenance": "claim",
            "source": "PR description, 'Root cause' section",
            "text": "The author says the non-consuming snapshot loses no bytes and adds no blocking read after the first line."
          }
        },
        {
          "alternatives": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Concatenate the snapshot and the first line. That is not correct in general, because the two overlap: first_line begins with the same bytes as the snapshot."
            }
          ],
          "componentIds": [
            "input-reader",
            "content-classifier"
          ],
          "confidence": "high",
          "consequences": [
            {
              "confidence": "high",
              "provenance": "interpretation",
              "source": null,
              "text": "The sample now appears to be at least as large as the old first-line sample (capped at 1 KB), so classification should not regress for small-buffer readers."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "After read_until, if min(first_line.len(), 1024) is greater than inspection_prefix.len(), the prefix is replaced with the first 1024 bytes of first_line."
          },
          "id": "fallback-to-first-line-when-longer",
          "level": "implementation",
          "options": [
            {
              "chosen": false,
              "detail": "simpler",
              "label": "Buffered snapshot only"
            },
            {
              "chosen": true,
              "detail": "never worse than before",
              "label": "Longer of snapshot or line"
            }
          ],
          "question": "What if the buffer exposes less than the first line?",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "src/input.rs:282-283",
              "text": "Code comment: 'A custom BufRead implementation may expose less than 1024 bytes at a time. Keep the old behavior for long first lines in that case.'"
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
          "title": "Use the first line as the sample when it is longer than the buffered snapshot",
          "tradeoffs": [],
          "why": {
            "confidence": null,
            "provenance": "claim",
            "source": "src/input.rs:282-283 code comment",
            "text": "A custom BufRead may expose under 1024 bytes at a time, so long first lines keep the old sample."
          }
        },
        {
          "alternatives": [],
          "componentIds": [
            "input-reader",
            "printer"
          ],
          "confidence": "high",
          "consequences": [
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Empty input still yields content_type None, so the printer's quiet_empty handling (content_type.is_none()) is preserved. The empty case in input_detection_does_not_read_twice covers this."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "read_until is only called if inspection_prefix is non-empty. An empty fill_buf leaves first_line empty and content_type None."
          },
          "id": "skip-read-on-empty-input",
          "level": "implementation",
          "options": [
            {
              "chosen": false,
              "detail": "simpler",
              "label": "Always read first line"
            },
            {
              "chosen": true,
              "detail": "single read on EOF",
              "label": "Skip when buffer empty"
            }
          ],
          "question": "Should empty input trigger a second EOF read?",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description",
              "text": "Author: 'Empty input is handled without requesting a second EOF event.' Once fill_buf has returned empty, BufReader's buffer is exhausted, so a following read_until would call read() on the inner source again. For a TTY or pipe, a second read after EOF could block or return data that arrives later."
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
              "endLine": 478,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 475
            },
            {
              "blobSha": null,
              "endLine": 490,
              "path": "src/printer.rs",
              "side": "head",
              "startLine": 487
            }
          ],
          "shape": "binary",
          "title": "Skip read_until when the initial fill_buf reports EOF",
          "tradeoffs": [],
          "why": {
            "confidence": null,
            "provenance": "claim",
            "source": "PR description",
            "text": "Author says empty input is handled without requesting a second EOF event."
          }
        }
      ]
    }
    """#

    private static let flowsJSON = #"""
    {
      "entryPoints": [
        {
          "changeKind": "touched",
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
          "flowId": "flow-stdin-custom-reader-detection",
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
          "title": "<producer> | bat (CLI, stdin input)"
        },
        {
          "changeKind": "touched",
          "flowId": "flow-stdin-custom-reader-detection",
          "id": "lib-pretty-printer-print",
          "kind": "public API",
          "refs": [
            {
              "blobSha": null,
              "endLine": 343,
              "path": "src/pretty_printer.rs",
              "side": "head",
              "startLine": 293
            },
            {
              "blobSha": null,
              "endLine": 165,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 158
            },
            {
              "blobSha": null,
              "endLine": 249,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 244
            }
          ],
          "title": "PrettyPrinter::print / print_with_writer (library API, incl. Input::from_reader custom readers)"
        },
        {
          "changeKind": "touched",
          "flowId": null,
          "id": "lessopen-preprocessor-open",
          "kind": "plugin point",
          "refs": [
            {
              "blobSha": null,
              "endLine": 160,
              "path": "src/controller.rs",
              "side": "head",
              "startLine": 149
            },
            {
              "blobSha": null,
              "endLine": 205,
              "path": "src/lessopen.rs",
              "side": "head",
              "startLine": 203
            }
          ],
          "title": "LESSOPEN preprocessor output opened as input (feature \"lessopen\")"
        },
        {
          "changeKind": "changed",
          "flowId": "flow-cli-file-binary-detection",
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
          "id": "flow-cli-file-binary-detection",
          "steps": [
            {
              "branches": [
                "input.is_stdin() -> pass io::stdin().lock() as the reader",
                "otherwise -> pass io::empty() as dummy stdin"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "input-source",
              "errorPaths": [
                "print_input error -> handle_error writes to stderr/pager and no_errors=false"
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
              "title": "CLI hands inputs to Controller::run, which calls print_input per input"
            },
            {
              "branches": [
                "lessopen feature + use_lessopen -> preprocessor.open (may build an InputReader over preprocessed output at lessopen.rs:205)",
                "path is a directory -> Err",
                "stdout surely conflicts with the input -> Err(\"IO circle detected\")"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "input-source",
              "errorPaths": [
                "File::open failure -> \"'<path>': <io error>\"",
                "try_new io::Error propagated via ?"
              ],
              "externalCalls": [
                "File::open",
                "file.metadata()"
              ],
              "id": "open-input",
              "index": 1,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 161,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 149
                },
                {
                  "blobSha": null,
                  "endLine": 243,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 216
                }
              ],
              "stateDelta": "File handle -> BufReader<File> passed to InputReader::try_new",
              "title": "Input::open opens the file, rejects directories and IO cycles, wraps it in a BufReader"
            },
            {
              "branches": [
                "fill_buf returns empty (EOF) -> inspection_prefix empty"
              ],
              "caution": "The prefix only covers what a single fill_buf exposes. If the first underlying read returns fewer bytes than 1024 (short read), bytes past that point are not inspected. The code comment at lines 282-283 covers the custom-BufRead case.",
              "changeKind": "new",
              "componentId": "input-reader",
              "errorPaths": [
                "fill_buf io::Error -> returned from try_new"
              ],
              "externalCalls": [
                "BufRead::fill_buf (triggers the first underlying read)"
              ],
              "id": "snapshot-prefix",
              "index": 2,
              "isAsyncBoundaryAfter": false,
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
                  "endLine": 275,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 267
                }
              ],
              "stateDelta": "inspection_prefix = copy of buffered[..min(len, 1024)]; the reader position does not change",
              "title": "fill_buf() snapshot of up to CONTENT_INSPECTION_LIMIT (1024) buffered bytes"
            },
            {
              "branches": [
                "inspection_prefix empty -> skip read_until, first_line stays empty (avoids a second EOF read)"
              ],
              "caution": null,
              "changeKind": "changed",
              "componentId": "input-reader",
              "errorPaths": [
                "read_until io::Error -> returned from try_new"
              ],
              "externalCalls": [
                "BufRead::read_until"
              ],
              "id": "read-first-line",
              "index": 3,
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
              "stateDelta": "first_line = bytes up to and including the first '\\n', consumed from the reader",
              "title": "read_until('\\n') splits out first_line, skipped when the prefix is empty"
            },
            {
              "branches": [
                "first_line_prefix_len > inspection_prefix.len() -> replace the prefix",
                "otherwise -> keep the buffered snapshot"
              ],
              "caution": null,
              "changeKind": "new",
              "componentId": "input-reader",
              "errorPaths": [],
              "externalCalls": [],
              "id": "fallback-first-line-prefix",
              "index": 4,
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
              "stateDelta": "inspection_prefix may be replaced by first_line[..min(len,1024)]",
              "title": "If first_line is longer than the snapshot, use the first line's first 1024 bytes instead"
            },
            {
              "branches": [
                "empty prefix -> None",
                "UTF_8 and starts with PK\\x03\\x04 / PK\\x05\\x06 / PK\\x07\\x08 -> BINARY",
                "otherwise -> content_inspector result"
              ],
              "caution": null,
              "changeKind": "changed",
              "componentId": "content-classifier",
              "errorPaths": [],
              "externalCalls": [
                "content_inspector::inspect"
              ],
              "id": "classify-content",
              "index": 5,
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
              "stateDelta": "content_type: None (empty) | BINARY | UTF_8 | UTF_16LE | UTF_16BE ...",
              "title": "inspect_content_type runs content_inspector on the prefix and applies the ZIP signature override"
            },
            {
              "branches": [
                "UTF_16LE -> read_utf16_line(0x00, 0x0A)",
                "UTF_16BE -> read_utf16_line(0x0A, 0x00)"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "line-reader",
              "errorPaths": [
                "read_utf16_line io::Error -> returned from try_new"
              ],
              "externalCalls": [
                "BufRead::read_until"
              ],
              "id": "utf16-first-line",
              "index": 6,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 304,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 292
                },
                {
                  "blobSha": null,
                  "endLine": 387,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 363
                }
              ],
              "stateDelta": "InputReader{first_line, content_type, unbuffered:false}",
              "title": "For UTF-16, extend first_line up to the UTF-16 newline and build the InputReader"
            },
            {
              "branches": [
                "loop_through -> SimplePrinter (ignores content_type in the header)",
                "header style off + BINARY -> \"[bat warning]: Binary content ... will not be printed\"",
                "BINARY/None and not AsText -> print_line returns early"
              ],
              "caution": null,
              "changeKind": "touched",
              "componentId": "printer",
              "errorPaths": [
                "write errors propagate as Result"
              ],
              "externalCalls": [],
              "id": "printer-uses-content-type",
              "index": 7,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 280,
                  "path": "src/printer.rs",
                  "side": "head",
                  "startLine": 271
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
                  "endLine": 671,
                  "path": "src/printer.rs",
                  "side": "head",
                  "startLine": 664
                },
                {
                  "blobSha": null,
                  "endLine": 247,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 222
                }
              ],
              "stateDelta": "Header gets \"   <BINARY>\" and binary lines are not written unless --binary=as-text or -A",
              "title": "InteractivePrinter uses content_type to skip syntax matching, pick the header mode or warning, and drop binary lines"
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
              "text": "Take a snapshot of up to 1024 buffered bytes without consuming them"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Split out the first line as before"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Classify content as binary, UTF-8 or UTF-16 from the larger sample"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Print the header with a <BINARY> marker, or a warning, and skip binary lines"
            }
          ],
          "title": "bat <file> -> content type chosen from a 1024-byte prefix -> header/lines printed or suppressed"
        },
        {
          "entryPointId": "cli-bat-stdin",
          "id": "flow-stdin-custom-reader-detection",
          "steps": [
            {
              "branches": [
                "stdin conflicts with stdout -> Err(\"IO circle detected\")"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "input-source",
              "errorPaths": [
                "identification failure -> \"Stdin: Error identifying file\""
              ],
              "externalCalls": [
                "clircle::Identifier::try_from(Stdin)"
              ],
              "id": "open-stdin-or-custom",
              "index": 0,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 213,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 199
                },
                {
                  "blobSha": null,
                  "endLine": 249,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 244
                },
                {
                  "blobSha": null,
                  "endLine": 343,
                  "path": "src/pretty_printer.rs",
                  "side": "head",
                  "startLine": 330
                }
              ],
              "stateDelta": null,
              "title": "Input::open passes the stdin lock, or a BufReader around the custom reader, to try_new"
            },
            {
              "branches": [
                "empty stdin -> no read_until call, content_type None (the test at src/input.rs input_detection_does_not_read_twice covers this with a WouldBlock-on-second-read reader)"
              ],
              "caution": "On pipes, the first fill_buf returns only what one read() delivered. Binary bytes arriving in a later chunk, past the first line, would still not be inspected. This appears to be an accepted limitation.",
              "changeKind": "changed",
              "componentId": "input-reader",
              "errorPaths": [
                "io::Error from fill_buf/read_until propagated"
              ],
              "externalCalls": [
                "BufRead::fill_buf",
                "BufRead::read_until"
              ],
              "id": "stdin-snapshot-and-classify",
              "index": 1,
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
              "stateDelta": "content_type comes from the first fill_buf chunk (up to 1024 bytes) or from the first line's prefix, whichever is longer",
              "title": "fill_buf snapshot, then read_until, then classify (same logic as the file flow)"
            },
            {
              "branches": [
                "UTF-16 -> read_utf16_line",
                "unbuffered -> read_line_unbuffered",
                "otherwise -> read_until('\\n')"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "line-reader",
              "errorPaths": [
                "io::Error propagates to print_file_ranges"
              ],
              "externalCalls": [],
              "id": "replay-lines",
              "index": 2,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 341,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 306
                },
                {
                  "blobSha": null,
                  "endLine": 298,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 272
                }
              ],
              "stateDelta": "No bytes are lost or reordered because the snapshot was not consumed",
              "title": "read_line returns the cached first_line, then continues reading from the untouched reader"
            }
          ],
          "storySteps": [
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Take input from stdin or a library-supplied reader"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Look at whatever the first buffered read returned, up to 1024 bytes"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Classify the content and replay lines unchanged"
            }
          ],
          "title": "stdin / custom reader -> InputReader::try_new -> content type"
        }
      ]
    }
    """#

    private static let judgmentJSON = #"""
    {
      "architectureImpact": {
        "confidence": "high",
        "provenance": "interpretation",
        "text": "The content-type check now looks at up to 1024 bytes that are already buffered, taken without consuming them before the first line is split out. Before, it only looked at the first line. So binary data with an early newline, such as encrypted files, appears to be caught before it reaches the terminal. The stream, line boundaries and UTF-16 handling are unchanged."
      },
      "changeMap": [
        {
          "filesChanged": 1,
          "name": "Input Reader initialization"
        },
        {
          "filesChanged": 0,
          "name": "Content Type Classifier"
        },
        {
          "filesChanged": 0,
          "name": "Line Reader / UTF-16 decoding"
        },
        {
          "filesChanged": 0,
          "name": "Input Source (file / stdin)"
        },
        {
          "filesChanged": 0,
          "name": "Printer / Terminal Output"
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
          "detail": "Pipes and custom readers can deliver small first chunks, so a NUL byte in a later chunk still goes unseen.",
          "explanation": "try_new calls fill_buf() once (src/input.rs:272-275) and inspects only what that one call exposes, capped at 1024 bytes. Files are wrapped in BufReader::new (src/input.rs:241), which has an 8 KiB buffer, so for ordinary files the first fill very likely covers the full 1 KB window. The stdin lock (src/input.rs:212) and custom readers wrapped in BufReader (src/input.rs:248) only return what the first underlying read() delivers. For example, `gpg -d ... | bat` or a slow producer may deliver a short first chunk. Any NUL byte past that chunk and past the first line is still missed, so the input is treated as UTF-8 and its bytes reach the terminal, just as before the fix. The author's code comment (lines 282-283) only covers custom BufReads that expose less than a long first line. This appears to be a deliberate trade for streaming latency, since input_detection_does_not_read_twice enforces a single read. The reviewer should decide whether the #3554 fix is meant to cover piped input. If it is, one option is to keep reading until 1024 bytes or EOF, but only when first_line is already complete and the buffer is short. That would cost the no-second-read guarantee, which the test relies on.",
          "id": "short-first-read-misses-binary",
          "kind": "concern",
          "provenance": "interpretation",
          "question": "Is detection reliable when the first read returns under 1 KB?",
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
            }
          ],
          "relatedIds": [
            "non-blocking-buffered-snapshot",
            "input-reader",
            "flow-stdin-custom-reader-detection"
          ]
        },
        {
          "confidence": "medium",
          "detail": "Files that used to display as text may now show only a binary warning or header in interactive mode.",
          "explanation": "The sample passed to inspect_content_type now covers up to 1024 bytes across lines (src/input.rs:290), not just the first line. If content_inspector returns BINARY, the interactive printer does one of two things. Without a header, it prints '[bat warning]: Binary content ... will not be printed to the terminal' (src/printer.rs:496-512). With a header, it shows '<BINARY>' (src/printer.rs:515-516). Either way the content is dropped unless the user passes -A or --binary=as-text. So a log or config file with a stray NUL byte on line 2-N, within its first KB, would stop rendering, where before it rendered as text. That matches what content_inspector is designed to do on 1 KB samples, and matches other tools that sniff the first KB. Still, it is a user-visible behavior change beyond encrypted files, and the CHANGELOG entry only mentions encrypted files. Piped output is described as unaffected by the warning text itself ('will be present if the output of bat is piped').",
          "id": "text-with-stray-nul-now-suppressed",
          "kind": "concern",
          "provenance": "interpretation",
          "question": "Is hiding mostly-text files with a later NUL byte acceptable?",
          "refs": [
            {
              "endLine": 290,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 290
            },
            {
              "endLine": 521,
              "path": "src/printer.rs",
              "side": "head",
              "startLine": 496
            }
          ],
          "relatedIds": [
            "inspect-first-kb-not-first-line",
            "printer",
            "binary-detection-beyond-first-line"
          ]
        },
        {
          "confidence": "high",
          "detail": "The branch that protects small-buffer readers from regressions has no test using a short-buffer reader.",
          "explanation": "Lines 284-288 replace inspection_prefix with the first 1024 bytes of first_line when the line is longer than the buffered snapshot. This is what keeps classification from regressing for BufRead implementations whose buffer is smaller than the first line. The new unit tests don't reach this branch. binary_detection_scans_beyond_first_line_and_preserves_input reads from &[u8], which exposes the whole slice through fill_buf. input_detection_does_not_read_twice returns the whole content in one read. A grep for with_capacity/chain in src/input.rs finds nothing. A test built on BufReader::with_capacity(16, ...), with a long first line that has a NUL after byte 16, would pin this down. So would a matching test for a short chunk followed by a NUL on line 2, documenting the accepted limitation.",
          "id": "fallback-branch-untested",
          "kind": "concern",
          "provenance": "interpretation",
          "question": "Is the long-first-line fallback path covered by any test?",
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
            "fallback-to-first-line-when-longer",
            "input-reader"
          ]
        },
        {
          "confidence": "low",
          "detail": "If it also checks prefixes or validates UTF-8, a 1 KB sample cut mid-character could change results.",
          "explanation": "content_inspector 0.2.4 (Cargo.toml:52) comes from an external crate, and its source is outside this checkout, so I couldn't read it. The PR description says it 'checks up to 1024 bytes for a NUL byte', and says BOM detection still takes precedence. If the crate only checks for BOMs, magic prefixes and NUL bytes, then cutting at 1024 bytes (possibly in the middle of a UTF-8 multibyte sequence) is harmless. If it does any UTF-8 validity or ratio checks, the cut point could matter. The reviewer may want to confirm the crate's inspect() behavior.",
          "id": "inspector-sample-semantics",
          "kind": "question",
          "provenance": "interpretation",
          "question": "Does the inspector judge anything beyond NUL bytes and BOMs?",
          "refs": [
            {
              "endLine": 355,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 344
            }
          ],
          "relatedIds": [
            "inspect-first-kb-not-first-line",
            "content-classifier"
          ]
        }
      ],
      "intent": {
        "provenance": "claim",
        "source": "Title: \"Detect binary content beyond the first line\"; Description: \"inspect up to the first 1024 already-buffered bytes before splitting out the first line\", \"preserve the reader's bytes, line boundaries, UTF-16 handling, and streaming behavior\", Root cause: \"content_inspector checks up to 1024 bytes for a NUL byte, but bat passed only the first line. Random or encrypted data can contain a newline before its first NUL byte, so the shortened sample was classified as UTF-8 and binary bytes were sent to the terminal.\" \"Fixes #3554.\"",
        "text": "The PR makes bat detect binary content beyond the first line. Before splitting out the first line, it inspects up to the first 1024 bytes that are already buffered. The goal is that files such as encrypted or random data, which may have a newline before their first NUL byte, are classified as binary rather than UTF-8 text. It aims to keep the reader's bytes, line boundaries, UTF-16/BOM handling and streaming behavior unchanged, without adding an extra blocking read. It fixes #3554."
      },
      "needsJudgment": [
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": null,
          "text": "Binary detection for stdin and custom readers still depends on how much the first read() returns. A reviewer needs to decide whether that partial fix for piped input is enough to close #3554, or only covers the file case."
        },
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": null,
          "text": "Text files with a NUL byte after line 1, within the first KB, are now suppressed in interactive output. The CHANGELOG only mentions encrypted files, so this broader user-visible change may deserve its own mention."
        },
        {
          "confidence": "high",
          "provenance": "interpretation",
          "source": null,
          "text": "The code comment says 'does not ... perform an additional read beyond the one read_until needs anyway.' That holds because fill_buf only triggers the read that read_until would have done first, and the empty-input case skips read_until (src/input.rs:278-280). The single-read test fixes this as an invariant, which blocks any future change toward reading until 1 KB or EOF."
        }
      ],
      "questions": [
        {
          "id": "piped-input-in-scope",
          "refs": [
            {
              "endLine": 213,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 199
            },
            {
              "endLine": 275,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 272
            }
          ],
          "relatedIds": [
            "non-blocking-buffered-snapshot",
            "flow-stdin-custom-reader-detection"
          ],
          "text": "Was #3554's fix meant to cover `gpg -d | bat` or other piped input, where the first chunk may be under 1 KB? Or only files opened directly?"
        },
        {
          "id": "content-inspector-behavior",
          "refs": [
            {
              "endLine": 355,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 344
            }
          ],
          "relatedIds": [
            "inspect-first-kb-not-first-line",
            "content-classifier"
          ],
          "text": "Does content_inspector::inspect (v0.2.4) do anything other than check BOMs, magic prefixes and NUL bytes? For example, does it validate UTF-8, which a 1024-byte cut could affect?"
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
            "input-reader"
          ],
          "text": "Has PR #3763 (bounded reads for newline-free binary files) merged, and was this change rebased onto it? I couldn't determine this from the checkout."
        }
      ],
      "uncertainties": [
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": null,
          "text": "I couldn't read the content_inspector 0.2.4 source (it's outside the checkout). So it's unverified whether inspect() looks only at BOMs, magic prefixes and NUL bytes, or also validates UTF-8."
        },
        {
          "confidence": "low",
          "provenance": "interpretation",
          "source": null,
          "text": "The PR description says PR #3763 touches the same initialization path. This checkout already has an `unbuffered` field and read_line_unbuffered (src/input.rs:258, 319-341), set after try_new at src/controller.rs:161. It is unclear whether those came from #3763 or from other work, and whether the rebase the author expected has already happened."
        },
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": null,
          "text": "In unbuffered mode (--unbuffered), try_new still blocks in read_until for a full first line before the unbuffered flag is applied (controller.rs:161). This behavior predates the PR and is unchanged by it, but it limits how much the 'no extra blocking read' guarantee actually helps streaming."
        }
      ]
    }
    """#
}
