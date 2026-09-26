#!/usr/bin/env python3
"""Rebuild MockAnalysisFixtures.swift from a CONTOUR_DUMP_STAGES directory.

Hand-written fixtures drift from what the models actually emit, which is the exact
failure the fixtures exist to catch. So they are generated from a real pipeline run:

    RUN_CONTOUR_INTEGRATION=1 CONTOUR_HARNESS=claude \\
    CONTOUR_DUMP_STAGES=/tmp/stages \\
    CONTOUR_PR_URL=https://github.com/sharkdp/bat/pull/3877 \\
      swift test --filter IntegrationSmokeTests/testFullPipelineAgainstRealTinyPR

    python3 scripts/regenerate-fixtures.py /tmp/stages

Then run `swift test` — MockAnalysisFixturesTests checks the new fixtures decode against
the current StageDecoding schema and that every cross-link resolves.
"""

import json
import pathlib
import sys

STAGES = [
    ("behaviorChange", "behaviorChangeJSON"),
    ("architecture", "architectureJSON"),
    ("intent", "intentJSON"),
    ("eli5", "eli5JSON"),
    ("decisions", "decisionsJSON"),
    ("flows", "flowsJSON"),
    ("judgment", "judgmentJSON"),
]

HEADER = '''import Foundation

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
'''


def swift_literal(name: str, payload: dict) -> str:
    '''Render one stage as a Swift multi-line string literal.

    Uses Swift's raw (hash-delimited) multi-line form so backslashes and quotes inside the
    captured JSON -- regexes, Windows paths, escaped quotes in prose -- survive without
    any re-escaping.
    '''
    body = json.dumps(payload, indent=2, ensure_ascii=False)
    indented = "\n".join(("    " + line).rstrip() for line in body.splitlines())
    return f'\n    private static let {name} = #"""\n{indented}\n    """#\n'


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    dump = pathlib.Path(sys.argv[1])
    out = pathlib.Path(__file__).resolve().parent.parent / \
        "Sources/Contour/Pipeline/MockAnalysisFixtures.swift"

    missing = [s for s, _ in STAGES if not (dump / f"{s}.json").exists()]
    if missing:
        print(f"error: no dump for stage(s): {', '.join(missing)}", file=sys.stderr)
        print(f"       looked in {dump}", file=sys.stderr)
        return 1

    parts = [HEADER]
    for stage, prop in STAGES:
        payload = json.loads((dump / f"{stage}.json").read_text())
        parts.append(swift_literal(prop, payload))
    parts.append("}\n")

    out.write_text("".join(parts))
    print(f"wrote {out} from {len(STAGES)} captured stages")
    return 0


if __name__ == "__main__":
    sys.exit(main())
