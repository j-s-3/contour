#!/usr/bin/env python3
"""Summarize Contour's latency metrics (AnalysisMetrics.swift, DESIGN.md §13).

Each line of metrics.jsonl is one PR open: elapsed seconds since the reviewer asked for
it, per LatencyMilestone, plus whether it was a cache hit. This prints p50/p95 per
milestone in milliseconds, which is the number that matters for regressions: not a single
run's time, but the distribution across everything logged so far.

A cache hit ("Reopening the same PR is instant", §13) is a different measurement --
Contour's own decode-and-render path, not the analysis pipeline -- so it's reported as
its own block rather than folded into the cold-open numbers, which would otherwise read
as misleadingly fast.

Usage:
    python3 scripts/summarize-metrics.py [path-to-metrics.jsonl]

Default path: ~/Library/Application Support/Contour/metrics.jsonl (where the app writes
it -- see AnalysisMetrics.fileURL). BenchTests (issue #60) doesn't write to this file; it
prints its own per-corpus table directly. This script is for real usage collected over
time, on a machine that has actually run the app.
"""
import json
import math
import sys
from pathlib import Path

DEFAULT_PATH = Path.home() / "Library" / "Application Support" / "Contour" / "metrics.jsonl"

# Mirrors LatencyMilestone.allCases / .label in AnalysisMetrics.swift, in the order the
# app defines them. A milestone this script hasn't seen (added after this script was
# last updated) still prints, just at the end and title-cased from its raw key.
MILESTONES = [
    ("prShell", "PR shell"),
    ("rawDiff", "Raw diff"),
    ("whatChanged", "What changed"),
    ("beforeAfter", "Before / after"),
    ("firstDecision", "First decision"),
    ("usefulOverview", "Useful overview"),
    ("architecture", "Architecture"),
    ("flows", "Flows"),
    ("fullAnalysis", "Full analysis"),
]


def percentile(values, pct):
    """Nearest-rank percentile of `values`, or None if it's empty."""
    if not values:
        return None
    ordered = sorted(values)
    rank = max(1, math.ceil(pct / 100 * len(ordered)))
    return ordered[rank - 1]


def load_records(path):
    records = []
    for lineno, line in enumerate(path.read_text().splitlines(), start=1):
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as e:
            print(f"warning: {path}:{lineno}: skipping unparseable line ({e})", file=sys.stderr)
    return records


def print_table(records, label):
    print(f"\n=== {label} ({len(records)} run{'s' if len(records) != 1 else ''}) ===")
    if not records:
        print("  (none)")
        return
    seen_keys = {key for r in records for key in r.get("milestones", {})}
    ordered_keys = [k for k, _ in MILESTONES if k in seen_keys]
    ordered_keys += sorted(seen_keys - set(ordered_keys))
    labels = dict(MILESTONES)

    print(f"  {'milestone':<18} {'n':>5} {'p50':>10} {'p95':>10} {'max':>10}")
    for key in ordered_keys:
        seconds = [r["milestones"][key] for r in records if key in r.get("milestones", {})]
        ms = sorted(v * 1000 for v in seconds)
        p50 = percentile(ms, 50)
        p95 = percentile(ms, 95)
        label_text = labels.get(key, key)
        print(f"  {label_text:<18} {len(ms):>5} {p50:>7.1f} ms {p95:>7.1f} ms {ms[-1]:>7.1f} ms")


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PATH
    if len(sys.argv) > 2:
        print(__doc__)
        return 2
    if not path.exists():
        print(f"error: no metrics file at {path}", file=sys.stderr)
        print("       open a few PRs first (or pass a path explicitly)", file=sys.stderr)
        return 1

    records = load_records(path)
    cold = [r for r in records if not r.get("fromCache")]
    cached = [r for r in records if r.get("fromCache")]

    print_table(cold, "Cold opens (real analysis)")
    print_table(cached, "Cache hits (reopening the same PR)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
