# Contour — reviewing a stack of pull requests

Status: draft 2026-10-02. Amends `DESIGN.md` §4.2 (Overview header), §8 (GitHub
integration), §9 (repository context), §10 (context file) and §13 (caching).

## Why

Authors split a large feature into a stack: a chain of pull requests where each one
targets the branch of the one below it. The example that prompted this design is a
seven-layer stack of about 25,000 added lines, each layer compiling and passing its own
tests. The author also kept the monolithic branch open as its own pull request.

Contour today reviews one pull request and knows nothing about the chain. The reviewer
has two poor options:

- **Open one layer.** The diff is right, because GitHub computes each pull request's
  diff against its own base branch, and the checkout contains the layers beneath it. But
  the analysis has no idea that "nothing reads these tables yet" is true because layer 3
  does the reading, so Judgment flags dead code, and the reviewer has no view of the
  feature as a whole.
- **Open the monolithic branch.** The whole feature is visible, but the context file
  truncates the diff at 120,000 characters, so the model sees roughly a tenth of a
  change this size. The layering the author built for reviewers is thrown away.

Reviewed as a stack, nearly every line reaches the model, each layer's analysis knows
where it sits, and the reviewer can move through the layers bottom-up the way the author
intended.

## Decisions taken during brainstorming

| Question | Decision |
|---|---|
| How a stack is recognised | Branch chaining: the parent is the open pull request whose head branch is this one's base branch; children are open pull requests whose base branch is this one's head. The description's "Part 1 of 7" text is never parsed |
| Unit of analysis | One layer at a time, through the existing pipeline and cache. No combined diff |
| What the model learns | A stack-context block in the context file: this layer's position, the other layers' titles, and that lower layers are already in the checkout |
| Opening a middle layer | The whole stack is offered, with the opened layer highlighted. A reviewer assigned layer 4 still benefits from seeing what layers 5 to 7 do with it |
| Whole-feature briefing | A locally assembled Stack lens listing each layer with its cached "what changed" headline. A synthesis stage that reads the layer summaries is deferred to a later design |
| Cache key | Unchanged. Merging a lower layer retargets the one above it, which moves its base SHA and misses the cache anyway |

## Non-goals

- A combined diff across layers, or any change to how a single layer's diff is fetched.
- A model stage that reasons across layers. The Stack lens is assembled from cached
  per-layer graphs.
- Stacks that fork: when a layer has more than one open child, the chain stops there.
- Cross-repository stacks. Every layer must live in the repository under review.
- Merged or closed layers. Once a layer merges, GitHub retargets the one above it and
  the stack shortens by itself.
- Detecting the monolithic pull request that duplicates a stack.
- Reviewing or submitting a verdict for the stack as a whole. Review submission stays
  per pull request.
- Showing stack membership on the start screen. The lists there carry no branch names,
  and discovery happens when a pull request is opened.

## 1. Discovery

Discovery runs in the pipeline as soon as the pull request is fetched, concurrently with
the checkout, so it never delays the review shell. It walks down from the opened pull
request until no open pull request has a head equal to the current base, then walks up
while exactly one open pull request has a base equal to the current head. A branch seen
twice ends the walk, and a chain is capped at 32 layers. A pull request with no parent
and no child is not stacked and the feature stays invisible.

| Access | Parent of a layer | Children of a layer |
|---|---|---|
| `gh` | `gh pr list -R owner/repo --state open --head <base> --json number,url,title,author,isDraft,headRefName,baseRefName,headRefOid,baseRefOid,additions,deletions,changedFiles` | the same with `--base <head>` |
| Anonymous | `GET /repos/{owner}/{repo}/pulls?state=open&head={owner}:{base}&per_page=10` | `GET /repos/{owner}/{repo}/pulls?state=open&base={head}&per_page=10` |

Both filters were checked against the example stack and against `cli/cli` on
2026-10-02. One call per link: a seven-layer stack opened at the bottom costs seven
calls, one of which returns empty. Under anonymous access that comes out of the same 60
requests per hour as opening the pull request.

Branch names are author-controlled and become arguments. Git refuses a reference that
begins with `-`, so a name that fails the refname rules (leading `-`, `..`, control
characters, `@{`, a trailing `.lock`) is treated as "no parent" rather than passed on.
For the REST transport the name is percent-encoded into the query.

A discovery failure of any kind is logged to the technical log and the review proceeds
as a plain pull request. Discovery is retried when the review is reopened.

### Types

```swift
struct StackLayer: Codable, Equatable, Identifiable, Sendable {
    var url: String
    var number: Int
    var title: String
    var author: String
    var isDraft: Bool
    var headRefName: String
    var baseRefName: String
    var headSha: String
    var baseSha: String
    var additions: Int
    var deletions: Int
    var changedFiles: Int
    var id: Int { number }
}

struct PRStack: Codable, Equatable, Sendable {
    var layers: [StackLayer]
    var currentIndex: Int
    var current: StackLayer { layers[currentIndex] }
    var position: String { "Part \(currentIndex + 1) of \(layers.count)" }
}
```

`layers` is ordered bottom-up: index 0 targets the trunk. `StackDiscovery` follows the
shape of `WatchedPullRequests`: an async `discover(ctx:)` that picks a transport from
`GitHubAccessMode`, pure `parse` functions per transport, and a pure `walk` that takes
two injected lookups (`parent(of:)`, `children(of:)`) and returns the chain, so the
walking rules are tested without a transport.

## 2. What the reviewer sees

### Stack strip

When a stack is found, the Overview header gains one line between the metadata line and
the facts line:

```
Part 3 of 7 in a stack                                  [ Analyze the whole stack ]
① Data layer   ② BFS writer   ③ Report pipeline   ④ Raw report fields   ⑤ Service and REST API   …
```

Each chip is the layer's number and its title, truncated in the middle to fit. The
opened layer is filled; the others are outlined. A chip whose analysis is already cached
carries a small check; one being analysed in the background carries the resolving mark;
one that failed carries a warning. Clicking a chip opens that layer exactly as pasting
its URL would. Hovering shows the full title, author and `+adds −dels · n files`.

The strip is absent for a pull request that is not stacked, and absent while discovery is
still running. Discovery runs beside the checkout and normally lands before it, so the
strip is usually in place before any section below the header has content; when it
lands later it is inserted once, with the same quiet appearance as a placeholder being
replaced, and nothing else in the header changes.

### Moving through the stack

| Where | Action |
|---|---|
| Strip chip | Open that layer |
| ⌘K | **Open next layer in stack**, **Open previous layer in stack**, **Analyze the whole stack** |
| File menu | the same three items in their own group after the Watch item, disabled when the open pull request is not stacked |

Opening another layer is `GraphStore.load(prURL:)`: the current review closes and the
next one opens. A layer analysed earlier is a cache hit and appears at once. The
navigation stack, chat and focus reset as they do for any newly opened pull request.

### Stack lens

The sidebar's Overview group gains a **Stack** row, present only when a stack is found.
It lists every layer bottom-up as a card: number, title, author, size, status, and the
dominant behaviour change's title from that layer's cached graph when one exists ("Adds
the component link tables behind a flag"). The opened layer is highlighted. Clicking a
card opens that layer.

The lens is the whole-feature overview for this design. It is assembled on the main
actor from `PRStack` and `AnalysisCache` reads; no model call is involved.

### Analyze the whole stack

The button and command queue every layer that has no complete cached analysis for its
current head and base, bottom-up, skipping the opened layer, which the foreground
pipeline is already analysing. Background analysis starts when the foreground analysis
of the opened layer has settled, so the review in front of the reviewer stays as fast as
today, and runs one layer at a time.

While it runs, the strip's chips show progress and the analysis indicator's details
popover gains a "Stack" section with the queue. **Stop analysis** stops the background
layer too. A failed layer is marked on its chip with Retry; the queue continues with the
next layer.

Closing the review (⌘W) or opening a pull request outside the stack cancels the queue.
Opening another layer of the same stack keeps it, with two rules:

- The queue pauses while the newly opened layer's foreground analysis runs, and
  resumes when it settles, so at most one layer is analysed in the background at a time
  and never beside a foreground analysis.
- Opening the layer the background is analysing right now cancels that background run
  and drops the layer from the queue. The stages it had finished are already in the
  cache, so the foreground pipeline resumes from them.

## 3. Checkout for background layers

`RepoContextService` keeps one clone per repository and checks the opened pull request's
head out into its working tree. The Evidence lens and the harness both read that tree,
so a background layer cannot use it.

A background layer is checked out into a detached worktree beside the clone:

```
~/Library/Application Support/Contour/repos/owner-repo              the clone, as today
~/Library/Application Support/Contour/repos/owner-repo-pr-18213     worktree for layer 2
```

made with `git fetch origin +refs/pull/N/head:refs/pr/N/head` into the clone, then
`git worktree add --detach <dir> refs/pr/N/head`. Objects are shared with the clone, so
the cost is the working tree alone. The worktree is removed with `git worktree remove
--force` when that layer's background analysis settles, whether it succeeded or failed,
and any worktree left over from an interrupted run is pruned the next time the
repository is opened. When the reviewer later opens that layer in the foreground, the
clone checks it out as today and the cached analysis is used.

`AnalysisPipeline` already takes a `checkoutOverride`; the background runner passes the
worktree checkout through it and otherwise drives an ordinary pipeline, so fetch,
cache restore, the six stages and the cache write are unchanged.

The worktree is as untrusted as the clone. The harness is invoked with the worktree as
its context directory under the same read-only, no-project-instructions flags.

## 4. Stack context in the prompt

`PromptBuilder.contextFileContents` takes an optional `PRStack`. When present, this block
follows the "Base:" line and precedes the changed-files line:

```
Stack: this pull request is part 3 of 7. Layers are listed bottom-up; each targets
the branch of the one before it. Layers 1-2 are already merged into this checkout and
are not part of this change: treat their code as existing code. Layers 4-7 build on
this one and are not in the checkout. Review only this layer's diff; code that this
layer adds but nothing yet calls is expected when a later layer is the caller.
<UNTRUSTED_PR_CONTENT>
1. #18212 Add the component link data layer behind COMPONENT_LINKS (1/7) CLM-53522
2. #18213 Move the Built From Source write code into a shared writer (2/7) CLM-53522
3. #18214 Apply component links when a report is enriched (3/7) CLM-53522   (this PR)
...
</UNTRUSTED_PR_CONTENT>
```

Titles and branch names are author content and sit inside the untrusted wrapper. The
sentences outside it are Contour's own words.

The block is written only for stacked pull requests, so the context file of a plain pull
request is byte-identical to today's and `pipelineVersion` does not change. A stacked
pull request analysed before this change has a cache entry made without the block; it is
kept, and "Re-analyze (ignore cache)" produces one with it.

The context file is written once both the checkout and discovery have finished.
Discovery runs beside the checkout, so it normally finishes first. If it is still
running five seconds after the checkout has finished, the file is written without the
block and the analysis starts; the strip still appears when discovery lands. The grace
period is a constant beside the pipeline version so a test can shorten it.

## 5. Data and state

`GraphStore` gains:

```swift
private(set) var stack: PRStack?
private(set) var stackAnalysis: [Int: StackLayerStatus]
enum StackLayerStatus: Equatable { case cached, queued, analyzing, failed(String) }

func openLayer(_ layer: StackLayer)
func openNextLayer()
func openPreviousLayer()
func analyzeWholeStack()
var canAnalyzeWholeStack: Bool
```

`PipelineEvent` gains `.stack(PRStack)`, emitted once by the foreground pipeline. The
status map is derived: a layer with a cache entry for its current head and base that
holds every analysis stage is `cached`; the background runner reports the rest; a layer
with no entry in the map has not been analysed and is not queued.

The background runner is a `@MainActor` `StackAnalyzer` owned by `GraphStore`, holding the
queue, the running pipeline and its event task. It takes the same `PipelineFactory`
closure the store uses, so tests drive it with a canned pipeline. Its only outputs are
status changes and cache writes.

`PRSummary` does not change. The stack is session state, not graph content, and is
re-discovered on every open so it reflects merges since the last visit.

## 6. Failures

| Cause | Where it shows | Message |
|---|---|---|
| Discovery failed | Technical log only | — |
| A background layer's fetch or checkout failed | Its chip, with Retry | "Couldn't open #18213 for analysis." |
| A background layer's analysis failed in part | Its chip, with Retry | the existing per-stage failure text, in the details popover |
| Anonymous rate limit during the queue | Its chip, queue pauses | "GitHub's anonymous limit is used up. Try again after 3:40 PM." |

Raw `gh` stderr and HTTP bodies go to the technical log.

## 7. Security

- Layer titles, authors and branch names are untrusted. They are rendered as verbatim
  text, truncated for display, and reach the prompt only inside the untrusted wrapper.
- Branch names are validated against git's refname rules before they become a `gh`
  argument, and percent-encoded for REST.
- Background worktrees are attacker-controlled checkouts like the clone. Every harness
  call on them keeps the invariants in `CLAUDE.md`; no new flag is introduced.
- No new credential is held. Private repositories are readable only through an already
  authenticated `gh`.

## 8. Code shape

| File | Change |
|---|---|
| `Models/PRStack.swift` | New. `StackLayer`, `PRStack`, the refname validator |
| `Services/StackDiscovery.swift` | New. Transport choice, both parsers, the pure walk |
| `Services/RepoContextService.swift` | `worktree(for:)` and `removeWorktree(for:)` beside the existing checkout, plus pruning on open |
| `Services/GraphStore.swift` | Stack state, the four actions, cancellation on close |
| `Services/StackAnalyzer.swift` | New. The background queue |
| `Pipeline/AnalysisPipeline.swift` | Run discovery beside the checkout, emit `.stack`, pass the stack to the prompt builder |
| `Pipeline/PromptBuilder.swift` | The stack block |
| `Views/Summary/SummaryView.swift` | The strip, with its layout logic in `SummaryViewLogic` |
| `Views/Stack/StackLensView.swift` | New. The Stack lens |
| `Views/ContentView.swift` | The sidebar row and `NavigationTarget.stack` |
| `Views/CommandPaletteView.swift`, `Views/PRSessionCommands.swift` | The three commands |
| `Views/Analysis/` | The queue section in the details popover |

Chip labels, truncation, status glyph choice, queue ordering and the "needs analysis"
test are pure functions beside the views, following `GraphLayout` and `DiagramMode`.
The repository follows a no-comments convention; these types carry none.

## 9. Testing

- **Parsers.** Fixtures captured from real `gh pr list --head` and `--base` output and
  from the two REST queries against a public repository, with provenance recorded in
  `Tests/ContourTests/Fixtures/README.md`. Cases: a parent found, no parent, one child,
  two children, missing optional fields.
- **Walk.** Injected lookups: a chain of three opened at the bottom, in the middle and
  at the top; a fork stopping the upward walk; a lookup that throws; an invalid branch
  name treated as no parent; a cycle guard.
- **Prompt.** The block's exact text for a middle layer, and its absence for a plain
  pull request, pinning that the plain context file is unchanged.
- **Pipeline.** With a `PRSource` struct and a canned discovery, `.stack` is emitted and
  the context file written to the checkout contains the block; a discovery that never
  returns does not block the stages.
- **Store and analyzer.** Injected pipeline factory: queue order skips cached and current
  layers, background work waits for the foreground to settle, stop cancels both, a
  failed layer does not stop the queue, opening a layer of the same stack keeps the
  queue and opening an unrelated pull request drops it.
- **Worktrees.** Against a scratch repository: add, remove, and pruning of a leftover.
- **Views.** Hosted in a window with a populated `PRStack`: strip states, the Stack lens
  with and without cached headlines, and the commands' enabled states through
  `PRSessionCommandsLogic`.
- **Integration.** `RUN_CONTOUR_INTEGRATION=1` adds one smoke case that opens a layer
  of a public stacked pull request and checks a stack is discovered.

Every new or touched file stays at 90% line coverage or above, and the overall figure
does not drop.

## 10. Documentation

- `DESIGN.md` §4.2: the strip in the header; a new §4.2a for the Stack lens.
- `DESIGN.md` §8: the discovery calls and their cost under anonymous access.
- `DESIGN.md` §9: background worktrees beside the clone.
- `DESIGN.md` §10: the stack block in the context file.
- `DESIGN.md` §13: a stack's layers are cached as ordinary entries.
- `README.md`: one paragraph under opening a pull request.

## 11. Order of work

Two pull requests, each shippable alone:

1. **Know the stack.** Types, discovery, the pipeline event, the prompt block, the
   strip, moving between layers, the commands and documentation. No background
   analysis: the strip shows only cached and current status.
2. **Analyze the whole stack.** Worktrees, the background queue, chip progress, the
   details popover section and the Stack lens.

A third design, not started here, would add a synthesis stage reading the cached layer
summaries to write a whole-feature briefing.
