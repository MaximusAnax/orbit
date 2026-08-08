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
echo "== stage 2/3 · grade + aggregate =="
python3 scripts/dev/aggregate.py "docs/evals/runs/$LABEL" --roundtrip

echo
echo "== stage 3/3 · precision =="
# Stage A only by default: free, deterministic, and it is the half that does not
# need a judge nobody has audited yet. ORBIT_JUDGE=1 adds the semantic pass.
if [ "${ORBIT_JUDGE:-0}" = "1" ]; then
  python3 scripts/dev/adjudicate.py "docs/evals/runs/$LABEL" --judge --workers 8 --sample 40 \
    > "docs/evals/runs/$LABEL/precision.md" && tail -12 "docs/evals/runs/$LABEL/precision.md"
  python3 scripts/dev/judge_audit.py build "docs/evals/runs/$LABEL" --n 40
else
  python3 scripts/dev/adjudicate.py "docs/evals/runs/$LABEL" \
    > "docs/evals/runs/$LABEL/precision.md" && head -10 "docs/evals/runs/$LABEL/precision.md"
fi

echo
echo "reports in docs/evals/runs/$LABEL/ :  aggregate.md  precision.md"
PREV="$(ls -1t docs/evals/runs | grep -v "^$LABEL$" | head -1)"
if [ -n "$PREV" ]; then
  echo
  echo "compare against the previous collection (paired, the only sound A/B):"
  echo "  python3 scripts/dev/compare.py docs/evals/runs/$PREV docs/evals/runs/$LABEL"
fi
