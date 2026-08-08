#!/usr/bin/env bash
# Structural enforcement, layer 3 of 3 (with SQL triggers and Swift access control):
#  INV-5  — only OrbitWrite may open a writable database connection.
#  INV-15 — no relationship-quality score column/API anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0

# INV-5: openWriter( is the sole writable-connection constructor in OrbitSQLite.
# It may appear in OrbitSQLite (definition), OrbitWrite (the funnel), and tests.
hits=$(grep -rn "openWriter" Sources --include='*.swift' \
  | grep -v '^Sources/OrbitSQLite/' \
  | grep -v '^Sources/OrbitWrite/' || true)
if [[ -n "$hits" ]]; then
  echo "INV-5 VIOLATION: writable connection opened outside OrbitWrite:"
  echo "$hits"
  fail=1
fi

# Cross-platform Foundation: `deletingPathExtension` is a METHOD on Darwin and a
# URL? PROPERTY on Linux, so calling it compiles on macOS and fails the Linux
# core workflow. That divergence cost two red core runs; the app workflow cannot
# catch it because it only builds on macOS. Everything under Sources/ and Tests/
# is compiled by Linux CI, so the call is banned there.
hits=$(grep -rn "deletingPathExtension()" Sources Tests --include='*.swift' \
  | grep -v '^[^:]*:[0-9]*: *//' || true)
if [[ -n "$hits" ]]; then
  echo "PORTABILITY VIOLATION: deletingPathExtension() is Darwin-only in this position."
  echo "Use lastPathComponent + string trimming instead:"
  echo "$hits"
  fail=1
fi

# INV-15: forbidden score-shaped identifiers on person/relationship surfaces.
# (Named patterns from EVALS INV-15; word-boundary to avoid e.g. 'health' in comments.)
hits=$(grep -rniE '\b(relationship_(strength|score|health)|closeness_score|person_score|strength_score)\b' Sources scripts 2>/dev/null \
  | grep -v 'lint-writepath.sh' || true)
if [[ -n "$hits" ]]; then
  echo "INV-15 VIOLATION: score-shaped identifier found:"
  echo "$hits"
  fail=1
fi

# SwiftUI containment: nothing in the platform-neutral package imports SwiftUI.
hits=$(grep -rn "import SwiftUI" Sources --include='*.swift' || true)
if [[ -n "$hits" ]]; then
  echo "BOUNDARY VIOLATION: SwiftUI imported inside platform-neutral package:"
  echo "$hits"
  fail=1
fi

exit $fail
