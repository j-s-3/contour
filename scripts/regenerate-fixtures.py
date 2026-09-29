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

The generated Swift carries no comments (see CLAUDE.md), so its provenance lives here:
the fixtures are captured verbatim from a real run against sharkdp/bat#3877 ("Detect
binary content beyond the first line"), which closes issue #3554 so the issue-tracker
path is exercised too. Only the analysis stages are canned; fetch and checkout still run
for real under CONTOUR_MOCK_ANALYSIS=1.
"""

import json
import pathlib
import sys

STAGES = [
    ("behaviorChange", "behaviorChangeJSON"),
    ("architecture", "architectureJSON"),
    ("understanding", "understandingJSON"),
    ("decisions", "decisionsJSON"),
    ("flows", "flowsJSON"),
    ("judgment", "judgmentJSON"),
]

HEADER = '''import Foundation

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
