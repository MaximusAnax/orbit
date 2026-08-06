#!/usr/bin/env bash
# The one gate. CI runs exactly this; no phase advances with it red.
# Layers (EVALS.md):
#   L0 invariants  -> OrbitInvariantTests (swift test)
#   L1 pipeline    -> OrbitPipelineTests + orbit-evals over replay fixtures
#   SQL fast-loop  -> scripts/dev/sql_check.py (same SQLite engine, no Swift needed)
set -euo pipefail
cd "$(dirname "$0")/.."

# Stages this machine could not run. Printed at the end, loudly: a green gate
# must never read as "everything is checked" when a whole tier was absent
# (FIELD-NOTES FN-3 — an AppleSpeechTranscriber hang sat in the tree with the
# gate fully green, because nothing here compiled the app at all).
# A newline-joined string, not an array: macOS ships bash 3.2, where an empty
# array under `set -u` is an unbound-variable error.
SKIPPED=""
skip() { SKIPPED="${SKIPPED}${SKIPPED:+$'\n'}$1"; }

echo "== write-path lint (INV-5 / INV-15) =="
./scripts/lint-writepath.sh

echo "== SQL fast-loop checks =="
python3 scripts/dev/sql_check.py

echo "== design-law lint (static tier of D-1..D-11) =="
python3 scripts/dev/design_lint.py

echo "== provisional PIPE measurement (T1 twin of orbit-evals --replay) =="
python3 scripts/dev/measure.py

if command -v swift >/dev/null 2>&1; then
  echo "== swift build =="
  swift build
  echo "== swift test (L0 + L1 + unit) =="
  swift test
  echo "== orbit-evals: replay measurement =="
  swift run orbit-evals measure --replay || { echo "orbit-evals measure failed"; exit 1; }
else
  skip "SPM package: swift build/test/replay — no swift toolchain on this machine"
fi

# The app target is NOT part of the SPM package: apps/OrbitApp/** (Transcription,
# AppModel, Screens, ViewModels) is compiled by nothing above. Build it when the
# Apple toolchain is here; say so plainly when it isn't.
if command -v xcodebuild >/dev/null 2>&1 && command -v xcodegen >/dev/null 2>&1; then
  echo "== iOS app target (xcodegen + xcodebuild) =="
  # honour a local whisper overlay so the gate never regenerates the project
  # without the vendored framework the developer just wired in
  SPEC=project.yml
  [ -f apps/OrbitApp/project-whisper.yml ] && SPEC=project-whisper.yml
  ( cd apps/OrbitApp \
    && xcodegen generate --spec "$SPEC" \
    && xcodebuild build \
         -project OrbitApp.xcodeproj \
         -scheme OrbitApp \
         -destination 'generic/platform=iOS Simulator' \
         CODE_SIGNING_ALLOWED=NO | tail -20 )
else
  skip "iOS app target: apps/OrbitApp/** compiled by NOTHING here — needs macOS with Xcode + xcodegen (CI: app workflow)"
fi

if [ -z "$SKIPPED" ]; then
  echo "== all checks passed (every stage ran here) =="
else
  echo "== all checks that RAN passed — but this gate was not complete =="
  printf '%s\n' "$SKIPPED" | while IFS= read -r s; do echo "   SKIPPED: $s"; done
  echo "   Green above covers only the stages that ran. Do not read it as more."
fi
