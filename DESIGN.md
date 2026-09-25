# Contour — design doc

> Contour is a fork of Aperture. Aperture assumed exactly one of everything: `pi` as the
> AI backend, `gh` as the only route to GitHub, and Jira as the only issue tracker. This
> document has been updated so §8, §10, and §16 describe the pluggable design that
> replaced those assumptions; see
> `docs/superpowers/specs/2026-09-25-contour-design.md` for the change itself.

A macOS-native pull request review application for GitHub, built around how humans
should review software when most of the code is AI-generated.

## 1. Product philosophy

Traditional PR review tools are built around reading diffs line by line. That model
breaks down as more code is machine-written: syntax-level inspection is increasingly a
machine's job, and the scarce human contribution is judgment about whether a change is
the right change, not whether the syntax is correct.

Contour's answer is to make the diff supporting evidence rather than the primary
interface. The primary interface is a knowledge graph over the PR: what changed
architecturally, what decisions the implementation embodies, what tradeoffs it accepted,
how the important behavior actually flows through the system, and where a human should
spend judgment. The diff stays one click away from everything, but nothing forces a
reviewer to read it front to back before they understand what the PR does.

Three commitments follow from this:

1. **Provenance is sacred.** Every statement the app shows is tagged as an observed fact,
   an author claim, or an AI interpretation. These are visually distinct everywhere, with
   no exceptions. The app should be trustworthy enough to lean on precisely because it
   never launders inference into fact.
2. **Everything links back to code.** No floating prose. Every architecture node,
   decision, tradeoff, and flow step carries concrete `path:startLine-endLine` references
   that resolve to real lines in the real checkout.
3. **The AI is a briefer, not a judge.** It structures, synthesizes, and asks questions.
   It never renders a verdict on whether a tradeoff was the right call — that stays with
   the human.

## 2. Primary user journey

A reviewer pastes a GitHub PR URL. Within a couple of minutes they should be able to
answer: what is this PR trying to do, what parts of the system does it touch, how does
the new behavior actually work, what decisions did the implementation make, what
tradeoffs did it accept, what deserves human judgment, and where's the code behind each
of those claims.

```
Paste URL
   │
   ▼
Fetch (gh) + local checkout ────────► progress shows real substeps, not a spinner
   │
   ▼
Staged AI analysis (pi, streamed) ──► summary appears first, deeper lenses fill in
   │
   ▼
Summary ◄── home base, one keystroke away at all times
   │
   ├─► Architecture (diagram-first)
   ├─► Decisions (accept / question / discuss)
   ├─► Tradeoffs
   ├─► Flows (interactive step list)
   ├─► Entry points
   │        all cross-linked to each other, all drilling into Evidence
   ▼
Evidence / code viewer ◄──► Raw diff
   │
   ▼
Reviewer leaves knowing exactly what they validated, not just what they scrolled past
```

## 3. Information architecture

The whole app is one knowledge graph rendered through different lenses — not five
static tabs of generated prose. See `Sources/Contour/Models/GraphModels.swift` for the
concrete types.

Node types: `PRSummary` (root), `ComponentNode`, `DecisionNode`, `TradeoffNode`,
`FlowNode` / `FlowStep`, `EntryPointNode`, `QuestionNode`, and `CodeRef` as the terminal
leaf every other node points at. `Statement` is the atomic provenance-tagged claim
embedded throughout (`Provenance`: fact / claim / interpretation, plus an optional
`Confidence` for interpretations).

Edges are expressed as ID arrays rather than a separate edge table, since the graph is
small per PR and this keeps the JSON schema the AI has to fill in simple:
`decisionIds`, `tradeoffIds`, `componentIds`, `flowId`, `entryPointId`, `dependsOnIds`.
`PRGraph` provides the traversal helpers (`decisions(affecting:)`, `tradeoffs(for:)`,
`flows(traversing:)`) that every lens uses to find a node's neighbors, which is what
makes "a component links the decisions that changed it" a one-line query instead of a
separate document per lens.

## 4. Detailed screen designs

### 4.1 Window shell

Three-column `NavigationSplitView`: a sidebar of lenses (Summary, Architecture,
Decisions, Tradeoffs, Flows, Entry points, Raw diff) plus review progress, and a main
pane driven entirely by `GraphStore.current: NavigationTarget`. See
`Sources/Contour/Views/ContentView.swift`.

### 4.2 Summary (landing page)

Intent, a component change-map bar, architecture impact statement, numbered key
decisions with reviewer-state glyphs, tradeoffs/entry-points side by side, a "needs human
judgment" section, an uncertainties section, and a review-progress bar. Everything here
links into its full lens. See `Views/Summary/SummaryView.swift`.

### 4.3 Architecture

A native, non-web diagram built to explain the change, not to visualize a dependency
graph. The primary content is directional, labeled edges (`ArchitectureEdge`): every arrow
carries a relationship verb ("uploads", "triggers", "reads", "queues"), a synchronous
(solid) vs. asynchronous (dashed) treatment, and a change classification on the
*relationship* itself (new / changed / existing / removed) so the eye goes to the
architectural delta — usually a newly-introduced interaction — rather than to a box that
happened to change. `SystemBoundary`s draw as containers (application, external service,
datastore, trust boundary) behind their members. `GraphLayoutEngine` lays nodes out along
the direction of travel of those edges (sources left, sinks right), keeping boundary
members contiguous; `ArchitectureDiagramView` renders it with SwiftUI `Canvas` for
connectors/arrowheads/labels and real hit-tested views for boxes and edge labels.

`ArchitectureView` adds two pieces of chrome: a **Before / After / Delta** mode (Delta is
the default — it shows enough existing context but fades it so the change stands out) and
a **System / Implementation** zoom. Selecting a node or an edge fills an inspector; an
edge surfaces the decisions it embodies (explicit `edge.decisionIds`, or decisions whose
components span both endpoints) with a link straight into the Decisions lens, connecting
architecture to review judgment. When a graph has no rich edges (an old cached analysis),
`PRGraph.resolvedEdges` degrades gracefully by synthesizing labeled edges from
`dependsOnIds`. See `Views/Architecture/ArchitectureDiagramView.swift`,
`ArchitectureView.swift`, and `GraphLayout.swift`.

### 4.4 Decisions

One full structured record per decision — Decision, Rationale, Alternatives,
Consequences, Confidence, Evidence — each field independently provenance-tagged, plus an
accept / question / discuss control that rolls up into the review-progress bar. See
`Views/Decisions/DecisionsView.swift`.

### 4.5 Tradeoffs

Two named poles per tradeoff and which side the implementation actually landed on,
without a verdict on whether that was correct. See `Views/Tradeoffs/TradeoffsView.swift`.

### 4.6 Flows

A three-pane picker (flow → step list → step detail) rather than a wall of text. Each
step's detail shows its component, state delta, branches, external calls, error paths,
an async-boundary marker, and a caution flag for concrete, code-visible risk. See
`Views/Flows/FlowsView.swift`.

### 4.7 Entry points

Grouped by kind, each with a "follow flow" link into the flow it triggers. See
`Views/EntryPoints/EntryPointsView.swift`.

### 4.8 Evidence / code viewer

Exact lines highlighted, a little surrounding context, expand-context and open-whole-file
actions, and a guaranteed `esc` back to wherever the reviewer came from in the
conceptual review — the navigation stack (`GraphStore.path`/`forwardStack`) is what makes
"never lose your place" an actual guarantee rather than a hope. See
`Views/Evidence/CodeViewerView.swift`.

## 5. Interaction model

Keyboard-first: `⌘K` command palette (jump to any lens or any named node), `esc` to pop
one level of the navigation stack, back/forward toolbar buttons backed by the same stack.
The sidebar and the palette both call `GraphStore.navigate(to:)`, so there's exactly one
navigation model in the app, not one per screen.

## 6. Concept representation and cross-linking

Enforced structurally, not just by convention: `ArchitectureView` reads
`graph.decisions(affecting:)` to show a component's decisions inline; `DecisionsView`
reads `graph.tradeoffs(for:)` to show a decision's tradeoffs inline;
`EntryPointsView`/`FlowsView` link through `flowId`/`entryPointId`. Every one of those
lookups is a graph traversal, not a hand-written per-screen reference.

## 7. Code-navigation experience

`RepoContextService` checks the PR out at its real head SHA on disk (via `git clone`
+ fetching GitHub's synthetic `refs/pull/<n>/head`), so both the AI and the code viewer
read real files rather than diff hunks. Three zoom levels on any reference: the exact
lines, expand-context, and whole-file. Base-side references (`RefSide.base`) read the
pre-PR blob via `git show <baseSha>:<path>` rather than the working tree. Jump-to-
definition/LSP-grade navigation is explicitly deferred (§17).

## 8. GitHub integration

Contour reads GitHub through one of two interchangeable `PRSource` implementations
(`Services/PRSource.swift` picks between them), and holds no GitHub credential either way.

- `GHCLISource` shells out to `gh` — `gh pr view --json ...` for
  metadata/commits/comments/reviews, `gh pr diff` for the raw diff, `gh issue view` for a
  linked issue. It inherits whatever `gh auth` is configured, including GitHub Enterprise,
  and it is the only path that can read private repositories.
- `AnonymousAPISource` uses GitHub's public REST API with no credentials at all, so a
  public pull request can be reviewed on a machine that has nothing but `git`.

Selection is a user setting (`auto` / `gh` / `anonymous`) defaulting to `auto`: use `gh`
when it is installed and authenticated — private repos, and 5000 requests/hour — and
otherwise the anonymous API at 60 requests/hour. A 404 or non-rate-limit 403 from the
anonymous path means the repository is not publicly readable, and is reported as exactly
that, naming `gh auth login` as the fix; rate limiting is distinguished from it by
`X-RateLimit-Remaining`.

Because `gh` wins whenever it is present, the anonymous path is the least-exercised one
while being the first one a new user meets. Two things counter that: the `anonymous`
setting forces it on demand, and a parity test asserts both sources produce identical
`RawPRContext` values for the same PR.

The checkout uses plain `git clone`, not `gh repo clone`. Git's credential helper — which
`gh` installs when it authenticates — already covers private repositories, so a single
code path serves both cases and the checkout depends on `gh` not at all.

Posting reviews back to GitHub is designed (one line-anchored comment per reviewer-marked
decision via the REST reviews API) but deferred past MVP.

One real-world robustness detail worth calling out because it surfaced during
development: PR base branches are frequently deleted after merge. Fetching the head ref
and the base ref in a single `git fetch` call fails outright if the base branch name no
longer resolves. `RepoContextService.checkout` fetches the head ref (via the PR-number
ref, which survives branch deletion) and the base ref independently, and falls back to
fetching the base commit by SHA if the branch-name fetch fails and the object isn't
already present from the initial clone.

## 8a. Issue-tracker integration

The issue a PR came from grounds the plain-language "problem to be solved" statement in
what was actually asked for, rather than in what the diff appears to do. Which tracker to
consult is pluggable behind `IssueTracker` (`Tracker/IssueTracker.swift`):

- `GitHubIssueTracker` is the default and requires nothing installed. It detects closing
  keywords (`Fixes #123`), cross-repo references (`owner/repo#123`), bare `#123` mentions,
  and issue numbers embedded in branch names, in that order of confidence, and fetches
  through whichever `PRSource` is already in use.
- `JiraTracker` shells out to `acli`. It is offered only when `acli` is on PATH and stays
  off until the user enables it — detecting `acli` never silently changes where Contour
  looks.

The contract is best-effort and load-bearing in both directions: a missing, unreachable,
or unparseable issue returns nil and the pipeline continues. No issue lookup may ever fail
a review.

## 9. Repository-context acquisition

The app does the minimum acquisition itself — clone/fetch, write one context file
(`.contour-context.md`, containing PR title/body/commits/comments/diff, all wrapped in
`<UNTRUSTED_PR_CONTENT>` tags) — and then hands the rest to `pi`'s own file tools. `pi`
reads real files, greps, and follows call chains itself rather than the app pre-computing
a symbol index and feeding a dumb model; this is the direct consequence of building the
AI backend on `pi` rather than a bare completion API (§10).

## 10. AI analysis pipeline

The AI backend is a CLI the user has already installed and signed in to. Contour holds no
provider key and inherits whatever model and provider that CLI is configured with.

Which CLI is a user setting. `Harness` (`Harness/Harness.swift`) is the seam, and it
abstracts exactly the two things that differ between them — how you invoke one, and how
you read its output stream. `AnalysisService` keeps everything shared: the grounding
system prompt, defensive JSON extraction, the mock short-circuit, the retry.

| Concern | `pi` | `claude` |
| --- | --- | --- |
| Non-interactive | `-p` | `-p` |
| Stream format | `--mode json` | `--output-format stream-json --verbose` |
| Ephemeral session | `--no-session` | default under `-p` |
| Read-only tools | `--tools read,grep,find,ls` | `--allowedTools Read,Grep,Glob` |
| Effort tier | `--thinking low\|high` | `--effort low\|high` |
| Context file | `@file` as its own argv token | contents inlined into the prompt |
| Progress event | `tool_execution_start` | `assistant` → `content[].tool_use` |
| Final text | `message_end` → last text block | `result`/`success` → `.result` |

Several properties are load-bearing and were validated by running both CLIs during
development, not assumed:

- **`@file` must be its own argv token.** `pi` resolves an `@path` reference by scanning
  the raw argument for a leading `@`; passing `"@file\n\nrest of the prompt"` as a single
  string causes `pi` to treat the entire remainder as part of the path and fail with
  "File not found". The fix is passing the file reference and the prompt body as two
  separate positional arguments after `-p`. `claude` has no equivalent convention, so
  `ClaudeHarness` inlines the file's contents instead; both must deliver the same text.
- **The final message lives in a different place per CLI.** `pi` puts it in the last text
  *block* of the assistant's `message_end` — and a `thinking` block with a null `text` can
  follow the real answer, so the extraction filters on block type rather than taking the
  last block. `claude` reports it once, on a separate `result` event.
- **Unknown events must be ignored, not treated as errors.** `claude` interleaves
  `system/hook_started`, `system/hook_response`, and `rate_limit_event` lines with real
  content, and both CLIs gain event types over time.
- **Bare model names are ambiguous across multi-provider setups.** Passing `--model
  haiku` matched an unauthenticated provider in one real test environment. Contour pins no
  model by default — `AnalysisTier.modelPattern` is nil unless Settings sets a per-tier
  override — so the model flag is omitted entirely and each CLI's own default applies.
- **Which binary a bare command name resolves to matters.** Two installs of the same CLI
  can accept different flags; resolution consults the inherited `PATH` first and only then
  a list of common install locations, which a Finder-launched app needs because it inherits
  a minimal `PATH`.
- **Models occasionally emit malformed JSON.** One observed stage returned an otherwise
  complete response containing a stray bracket. With seven stages per run, that would throw
  away a whole pipeline including the stages already paid for, so a stage retries once on
  unparseable JSON — and only once.

Six sequential stages, each reading the previous stage's output for cross-linking IDs
(`Pipeline/AnalysisPipeline.swift`, prompts in `Pipeline/PromptBuilder.swift`):

1. **Architecture** (low effort) — components, `dependsOnIds`, trust boundaries,
   overall architecture-impact statement.
2. **Intent** (low effort) — what the author says the PR does, quoted/paraphrased where
   possible.
3. **Decisions** (high effort) — the handful of decisions worth a reviewer's attention,
   linked to components.
4. **Tradeoffs** (high effort) — named poles per decision that embodies one.
5. **Flows + entry points** (high effort) — traced by the harness actually reading the
   call chain, not guessed.
6. **Judgment + questions** (high effort) — final synthesis pass that sees the assembled
   graph so far and is asked specifically for what a senior engineer would want to judge,
   plus honest open questions.

Every stage's system prompt instructs the harness to treat anything inside
`<UNTRUSTED_PR_CONTENT>` as data, never instructions — the mitigation for prompt
injection via a malicious PR description/comment/commit message, given the harness is
agentic and reads attacker-influenceable text. Every invocation is restricted to read-only
tools
(`read,grep,find,ls` — no `bash`, `edit`, or `write`).

Each stage's raw `[String: Any]` response is decoded through `StageDecoding` into
graph-node types with lenient `init(from:)` implementations (see §11) — this was not
optional: a live-captured `pi` response used as a regression fixture
(`Tests/ContourTests/Fixtures/architecture_response.json`) omits `blobSha`/`side` on
some refs, which Swift's synthesized `Decodable` treats as a hard failure regardless of
declared default values.

## 11. Data model — the PR knowledge graph

See `Sources/Contour/Models/GraphModels.swift` for the authoritative types. In brief:

```
Statement { text, provenance: fact|claim|interpretation, confidence?, source? }
CodeRef   { path, startLine, endLine, blobSha?, side: head|base }

ComponentNode  { id, title, changeKind, summary?, refs, decisionIds, flowIds,
                 dependsOnIds, isTrustBoundaryEdge, filesChanged }
DecisionNode   { id, title, decision, rationale[], alternatives[], consequences[],
                 confidence, refs, tradeoffIds, componentIds, reviewerState, reviewerNote }
TradeoffNode   { id, title, poleA, poleB, chosen, explanation, decisionIds, refs }
FlowStep       { id, index, title, componentId?, refs, stateDelta?, branches[],
                 externalCalls[], errorPaths[], changeKind, isAsyncBoundaryAfter, caution? }
FlowNode       { id, title, steps[], entryPointId? }
EntryPointNode { id, title, kind, changeKind, refs, flowId? }
QuestionNode   { id, text, relatedIds[], refs }

PRSummary { repo, number, title, author, state, branch, baseBranch, headSha, baseSha,
            intent, filesChanged, additions, deletions, changeMap[],
            architectureImpact?, needsJudgment[], uncertainties[] }

PRGraph { pr, components[], decisions[], tradeoffs[], flows[], entryPoints[], questions[] }
```

`PRGraph` is `Codable` end to end and is the only thing `GraphStore` holds — every lens
is a read-only query over it, plus reviewer-state mutations
(`setReviewerState`/`setReviewerNote`) confined to `DecisionNode`.

## 12. SwiftUI / macOS application architecture

Pure SwiftUI, `NavigationSplitView` shell, `@Observable` state (`GraphStore`), Swift
Concurrency throughout (the pipeline is an `actor`; `Shell.stream` exposes `pi`'s JSONL
output as an `AsyncThrowingStream`). No web view anywhere in the UI — the architecture
diagram is a native `Canvas`, the code viewer is native text, the command palette is a
native sheet. Layering:

```
GitHubService, RepoContextService, AnalysisService   (external-process wrappers)
        │
Pipeline (PromptBuilder, StageDecoding, AnalysisPipeline)   (orchestration)
        │
GraphStore   (@Observable, single source of truth + navigation stack)
        │
Views/*   (one lens per file, all reading GraphStore)
```

## 13. Caching and performance

MVP implements checkout-level caching (`RepoContextService` reuses an existing clone if
the head SHA already matches) but not yet per-stage analysis caching keyed by
(headSha, baseSha, pipeline-version) — that's a near-term enhancement, not a design gap:
the seams for it already exist (`AnalysisPipeline.run` is a pure function of the fetched
context plus the checkout).

## 14. Handling very large PRs and repositories

Guarded today: the context file truncates the diff to 120,000 characters and tells `pi`
to use `grep`/`find` on the checkout for anything the truncated diff missed, rather than
silently pretending the diff was complete. Full component-level sharding (map-reduce
across components with a synthesis pass) is designed in the original product brief but
not yet implemented — the six-stage pipeline as built analyzes the whole PR per stage,
which is the right MVP tradeoff (simplicity now, sharding once a real oversized PR proves
it's needed) but is a known scaling limit.

## 15. AI confidence and provenance model

Three classes, enforced by `Statement`'s `Provenance` and rendered identically everywhere
via `ProvenanceBadge`/`StatementView` (`Views/Components/Badges.swift`): fact (observed
directly), claim (author-stated, quoted/paraphrased), interpretation (AI-derived, always
carries a `Confidence` and is required by every stage's system prompt to use hedged
language). The grounding gate is enforced by instruction ("every field you emit must be
backed by a CodeRef your tools actually resolved") rather than a separate mechanical
verification pass in this MVP — mechanical CodeRef verification against the checkout is
a near-term hardening item, not yet wired in.

## 16. Security considerations

No token handling anywhere in this app: `gh` owns GitHub auth (when used at all), the
chosen harness owns model-provider auth, and both are inherited from whatever the user
already has configured. Public pull requests need no credential of any kind. Code stays
local — the checkout lives in `~/Library/Application Support/Contour/repos/`, and the only
thing that leaves the machine is whatever the harness's own configured provider call sends,
governed by that CLI's config rather than this app's.

Two distinct prompt-injection surfaces exist, and they need different mitigations:

1. **PR-derived text** (title, description, commits, comments) is attacker-influenceable
   prose the harness must read. Mitigated by wrapping it in `<UNTRUSTED_PR_CONTENT>` and
   instructing the harness, in every stage's system prompt, to treat it as data.
2. **Instruction files inside the checkout.** Both supported harnesses auto-discover
   `CLAUDE.md` / `AGENTS.md`, skills, hooks, and plugins from the working directory. For a
   tool whose entire job is analyzing arbitrary pull requests from the internet, those
   files are attacker-controlled content that would be loaded as *instructions* — and the
   `<UNTRUSTED_PR_CONTENT>` wrapper does nothing about them, because it only wraps prose.

The second surface is mitigated by disabling project-resident customization on every
invocation: `--no-context-files --no-extensions --no-skills` for `pi`, and `--restricted
--safe-mode` for `claude`. `--bare` would also disable CLAUDE.md discovery for `claude` but
was rejected: it forces `ANTHROPIC_API_KEY`-only auth and would break anyone signed in
through a subscription.

Beyond that, every invocation is read-only (no `bash`, no edit, no write, no WebFetch),
ephemeral, and session-less, so nothing a PR contains can persist into a later analysis.

## 17. MVP scope (implemented)

- Paste-URL → fetch → checkout → six-stage pipeline → knowledge graph, exactly as
  described above.
- Summary, Architecture (diagram), Decisions (full record + reviewer state), Tradeoffs,
  Flows, Entry points, Raw diff, Evidence/code viewer.
- Command palette, semantic back/forward navigation, review-progress tracking.
- Provenance/confidence rendered throughout.

**Explicitly deferred:** posting reviews back to GitHub, LSP-grade jump-to-
definition/call-graph navigation, sequence-diagram rendering as an alternate flow view,
sharded analysis for oversized PRs, per-stage result caching, a Settings screen for
per-tier model overrides, mechanical CodeRef verification against the checkout.

## 18. Later enhancements

In priority order given what MVP validated: (1) per-stage analysis caching keyed by
head/base SHA, since re-opening the same PR should be instant; (2) mechanical CodeRef
verification, since it closes the one remaining gap between "the AI was told to ground
every claim" and "the app proved it did"; (3) posting reviewer marks back to GitHub as a
real review; (4) sharded analysis for large PRs; (5) LSP-backed code navigation; (6) a
Settings screen exposing per-tier model overrides for users running multiple providers.
