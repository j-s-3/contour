#!/bin/sh
# Run SwiftLint's analyzer rules (analyzer_rules in .swiftlint.yml), which need the full
# swiftc invocations from a verbose build log.
#
# Not run in CI: the Swift Build backend doesn't print per-module swiftc command lines, so
# this needs the deprecated native build system, and the analysis itself takes over ten
# minutes because it type-checks every file through SourceKit. Run it occasionally.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$root/.build/swiftlint"
log="$scratch/build.log"

cd "$root"
rm -rf "$scratch"
mkdir -p "$scratch"
swift build --build-tests --build-system native --scratch-path "$scratch" -v >"$log" 2>&1
swiftlint analyze --strict --compiler-log-path "$log" "$@"
