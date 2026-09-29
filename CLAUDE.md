# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Contour is a native macOS app (pure SwiftUI, Swift 6.4, macOS 15+) that turns a GitHub pull
request into a review briefing: what changed, the decisions it made, the architecture and
runtime flows it touches, with every claim cited back to `path:line` in a real checkout.
It drives an AI CLI the user already has (`pi` or `claude`), holds no credentials, and
reads GitHub through `gh` or the anonymous REST API.

`README.md` is the user-facing tour and configuration reference. `DESIGN.md` is the full
product and technical design; §10 (pipeline), §11 (data model), §12 (app layering), §13
(caching) and §16 (security) are the sections worth reading before touching those areas.
`docs/superpowers/specs/2026-09-25-contour-design.md` is the approved spec that introduced
the harness / tracker / GitHub-access seams.

## Commands

The package only builds on macOS with the Swift 6.4 toolchain (Xcode 27). CI runs on
GitHub's `xcode-27` runner (`.github/workflows/build.yml`); there is no Linux build.

```sh
swift build                                   # debug build
swift run Contour                             # run the app
CONTOUR_MOCK_ANALYSIS=1 swift run Contour     # real fetch + checkout, canned analysis (seconds, no model)
swift build -c release                        # what the Homebrew formula and CI release step do

swift test                                    # unit tests only: no network, no model
swift test --filter UnifiedDiffTests          # one suite
swift test --filter UnifiedDiffTests/newAndDeletedFilesHaveOnlyOneSide   # one Swift Testing test
swift test --filter PRLinkTests/testExtractsABareURL                     # one XCTest
RUN_CONTOUR_INTEGRATION=1 swift test --filter IntegrationSmoke      # real pipeline against a public PR
```

Integration tests need a working harness and network; `CONTOUR_HARNESS` and
`CONTOUR_GITHUB_ACCESS` parameterize them. Regenerating the mock fixtures after a prompt
or schema change is a two-step process documented at the top of
`scripts/regenerate-fixtures.py`.

### Measuring coverage locally

CI measures line coverage over `Sources/` (only `.build` and `Tests/` are excluded, so
`Views/` and `Pipeline/MockAnalysisFixtures.swift` count) and posts the report to the job
summary. Reproduce it with:

```sh
swift test --enable-code-coverage
TEST_BINARY="$(find .build -type f -path '*.xctest/Contents/MacOS/*' -print -quit)"
PROFDATA="$(find .build -type f -name 'default.profdata' -print -quit)"
xcrun llvm-cov report "$TEST_BINARY" -instr-profile "$PROFDATA" -ignore-filename-regex='\.build|Tests/'
```

Add `-show-line-counts-with-regions <file>` (or `llvm-cov show`) to see which lines of a
specific file are unexercised.

## Test coverage policy

The target is **90%+ line coverage**. The repository currently sits around **33%**, so
the gap is closed incrementally: every change must leave the code it adds or modifies at
90%+ coverage, and must never lower the overall number. Concretely, for any PR:

- Run the coverage report above before pushing and check the files you touched. A new or
  changed file below 90% is not done.
- Put logic where it can be tested. Parsing, decoding, layout math, state transitions,
  cache keys and link resolution belong in `Models/`, `Pipeline/`, `Services/` or a
  plain struct beside the view, not inside a SwiftUI `body`. Views should be thin; the
  existing `GraphLayout`, `BehaviorDiagramLayout`, `DiagramMode` and `ReviewSubject`
  types are the pattern: pure types next to the view, tested directly.
- Every member of a `View` is implicitly `@MainActor`. A pure `static func` helper left on
  a view type must be declared `nonisolated` so a (nonisolated) `@Test` can call it; if it
  genuinely needs the main actor (it takes a `GraphStore`, a `Binding`, an `NSItemProvider`),
  mark the test `@MainActor` instead. CI fails on "main actor-isolated … in a synchronous
  nonisolated context" warnings, since those become errors under Swift 6 mode (#185, #72).
- Use the seams instead of the network: `Harness` (replay a captured stream through
  `interpret`), `PRSource` (a struct returning a canned `RawPRContext`),
  `AnalysisCache(directory:)` with a temp directory, `GraphStore()` on `@MainActor`, and
  `ContourSampleData` / `MockAnalysisFixtures` for a populated `PRGraph`.
- Fixtures under `Tests/ContourTests/Fixtures/` are captured real CLI output, never
  hand-written; `Fixtures/README.md` records provenance and must be updated when a fixture
  is added or re-captured.
- Name tests so they say what invariant they pin. Both Swift Testing (`@Test`, `#expect`)
  and XCTest exist; prefer Swift Testing for new suites.
- When you touch a file that is under 90%, bring it up, or at minimum cover the paths your
  change adds. Do not exclude files from the coverage regex to make the number move.

## Architecture

### Layering

```
GitHubService (PRSource: GHCLISource | AnonymousAPISource), RepoContextService,
AnalysisService(Harness: PiHarness | ClaudeHarness), IssueTracker (GitHub | Jira)
        │   external-process wrappers; all shelling out goes through Support/ShellProcess
Pipeline: PromptBuilder → AnalysisService.runStage → StageDecoding → CodeRefVerifier
          → GraphLinker → GraphAssembly, orchestrated by the AnalysisPipeline actor
        │   emits PipelineEvent on an AsyncStream
GraphStore  (@Observable, @MainActor mutations) single source of truth: PRGraph, phase,
            per-stage AnalysisState, navigation stack, review submission, metrics
        │
Views/*     one lens per folder (Summary, Decisions, Architecture, Flows, Diff, Evidence,
            Chat); all read GraphStore, mutate only via its methods
```

`ContentView` is the `NavigationSplitView` shell; `PRSessionCommands` holds the menu
commands; `Preferences` is the settings store with the precedence
**environment variable > stored setting > detected on machine** (`CONTOUR_HARNESS`,
`CONTOUR_TRACKER`, `CONTOUR_GITHUB_ACCESS`, `CONTOUR_MOCK_*`, see README).

### The pipeline is a DAG, not a sequence

Six stages (`PipelineStage`) run as soon as their inputs exist: fetch opens the review
with title, metadata and raw diff; after checkout, Understanding (with issue lookup),
Behavior change, Decisions and Architecture run in parallel; Flows waits on Architecture;
Judgment waits on everything. Decisions and Flows stream: `StreamingArrayExtractor`
yields array elements as the model writes them, and the final parsed response stays
authoritative. Every stage fails and retries independently; only fetch and checkout are
fatal. Cross-links between decisions, parts and flow stages are derived locally in
`GraphLinker` from overlapping `CodeRef`s so stages don't wait on each other for ids.

`AnalysisCache` stores each stage as it lands, keyed by (repo, PR, headSha, baseSha,
pipeline version), so interrupted runs resume and a moved head shows the previous
revision's analysis marked stale while the new one runs. Bump the pipeline version when a
prompt or schema change makes old cache entries wrong.

### Decoding is deliberately lenient

Stage responses are `[String: Any]` decoded through `StageDecoding` into
`GraphModels.swift` types whose `init(from:)` tolerate missing fields, because real model
output omits optional keys (`blobSha`, `side`). Do not replace these with synthesized
`Decodable`. After decoding, `CodeRefVerifier` resolves every ref against the checkout
(`head` refs against the working tree, `base` refs via `git cat-file`), trims overlong
ranges, moves refs to deleted files to `base`, drops the rest, and demotes any statement
whose refs all failed. `MockAnalysisFixturesTests` pins that the canned fixtures still
decode and cross-link; a schema change that breaks them means regenerating fixtures.

### Provenance is a type, not a convention

Every `Statement` carries `Provenance` (fact / claim / interpretation) and interpretations
carry a `Confidence`. Rendering goes through `ProvenanceBadge` / `StatementView` in
`Views/Components/Badges.swift`. The app never presents an inference as a fact; keep new
model output flowing through `Statement` rather than bare strings.

### Security invariants (do not loosen)

- Every harness invocation is single-shot, session-less and read-only
  (`--allowedTools Read,Grep,Glob` for claude, `--tools read,grep,find,ls` for pi).
- Project-resident instruction files are disabled on every call: `--restricted --safe-mode`
  for claude, `--no-context-files --no-extensions --no-skills` for pi. The checkout is
  the PR under review, so any `CLAUDE.md`, skill or hook in it is attacker-controlled.
- PR-derived prose is wrapped in `<UNTRUSTED_PR_CONTENT>` and every system prompt tells
  the model to treat it as data.
- No model is pinned by default; `AnalysisTier.modelPattern` is nil unless Settings sets
  a per-tier override. Bare model names resolve ambiguously across multi-provider setups.
- `HarnessContractTests` replay captured `claude` and `pi` streams through `interpret`
  and check the exact argv. Changing a flag means updating those tests and the table in
  `DESIGN.md` §10.

### Harness quirks that are load-bearing

`Harness` abstracts only argv construction and stream interpretation; everything else
(system prompt, JSON extraction, retry-once on malformed JSON, mock short-circuit) is
shared in `AnalysisService`. `pi` needs the context file as its own `@file` argv token,
puts the final text in the last *text* block of `message_end` (a null `thinking` block
can follow it), and `claude` inlines the context file and reports the answer on a
`result` event. Unknown stream events are ignored, never errors.

## Conventions

- **No code comments.** Swift sources and tests carry no `//`, `///` or `/* */` comments
  (including `// MARK:`). Say it in names, types and structure instead, and put rationale in
  the commit message or `DESIGN.md`. The one exception is the mandatory
  `// swift-tools-version:` line in `Package.swift`.
- `Package.swift` pins `.swiftLanguageMode(.v6)` on the app target: full strict
  concurrency checking. A closure crossing into a `nonisolated`/`@concurrent` call (e.g.
  `AnalysisService.runStage`'s `onProgress`) needs `@Sendable` on its type, matching the
  existing `onElement` parameter; a class that must cross isolation needs a real
  `Sendable` conformance or the existing `NSLock`-boxed `@unchecked Sendable`/
  `nonisolated(unsafe)` pattern (`ShellProcess.swift`, `AnalysisService.swift`,
  `MainThreadWatchdog.swift`), not a new idiom.
- User-facing failure text is written in the reviewer's terms ("Couldn't map the
  architecture."); raw model output and CLI stderr go to the technical log only.
- The web site under `site/` is deployed as-is by `pages.yml`; the Homebrew formula in
  `Formula/contour.rb` builds `main` from source and has no release to pin yet.
