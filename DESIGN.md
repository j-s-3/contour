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
   ├─► Decisions (choice + tradeoff + why; accept / question / discuss)
   ├─► Flows (what happens at runtime)
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

Node types: `PRSummary` (root), `ComponentNode`, `DecisionNode` (which carries its own
`DecisionTradeoff`s — a tradeoff is a property of the decision that made it, not a node),
`FlowNode` / `FlowStep`, `EntryPointNode`, `QuestionNode`, and `CodeRef` as the terminal
leaf every other node points at. `Statement` is the atomic provenance-tagged claim
embedded throughout (`Provenance`: fact / claim / interpretation, plus an optional
`Confidence` for interpretations).

Edges are expressed as ID arrays rather than a separate edge table, since the graph is
small per PR and this keeps the JSON schema the AI has to fill in simple:
`decisionIds`, `componentIds`, `flowId`, `entryPointId`, `dependsOnIds`.
`PRGraph` provides the traversal helpers (`decisions(affecting:)`, `affects(_:)`,
`flows(traversing:)`) that every lens uses to find a node's neighbors, which is what
makes "a component links the decisions that changed it" a one-line query instead of a
separate document per lens.

## 4. Detailed screen designs

### 4.1 Window shell

Three-column `NavigationSplitView`: a sidebar grouped as Overview / System (Architecture,
Flows) / Review (Decisions, with review progress) / Code (Raw diff), and a main
pane driven entirely by `GraphStore.current: NavigationTarget`. See
`Sources/Contour/Views/ContentView.swift`.

The window opens as an ordinary window at its last size and position, not in full screen:
a reviewer usually arrives from a link in Slack or a browser, and taking over a Space loses
the window they came from. Full screen at launch is an opt-in in Settings › Window.

**Opening a PR is progressive.** There is no full-screen analysis wait: "Opening the pull
request…" lasts only as long as the GitHub fetch, then the window shell appears with the title,
metadata and raw diff, and the analysis fills it in. Every destination is always open.
The sidebar says per row how far along its section is ("Mapping system change…", "2 found
so far", ⚠ "Couldn't be generated"). A lens with nothing yet says what it's working on and
what's already known. A lens with partial content shows it, with a small floating note
while more arrives. The Overview reserves each section's place with a placeholder ("✦
Understanding the change…", "Loading…"). Placeholders are replaced in place and
decisions are appended, so nothing the reviewer is reading moves. Completion never
navigates, scrolls, or takes focus.

A compact toolbar indicator (the resolving Contour mark with "Analyzing PR… 3 remaining"
→ "Analysis complete", which then recedes; §4.1a) opens the details: each section's
status with Retry for failures, then, behind disclosures, the pipeline's own stages, the
latency metrics, and the raw technical log. Contextual chat works from the moment the shell appears: the harness can
read the checkout itself and doesn't need the precomputed analysis.

### 4.1a Welcome, analysis, and the Contour mark

The rounded-square icon is only the macOS app icon (Dock, Finder, Spotlight). Inside
the app the brand is the raw mark: the contour rings and amber peak with no tile,
drawn by `ContourMarkView` from a Swift port of `scripts/generate-logo.py` (a test pins
it to the icon SVG). Light appearance uses deeper tones of the same teal and amber,
since the icon's pale amber disappears on a light window.

- **Welcome.** Mark, "Contour", then the proposition ("Understand the change, not just
  the diff.") and the URL field. The mark stays still. Idle motion would pull the eye
  away from the one thing to do on this screen. Under the field, so a review session
  can start here rather than with a hunt for a URL: PRs awaiting the user's review
  (`gh search prs --review-requested=@me --state=open`, shown only when `gh` can
  answer) and the PRs opened most recently, with repo and when each was last opened.
  Recent PRs reopen instantly from the analysis cache. The URL field covers the rest.
- **Opening.** The same mark carries over from the welcome screen and starts to
  resolve while the PR is fetched: first the peak, then the rings from the summit
  outward. Each stage owns a slice of the mark sized by its typical cost, and within a
  stage the line eases toward the end of its slice without reaching it. It is not a
  percentage meter. Unresolved rings show as a faint trace. Nothing pulses, loops, or
  glows. A headline in the reviewer's terms and the latest real step always go with
  the mark, and the full log is behind "Show activity". This screen now lasts only as
  long as the fetch, because the review opens as soon as the PR has been read (§4.1).
- **Review.** The mark carries on, small, in the toolbar indicator. There it keeps
  resolving while the analysis fills in the open review. Stages run in parallel, so
  each stage's slice resolves when that stage settles, in whatever order they finish. A
  retried stage's slice unresolves until the stage settles again. When the mark is
  whole, the indicator says "Analysis complete" (or "Opened saved analysis") and then
  fades to the bare mark.
- **Reduce Motion.** No drawn lines and no mark gliding between screens. Whole rings
  fade in as stages complete, and screens crossfade.

Keep the mark rare. It appears in these places, not as decoration on empty states.

### 4.2 Overview (landing page)

A thirty-second briefing from a staff engineer, not a dashboard: one centered column
(max ~1240pt) that reads top to bottom — title and metadata, with one quiet facts line
(`12 files · +148 −37 · CI passing · 2 approvals · 3 unresolved threads · opened 2 days
ago`, `PRGlance`) that omits whatever the source couldn't tell; **What changed**, the
before/after stage diagram as the hero (3–6 short stages per side, green for a step this PR
adds, dashed for a step that no longer happens, an optional success/failure outcome on the
last stage); **Why** and **Consequence** at one or two lines each; **Things to think
about**, 1–5 question-shaped items (a question plus one sentence) that merge what used to
be separate needs-judgment and uncertainty lists, distinguished only by a subtle badge;
**Other behavior changes**, one line each, expanding inline; and **Explore the change**,
three navigation tiles (Architecture, Flows, Decisions). Provenance is a tertiary glyph
with a tooltip rather than a colored badge. The things to think about are the review
checklist: there is one measure of review progress, "n of m things to think about
resolved", and the list's header, its checked-off badges, the Decisions tile, the Decisions
header and the sidebar all show that same n of m (`PRGraph.reviewProgress`). An item is
resolved by judging the decision it's reviewed on; when it has no decision to be judged on
(none, or one outside Decisions to Review), by talking it through in a conversation. Longer
reasoning, evidence, and file locations are drill-down only — an expansion, a click, or
right-click → Ask about this…. The judgment stage writes `considerations` to these budgets;
older graphs are condensed by `PRGraph.thingsToThinkAbout`. See
`Views/Summary/SummaryView.swift`.

### 4.3 Architecture

"Draw the relevant part of the system on a whiteboard, and show me where this change
sits." Architecture is a conceptual map one level above the code — the three to seven
parts a staff engineer would draw in thirty seconds ("Input", "Content Inspection",
"Rendering"), not the classes the diff touched. Changed files, symbols and call graphs are
the evidence the architecture stage reads; they are never the boxes. Components changed by
a PR are not the same thing as architecture changed by a PR, and most PRs change little:
saying so is a useful result.

The lens opens with the **architectural impact** (`ArchitectureAssessment`: none / low /
moderate / significant — words, not a score), a one-line headline ("No structural change:
content inspection now gets a bigger sample") and one or two sentences naming the
relationship or responsibility that moved. Below it, the drawing:

- **Boxes** show a part's name, its responsibility in about ten words, and, when it
  changed, a short before → after phrase (`ResponsibilityDelta`: "first line → buffered
  sample"). Unchanged parts are quiet context.
- **Arrows** say what crosses them — data, an event, a request ("bytes", "content type") —
  with the previous label struck through when that changed (`ArchitectureEdge.previousLabel`),
  a change class (new / changed / existing / removed), and a dashed line when asynchronous.
- **Containers** (`SystemBoundary`) only where the boundary means something: a process, a
  service, an external system, a datastore, a trust boundary.
- **Decisions** (◇, design-level only) and **Overview questions** (⚠) are marked on the box
  or arrow they explain (`decisionAnchors`/`questionAnchors`), and open the Decisions lens.

**Delta** (the default) colors only the change; **Before** and **After** are plain
snapshots. Parts nest (`ComponentNode.parentId`), which is how the reviewer zooms: system →
the parts inside one part (drawn as a container, with its neighbors as quiet context) →
implementation and code from the inspector. `PRGraph.architectureLevel(path:)` projects the
graph onto one zoom level: every node and edge is represented by its visible ancestor,
arrows inside one box disappear, and parallel arrows fold into the most important one — so
the model can attach an arrow to the sub-part it really enters and the zoomed-out drawing
still shows one arrow between two boxes.

Selecting a box or arrow opens an inspector beside the drawing (never permanently
reserved): purpose, what this PR did to it, connections, the review questions and decisions
that concern it, flows through it, its implementation and code, and Ask about this….
Implementation counts and provenance live there, not on the canvas.

`GraphLayoutEngine` draws deliberately rather than as a graph: columns follow the
direction of travel; each boundary is laid out as a block, and blocks whose columns
overlap stack in separate bands, so a container never encloses a part that isn't in it
(a boundary whose members sit far apart becomes one container per run); every connector is
orthogonal, routed straight across, through one elbow in the gap, or along a channel
reserved below its band, so no line crosses a box; gaps are sized to their labels. The
drawing fits itself to the pane and turns top-to-bottom when that shows it clearly larger;
it scrolls only when it can't be read at about two-thirds size. Nothing in the lens takes
its ideal size from long text: a statement pinned to its wrapped height at the top of a
non-scrolling detail column once made that column wider than the window and blanked the
sidebar.

Older graphs still draw: parts without parents are top-level, `resolvedEdges` synthesizes
"depends on" arrows from `dependsOnIds`, and the header falls back to the prose
`architectureImpact`. See `Models/ArchitectureModel.swift` and `Views/Architecture/`.

### 4.4 Decisions

Where the reviewer makes judgments: the Overview says what deserves thought, Decisions
records it. Each decision is drawn as the question the engineer had to answer, the options
on the table with the chosen one marked, drawn in the shape that fits (two approaches on a
line, an ordered threshold scale, a radio list, or a tiny before/after diagram for an
architectural choice; never a forced two-sided spectrum), then **What we're trading** — the
decision's primary tradeoff as a one-line spectrum between the two qualities traded — and
**Why this side?**, at most two lines with provenance as a quiet note. Choice → alternative
→ tradeoff → rationale reads as one unit. The tradeoff line is omitted when there is none
or when the options' own details already name both qualities. Then come explicit **Looks good / Question / Discuss** buttons:
Question opens a note to the author, and Discuss opens a conversation. Everything else
(how it's implemented, full rationale, alternatives, every tradeoff with its explanation
and code — secondary tradeoffs only appear here — consequences, the architecture,
relationships and flows it affects, evidence) sits behind More…. Right-clicking a tradeoff
offers Ask about this…, Why did the PR choose this side?, Show Consequences, and Show
Evidence; the conversation gets the whole decision around it.

The screen directs scarce attention, so it is titled **Decisions to Review**: "2 choices in
this PR appear worth your attention, out of 4 identified. Do you agree with them?"
**Significance determines attention; abstraction does not.** The decisions stage finds every
meaningful decision, then assesses two separate things. The first is `level`, what kind
of choice it is: behavior, system, component or implementation. The second is
`significance` (high/medium/low), whether a strong engineer would want to stop and
consciously agree with it. Significance weighs failure consequence, blast radius,
reversibility, novelty, boundary crossing, uncertainty and tradeoff magnitude. Each decision
also carries its `impacts` (correctness, concurrency, compatibility…) and a one-sentence
`significanceReason`.
An implementation choice about retries or transaction boundaries can be high; where a helper
lives can be low. High-significance decisions get the full card, with a quiet "Impacts … —
reason" line under the question; there is never a numeric score. An Overview question
reviewed on a decision raises its significance one step, so a concern can promote a medium
decision but not a low one. Graphs without an assessed significance infer it from the
primary tradeoff: a lean of at least 0.25 from the middle is high, any other tradeoff is
medium, and no tradeoff is low. The level is never used.

Everything else is under **Other Decisions**, collapsed ("Show 2 lower-impact decisions") into
compact rows: the question, what was chosen, **Why it's here**, and any Overview question,
with Add to review, Ask…, and Show (the drawn choice, reasoning and evidence). The AI
proposes the review surface and the reviewer controls it. **Add to review** promotes a
decision, and **Not worth reviewing** on a card demotes one. Both are stored as
`reviewerPlacement`, and moving a decision back to where the analysis put it clears the
override. Nothing is promoted to fill the list: when nothing stands out, the screen says so.
Decisions is where a judgment is recorded, not a second checklist: review progress counts
the Overview's things to think about (§4.2), and judging a decision resolves every question
reviewed on it. The header shows the same n of m as the sidebar's Decisions row, one dot
per question. Decisions to review are the only ones with judgment buttons, and the only
decisions marked on the Architecture drawing and in Flows. An Overview question's
"Review →" opens its first related decision and highlights it briefly; the card names its
questions as one more line, "Overview asks", rather than re-quoting them as a block. The lens is keyboard-driven
(J/K or ↑/↓ move, A/Q/C judge, M more). A "One at a time" mode reads like a design review.
Graphs without `question`/`options`/`why` are condensed by `PRGraph.brief(for:)`. See
`Views/Decisions/DecisionsView.swift` and `Models/DecisionBriefing.swift`.

### 4.5 Tradeoffs

Not a screen, a node, or a review item. A tradeoff exists because a decision was made, so
it lives on `DecisionNode.tradeoffs` and is judged with that decision: two qualities being
traded, where the choice landed, and whether it's the decision's primary tension or a
secondary one — never a verdict. A decision may have none; the analysis is told not to
manufacture one. Review progress counts the things to think about, never tradeoffs.

### 4.6 Flows

"Show me what happens when…" — the runtime story at the level an engineer draws on a
whiteboard, not a call trace translated into English. Architecture is structural (what the
parts are); Flows is temporal (what happens over time).

Each flow is named as a scenario ("Open a file", "Pipe data into bat") and drawn as a
top-down behavior diagram (`FlowBehavior`): a trigger, 4–8 conceptual stages, branch points
labeled as the question they ask with one labeled edge per case, outcomes, external
systems, storage, and boundaries around the systems it crosses. Async hops are dashed. A
stage that several triggers converge on is its own flow, reached through a "shared flow"
stage, and the flow it belongs to lists "Also reached from".

The screen is about how the PR changed the flow. A **Before / After / Delta** control
defaults to Delta: unchanged stages recede, new stages are green, removed ones dashed red,
and a changed stage carries its own BEFORE / AFTER lines ("first line" → "up to 1 KB").
The header gives the ten-second version: one or two sentences of what happens, and one
line on what this PR changed. Decisions that shape a point in the flow, and Overview
review questions about it, hang as notes beside the connection where they matter. The
diagram spreads to the canvas width: notes widen and side-by-side branches move apart to
keep them readable, and every note is drawn on a wide canvas (a narrow one shows three per
stage, then "+N more"); clicking one opens it in Decisions, and each decision
card links back with "Appears in: <flow>". Provenance is not shown on traced stages — only
an inferred stage gets a "?".

The diagram owns the canvas: scenarios are tabs, and an inspector opens beside the diagram
only when a stage is selected. It walks the abstraction ladder — Behavior (what happens,
before/after, neighbors, pinned decisions and questions) › Steps (sub-steps) ›
Implementation (component and traced `FlowStep`s, with branches, external calls, error
paths, and cautions) › Code (evidence). Double-click steps down a rung. Right-click on a
stage adds Show Implementation to the standard menu, and Ask about this… sends the stage
with its neighbors, pinned decisions and questions, and the implementation underneath.
Each traced step names the architecture part it happens in and opens it there, and the
Architecture inspector lists the flows through a part: two views of the same model, one of
parts and one of time.

Graphs from before the redesign carry no `behavior`; `PRGraph.behavior(for:)` condenses a
linear one from the story steps, classifying each by the implementation steps it most
plausibly summarizes, and pins decisions and questions by component and related ids. See
`Views/Flows/`, `Models/FlowBehavior.swift`, and `Models/FlowBriefing.swift`.

### 4.7 Entry points

Grouped by kind, each with a "follow flow" link into the flow it triggers. See
`Views/EntryPoints/EntryPointsView.swift`.

### 4.8 Evidence / code viewer

Exact lines highlighted, a little surrounding context, expand-context and open-whole-file
actions, and a guaranteed `esc` back to wherever the reviewer came from in the
conceptual review — the navigation stack (`GraphStore.path`/`forwardStack`) is what makes
"never lose your place" an actual guarantee rather than a hope. See
`Views/Evidence/CodeViewerView.swift`.

### 4.9 Contextual chat

Every boxed element — before/after stages, why/consequence, things to think about,
architecture nodes and relationships, decisions, tradeoffs, flows and their steps, code
references — carries the same right-click menu (`.reviewContextMenu`): **Ask about this…**
(⌘⇧A), then Open details, Show in Architecture (for anything that happens in a part),
related decisions/flows, Show in code, Open on GitHub, and Copy Link. Asking opens a conversation in the window's inspector column, so it survives
navigation: code citations in an answer open the code viewer beside the thread, and the
reviewer can pull the lines they're viewing into the conversation.

A click is a `ReviewSubject` — an address into the graph, not a copy of it. `PRGraph.resolve`
turns it into the object plus its lineage and neighbors (a relationship brings both
endpoints; a code range brings the concepts that cite it), and `ChatContextBuilder` writes
that as a focused, hierarchical context document. The default is narrow; the reviewer can
widen it per conversation (related decisions, related flows, implementation excerpts, the
entire PR). Each turn runs through the same `Harness` as the analysis stages — same
read-only tools, same instruction-file hardening, same untrusted-content rule — with a
chat-specific system prompt that asks for answers at the selected object's level of
abstraction, code cited as `path:start-end`, and review objects linked as `[[kind:id]]`;
both become inline links. Invocations are ephemeral, so the conversation so far is replayed
into each turn. Answers stream (`HarnessEvent.textDelta`) where the CLI supports it.
Conversations persist for the review session, one per subject. See `Chat/` and
`Views/Chat/`.

## 5. Interaction model

Keyboard-first: `⌘K` command palette (jump to any lens or any named node), `esc` to pop
one level of the navigation stack, back/forward toolbar buttons backed by the same stack.
The sidebar and the palette both call `GraphStore.navigate(to:)`, so there's exactly one
navigation model in the app, not one per screen.

## 6. Concept representation and cross-linking

Enforced structurally, not just by convention: `ArchitectureView` reads
`graph.decisions(affecting:)` to show a component's decisions inline; `DecisionsView`
draws `decision.tradeoffs` in place;
`EntryPointsView`/`FlowsView` link through `flowId`/`entryPointId`. Every one of those
lookups is a graph traversal, not a hand-written per-screen reference.

## 7. Code-navigation experience

`RepoContextService` checks the PR out at its real head SHA on disk (via `git clone`
+ fetching GitHub's synthetic `refs/pull/<n>/head`), so both the AI and the code viewer
read real files rather than diff hunks. Three zoom levels on any reference: the exact
lines, expand-context, and whole-file. Base-side references (`RefSide.base`) read the
pre-PR blob via `git show <baseSha>:<path>` rather than the working tree. Jump-to-
definition/LSP-grade navigation is explicitly deferred (§17).

The raw diff is parsed into files and hunks (`Models/UnifiedDiff.swift`) rather than shown as
one string: a file list with +/− counts to jump from, collapsible file sections, old and new
line numbers side by side, and each hunk badged with the decisions and flow stages whose
`CodeRef`s fall inside it, so the diff links back up the ladder. "Show in diff" (in the code
viewer and on any code reference's context menu) lands on the reference's file and hunk
with the cited lines highlighted.

## 8. GitHub integration

Contour reads GitHub through one of two interchangeable `PRSource` implementations
(`Services/PRSource.swift` picks between them), and holds no GitHub credential either way.

- `GHCLISource` shells out to `gh` — `gh pr view --json ...` for
  metadata/commits/comments/reviews and CI (`statusCheckRollup`), `gh pr diff` for the raw
  diff, one `gh api graphql` query for unresolved review threads, `gh issue view` for a
  linked issue. It inherits whatever `gh auth` is configured, including GitHub Enterprise,
  and it is the only path that can read private repositories.
- `AnonymousAPISource` uses GitHub's public REST API with no credentials at all, so a
  public pull request can be reviewed on a machine that has nothing but `git`. It reads
  CI from the head commit's check runs and statuses, but can't see thread resolution,
  which is GraphQL-only and needs authentication.

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
decision via the REST reviews API) but deferred past MVP. Until then the review still has a
way out: **Open on GitHub** (toolbar, File menu, ⌘⇧O) and **Copy Review Summary** (toolbar,
File menu, ⌘K), which puts the reviewer's judgment on the pasteboard as Markdown for a review
comment — what changed in one line, each judged decision with its state and note, and the
Overview questions no "Looks good" has settled. That Markdown
(`PRGraph.reviewSummaryMarkdown`, `Models/ReviewSummary.swift`) is the payload the deferred
posting will send.

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
  complete response containing a stray bracket. With several stages per run, that would throw
  away a whole pipeline including the stages already paid for, so a stage retries once on
  unparseable JSON — and only once.

Six analysis stages, run as a dependency graph rather than a sequence
(`Pipeline/AnalysisPipeline.swift`, prompts in `Pipeline/PromptBuilder.swift`). Everything
independent runs in parallel as soon as the checkout exists:

```
fetch ──► review opens (title, metadata, raw diff)
checkout ─┬─ issue lookup ──► Understanding          tier 1: what changed, why
          ├─ Behavior change                          tier 1: the before/after hero
          ├─ Decisions (streamed)                     tier 2: what needs judgment
          ├─ Architecture ──► Flows (streamed)        tier 3: the system around it
          └────────────────────────────► Judgment     needs all of the above
```

1. **Behavior change** (low effort) — the Overview's before/after hero, its why and
   consequence.
2. **Understanding** (low effort) — the author's intent plus the two plain-language
   briefs (problem to be solved / how it was solved). One call: these were two calls over
   the same PR prose, and the second only rediscovered what the first had read.
3. **Architecture** (low effort) — the conceptual parts (with sub-parts and
   implementation beneath them), what crosses each relationship, meaningful boundaries,
   and an impact assessment that is told not to inflate implementation changes.
4. **Decisions** (high effort) — the handful of decisions worth a reviewer's attention,
   most consequential first, each with the tradeoffs it made (primary / secondary, zero
   when there's no real tension).
5. **Flows + entry points** (high effort) — traced by the harness actually reading the
   call chain, not guessed, then written as a scenario-named behavior model (stages,
   branches, boundaries, what the PR changed). The judgment stage then anchors each review
   question to a stage (`flowAnchors`).
6. **Judgment + questions** (high effort) — final synthesis pass that sees the assembled
   graph so far and is asked specifically for what a senior engineer would want to judge,
   plus honest open questions.

Only Architecture → Flows (a flow's stages are attributed to architecture parts) and
everything → Judgment are real dependencies. Decisions used to wait for Architecture and
Flows for Decisions, but only to be handed ids for cross-linking — so those links are now
derived locally, from the code both sides cite (`Pipeline/GraphLinker.swift`): a decision
links to the most specific parts whose refs overlap its own, and is pinned to the one flow
stage whose code it touches (never on a tie). That takes two strong-tier calls off the
critical path. Links a model does supply are kept.

Decisions and flows are **streamed**: the stage runs with the CLI's text deltas on, and
`StreamingArrayExtractor` hands out each array element as soon as the model finishes
writing it, so the reviewer sees the first decision long before the stage returns. The
final parsed response stays authoritative; streamed elements are applied, in order, before
it lands, so nothing can arrive after and duplicate it.

Every analysis stage **fails on its own**. Its slice stays empty, the section says so and
offers Retry (and a conversation instead), and every other section carries on; Judgment
runs with whatever exists. Only fetching and checking out the PR are fatal — and a
checkout failure after the review has opened still leaves the raw diff on screen. The
section says what failed in the reviewer's terms ("Couldn't map the architecture. The
model's answer wasn't readable."); the model's raw response and the CLI's stderr go only
to the technical log behind "Show log".

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
                 dependsOnIds, isTrustBoundaryEdge, filesChanged, level, implementedBy[],
                 parentId?, delta? { before?, after?, summary? } }
ArchitectureEdge { id, fromId, toId, label, previousLabel?, flow, change,
                   isTrustBoundary, onCriticalPath, decisionIds, note? }
ArchitectureAssessment { impact: none|low|moderate|significant, headline,
                         explanation?, focusIds[] }
DecisionNode   { id, title, decision, rationale[], alternatives[], consequences[],
                 confidence, refs, tradeoffs[], componentIds, reviewerState, reviewerNote,
                 level, question?, options[], shape?, why? }
DecisionTradeoff { dimensionA, dimensionB, chosenPosition, explanation?, prominence, refs }
FlowStep       { id, index, title, componentId?, refs, stateDelta?, branches[],
                 externalCalls[], errorPaths[], changeKind, isAsyncBoundaryAfter, caution? }
FlowNode       { id, title, steps[], entryPointId?, storySteps[], behavior? }
FlowBehavior   { summary?, changeSummary?, nodes[], edges[], boundaries[] }
FlowBehaviorNode { id, label, kind, detail?, change, before?, after?, substeps[],
                 stepIds[], componentId?, subflowId?, boundaryId?, decisionIds[], refs }
EntryPointNode { id, title, kind, changeKind, refs, flowId? }
QuestionNode   { id, text, relatedIds[], refs }

PRSummary { repo, number, title, author, state, branch, baseBranch, headSha, baseSha,
            intent, filesChanged, additions, deletions, changeMap[],
            architectureImpact?, needsJudgment[], uncertainties[] }

PRGraph { pr, components[], decisions[], flows[], entryPoints[], questions[],
          behaviorChanges[], architectureEdges[], boundaries[], architecture? }
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

The measure that matters is **time to a useful Overview**, not time to a complete
analysis: the reviewer should never feel they are waiting for the AI. So the review opens
as soon as the PR is fetched and fills in as stages land (§4.1), and the pipeline runs
independent stages in parallel (§10).

- **Checkout.** `RepoContextService` reuses an existing clone if the head SHA matches.
- **Analysis cache** (`Services/AnalysisCache.swift`), keyed by (repo, PR, headSha,
  baseSha, pipeline version). Written as each stage lands, recording which stages it
  holds, so an interrupted run resumes with only the missing stages. Reopening the same
  commit shows everything at once. Beside the entries, a small `recent-prs.json` index
  of the last PRs opened (URL, repo, title, when) feeds the welcome screen's recent list
  without decoding every cached graph.
- **Stale-while-revalidate.** When the head has moved, the newest analysis of an earlier
  head is shown straight away, marked "from previous revision" (banner, stage status),
  and replaced slice by slice as the current revision's stages land. A stale slice is
  never mixed with a fresh one within a section, is cleared if its stage fails, and is
  never saved under the new head.
- **Latency metrics** (`Services/AnalysisMetrics.swift`): time to PR shell, raw diff, what
  changed, before/after, first decision, useful overview, architecture, flows and full
  analysis, plus whether the reviewer started working before analysis finished. Shown under
  the analysis indicator's details and appended locally to `metrics.jsonl`; never sent
  anywhere.

Nothing is computed lazily on demand yet. That is deliberately left until the metrics say
which enrichments reviewers actually open before analysis finishes.

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
language). The grounding gate is asked for by instruction ("every field you emit must be
backed by a CodeRef your tools actually resolved") and then checked mechanically:
`CodeRefVerifier` (`Pipeline/CodeRefVerifier.swift`) resolves every stage's refs against
the checkout as the stage lands, before it reaches the screen or `GraphLinker`. A `head`
ref must name a file in the working tree whose range starts inside it; a `base` ref must
resolve via `git cat-file blob <baseSha>:<path>`. A range running past the end is trimmed
to it, and a `head` ref to a file the PR deleted is moved to `base` (the model omits
`side` more often than not). Refs that still don't resolve are dropped, and a statement
whose refs *all* failed keeps its text but loses its standing: a fact becomes a
low-confidence interpretation, an interpretation drops to low confidence, a decision's
own confidence drops to low; an author's claim stays a claim. Each stage's tally is kept
on the graph (`PRGraph.refChecks`) and the analysis details say "3 of 41 code references
couldn't be verified", listing them. File line counts are cached per run, and all of it
runs off the main actor.

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

- Paste-URL → fetch → checkout → staged pipeline → knowledge graph, exactly as
  described above.
- Summary, Architecture (diagram), Decisions (choice, tradeoffs, full record + reviewer state),
  Flows, Entry points, Raw diff, Evidence/code viewer.
- Command palette, semantic back/forward navigation, review-progress tracking.
- Provenance/confidence rendered throughout.

**Explicitly deferred:** posting reviews back to GitHub, LSP-grade jump-to-
definition/call-graph navigation, sequence-diagram rendering as an alternate flow view,
sharded analysis for oversized PRs, per-stage result caching, a Settings screen for
per-tier model overrides, mechanical CodeRef verification against the checkout (since
done, §15).

## 18. Later enhancements

In priority order given what MVP validated: (1) per-stage analysis caching keyed by
head/base SHA, since re-opening the same PR should be instant; (2) ~~mechanical CodeRef
verification, since it closes the one remaining gap between "the AI was told to ground
every claim" and "the app proved it did"~~ — done: `CodeRefVerifier` drops refs that don't
resolve against the checkout and demotes statements resting only on them (§15); (3) posting reviewer marks back to GitHub as a
real review; (4) sharded analysis for large PRs; (5) LSP-backed code navigation; (6) a
Settings screen exposing per-tier model overrides for users running multiple providers.
