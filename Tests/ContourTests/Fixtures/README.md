# Test fixtures

## `corpus.json`
The nightly real-PR corpus (issue #64): a list of `{url, reason}` entries, public and
long-merged, chosen for variety (tiny, docs-only, a new package, a cross-package refactor, fork PRs,
code moved between files, a large command rewrite). Every entry was checked against
GitHub before it went in; each `reason` says what shape it covers. `CorpusRunTests` runs the full pipeline against every entry and
records what happened, stage by stage. See "Running the corpus locally" below.

## `sample-corpus-results.jsonl`
A small, hand-written results file in the exact shape `CorpusRunTests` writes (one
success, one PR with a failed stage and a malformed-JSON retry, one fatal checkout
failure) — enough to exercise every code path in `scripts/summarize-corpus.py` without
running the real corpus:

```sh
python3 scripts/summarize-corpus.py Tests/ContourTests/Fixtures/sample-corpus-results.jsonl
```

## `architecture_response.json`
A captured real analysis-stage response, used as a decoding regression fixture so the
schema contract in `PromptBuilder`/`StageDecoding` stays honest without needing network.

## `claude-stream.jsonl`
A real `claude -p --output-format stream-json --verbose` stream, captured 2026-09-25 from
a run that read a file and returned JSON. Absolute paths were rewritten to `/repo`.
Deliberately retains the `system/hook_started`, `system/hook_response`, and
`rate_limit_event` lines that interleave with content, because `ClaudeHarness.interpret`
must ignore them rather than choke on them.

## `pi-stream.jsonl`
Mixed provenance, deliberately:

- The `session`, `message_start`, and `message_end` lines are a real `pi --mode json`
  capture from 2026-09-25, including the `thinking` content block whose `text` is null —
  which is why the final-text extraction filters on block type rather than taking the
  last block.
- The five `tool_execution_start` lines are synthesized against the schema
  `PiHarness.interpret` parses (`toolName` plus `args`). They could not be captured live:
  every provider configured for `pi` on the capture machine routes through an
  API proxy that rejects pi's own tool schema
  (`tools.0.custom.strict: Extra inputs are not permitted`), so `pi` cannot execute a
  tool call there at all. The last of the five uses an unknown tool name on purpose, to
  pin the generic "using <tool>" fallback.

If you can run `pi` with working tools, re-capture this file and drop this caveat.

## Running the corpus locally

`CorpusRunTests` is gated behind `RUN_CONTOUR_INTEGRATION`, exactly like
`IntegrationSmokeTests` — a plain `swift test` never touches it:

```sh
RUN_CONTOUR_INTEGRATION=1 swift test --filter CorpusRunTests
```

It runs the full pipeline once per PR in `corpus.json` (network + real model calls per
PR — expect several minutes total), and appends one JSON line per PR to a results file as
each one finishes, so a crash partway through still leaves every PR analyzed up to that
point on disk. A PR that fails is a recorded result, not a stopped run: every entry in the
corpus is always attempted. The results file's path defaults to somewhere under the test's
temp directory and is printed at the start of the run; point it somewhere specific with:

```sh
CONTOUR_CORPUS_RESULTS=/tmp/corpus-results.jsonl \
RUN_CONTOUR_INTEGRATION=1 swift test --filter CorpusRunTests
```

`CONTOUR_HARNESS` and `CONTOUR_GITHUB_ACCESS` work the same as for `IntegrationSmokeTests`
(see the README's Tests section). Then summarize the results:

```sh
python3 scripts/summarize-corpus.py /tmp/corpus-results.jsonl
```

which prints, per stage, the failure rate, the malformed-JSON retry count, and the
unverifiable-citation rate, plus p50/p95 latency per `AnalysisMetrics` milestone and the
list of failed PRs with their messages. This is also what the nightly workflow
(`.github/workflows/nightly-corpus.yml`) runs and uploads as an artifact.
## `fake-cli.sh`
A fake CLI used by `ShellProcessTests` to inject faults `Shell.run`/`Shell.stream` have to
survive — a hung process, a burst written right before exit, an invalid-UTF-8 line, and so
on — none of which a captured fixture (a fixed, finite JSONL file) can produce, since they
depend on how and when a real process writes and exits.

It picks a behavior from its first argument (`hang`, `exit-mid-stream`,
`nonzero-with-stdout`, `partial-last-line`, `huge-line`, `invalid-utf8-line`,
`burst-then-exit`, `unknown-events`, `rate-limit-events` — see the comment above each
`case` in the script for what it does and which fault it exercises). Behaviors that emit
JSONL emit the shape `ClaudeHarness.interpret`/`PiHarness.interpret` parse, so a test can
also replay the output through a harness, not just through `Shell.stream` directly.

Tests invoke it as `/bin/sh <path to fake-cli.sh> <behavior>` rather than running the
script directly — `Bundle.module`'s copy of a test resource isn't guaranteed to keep the
executable bit SwiftPM copied it with, and `/bin/sh` sidesteps that entirely. Kept to
`/bin/sh` builtins (`printf`, `head -c`, `tr`) rather than bash-isms, so it runs the same
under whatever `/bin/sh` actually is.

### A note on the `system` events in `claude-stream.jsonl`

`claude`'s real `system/init` event carries a full dump of the capturing machine's local
configuration — installed plugins, MCP servers, skill names, session ids, and absolute
home-directory paths. None of that belongs in a committed fixture, and none of it is
load-bearing: `ClaudeHarness.interpret` ignores every `system` event regardless of
payload. The `system` lines here are therefore trimmed to just the fields that identify
the event, so the fixture still proves the noise is skipped without publishing one
developer's environment.

## `gh-pr-list.json`
Real output of `gh pr list -R cli/cli --state open --limit 30 --json
number,title,url,author,isDraft,createdAt`, captured 2026-10-01 and unedited. It holds
pull requests from people and from bots; `gh` spells a bot's login `app/dependabot` and
sets `author.is_bot`. `WatchedPullRequestsParseTests` relies on at least one bot being
present.

## `rest-pulls.json`
Real output of `GET /repos/cli/cli/pulls?state=open&sort=created&direction=desc&per_page=30`
from the anonymous REST API, captured 2026-10-01. The response was projected with `jq` to
the seven fields the parser reads (`number`, `title`, `html_url`, `draft`, `created_at`,
`user.login`, `user.type`), because the full response is several hundred kilobytes of
fields nothing reads. No value was changed. The REST API spells a bot's login
`dependabot[bot]` and sets `user.type` to `Bot`.

## `gh-pr-list-head.json`, `gh-pr-list-base.json`
Real output of `gh pr list -R cli/cli --state open --limit 10 --head babakks/refresh-token-a-foundation --json
number,url,title,author,isDraft,headRefName,baseRefName,headRefOid,baseRefOid,additions,deletions,changedFiles,isCrossRepository`
and the same with `--base` in place of `--head`, captured 2026-10-06 and unedited. The branch is
layer 1 of a seven-layer stack (`Refreshable tokens (1/7)` to `(7/7)`); the `--head` answer is that
layer, the `--base` answer is layer 2. `StackDiscoveryParseTests` relies on each holding one row.

## `rest-pulls-head.json`, `rest-pulls-base.json`
Real output of `GET /repos/cli/cli/pulls?state=open&per_page=10&head=cli:babakks/refresh-token-a-foundation`
and `...&base=babakks/refresh-token-a-foundation`, captured 2026-10-06. Each response was
projected with `jq` to the fields the parser reads (`number`, `title`, `html_url`, `draft`,
`user.login`, `head.ref`, `head.sha`, `head.repo.full_name`, `base.ref`, `base.sha`, `additions`,
`deletions`, `changed_files`). No value was changed. The list endpoint returns `null` for the
three size fields, which is why `StackLayer.size` is optional.
