# Contour — design doc

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

`RepoContextService` checks the PR out at its real head SHA on disk (via `gh repo clone`
+ fetching GitHub's synthetic `refs/pull/<n>/head`), so both the AI and the code viewer
read real files rather than diff hunks. Three zoom levels on any reference: the exact
lines, expand-context, and whole-file. Base-side references (`RefSide.base`) read the
pre-PR blob via `git show <baseSha>:<path>` rather than the working tree. Jump-to-
definition/LSP-grade navigation is explicitly deferred (§17).

## 8. GitHub integration

All of it goes through the `gh` CLI (`Services/GitHubService.swift`): `gh pr view --json
...` for metadata/commits/comments/reviews, `gh pr diff` for the raw diff, `gh repo
clone` + `git fetch origin refs/pull/<n>/head` for the checkout. No token handling, no
GitHub SDK, no separate auth flow — the app inherits whatever `gh auth` is already
configured, including GitHub Enterprise. Posting reviews back to GitHub is designed
(one line-anchored comment per reviewer-marked decision via the REST reviews API) but
deferred past MVP.

One real-world robustness detail worth calling out because it surfaced during
development: PR base branches are frequently deleted after merge. Fetching the head ref
and the base ref in a single `git fetch` call fails outright if the base branch name no
longer resolves. `RepoContextService.checkout` fetches the head ref (via the PR-number
ref, which survives branch deletion) and the base ref independently, and falls back to
fetching the base commit by SHA if the branch-name fetch fails and the object isn't
already present from the initial clone.

## 9. Repository-context acquisition

The app does the minimum acquisition itself — clone/fetch, write one context file
(`.contour-context.md`, containing PR title/body/commits/comments/diff, all wrapped in
`<UNTRUSTED_PR_CONTENT>` tags) — and then hands the rest to `pi`'s own file tools. `pi`
reads real files, greps, and follows call chains itself rather than the app pre-computing
a symbol index and feeding a dumb model; this is the direct consequence of building the
AI backend on `pi` rather than a bare completion API (§10).

## 10. AI analysis pipeline

The whole AI backend is the `pi` CLI, invoked exactly like `gh`: shelled out to, no API
key held by this app, whatever provider/model `pi` is configured with is what runs.
`Services/AnalysisService.swift` builds each invocation as:

```
pi --mode json --no-session --tools read,grep,find,ls --thinking <low|high> \
   --append-system-prompt <grounding rules> \
   -p "@.contour-context.md" "<stage-specific prompt>"
```

Two properties of this are load-bearing and were validated against a real `pi`
invocation during development, not assumed:

- **`@file` must be its own argv token.** `pi` resolves an `@path` reference by scanning
  the raw argument for a leading `@`; passing `"@file\n\nrest of the prompt"` as a single
  string causes `pi` to treat the entire remainder as part of the path and fail with
  "File not found". The fix is passing the file reference and the prompt body as two
  separate positional arguments after `-p`.
- **Bare model names are ambiguous across multi-provider setups.** Passing `--model
  haiku` matched an unauthenticated provider in one real test environment. The app does
  not pin a model/provider by default — `AnalysisTier.modelPattern` is `nil` unless a
  future Settings screen sets an override, so `--model` is omitted and `pi`'s own
  configured default handles it. Effort is still tiered via `--thinking` (`low` for
  mechanical stages, `high` for judgment-heavy ones).

Six sequential stages, each reading the previous stage's output for cross-linking IDs
(`Pipeline/AnalysisPipeline.swift`, prompts in `Pipeline/PromptBuilder.swift`):

1. **Architecture** (low effort) — components, `dependsOnIds`, trust boundaries,
   overall architecture-impact statement.
2. **Intent** (low effort) — what the author says the PR does, quoted/paraphrased where
   possible.
3. **Decisions** (high effort) — the handful of decisions worth a reviewer's attention,
   linked to components.
4. **Tradeoffs** (high effort) — named poles per decision that embodies one.
5. **Flows + entry points** (high effort) — traced by `pi` actually reading the call
   chain, not guessed.
6. **Judgment + questions** (high effort) — final synthesis pass that sees the assembled
   graph so far and is asked specifically for what a senior engineer would want to judge,
   plus honest open questions.

Every stage's system prompt instructs `pi` to treat anything inside
`<UNTRUSTED_PR_CONTENT>` as data, never instructions — the mitigation for prompt
injection via a malicious PR description/comment/commit message, given `pi` is agentic
and reads attacker-influenceable text. Every invocation is restricted to read-only tools
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

## 16. Security considerations for private repositories

No token handling anywhere in this app: `gh` owns GitHub auth, `pi` owns model-provider
auth, and both are inherited from whatever the user already has configured. Code stays
local — the checkout lives in `~/Library/Application Support/Contour/repos/`, and the
only thing that leaves the machine is whatever `pi`'s own configured provider call sends
(governed by `pi`'s own config, not this app's). The concrete mitigation for the one real
risk this design introduces — an agentic tool reading attacker-influenceable PR text —
is the `<UNTRUSTED_PR_CONTENT>` wrapping plus the read-only tool restriction described in
§10; there is no `bash` access at any point in the analysis pipeline.

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
