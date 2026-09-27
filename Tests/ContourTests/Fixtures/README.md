# Test fixtures

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
