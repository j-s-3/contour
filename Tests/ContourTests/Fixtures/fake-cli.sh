#!/bin/sh
# Fake CLI fixture for `Support/ShellProcess.swift` fault-injection tests (issue #61).
#
# Stands in for a hung or misbehaving `claude`/`pi` without needing either installed.
# Invoked as `/bin/sh <path to this file> <behavior>` (see the README section on why it's
# run through `/bin/sh` rather than executed directly) so the tests don't depend on the
# executable bit surviving SwiftPM's resource copy.
#
# Behaviors that emit JSONL emit the shape `ClaudeHarness.interpret`/`PiHarness.interpret`
# parse (see `claude-stream.jsonl`/`pi-stream.jsonl`), so a test can pipe this script's
# output through either harness and not just through `Shell.stream` directly.

set -eu

behavior="${1:-}"

case "$behavior" in

  # Never writes anything and never exits on its own — only a watchdog or an explicit kill
  # ends it. Exercises `Shell.stream`'s inactivity timeout. `exec`'d so this script's
  # process becomes `sleep` itself rather than forking a child of its own: `Process.terminate()`
  # only signals the one PID it tracks, and a test that asserts the child is gone shouldn't
  # have to also chase down an orphaned grandchild.
  hang)
    exec sleep 999999
    ;;

  # Writes one valid progress-shaped line, then exits nonzero with no final result at all —
  # a stage that started but never produced an answer.
  exit-mid-stream)
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/repo/a.txt"}}]}}'
    exit 7
    ;;

  # Writes a complete, valid final result, then still exits nonzero. `Shell.run`/`Shell.stream`
  # must surface this as an error (the exit code is authoritative) rather than the stdout it
  # happened to produce along the way. `printf` (not `echo`) for the embedded `\"`: some
  # `/bin/sh` builtins (POSIX-mode bash, which is `/bin/sh` on macOS, among them) interpret
  # `echo`'s backslash escapes differently than `dash` does; `printf`'s escape handling is
  # well-defined by POSIX regardless of which shell is running this script.
  nonzero-with-stdout)
    printf '{"type":"result","subtype":"success","result":"{\\"lineCount\\": 1}"}\n'
    echo "fake-cli: stage failed after producing output" >&2
    exit 1
    ;;

  # Writes its last line with no trailing newline, then exits 0. The line must still reach
  # the caller — this is what the termination-time "trailing buffer" flush is for.
  partial-last-line)
    printf '{"type":"result","subtype":"success","result":"{\\"lineCount\\": 2}"}'
    ;;

  # One ~10MB single-line JSON value, to make sure a huge line isn't truncated or dropped.
  huge-line)
    printf '{"type":"result","subtype":"success","result":"'
    head -c 10000000 /dev/zero | tr '\0' 'x'
    printf '"}\n'
    ;;

  # A line containing bytes that aren't valid UTF-8. `Shell.stream` must log this rather
  # than silently drop it, and still hand the caller a (lossily decoded) line. One `printf`
  # call, with the invalid bytes in the middle of its format string: a leading `-` on a
  # `printf` argument is parsed as an option by some `/bin/sh` builtins (dash included).
  invalid-utf8-line)
    printf '{"type":"result","subtype":"success","result":"before-\377\376-after"}\n'
    ;;

  # Writes ~1MB in one burst and exits immediately — the drain race `terminationHandler`
  # can lose data to if it fires before `readabilityHandler` finished draining the pipe.
  burst-then-exit)
    printf '{"type":"result","subtype":"success","result":"'
    head -c 1000000 /dev/zero | tr '\0' 'x'
    printf '"}\n'
    ;;

  # Event types neither harness recognizes, interleaved with a real result. Both
  # `ClaudeHarness.interpret` and `PiHarness.interpret` must ignore them rather than error —
  # both CLIs gain event types over time.
  unknown-events)
    echo '{"type":"a_future_event_type","payload":{"anything":true}}'
    printf '{"type":"result","subtype":"success","result":"{\\"lineCount\\": 5}"}\n'
    ;;

  # claude-shaped `rate_limit_event` lines interleaved with real content, as claude
  # actually emits them (see `claude-stream.jsonl`). Must be ignored, not treated as errors.
  rate-limit-events)
    echo '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}'
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/repo/b.txt"}}]}}'
    echo '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}'
    printf '{"type":"result","subtype":"success","result":"{\\"lineCount\\": 6}"}\n'
    ;;

  *)
    echo "fake-cli.sh: unknown behavior '$behavior'" >&2
    exit 2
    ;;

esac
