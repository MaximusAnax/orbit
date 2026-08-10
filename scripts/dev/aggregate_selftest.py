#!/usr/bin/env python3
"""Self-test for the grading half of `scripts/dev/overnight.sh`.

The overnight job has two stages: collect (Swift, needs an API key and money)
and grade (Python, needs neither). Only the first is expensive, and only the
second was unreachable from CI — so a defect in the grader could sit undetected
until it surfaced at the end of a paid ten-run collection, which is the worst
possible moment to find out.

This builds a synthetic collection from the canonical fixtures, runs
`aggregate.py` over it, and asserts the invariants that are easy to break and
silent when broken. It costs nothing and needs no toolchain, so it belongs in
the gate.

The deliberate gaps are the point. A missing fixture is the case the aggregator
exists to handle correctly: skipping one changes `required_total` between runs
of an identical configuration, which mixes collection holes into what is
supposed to be model variance.
"""
import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "docs/evals/fixtures"

# run -> memo deliberately withheld from it.
#   run-02 drops an ordinary memo.
#   run-03 drops the `expect_empty` golden, where an absent fixture is an empty
#          payload, and an empty payload is exactly what that golden wants — so
#          a hole there scores as a *pass* unless it is special-cased.
GAPS = {1: None, 2: "nikos", 3: "silence"}


def build(collection: pathlib.Path) -> list[str]:
    memos = sorted(p for p in FIXTURES.glob("*.json"))
    if not memos:
        sys.exit("FAIL: no canonical fixtures to synthesize from")
    for index, dropped in GAPS.items():
        run_dir = collection / f"run-{index:02d}"
        run_dir.mkdir(parents=True)
        for memo in memos:
            if memo.stem == dropped:
                continue
            payload = json.loads(memo.read_text())
            payload["run_index"] = index
            payload.setdefault("model_id", "selftest")
            payload.setdefault("prompt_version", "v0")
            payload["telemetry"] = {"totalTokens": 1000, "latencySeconds": 1.0}
            (run_dir / memo.name).write_text(json.dumps(payload, sort_keys=True))
    (collection / "manifest.json").write_text(json.dumps({
        "label": "selftest", "model": "selftest", "prompt_version": "v0",
        "runs": len(GAPS), "memos": [m.stem for m in memos], "git_sha": "selftest",
        "collected_at": "2026-01-01T00:00:00Z",
        "last_collected_at": "2026-01-01T00:00:00Z",
        "total_tokens": 1000 * len(GAPS), "total_seconds": 1.0 * len(GAPS),
        "failures": [],
    }, sort_keys=True))
    return [m.stem for m in memos]


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        collection = pathlib.Path(tmp) / "selftest"
        build(collection)

        # No --roundtrip: that stage shells out to the Swift binary, which is
        # the half this self-test deliberately does not depend on.
        proc = subprocess.run(
            [sys.executable, str(ROOT / "scripts/dev/aggregate.py"), str(collection)],
            capture_output=True, text=True)
        if proc.returncode != 0:
            print(proc.stdout)
            print(proc.stderr, file=sys.stderr)
            print("FAIL: aggregate.py exited non-zero on a well-formed collection")
            return 1

        report = (collection / "aggregate.md").read_text()
        data = json.loads((collection / "aggregate.json").read_text())
        runs = {r["name"]: r for r in data["runs"]}
        failures = []

        if len(runs) != len(GAPS):
            failures.append(f"graded {len(runs)} runs, expected {len(GAPS)}")

        complete, gapped = runs.get("run-01"), [runs.get("run-02"), runs.get("run-03")]
        if complete is None or any(r is None for r in gapped):
            print("FAIL: aggregate.json is missing runs")
            return 1

        # The invariant the aggregator exists for: a hole is scored, never
        # skipped, so the denominator is identical across runs and the spread
        # measures the model rather than the collection.
        for run in gapped:
            if run["required_total"] != complete["required_total"]:
                failures.append(
                    f"{run['name']} required_total {run['required_total']} != "
                    f"run-01 {complete['required_total']} — a gap changed the denominator")
            if run["recall"] >= complete["recall"]:
                failures.append(
                    f"{run['name']} recall {run['recall']:.3f} is not below the complete "
                    f"run's {complete['recall']:.3f} — the gap scored as a pass")
            if "collection gap" not in run["by_check"]:
                failures.append(f"{run['name']} did not raise a collection-gap critical")

        for run, memo in (("run-02", "nikos"), ("run-03", "silence")):
            if memo not in runs[run]["missing"]:
                failures.append(f"{run} did not report {memo} as missing")

        for marker in ("Distribution, not a point", "missing fixture"):
            if marker not in report:
                failures.append(f"report is missing the {marker!r} section")

        if failures:
            print("FAIL: grading stage self-test")
            for f in failures:
                print(f"  - {f}")
            return 1

    print(f"aggregate.py self-test: {len(GAPS)} synthetic runs graded, "
          "gaps scored as zero recall with the denominator held fixed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
