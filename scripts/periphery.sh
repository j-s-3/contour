#!/bin/sh
# Scan for unused code with Periphery (options live in .periphery.yml).
#
# Builds app and tests into a fresh scratch path first: the index store keeps units from
# earlier compiles, so scanning an incrementally built .build reports code that has
# already been deleted. Periphery's own build step looks for the index store where the
# old SwiftPM backend wrote it (.build/debug/index/store); the Swift Build backend writes
# it to <scratch>/out, hence --skip-build with an explicit --index-store-path.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$root/.build/periphery"

cd "$root"
rm -rf "$scratch"
swift build --build-tests --scratch-path "$scratch"
periphery scan --skip-build --index-store-path "$scratch/out" "$@"
