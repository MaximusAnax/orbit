#!/usr/bin/env bash
# Overnight measurement job — MEASUREMENT-REWORK Phase 0+1.
#
#   OPENAI_API_KEY=... scripts/dev/overnight.sh [k] [label]
#
# Collects k independent runs of the corpus, then grades and aggregates them in
# the same invocation. Collection and grading stay separate *stages* — the runs
# land on disk first, so an improved grader can re-score them later without
# spending the API again — but one command does both, so a cloud agent needs no
# second step.
#
# Safe to re-run: collection is checkpointed per (run, memo), so a job that dies
# resumes instead of starting over.
set -uo pipefail
cd "$(dirname "$0")/../.."

K="${1:-10}"
LABEL="${2:-}"
CONCURRENCY="${ORBIT_CONCURRENCY:-3}"

if [ -z "${OPENAI_API_KEY:-}" ]; then
  if [ -f .env ]; then set -a; . ./.env; set +a; fi
fi
if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "FAIL: OPENAI_API_KEY not set (and no .env carrying it)" >&2
  exit 1
fi

echo "== build =="
swift build 2>&1 | grep -E "error:|warning: .*deprecated" | head -20
swift build -q || { echo "FAIL: build" >&2; exit 1; }

echo
echo "== stage 1/2 · collect =="
ARGS=(run orbit-evals measure --live --runs "$K" --concurrency "$CONCURRENCY")
[ -n "$LABEL" ] && ARGS+=(--out "$LABEL")
swift "${ARGS[@]}" || echo "!! collection reported failures — continuing to grade what landed"

# Newest collection, unless one was named.
if [ -z "$LABEL" ]; then
  LABEL="$(ls -1t docs/evals/runs 2>/dev/null | head -1)"
fi
if [ -z "$LABEL" ] || [ ! -d "docs/evals/runs/$LABEL" ]; then
  echo "FAIL: no collection to grade" >&2
  exit 1
fi

echo
echo "== stage 2/2 · grade + aggregate =="
python3 scripts/dev/aggregate.py "docs/evals/runs/$LABEL" --roundtrip

echo
echo "report: docs/evals/runs/$LABEL/aggregate.md"
