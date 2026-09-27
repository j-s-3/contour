#!/usr/bin/env python3
"""Summarize a CorpusRunTests results file (issue #64).

Reads the JSON-lines file CorpusRunTests writes (one line per corpus PR: outcome, per-stage
durations/outcomes/retries/citation checks, and AnalysisMetrics-style latency milestones) and
prints:

  - failure rate per stage (failed / attempted, "attempted" excluding stages that never ran
    because an earlier fatal error — a failed fetch or checkout — stopped the pipeline before
    they started)
  - malformed-JSON retry rate per stage
  - p50/p95 latency per AnalysisMetrics milestone, across every PR that reached it
  - every failed PR, with its stage and message

Usage:
    RUN_CONTOUR_INTEGRATION=1 swift test --filter CorpusRunTests   # writes the results file,
                                                                    # path printed to stdout
    python3 scripts/summarize-corpus.py /path/to/results.jsonl

Standard library only — this runs in the nightly workflow, where nothing else is installed.
"""
import json
import sys
from pathlib import Path


def load(path):
    """Yields one parsed record per non-blank line. A malformed line is skipped with a
    warning rather than failing the whole summary — the results file is append-only and a
    partial last line (a crash mid-write) shouldn't hide everything before it."""
    with open(path, encoding="utf-8") as f:
        for lineno, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError as e:
                print(f"warning: {path}:{lineno}: skipping unparseable line ({e})", file=sys.stderr)


def percentile(values, pct):
    """Nearest-rank percentile; good enough for the handful of PRs a corpus run has."""
    if not values:
        return None
    ordered = sorted(values)
    rank = max(0, min(len(ordered) - 1, int(round(pct / 100 * (len(ordered) - 1)))))
    return ordered[rank]


def fmt_seconds(value):
    return "n/a" if value is None else f"{value:.1f}s"


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <results.jsonl>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"error: no such file: {path}", file=sys.stderr)
        return 2

    records = list(load(path))
    if not records:
        print(f"no results in {path}")
        return 0

    print(f"=== Corpus summary: {path} ===")
    print(f"{len(records)} PR(s) run\n")

    # --- Per-stage failure and retry rates --------------------------------------------
    stage_attempts = {}   # stage -> count of PRs where the stage settled at all
    stage_failures = {}   # stage -> count of PRs where the stage's outcome was "failed"
    stage_retries = {}    # stage -> total malformed-JSON retries across every PR
    stage_citations_checked = {}
    stage_citations_unverifiable = {}
    stage_durations = {}  # stage -> list of durationSeconds

    for record in records:
        for stage in record.get("stages", []):
            name = stage.get("stage", "unknown")
            outcome = stage.get("outcome")
            if outcome in ("done", "failed", "stopped"):
                stage_attempts[name] = stage_attempts.get(name, 0) + 1
            if outcome == "failed":
                stage_failures[name] = stage_failures.get(name, 0) + 1
            stage_retries[name] = stage_retries.get(name, 0) + stage.get("malformedJSONRetries", 0) or 0
            stage_citations_checked[name] = stage_citations_checked.get(name, 0) + (stage.get("citationsChecked") or 0)
            stage_citations_unverifiable[name] = stage_citations_unverifiable.get(name, 0) + (stage.get("citationsUnverifiable") or 0)
            duration = stage.get("durationSeconds")
            if duration is not None:
                stage_durations.setdefault(name, []).append(duration)

    print("--- Per-stage failure rate ---")
    for name in sorted(stage_attempts):
        attempts = stage_attempts[name]
        failures = stage_failures.get(name, 0)
        rate = failures / attempts if attempts else 0.0
        retries = stage_retries.get(name, 0)
        checked = stage_citations_checked.get(name, 0)
        unverifiable = stage_citations_unverifiable.get(name, 0)
        citation_rate = unverifiable / checked if checked else 0.0
        durations = stage_durations.get(name, [])
        p50 = percentile(durations, 50)
        p95 = percentile(durations, 95)
        print(f"  {name}: {failures}/{attempts} failed ({rate:.0%}), "
              f"{retries} malformed-JSON retr{'y' if retries == 1 else 'ies'}, "
              f"{unverifiable}/{checked} citations unverifiable ({citation_rate:.0%}), "
              f"duration p50={fmt_seconds(p50)} p95={fmt_seconds(p95)}")
    print()

    # --- Latency milestones (AnalysisMetrics) ------------------------------------------
    milestone_values = {}
    for record in records:
        for name, seconds in (record.get("milestones") or {}).items():
            milestone_values.setdefault(name, []).append(seconds)

    print("--- Latency milestones (p50 / p95, seconds; reached / total) ---")
    for name in sorted(milestone_values):
        values = milestone_values[name]
        print(f"  {name}: p50={fmt_seconds(percentile(values, 50))} "
              f"p95={fmt_seconds(percentile(values, 95))} ({len(values)}/{len(records)})")
    print()

    # --- Failed PRs ----------------------------------------------------------------
    failed_prs = [r for r in records if r.get("outcome") not in ("completed",)]
    prs_with_failed_stages = [
        r for r in records
        if r.get("outcome") == "completed" and any(s.get("outcome") == "failed" for s in r.get("stages", []))
    ]

    print(f"--- Failed PRs (fatal/error): {len(failed_prs)} ---")
    for r in failed_prs:
        print(f"  {r.get('url')}: {r.get('outcome')} — {r.get('fatalMessage')}")

    print(f"\n--- Completed PRs with at least one failed stage: {len(prs_with_failed_stages)} ---")
    for r in prs_with_failed_stages:
        failed_stage_names = [
            f"{s.get('stage')} ({s.get('failureMessage')})"
            for s in r.get("stages", []) if s.get("outcome") == "failed"
        ]
        print(f"  {r.get('url')}: {', '.join(failed_stage_names)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
