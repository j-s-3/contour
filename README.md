# Contour

A macOS-native PR review app built around the thesis that human review should validate
engineering decisions, not re-read every line an AI generated. See `DESIGN.md` for the
full product and technical design.

## What's implemented (MVP slice)

- Paste a GitHub PR URL → `gh` fetches metadata/diff/commits/comments → local checkout at
  the PR's head SHA → a staged pipeline of `pi` calls builds a knowledge graph (components,
  decisions, tradeoffs, flows, entry points, questions) → native SwiftUI views render it.
- Every AI-produced statement is tagged fact / author-claim / AI-interpretation, with
  confidence on interpretations, visible everywhere via `ProvenanceBadge`.
- Native architecture diagram (SwiftUI `Canvas`, layered layout, no web view).
- Full decision records (Decision / Rationale / Alternatives / Consequences / Confidence /
  Evidence) with accept / question / discuss reviewer state.
- Tradeoffs made visible without a verdict; interactive flow step lists; entry points
  linking into their flows.
- Focused code viewer reading the real local checkout, with expand-context / whole-file /
  a guaranteed path back to wherever the reviewer was in the conceptual review.
- Command palette (⌘K) jumping to any lens or any named node in the graph.
- Read-only, `--no-session` `pi` invocations with prompt-injection mitigations (PR text is
  wrapped in `<UNTRUSTED_PR_CONTENT>` and the system prompt tells `pi` to treat it as data).

Deferred past MVP (see `DESIGN.md` §17/§18): posting reviews back to GitHub, LSP-grade
jump-to-definition, sequence-diagram rendering, sharded analysis for very large PRs.

## Requirements

- macOS with Xcode 16+ / Swift 6 toolchain.
- `gh` installed and authenticated (`gh auth status`).
- `pi` installed and configured with at least one working model
  (`pi --list-models`, `pi auth check --provider <name>`).

## Build & run

```sh
swift build
swift run Contour
```

## Tests

```sh
swift test                                   # unit tests only, no network, fast
RUN_CONTOUR_INTEGRATION=1 swift test        # + full pipeline run against a real tiny PR
```

The integration test hits `gh` and `pi` for real (network + model cost) and is gated
behind an env var for that reason. `Tests/ContourTests/Fixtures/architecture_response.json`
is a captured real `pi` response used as a decoding regression fixture, so the schema
contract in `PromptBuilder`/`StageDecoding` stays honest without needing the network.

## Manual testing without waiting on `pi`

```sh
CONTOUR_MOCK_ANALYSIS=1 swift run Contour
```

With this set, `gh` fetch and the local checkout still run for real (so the code
viewer/Evidence lens has real files), but all six analysis stages return canned JSON
from `Sources/Contour/Pipeline/MockAnalysisFixtures.swift` instead of shelling out to
`pi` — a PR opens in a second or two instead of minutes. The fixture data is modeled on
a realistic PR so the UI exercises realistic components, decisions,
tradeoffs, and flows rather than a placeholder graph. `MockAnalysisFixturesTests`
checks the fixtures decode cleanly and their cross-links (`decisionIds`, `tradeoffIds`,
`dependsOnIds`, `flowId`, ...) all resolve, so drift from a `StageDecoding` schema change
fails the test suite instead of only surfacing when someone flips the env var on.

This mocks the AI results only — it's unrelated to `AnalysisCache` (§13), which
instead caches a real completed run keyed by (repo, PR number, headSha, baseSha,
pipeline version) so re-opening the *same* PR is instant on a later run.

## Project layout

```
Sources/Contour/
  Models/GraphModels.swift        PR knowledge graph data model (§11)
  Support/ShellProcess.swift      Process wrapper for gh/git/pi
  Services/GitHubService.swift    gh CLI wrapper
  Services/RepoContextService.swift  local checkout + code reads
  Services/AnalysisService.swift  pi CLI wrapper, JSONL event parsing
  Services/GraphStore.swift       @Observable session state + semantic nav stack
  Pipeline/PromptBuilder.swift    per-stage prompts + JSON schema contracts
  Pipeline/AnalysisPipeline.swift orchestrates the staged pi calls
  Pipeline/StageDecoding.swift    lenient decoding of AI JSON into graph nodes
  Views/                          SwiftUI lenses (Summary, Architecture, Decisions, …)
```
