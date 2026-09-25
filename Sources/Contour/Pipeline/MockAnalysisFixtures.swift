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
              "label": "Snapshot buffered prefix",
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
              "componentIds": [],
              "flowId": null,
              "label": "Fall back if longer",
              "refs": [
                {
                  "endLine": 288,
                  "path": "src/input.rs",
                  "startLine": 282
                }
              ],
              "tag": "afterOnly"
            },
            {
              "componentIds": [
                "inspect_content_type"
              ],
              "flowId": null,
              "label": "Classify inspected prefix",
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
              "componentIds": [
                "read_utf16_line"
              ],
              "flowId": null,
              "label": "Handle UTF-16 lines",
              "refs": [
                {
                  "endLine": 295,
                  "path": "src/input.rs",
                  "startLine": 292
                }
              ],
              "tag": "both"
            },
            {
              "componentIds": [],
              "flowId": null,
              "label": "Print or mark binary",
              "refs": [],
              "tag": "both"
            }
          ],
          "before": [
            {
              "componentIds": [
                "InputReader::try_new"
              ],
              "flowId": null,
              "label": "Open input stream",
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
              "label": "Classify first line only",
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
              "componentIds": [
                "read_utf16_line"
              ],
              "flowId": null,
              "label": "Handle UTF-16 lines",
              "refs": [
                {
                  "endLine": 295,
                  "path": "src/input.rs",
                  "startLine": 292
                }
              ],
              "tag": "both"
            },
            {
              "componentIds": [],
              "flowId": null,
              "label": "Print or mark binary",
              "refs": [],
              "tag": "both"
            }
          ],
          "consequence": {
            "confidence": "high",
            "provenance": "interpretation",
            "source": null,
            "text": "Files with a NUL byte anywhere in the first 1024 buffered bytes, including after an early newline, now appear to be shown as <BINARY> instead of being dumped to the terminal as text."
          },
          "humanQuestion": {
            "confidence": "medium",
            "provenance": "interpretation",
            "source": null,
            "text": "Detection now depends on how many bytes the reader happens to have buffered (for example, a pipe or stdin that delivers a short first chunk). Is it acceptable that the same content could be classified differently depending on read timing, or should detection keep reading until it has 1024 bytes?"
          },
          "id": "binary-detection-buffered-prefix",
          "title": "Binary detection inspects up to 1024 buffered bytes instead of only the first line",
          "why": {
            "confidence": null,
            "provenance": "claim",
            "source": "PR description, Root cause section",
            "text": "The author says bat passed only the first line to content_inspector, so binary or encrypted data with a newline before its first NUL byte was classified as UTF-8 and its bytes were sent to the terminal (#3554)."
          }
        }
      ]
    }
    """#

    private static let architectureJSON = #"""
    {
      "architectureImpact": {
        "confidence": null,
        "provenance": "claim",
        "source": "PR description",
        "text": "Binary detection now looks at the reader's already-buffered prefix (up to 1024 bytes) instead of only the first line. So a NUL byte after an early newline still marks the input as binary. The streaming, BOM and ZIP detection paths are unchanged, and no extra reads are added."
      },
      "boundaries": [
        {
          "componentIds": [
            "input-reader",
            "content-inspection",
            "printer"
          ],
          "id": "bat-process",
          "kind": "process",
          "label": "bat process"
        },
        {
          "componentIds": [
            "input-source"
          ],
          "id": "external-input",
          "kind": "external",
          "label": "User file / stdin"
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
          "isTrustBoundaryEdge": true,
          "level": "system",
          "refs": [
            {
              "blobSha": null,
              "endLine": 267,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 263
            }
          ],
          "summary": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "The byte stream that bat reads from. InputReader::try_new takes it as a generic BufRead."
          },
          "title": "Input Source (file / stdin reader)"
        },
        {
          "changeKind": "changed",
          "dependsOnIds": [],
          "filesChanged": 1,
          "id": "input-reader",
          "implementedBy": [
            "InputReader",
            "src/input.rs"
          ],
          "isTrustBoundaryEdge": false,
          "level": "system",
          "refs": [
            {
              "blobSha": null,
              "endLine": 290,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 267
            }
          ],
          "summary": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "try_new now calls fill_buf() to copy up to 1024 bytes that are already buffered, without consuming them, before read_until splits off the first line. It uses whichever is longer, that snapshot or the first line, for content inspection."
          },
          "title": "Input Initialization & Line Reader"
        },
        {
          "changeKind": "touched",
          "dependsOnIds": [],
          "filesChanged": 0,
          "id": "content-inspection",
          "implementedBy": [
            "inspect_content_type",
            "content_inspector crate"
          ],
          "isTrustBoundaryEdge": false,
          "level": "system",
          "refs": [
            {
              "blobSha": null,
              "endLine": 344,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 344
            },
            {
              "blobSha": null,
              "endLine": 12,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 12
            }
          ],
          "summary": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "Sorts input into BINARY, UTF-8 or UTF-16 by checking for a BOM, a ZIP signature, or a NUL byte in the first 1024 bytes. It now receives the buffered prefix instead of only the first line."
          },
          "title": "Content Type Detection"
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
              "endLine": 2285,
              "path": "tests/integration_tests.rs",
              "side": "head",
              "startLine": 2267
            }
          ],
          "summary": {
            "confidence": "medium",
            "provenance": "interpretation",
            "source": null,
            "text": "Uses content_type to decide whether to print the text or show a <BINARY> header. This is inferred from the integration test."
          },
          "title": "Output / Printer (terminal)"
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
          "label": "peeks buffered prefix (fill_buf)",
          "note": "NEW: non-consuming snapshot of up to 1024 bytes, taken before read_until",
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
          "label": "classifies prefix",
          "note": "Input is now the buffered prefix instead of only the first line",
          "onCriticalPath": true,
          "toId": "content-inspection"
        },
        {
          "change": "existing",
          "decisionIds": [],
          "flow": "sync",
          "fromId": "input-reader",
          "id": "reader-to-printer",
          "isTrustBoundary": false,
          "label": "streams lines + content type",
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
        "source": "Title: \"Detect binary content beyond the first line\"; Description: \"inspect up to the first 1024 already-buffered bytes before splitting out the first line\", \"preserve the reader's bytes, line boundaries, UTF-16 handling, and streaming behavior\", \"content_inspector checks up to 1024 bytes for a NUL byte, but bat passed only the first line. Random or encrypted data can contain a newline before its first NUL byte, so the shortened sample was classified as UTF-8 and binary bytes were sent to the terminal.\" \"Fixes #3554.\"",
        "text": "Make bat's binary detection look at up to the first 1024 bytes that are already buffered, not just the first line. This stops binary data such as encrypted files, which can contain a newline before their first NUL byte, from being treated as UTF-8 text and printed to the terminal. The change is meant to keep the reader's bytes, line boundaries, UTF-16 handling and streaming behavior unchanged, and it fixes #3554."
      }
    }
    """#

    private static let eli5JSON = #"""
    {
      "howItWasSolved": {
        "confidence": "high",
        "provenance": "interpretation",
        "source": "src/input.rs:12, src/input.rs:268-290",
        "text": "Before, bat decided whether a file was text by looking only at its first line. Now it looks at up to the first 1,024 bytes of the file, even if that runs past the first line, and it does this without changing or losing any of the file's contents. Encrypted files that happen to have a line break early on are now correctly labeled as binary."
      },
      "problemToBeSolved": {
        "confidence": null,
        "provenance": "claim",
        "source": "#3554",
        "text": "When someone opened a GPG-encrypted file with bat, the tool didn't recognize it as binary (non-text) data. It printed the scrambled contents to the terminal, which showed up as broken symbols instead of a simple 'binary file' notice. The reporter said this happened with most of their encrypted files, not all."
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
              "text": "Keep reading lines until 1024 bytes have been collected, then inspect them. This gives a full sample even when the buffer is small, but it adds blocking reads and buffers more lines up front, which the author appears to have wanted to avoid."
            },
            {
              "confidence": "low",
              "provenance": "interpretation",
              "source": null,
              "text": "Use a different binary heuristic, such as a ratio of non-printable bytes or file-extension hints like .gpg. Plausible for encrypted data that has no NUL in its first 1KB, but it would change classification behavior much more widely."
            }
          ],
          "componentIds": [
            "input-reader",
            "content-inspection",
            "printer"
          ],
          "confidence": "high",
          "consequences": [
            {
              "confidence": "high",
              "provenance": "interpretation",
              "source": null,
              "text": "Files whose first 1024 bytes contain a NUL anywhere (not just in the first line) are now reported as <BINARY>, and the printer suppresses their content. This follows from printer.rs's is_printing_binary check on content_type. Some text files with a stray NUL after line 1 may now be treated as binary when they weren't before."
            },
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Detection now depends on how many bytes the first fill_buf returns. For pipes or stdin that deliver data in small chunks, the sample can be shorter than 1024 bytes, so detection may vary with read timing."
            },
            {
              "confidence": "high",
              "provenance": "interpretation",
              "source": null,
              "text": "The ZIP-signature check in inspect_content_type now runs on the prefix. Because it uses starts_with, the result is effectively the same as before."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "InputReader::try_new now snapshots up to CONTENT_INSPECTION_LIMIT (1024) bytes from reader.fill_buf() before calling read_until, and passes that prefix to inspect_content_type instead of just first_line. That means a NUL byte after the first newline can now mark the input as BINARY."
          },
          "id": "inspect-buffered-prefix-not-first-line",
          "level": "system",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description, 'Root cause'",
              "text": "The author says content_inspector checks up to 1024 bytes for a NUL byte, but bat only gave it the first line. Random or encrypted data can hit a newline before its first NUL, so the short sample was classified as UTF-8 and binary bytes were sent to the terminal (#3554)."
            },
            {
              "confidence": null,
              "provenance": "claim",
              "source": "src/input.rs:268-271",
              "text": "The code comment says the capture happens 'so an early newline in binary data does not shorten the inspected content.'"
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
              "endLine": 274,
              "path": "src/printer.rs",
              "side": "head",
              "startLine": 270
            },
            {
              "blobSha": null,
              "endLine": 2285,
              "path": "tests/integration_tests.rs",
              "side": "head",
              "startLine": 2267
            }
          ],
          "title": "Classify content from the buffered prefix (up to 1024 bytes) rather than only the first line"
        },
        {
          "alternatives": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Read ahead until 1024 bytes or EOF are buffered, for example by looping fill_buf/read. This gives a more consistent sample, but it can block on slow streams."
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
              "text": "The size of the sample depends on the underlying reader's buffer capacity and on how much the first read() returned. With the default 8 KiB BufReader around a file, the full 1024 bytes are usually available. With chunked streams it may be less."
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": "src/input.rs:456-479",
              "text": "The input_detection_does_not_read_twice test pins this down: a reader that returns WouldBlock on a second read() must still succeed for both a one-line input and an empty input."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "The prefix is copied from the BufRead's current internal buffer with fill_buf() and not consumed. read_until then splits out the first line from the same buffer. No read is added beyond the one read_until needed anyway, and the reader's bytes stay in their original order."
          },
          "id": "non-consuming-fill-buf-no-extra-read",
          "level": "system",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description, 'Root cause' and 'Summary'",
              "text": "The author says the snapshot is non-consuming, so no bytes are lost or reordered, and it adds no blocking read after the first line. They describe this as preserving streaming behavior."
            },
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "This appears to protect interactive or streaming stdin (for example `tail -f | bat`), where an extra blocking read before printing the first line would stall output."
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
              "endLine": 479,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 434
            }
          ],
          "title": "Peek with a non-consuming fill_buf instead of doing extra reads"
        },
        {
          "alternatives": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Always call read_until as before. For a reader that has already returned EOF once, this would call read() a second time, which may block or error on some sources (for example a TTY after Ctrl-D)."
            }
          ],
          "componentIds": [
            "input-reader",
            "content-inspection"
          ],
          "confidence": "high",
          "consequences": [
            {
              "confidence": "high",
              "provenance": "interpretation",
              "source": null,
              "text": "Empty input still gives content_type None, so the printer's quiet_empty handling keeps working (printer.rs checks content_type.is_none())."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "read_until is only called if inspection_prefix is non-empty. An empty first fill_buf is treated as EOF: first_line stays empty and inspect_content_type returns None."
          },
          "id": "skip-read-until-on-empty-buffer",
          "level": "implementation",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description, 'Root cause'",
              "text": "The author says 'Empty input is handled without requesting a second EOF event.'"
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
              "endLine": 488,
              "path": "src/printer.rs",
              "side": "head",
              "startLine": 488
            }
          ],
          "title": "Skip read_until when the first fill_buf returns nothing (treat as empty input)"
        },
        {
          "alternatives": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "Concatenate the snapshot with any extra bytes that read_until pulled in. When the buffer refills inside read_until, the first line is a superset of the snapshot anyway, so replacing the prefix appears to be the simpler and equivalent choice."
            }
          ],
          "componentIds": [
            "input-reader",
            "content-inspection"
          ],
          "confidence": "high",
          "consequences": [
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "This rules out a regression where a small-buffer reader would have inspected fewer bytes than before the PR. It only helps when the first line is long, though: for inputs with an early newline and a small buffer, bytes past the snapshot are still not inspected."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "After read_until, if first_line (capped at 1024 bytes) is longer than the fill_buf snapshot, the inspection prefix is replaced with the first line's prefix. The sample is therefore never shorter than what the old first-line-only behavior would have inspected."
          },
          "id": "fallback-to-first-line-when-longer",
          "level": "implementation",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "src/input.rs:282-283",
              "text": "The code comment says a custom BufRead implementation may expose fewer than 1024 bytes at a time, and the fallback keeps the old behavior for long first lines in that case."
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
          "title": "Fall back to the first line when it is longer than the buffered prefix"
        },
        {
          "alternatives": [],
          "componentIds": [
            "input-reader",
            "content-inspection"
          ],
          "confidence": "medium",
          "consequences": [
            {
              "confidence": "low",
              "provenance": "interpretation",
              "source": null,
              "text": "UTF-16 files without a BOM, which often have NULs in their first 1024 bytes, were probably already classified as binary when those NULs appeared in the first line. The wider window may reclassify some that previously slipped through as UTF-8."
            }
          ],
          "decision": {
            "confidence": null,
            "provenance": "fact",
            "source": null,
            "text": "The UTF-16LE/BE branch that extends first_line with read_utf16_line is unchanged. It now keys off the content_type computed from the wider prefix."
          },
          "id": "bom-precedence-utf16-unchanged",
          "level": "implementation",
          "rationale": [
            {
              "confidence": null,
              "provenance": "claim",
              "source": "PR description, 'Compatibility'",
              "text": "The author says BOM detection still takes precedence, so UTF-16 input handling is unchanged."
            },
            {
              "confidence": "medium",
              "provenance": "interpretation",
              "source": null,
              "text": "A UTF-16 BOM sits at byte 0, and content_inspector appears to check for a BOM before scanning for NUL. That suggests the wider prefix, which will contain NULs for UTF-16 ASCII text, still classifies as UTF-16 rather than BINARY."
            }
          ],
          "refs": [
            {
              "blobSha": null,
              "endLine": 296,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 290
            }
          ],
          "title": "Keep UTF-16 first-line handling tied to the prefix classification"
        }
      ]
    }
    """#

    private static let tradeoffsJSON = #"""
    {
      "tradeoffs": [
        {
          "chosen": "buffered prefix up to 1024",
          "decisionIds": [
            "inspect-buffered-prefix-not-first-line"
          ],
          "explanation": {
            "confidence": "high",
            "provenance": "interpretation",
            "source": null,
            "text": "Fact: try_new now builds `inspection_prefix` from `reader.fill_buf()`, capped at CONTENT_INSPECTION_LIMIT (1024), and passes that to inspect_content_type instead of `first_line` (src/input.rs:12, 272-275, 290). The test at src/input.rs:434-454 checks that a NUL at byte 1023 after an early newline is classified BINARY, while a NUL at byte 1024 is still UTF_8. Claim: the author says content_inspector 'checks up to 1024 bytes for a NUL byte, but bat passed only the first line'. Interpretation: this appears to trade the old sample's simple, predictable size (always exactly one line) for better detection accuracy. The sample now also depends on how much the reader happened to buffer, so it only reaches the full 1024-byte window when the buffer holds that much."
          },
          "id": "inspection-sample-scope",
          "poleA": "first-line sample",
          "poleAWeight": 0.75,
          "poleB": "full 1024-byte window",
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
              "startLine": 434
            }
          ],
          "title": "Inspection sample: first line vs buffered prefix"
        },
        {
          "chosen": "poleB",
          "decisionIds": [
            "non-consuming-fill-buf-no-extra-read"
          ],
          "explanation": {
            "confidence": "high",
            "provenance": "interpretation",
            "source": null,
            "text": "Fact: the prefix comes from a single `fill_buf()` call and is copied with `.to_vec()` without calling `consume`. No loop reads more data to fill the 1024 bytes (src/input.rs:272-275). The comment says this 'does not consume input or perform an additional read beyond the one read_until needs anyway' (src/input.rs:268-271). The test `input_detection_does_not_read_twice` uses a reader that returns WouldBlock after its first read (src/input.rs:456-479). Interpretation: this appears to put streaming and interactive latency (for example, a pipe that delivers a short first chunk) ahead of full detection coverage. A NUL past the first chunk from the OS may still go undetected."
          },
          "id": "peek-vs-extra-read",
          "poleA": "guaranteed 1024-byte sample",
          "poleAWeight": 0.9,
          "poleB": "no extra blocking read",
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
              "endLine": 479,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 456
            }
          ],
          "title": "Non-consuming peek vs guaranteed full sample"
        },
        {
          "chosen": "poleB",
          "decisionIds": [
            "skip-read-until-on-empty-buffer"
          ],
          "explanation": {
            "confidence": "medium",
            "provenance": "interpretation",
            "source": null,
            "text": "Fact: `read_until` runs only when `inspection_prefix` is non-empty (src/input.rs:277-280). For an empty prefix, inspect_content_type returns None (src/input.rs:344-347). The test sends `b\"\"` and expects None without a second read (src/input.rs:475-478). Claim: the author says 'Empty input is handled without requesting a second EOF event.' Interpretation: this appears to add a branch that ties 'empty first buffer' to 'empty input' so the reader is not polled again after EOF. That fits readers whose fill_buf returns empty only at EOF, at the cost of a less uniform control flow."
          },
          "id": "empty-buffer-short-circuit",
          "poleA": "uniform read path",
          "poleAWeight": 0.8,
          "poleB": "single EOF event",
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
          "title": "Empty first fill_buf treated as empty input"
        },
        {
          "chosen": "longer of prefix or first line",
          "decisionIds": [
            "fallback-to-first-line-when-longer"
          ],
          "explanation": {
            "confidence": "medium",
            "provenance": "interpretation",
            "source": null,
            "text": "Fact: after read_until, if the first line's 1024-capped length is greater than the buffered prefix length, the prefix is replaced with the first line's leading bytes (src/input.rs:282-288). The comment says this keeps 'the old behavior for long first lines' when a custom BufRead exposes fewer than 1024 bytes at a time. Interpretation: both samples start at the same offset, so this appears to pick whichever sample is longer. Classification should then never regress relative to the old first-line behavior, at the cost of a second sample source and a comparison step."
          },
          "id": "longest-sample-fallback",
          "poleA": "single sample source",
          "poleAWeight": 0.7,
          "poleB": "backward compatibility",
          "refs": [
            {
              "blobSha": null,
              "endLine": 290,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 282
            }
          ],
          "title": "Fallback to first line when it is longer"
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
          "id": "cli-file-arg",
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
            },
            {
              "blobSha": null,
              "endLine": 2285,
              "path": "tests/integration_tests.rs",
              "side": "head",
              "startLine": 2269
            }
          ],
          "title": "bat <file> (CLI, ordinary file input)"
        },
        {
          "changeKind": "touched",
          "flowId": "flow-stdin-custom-reader-detection",
          "id": "cli-stdin",
          "kind": "CLI command",
          "refs": [
            {
              "blobSha": null,
              "endLine": 119,
              "path": "src/controller.rs",
              "side": "head",
              "startLine": 112
            },
            {
              "blobSha": null,
              "endLine": 214,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 199
            }
          ],
          "title": "<cmd> | bat (CLI, stdin input)"
        },
        {
          "changeKind": "touched",
          "flowId": "flow-stdin-custom-reader-detection",
          "id": "lib-pretty-printer-reader",
          "kind": "public API",
          "refs": [
            {
              "blobSha": null,
              "endLine": 345,
              "path": "src/pretty_printer.rs",
              "side": "head",
              "startLine": 293
            },
            {
              "blobSha": null,
              "endLine": 378,
              "path": "src/pretty_printer.rs",
              "side": "head",
              "startLine": 359
            },
            {
              "blobSha": null,
              "endLine": 249,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 244
            }
          ],
          "title": "PrettyPrinter Input::from_reader / from_bytes / from_file (library API)"
        },
        {
          "changeKind": "touched",
          "flowId": null,
          "id": "lessopen-preprocessor",
          "kind": "plugin point",
          "refs": [
            {
              "blobSha": null,
              "endLine": 229,
              "path": "src/lessopen.rs",
              "side": "head",
              "startLine": 124
            },
            {
              "blobSha": null,
              "endLine": 160,
              "path": "src/controller.rs",
              "side": "head",
              "startLine": 149
            }
          ],
          "title": "LESSOPEN preprocessor output opened as input (lessopen feature)"
        }
      ],
      "flows": [
        {
          "entryPointId": "cli-file-arg",
          "id": "flow-cli-file-binary-detection",
          "steps": [
            {
              "branches": [
                "if input.is_stdin() -> print_input with io::stdin().lock()",
                "else -> print_input with io::empty() dummy stdin"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "input-source",
              "errorPaths": [
                "print_input error is routed to handle_error (pager or stderr), and no_errors becomes false (controller.rs:121-135)"
              ],
              "externalCalls": [],
              "id": "s0-run-controller",
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
                  "endLine": 119,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 112
                }
              ],
              "stateDelta": null,
              "title": "CLI builds controller and iterates inputs"
            },
            {
              "branches": [
                "path is a directory -> error",
                "stdout identifier conflicts with input -> IO circle error"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "input-source",
              "errorPaths": [
                "\"'<path>': <io error>\" on open failure",
                "\"'<path>' is a directory.\""
              ],
              "externalCalls": [
                "File::open",
                "file.metadata()"
              ],
              "id": "s1-open-file",
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
              "stateDelta": "File handle wrapped in BufReader (default std capacity) and passed to InputReader::try_new",
              "title": "Input::open opens the file and wraps it in a BufReader"
            },
            {
              "branches": [],
              "caution": "fill_buf returns only whatever the first underlying read produced, and nothing tops the sample up to 1024 bytes. A reader whose first read returns fewer than 1024 bytes therefore gets a shorter sample.",
              "changeKind": "new",
              "componentId": "input-reader",
              "errorPaths": [
                "fill_buf io::Error is propagated with ? (the previous code surfaced errors from read_until instead)"
              ],
              "externalCalls": [
                "BufRead::fill_buf (may issue the underlying read)"
              ],
              "id": "s2-snapshot-prefix",
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
              "stateDelta": "inspection_prefix = copy of buffered[..min(len,1024)]; reader position is not advanced",
              "title": "try_new snapshots up to CONTENT_INSPECTION_LIMIT (1024) buffered bytes via fill_buf"
            },
            {
              "branches": [
                "inspection_prefix empty (EOF) -> skip read_until, first_line stays empty"
              ],
              "caution": null,
              "changeKind": "changed",
              "componentId": "input-reader",
              "errorPaths": [
                "read_until io::Error propagated"
              ],
              "externalCalls": [
                "BufRead::read_until(b'\\n')"
              ],
              "id": "s3-read-first-line",
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
              "stateDelta": "first_line holds bytes up to and including the first '\\n' (or to EOF); the reader advances past it",
              "title": "Read the first line only if the prefix is non-empty"
            },
            {
              "branches": [
                "min(first_line.len(),1024) > inspection_prefix.len() -> use first-line prefix",
                "otherwise keep the fill_buf snapshot, which may extend past the first newline"
              ],
              "caution": null,
              "changeKind": "new",
              "componentId": "input-reader",
              "errorPaths": [],
              "externalCalls": [],
              "id": "s4-fallback-long-line",
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
              "stateDelta": "inspection_prefix may be replaced with first_line[..min(len,1024)]",
              "title": "Fall back to the first-line prefix when it is longer than the buffered snapshot"
            },
            {
              "branches": [
                "empty prefix -> None",
                "UTF_8 but starts with a PK\\x03\\x04 / PK\\x05\\x06 / PK\\x07\\x08 signature -> BINARY",
                "UTF_16LE/BE -> read_utf16_line extends first_line to a full UTF-16 line"
              ],
              "caution": null,
              "changeKind": "changed",
              "componentId": "content-inspection",
              "errorPaths": [
                "read_utf16_line io::Error propagated"
              ],
              "externalCalls": [
                "content_inspector::inspect"
              ],
              "id": "s5-inspect",
              "index": 5,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 296,
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
              "stateDelta": "content_type = None (empty) | Some(UTF_8/UTF_16LE/UTF_16BE/BINARY)",
              "title": "Classify the prefix with content_inspector plus the ZIP signature override"
            },
            {
              "branches": [
                "binary and not show_nonprintable and binary != AsText -> no syntax highlighter"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "printer",
              "errorPaths": [
                "get_syntax errors other than UndetectedSyntax are returned"
              ],
              "externalCalls": [],
              "id": "s6-printer-setup",
              "index": 6,
              "isAsyncBoundaryAfter": false,
              "refs": [
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
              "stateDelta": "printer.content_type copied from input.reader.content_type",
              "title": "InteractivePrinter uses content_type to skip syntax matching for binary input"
            },
            {
              "branches": [
                "no header style + BINARY -> '[bat warning]: Binary content ... will not be printed'",
                "header style + BINARY -> '   <BINARY>' suffix",
                "print_line: BINARY or None and not AsText -> return without writing"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "printer",
              "errorPaths": [
                "write errors propagated as Result"
              ],
              "externalCalls": [
                "writeln! to OutputHandle"
              ],
              "id": "s7-header-and-lines",
              "index": 7,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 250,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 214
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
                },
                {
                  "blobSha": null,
                  "endLine": 325,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 306
                }
              ],
              "stateDelta": "Lines are replayed from first_line and then the inner reader; binary lines produce no output",
              "title": "Print header (<BINARY> tag or warning) and suppress binary line output"
            }
          ],
          "storySteps": [
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Open the file for reading"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Take a sample of up to 1024 buffered bytes without consuming it"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Split off the first line"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Classify content as text, UTF-16, binary, or empty"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Choose the header tag and whether to print the body"
            }
          ],
          "title": "bat <file> -> content type detected -> <BINARY> header / suppressed body"
        },
        {
          "entryPointId": "cli-stdin",
          "id": "flow-stdin-custom-reader-detection",
          "steps": [
            {
              "branches": [
                "stdin conflicts with stdout -> IO circle error"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "input-source",
              "errorPaths": [
                "\"IO circle detected ...\" error"
              ],
              "externalCalls": [
                "clircle::Identifier::try_from(Stdin)"
              ],
              "id": "t0-open-stream",
              "index": 0,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 214,
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
                  "endLine": 373,
                  "path": "src/pretty_printer.rs",
                  "side": "head",
                  "startLine": 359
                }
              ],
              "stateDelta": "StdIn: the stdin BufRead is passed directly. CustomReader: the reader is wrapped in BufReader::new",
              "title": "Stdin lock or custom reader handed to InputReader::try_new"
            },
            {
              "branches": [
                "empty chunk -> no read_until call, content_type None",
                "non-empty chunk -> read_until to first newline"
              ],
              "caution": "For pipes, the first read may return a short chunk. If that chunk ends before any NUL byte that falls within the first 1024 bytes, the input can still be classified as UTF-8.",
              "changeKind": "new",
              "componentId": "input-reader",
              "errorPaths": [
                "io::Error from fill_buf/read_until propagated (e.g., WouldBlock from a non-blocking reader)"
              ],
              "externalCalls": [
                "BufRead::fill_buf",
                "BufRead::read_until"
              ],
              "id": "t1-fill-buf-once",
              "index": 1,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 280,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 272
                },
                {
                  "blobSha": null,
                  "endLine": 479,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 457
                }
              ],
              "stateDelta": "inspection_prefix = first buffered chunk (≤1024). first_line stays empty when the chunk is empty",
              "title": "Single fill_buf snapshot; empty input skips read_until"
            },
            {
              "branches": [
                "first-line prefix longer than the snapshot -> inspect the first-line prefix"
              ],
              "caution": null,
              "changeKind": "changed",
              "componentId": "content-inspection",
              "errorPaths": [],
              "externalCalls": [
                "content_inspector::inspect"
              ],
              "id": "t2-classify",
              "index": 2,
              "isAsyncBoundaryAfter": false,
              "refs": [
                {
                  "blobSha": null,
                  "endLine": 296,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 282
                },
                {
                  "blobSha": null,
                  "endLine": 355,
                  "path": "src/input.rs",
                  "side": "head",
                  "startLine": 344
                }
              ],
              "stateDelta": "content_type set on the InputReader",
              "title": "Choose between the buffered prefix and the first-line prefix, then inspect"
            },
            {
              "branches": [
                "first_line empty and no header style -> header skipped",
                "content_type None -> '<EMPTY>' header, or nothing if quiet_empty"
              ],
              "caution": null,
              "changeKind": "unchanged",
              "componentId": "printer",
              "errorPaths": [
                "write errors propagated"
              ],
              "externalCalls": [],
              "id": "t3-print",
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
                  "endLine": 250,
                  "path": "src/controller.rs",
                  "side": "head",
                  "startLine": 214
                },
                {
                  "blobSha": null,
                  "endLine": 521,
                  "path": "src/printer.rs",
                  "side": "head",
                  "startLine": 515
                }
              ],
              "stateDelta": "reader.unbuffered set from config before printing",
              "title": "Controller prints header and lines according to content_type"
            }
          ],
          "storySteps": [
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Receive a stream from stdin or a caller-supplied reader"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Sample whatever bytes are already buffered"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Skip the line read if the stream is empty"
            },
            {
              "confidence": null,
              "provenance": "fact",
              "source": null,
              "text": "Classify and hand off to the printer"
            }
          ],
          "title": "stdin / PrettyPrinter reader -> content type detection with reader-sized buffers"
        }
      ]
    }
    """#

    private static let judgmentJSON = #"""
    {
      "changeMap": [
        {
          "filesChanged": 1,
          "name": "Input Initialization & Line Reader"
        },
        {
          "filesChanged": 0,
          "name": "Input Source (file / stdin reader)"
        },
        {
          "filesChanged": 0,
          "name": "Content Type Detection"
        },
        {
          "filesChanged": 0,
          "name": "Output / Printer (terminal)"
        },
        {
          "filesChanged": 1,
          "name": "CLI integration tests"
        },
        {
          "filesChanged": 1,
          "name": "Changelog"
        }
      ],
      "needsJudgment": [
        {
          "confidence": "high",
          "provenance": "interpretation",
          "source": "src/input.rs:272-290; src/printer.rs:270-277; src/printer.rs:664-669",
          "text": "Text files that contain a NUL byte after line 1 (within the first 1024 bytes) now appear to be treated as fully binary in interactive mode. try_new classifies the whole 1024-byte buffered prefix (src/input.rs:272-290). InteractivePrinter::print_line then returns early for BINARY unless --binary=as-text or -A is set (src/printer.rs:664-669), and syntax matching is skipped (src/printer.rs:270-277). The whole body gets suppressed, not just the offending line. A reviewer should decide whether this wider window is the intended policy for mostly-text files with a stray NUL on line 2+, such as some logs or NUL-padded config files. It also affects the lessopen and PrettyPrinter paths, which share this constructor (src/lessopen.rs:205, src/input.rs:248). The only escape hatch for users is --binary=as-text / -A."
        },
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": "src/input.rs:268-280; src/controller.rs:116",
          "text": "The fix appears to be only partial for the stdin case in the original report (e.g. `gpg -d ... | bat` or `curl ... | bat`). The sample is whatever a single fill_buf returned (src/input.rs:273-274), and stdin is passed as io::stdin().lock() (src/controller.rs:116). If a pipe delivers a first chunk that ends before a NUL that is still inside the first 1024 bytes, and that chunk has an early newline, the input is still classified UTF-8. The same bytes read from a file would be BINARY. So the classification is timing-dependent. Someone needs to decide whether that is acceptable, or whether detection should top up to 1024 bytes when the first chunk has no newline issue. That would mean accepting an extra read that may block on slow or interactive streams."
        },
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": "src/input.rs:12; src/input.rs:435-455; Cargo.toml:52",
          "text": "The CONTENT_INSPECTION_LIMIT = 1024 constant (src/input.rs:12) hard-codes an internal detail of the external content_inspector crate (Cargo.toml:52, \"0.2.4\"). The unit test at src/input.rs:435-455 checks the boundary: a NUL at index 1023 gives BINARY and a NUL at 1024 gives UTF_8. That also implicitly checks the crate's scan window. If a future content_inspector version scans more or fewer bytes, bat's prefix would silently cap or waste detection, and this test would start failing for reasons outside bat. A reviewer may want to decide whether that coupling is acceptable or should be documented as tied to the crate version."
        },
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": "src/input.rs:282-288; src/input.rs:390-615",
          "text": "The long-first-line fallback branch (src/input.rs:282-288) has no direct test that I can see. The unit tests at src/input.rs:435-480 use either a &[u8] reader, which exposes the whole buffer, or a default BufReader. None of them build a small-capacity BufRead (no `with_capacity` appears in src/input.rs tests). The code comment says this branch exists for custom BufRead implementations that expose fewer than 1024 bytes. Whether it actually preserves the old behavior (classify from the first line) looks unverified by tests."
        },
        {
          "confidence": "low",
          "provenance": "interpretation",
          "source": "src/input.rs:273-280; src/input.rs:244-249",
          "text": "The error path has shifted slightly. A read error on the very first read now comes from fill_buf (src/input.rs:273) rather than read_until. And when the first fill_buf returns 0 bytes, read_until is skipped entirely (src/input.rs:278-280). A reader that returns Ok(0) spuriously on its first read but has data later would now be treated as empty input (content_type None, <EMPTY> header), with no second read attempt. Before this PR, read_until would have retried the read internally. This is probably fine for std readers, since Ok(0) means EOF. Still, it is a semantic change to the public CustomReader path (src/input.rs:244-249) that a reviewer may want to confirm on purpose."
        }
      ],
      "questions": [
        {
          "id": "stdin-short-chunk-policy",
          "refs": [
            {
              "endLine": 280,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 268
            },
            {
              "endLine": 116,
              "path": "src/controller.rs",
              "side": "head",
              "startLine": 115
            }
          ],
          "relatedIds": [
            "non-consuming-fill-buf-no-extra-read",
            "peek-vs-extra-read",
            "flow-stdin-custom-reader-detection"
          ],
          "text": "For stdin/pipe input, the sample is limited to the first chunk the OS returns. Is timing-dependent classification of the same bytes acceptable, or should try_new keep calling fill_buf until 1024 bytes or EOF when the first chunk is short, at the cost of possible blocking on interactive streams?"
        },
        {
          "id": "stray-nul-text-files",
          "refs": [
            {
              "endLine": 669,
              "path": "src/printer.rs",
              "side": "head",
              "startLine": 664
            },
            {
              "endLine": 290,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 290
            }
          ],
          "relatedIds": [
            "inspect-buffered-prefix-not-first-line",
            "printer"
          ],
          "text": "Is it intended that mostly-text files with a NUL on a later line within the first 1 KiB now have their entire body suppressed in terminal output (not only the header tag changing)?"
        },
        {
          "id": "fallback-branch-test",
          "refs": [
            {
              "endLine": 288,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 282
            }
          ],
          "relatedIds": [
            "fallback-to-first-line-when-longer"
          ],
          "text": "Should there be a unit test with a small-capacity BufReader (e.g. BufReader::with_capacity(16, ...)) that exercises the first-line fallback at src/input.rs:282-288?"
        },
        {
          "id": "inspector-limit-coupling",
          "refs": [
            {
              "endLine": 12,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 12
            },
            {
              "endLine": 455,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 435
            }
          ],
          "relatedIds": [
            "inspect-buffered-prefix-not-first-line",
            "content-inspection"
          ],
          "text": "Should CONTENT_INSPECTION_LIMIT be documented as mirroring content_inspector's internal scan window (and re-checked on crate upgrades), given that the boundary test depends on it?"
        },
        {
          "id": "pr-3763-interaction",
          "refs": [
            {
              "endLine": 288,
              "path": "src/input.rs",
              "side": "head",
              "startLine": 277
            }
          ],
          "relatedIds": [
            "input-reader",
            "fallback-to-first-line-when-longer"
          ],
          "text": "The author says PR #3763 (bounded reads for newline-free binary files) touches the same try_new path. Has the combined behavior been checked, especially the fallback branch, which copies from first_line and would interact with any cap on read_until?"
        }
      ],
      "uncertainties": [
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": "Cargo.toml:52",
          "text": "The content_inspector 0.2.4 source could not be inspected: the registry is outside the allowed working directory. So I could not confirm that inspect() scans exactly 1024 bytes, checks BOMs before NUL scanning, or uses other heuristics besides NUL detection. The author's 'BOM detection still takes precedence' claim for UTF-16 therefore rests on their statement and the existing utf16le tests, not on crate source."
        },
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": null,
          "text": "I could not determine how often a GPG or encrypted payload has no NUL byte in its first 1024 bytes. Probabilistically, random data has about a 1-(255/256)^1024 ≈ 98% chance of containing a NUL in 1024 bytes. The reporter said the problem affected 'most' files, so a small fraction of encrypted files may still be shown as text after this fix. Whether that residual rate is acceptable was not discussed in the PR."
        },
        {
          "confidence": "medium",
          "provenance": "interpretation",
          "source": "src/printer.rs:118-163; src/controller.rs:192-202",
          "text": "Piped (loop-through) output uses SimplePrinter, whose print_header is a no-op and whose print_line does not consult content_type (src/printer.rs:118-163). So this change appears to affect only interactive/terminal output. I did not trace every other consumer of content_type (e.g. the pager decision, or PrettyPrinter callers relying on output from binary-looking content), so I can't rule out other effects."
        }
      ]
    }
    """#
}
