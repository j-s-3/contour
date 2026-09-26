<p align="center"><img src="Assets/Logo/contour-logo.svg" alt="Contour" width="360"></p>

# Contour

A macOS-native PR review app built around the thesis that human review should validate
engineering decisions, not re-read every line an AI generated. See `DESIGN.md` for the
full product and technical design.

The AI harness (`pi` or Claude Code), the issue tracker (GitHub issues or Jira), and the
way it reaches GitHub (`gh` or the anonymous API) are all pluggable. The only hard
requirements are `git` and one AI CLI you're already signed in to.

> **Status:** early and experimental. Expect rough edges and breaking changes.

## What's implemented

- Paste a GitHub PR URL → PR metadata/diff/commits/comments are fetched → the repo is
  checked out locally at the PR's head SHA → a staged pipeline of AI calls builds a
  knowledge graph (components, decisions, tradeoffs, flows, questions) →
  native SwiftUI views render it.
- An Overview that reads as a briefing: the before/after behavior change, why it was
  made, and a short list of "things to think about".
- Every AI-produced statement is tagged fact / author-claim / AI-interpretation, with
  confidence on interpretations, visible everywhere via `ProvenanceBadge`.
- Native architecture diagram (SwiftUI `Canvas`, layered layout, no web view).
- Full decision records (Decision / Rationale / Alternatives / Consequences / Confidence /
  Evidence) with accept / question / discuss reviewer state.
- Tradeoffs made visible without a verdict; interactive flow step lists.
- Contextual chat: right-click any element and choose "Ask about this…" (⌘⇧A). The model
  gets that element plus its lineage and neighbors, and cites code and review objects as
  clickable links.
- Focused code viewer reading the real local checkout, with expand-context / whole-file /
  a guaranteed path back to wherever the reviewer was in the conceptual review.
- Command palette (⌘K) jumping to any lens or any named node in the graph.

Deferred (see `DESIGN.md` §17/§18): posting reviews back to GitHub, LSP-grade
jump-to-definition, sequence-diagram rendering, sharded analysis for very large PRs.

## Requirements

- macOS 15+ with a Swift 6.4 toolchain (the package declares `swift-tools-version: 6.4`).
- `git`.
- **One AI harness**, either:
  - `pi`, configured with at least one working model (`pi --list-models`), or
  - `claude` (Claude Code) 2.1.24+ — earlier builds lack the `--restricted` and
    `--safe-mode` flags Contour uses to harden each run.

That's the whole list. Everything below is optional:

- `gh` — **only needed for private pull requests.** Public PRs are read through GitHub's
  anonymous REST API, so Contour works on a machine with nothing but `git` and a harness.
- `acli` — only needed if you want Jira instead of GitHub issues for issue lookup.

On first launch a setup wizard probes for all of these and tells you what it found, what
each one buys you, and what (if anything) is actually missing.

## Build & run

```sh
swift build
swift run Contour
```

## Configuration

Everything is in Settings (⌘,): which harness to drive, how to reach GitHub, which issue
tracker to use, and optional per-tier model overrides.

Environment variables override the stored settings, which is how tests and scripts pin
behavior. Precedence is **environment > stored setting > what's detected on the machine**.

| Variable | Values | Effect |
| --- | --- | --- |
| `CONTOUR_HARNESS` | `pi`, `claude` | Which AI CLI to drive |
| `CONTOUR_TRACKER` | `github`, `jira`, `none` | Where to look for the originating issue |
| `CONTOUR_GITHUB_ACCESS` | `auto`, `gh`, `anonymous` | How to reach GitHub |
| `CONTOUR_MOCK_ANALYSIS` | `1` | Use canned analysis (and canned chat answers) instead of calling a model |
| `CONTOUR_OPEN_PR_URL` | a PR URL | Open straight into that PR on launch |
| `CONTOUR_DUMP_STAGES` | a directory | Write each stage's raw JSON there |

### Harness

Contour holds no provider credentials. It shells out to a CLI you have already installed
and signed in to, and inherits whatever model and provider that CLI is configured with.
By default it passes no model flag at all, so each CLI's own default applies; a bare
pattern like `sonnet` can match an unauthenticated provider when several are configured,
so set the per-tier overrides only if you know which model you want.

Every invocation is single-shot, ephemeral, and restricted to read-only tools. It also
refuses to load any `CLAUDE.md`, `AGENTS.md`, skill, hook, or plugin **from the checkout** —
the checkout is the pull request under review, so for any PR off the internet those files
are attacker-controlled content that would otherwise arrive as instructions.

### GitHub access

`auto` (the default) uses `gh` when it's installed and authenticated — private repos, and
a 5000 requests/hour limit — and otherwise falls back to the anonymous API, which reads
public PRs with no setup at all at 60 requests/hour.

Because `gh` is preferred whenever it's present, the anonymous path is the one that gets
exercised least while being the one a new user hits first. `anonymous` forces it, so you
can check that path deliberately rather than hoping.

### Issue tracker

The linked issue grounds the plain-language "problem to be solved" summary in what was
actually asked for, rather than in what the diff appears to do. GitHub issues are the
default and need nothing installed: Contour reads closing keywords (`Fixes #123`),
cross-repo references (`owner/repo#123`), bare `#123` mentions, and issue numbers embedded
in branch names.

Jira is offered only when `acli` is on your PATH, and stays off until you turn it on —
detecting `acli` never changes where Contour looks on its own.

A missing, unreachable, or unparseable issue never fails a review.

## Tests

```sh
swift test                                   # unit tests only, no network, fast
RUN_CONTOUR_INTEGRATION=1 swift test         # + real pipeline runs against a public PR
```

The integration tests hit the network and a real model, so they're gated behind an env
var. They target a public PR, so they need no private-repo access, and both the harness
and the GitHub path are parameterized:

```sh
RUN_CONTOUR_INTEGRATION=1 CONTOUR_HARNESS=claude swift test --filter IntegrationSmoke
RUN_CONTOUR_INTEGRATION=1 CONTOUR_GITHUB_ACCESS=anonymous swift test --filter IntegrationSmoke
```

`Tests/ContourTests/Fixtures/` holds captured real output used as regression fixtures —
see its `README.md` for what came from where, including one fixture that is partly
synthesized and why.

## Manual testing without waiting on a model

```sh
CONTOUR_MOCK_ANALYSIS=1 swift run Contour
```

The GitHub fetch and local checkout still run for real (so the code viewer and Evidence
lens have real files), but every analysis stage returns canned JSON from
`Sources/Contour/Pipeline/MockAnalysisFixtures.swift` instead of calling a model — a PR
opens in a second or two instead of minutes.

Those fixtures were captured from a genuine pipeline run against
[sharkdp/bat#3877](https://github.com/sharkdp/bat/pull/3877), a small public PR that
closes a GitHub issue, so the UI exercises a realistic graph and the issue-tracker path at
once. `MockAnalysisFixturesTests` checks that they still decode against the current
`StageDecoding` schema and that their cross-links all resolve, so drift fails the suite
rather than surfacing the next time someone flips the env var on.

To regenerate them after a prompt or schema change:

```sh
RUN_CONTOUR_INTEGRATION=1 CONTOUR_HARNESS=claude \
CONTOUR_DUMP_STAGES=/tmp/stages \
CONTOUR_PR_URL=https://github.com/sharkdp/bat/pull/3877 \
  swift test --filter IntegrationSmokeTests/testFullPipelineAgainstRealTinyPR
```

This is unrelated to `AnalysisCache` (§13), which instead caches a real completed run
keyed by (repo, PR number, headSha, baseSha, pipeline version) so re-opening the *same* PR
is instant on a later run.

## Project layout

```
Sources/Contour/
  Models/GraphModels.swift           PR knowledge graph data model (§11)
  Models/PRContext.swift             raw PR material, before analysis
  Support/ShellProcess.swift         Process wrapper + executable resolution
  Harness/Harness.swift              the AI-CLI seam: argv in, events out
  Harness/PiHarness.swift            pi conformer
  Harness/ClaudeHarness.swift        claude conformer
  Services/PRSource.swift            the GitHub seam + access-mode selection
  Services/GHCLISource.swift         gh-backed source (public and private)
  Services/AnonymousAPISource.swift  anonymous REST source (public only)
  Services/RepoContextService.swift  local checkout + code reads
  Services/AnalysisService.swift     harness-independent stage execution
  Services/EnvironmentProbe.swift    what's installed and usable
  Services/Preferences.swift         settings + resolution precedence
  Services/GraphStore.swift          @Observable session state + semantic nav stack
  Chat/                              contextual chat: subject resolution, context, links
  Tracker/IssueTracker.swift         the issue-tracker seam
  Tracker/GitHubIssueTracker.swift   default tracker, needs nothing installed
  Tracker/JiraTracker.swift          opt-in tracker via acli
  Pipeline/PromptBuilder.swift       per-stage prompts + JSON schema contracts
  Pipeline/AnalysisPipeline.swift    orchestrates the staged harness calls
  Pipeline/StageDecoding.swift       lenient decoding of AI JSON into graph nodes
  Views/                             SwiftUI lenses (Summary, Architecture, Decisions, …)
  Views/Settings/                    Settings scene + first-run wizard
Assets/Logo/                         app icon and logo (from scripts/generate-logo.py)
```

## License

Apache License 2.0; see [`LICENSE`](LICENSE).
