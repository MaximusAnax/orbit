#!/usr/bin/env bash
# The one gate. CI runs exactly this; no phase advances with it red.
# Layers (EVALS.md):
#   L0 invariants  -> OrbitInvariantTests (swift test)
#   L1 pipeline    -> OrbitPipelineTests + orbit-evals over replay fixtures
#   SQL fast-loop  -> scripts/dev/sql_check.py (same SQLite engine, no Swift needed)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== write-path lint (INV-5 / INV-15) =="
./scripts/lint-writepath.sh

echo "== SQL fast-loop checks =="
python3 scripts/dev/sql_check.py

echo "== design-law lint (static tier of D-1..D-11) =="
python3 scripts/dev/design_lint.py

if command -v swift >/dev/null 2>&1; then
  echo "== swift build =="
  swift build
  echo "== swift test (L0 + L1 + unit) =="
  swift test
  echo "== orbit-evals: replay measurement =="
  swift run orbit-evals measure --replay || { echo "orbit-evals measure failed"; exit 1; }
else
  echo "!! swift toolchain not present — Swift stages skipped (CI runs them)"
fi

echo "== all checks passed =="
