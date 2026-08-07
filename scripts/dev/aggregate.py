#!/usr/bin/env python3
"""Aggregate k collected runs into a distribution — MEASUREMENT-REWORK Phase 1.

    python3 scripts/dev/aggregate.py docs/evals/runs/<label> [--runtrip]

Grades every run in a collection independently, then reports what one run
cannot: the spread, and which checks are stable enough to gate on.

The point is FN-37. Two consecutive runs of the identical prompt scored 7/10 and
9/10 on the round-trip, with criticals at 32 and 14. A point estimate from a
stochastic system is not a measurement, and a CI gate built on a check that
flickers is a lottery — which is how a team learns to ignore its own CI.

Per EVALS §3.5 / PIPE-15, an item's flicker rate is not merely an error bar: it
is the uncertainty signal the product is supposed to consume. An item appearing
in fewer than 70% of runs should be arriving hedged or as a DISAMBIGUATE, and
this report is what makes that claim testable for the first time.
"""
import json
import pathlib
import statistics
import subprocess
import sys
import importlib.util

ROOT = pathlib.Path(__file__).resolve().parents[2]
STABLE = 0.70          # PIPE-15's provisional flicker boundary


def load_grader():
    spec = importlib.util.spec_from_file_location("measure", ROOT / "scripts/dev/measure.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def pct(x):
    return f"{x:.0%}"


def classify(rate):
    if rate >= 1.0:
        return "stable-pass"
    if rate <= 0.0:
        return "stable-fail"
    return "FLICKER"


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    coll = pathlib.Path(sys.argv[1])
    if not coll.is_absolute():
        coll = ROOT / coll
    manifest = json.loads((coll / "manifest.json").read_text())
    run_dirs = sorted(d for d in coll.iterdir() if d.is_dir() and d.name.startswith("run-"))
    if not run_dirs:
        sys.exit(f"no run-* directories in {coll}")

    m = load_grader()
    goldens = m.load_goldens()

    # ---- grade every run independently -------------------------------------
    per_run = []                      # one dict per run
    item_hits = {}                    # required-item label -> runs where it hit
    item_seen = {}                    # required-item label -> runs where it was checked
    for rd in run_dirs:
        m.FIX = rd
        run = {"name": rd.name, "required_hit": 0, "required_total": 0,
               "criticals": 0, "by_check": {}}
        for memo, golden in goldens.items():
            f = rd / f"{memo}.json"
            if not f.exists():
                continue                      # a hole in the distribution; counted below
            g = m.Grader(memo, golden, json.loads(f.read_text()))
            g.grade()
            run["required_hit"] += g.required_hit
            run["required_total"] += g.required_total
            run["criticals"] += len(g.criticals)
            for label in g.hits:
                key = f"{memo}:{label}"
                item_hits[key] = item_hits.get(key, 0) + 1
                item_seen[key] = item_seen.get(key, 0) + 1
            for label in g.misses:
                key = f"{memo}:{label}"
                item_hits.setdefault(key, 0)
                item_seen[key] = item_seen.get(key, 0) + 1
            for cid, _ in g.criticals:
                run["by_check"][cid] = run["by_check"].get(cid, 0) + 1
        run["recall"] = (run["required_hit"] / run["required_total"]
                         if run["required_total"] else 0.0)
        per_run.append(run)

    # ---- round-trip per run (optional; needs a build) ----------------------
    roundtrip = []
    if "--roundtrip" in sys.argv:
        for rd in run_dirs:
            rel = rd.relative_to(ROOT)
            out = subprocess.run(
                ["swift", "run", "orbit-evals", "measure", "--replay", "--fixtures", str(rel)],
                cwd=ROOT, capture_output=True, text=True).stdout
            line = [l for l in out.splitlines() if l.startswith("round-trip:")]
            roundtrip.append(line[-1] if line else "round-trip: (not reported)")

    # ---- report -------------------------------------------------------------
    recalls = [r["recall"] for r in per_run]
    crits = [r["criticals"] for r in per_run]
    n = len(per_run)

    def spread(vals, fmt=lambda v: f"{v}"):
        if not vals:
            return "—"
        if len(vals) == 1:
            return fmt(vals[0])
        return (f"median {fmt(statistics.median(vals))} · "
                f"min {fmt(min(vals))} · max {fmt(max(vals))}")

    L = []
    L.append(f"# Aggregate — {manifest.get('label', coll.name)}")
    L.append("")
    L.append(f"**{n} runs** · model `{manifest.get('model')}` · prompt "
             f"`{manifest.get('prompt_version')}` · git `{manifest.get('git_sha')}`  ")
    L.append(f"collected {manifest.get('collected_at')} · "
             f"{manifest.get('total_tokens', 0):,} tokens · "
             f"{manifest.get('total_seconds', 0):.0f}s model time")
    if manifest.get("failures"):
        L.append("")
        L.append(f"⚠️ **{len(manifest['failures'])} extraction failure(s)** — the "
                 "distribution has holes; treat every number below as a floor.")
    L.append("")
    L.append("## Distribution, not a point")
    L.append("")
    L.append("| Metric | Spread across runs |")
    L.append("| --- | --- |")
    L.append(f"| PIPE-3 required-item recall | {spread(recalls, pct)} |")
    L.append(f"| PIPE-4-class criticals | {spread(crits)} |")
    if roundtrip:
        passes = []
        for rt in roundtrip:
            try:
                passes.append(int(rt.split("round-trip:")[1].split("passed")[0].strip()))
            except (IndexError, ValueError):
                pass
        if passes:
            L.append(f"| round-trip checks passed | {spread(passes)} |")
        L.append("")
        L.append("Round-trip, run by run: "
                 + " · ".join(f"{run_dirs[i].name} {rt.replace('round-trip: ', '')}"
                              for i, rt in enumerate(roundtrip)))
    if len(recalls) > 1:
        band = max(recalls) - min(recalls)
        L.append("")
        L.append(f"Recall spans **{band:.1%}** between the best and worst run of an "
                 "identical configuration. Any prompt comparison smaller than that "
                 "band is noise.")

    # ---- per-item flicker (the PIPE-15 input) -------------------------------
    rates = {k: item_hits[k] / item_seen[k] for k in item_seen if item_seen[k]}
    flickering = sorted([(r, k) for k, r in rates.items() if 0 < r < 1.0])
    stable_pass = [k for k, r in rates.items() if r >= 1.0]
    stable_fail = [k for k, r in rates.items() if r <= 0.0]

    L.append("")
    L.append("## Per-item stability")
    L.append("")
    L.append(f"- **{len(stable_pass)}** always extracted (stable core)")
    L.append(f"- **{len(stable_fail)}** never extracted (stable miss — a real gap)")
    L.append(f"- **{len(flickering)}** flicker between runs")
    if flickering:
        L.append("")
        L.append("Only the stable rows can carry a gate. The flickering ones are "
                 "PIPE-15's actual subject: below the 70% line, the product is "
                 "supposed to hedge or ask rather than assert.")
        L.append("")
        L.append("| Required item | Hit rate | Under PIPE-15 |")
        L.append("| --- | --- | --- |")
        for r, k in flickering:
            verdict = "must hedge / DISAMBIGUATE" if r < STABLE else "stable-core-ish"
            L.append(f"| `{k}` | {pct(r)} | {verdict} |")

    L.append("")
    L.append("## Check stability")
    L.append("")
    L.append("| Check | Runs firing | Classification |")
    L.append("| --- | --- | --- |")
    all_checks = sorted({c for r in per_run for c in r["by_check"]})
    for c in all_checks:
        firing = sum(1 for r in per_run if r["by_check"].get(c))
        L.append(f"| {c} | {firing}/{n} | {classify(1 - firing / n)} |")
    if not all_checks:
        L.append("| — | — | no criticals fired in any run |")

    L.append("")
    L.append("---")
    L.append("")
    L.append("*Grading is separate from collection by design: these runs are on "
             "disk and can be re-graded for free when the grader improves "
             "(MEASUREMENT-REWORK Phase 2). No number here is better than the "
             "grader that produced it — PIPE-4 still counts enumerated forbidden "
             "items rather than measuring precision, and required-fact matching "
             "is still substring plus exact predicate.*")

    report = "\n".join(L) + "\n"
    (coll / "aggregate.md").write_text(report)
    (coll / "aggregate.json").write_text(json.dumps({
        "manifest": manifest,
        "runs": per_run,
        "item_hit_rates": rates,
        "roundtrip": roundtrip,
    }, indent=2, sort_keys=True))
    print(report)
    print(f"written: {coll/'aggregate.md'}  and  {coll/'aggregate.json'}")


if __name__ == "__main__":
    main()
