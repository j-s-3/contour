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

### A note on the `system` events in `claude-stream.jsonl`

`claude`'s real `system/init` event carries a full dump of the capturing machine's local
configuration — installed plugins, MCP servers, skill names, session ids, and absolute
home-directory paths. None of that belongs in a committed fixture, and none of it is
load-bearing: `ClaudeHarness.interpret` ignores every `system` event regardless of
payload. The `system` lines here are therefore trimmed to just the fields that identify
the event, so the fixture still proves the noise is skipped without publishing one
developer's environment.
