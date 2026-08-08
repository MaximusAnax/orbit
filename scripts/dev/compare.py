#!/usr/bin/env python3
"""Paired comparison of two k-run collections — MEASUREMENT-REWORK finding B4.

    python3 scripts/dev/compare.py <collection-a> <collection-b>

Every prompt comparison in this project until now has been two point estimates
held up next to each other, which is the least sensitive design available and
the reason v3 through v6 "improved" nothing measurable: recall spans 11 points
across identical configurations, so any single-run difference smaller than that
is noise wearing a number.

Pairing fixes it. The same 89 required items run under both prompts, so each item
is its own control — the question stops being "is B's average higher" and becomes
"which items changed, and did more improve than regressed". Item-level noise
cancels; only the differences carry signal.

Reports:
  * recall and criticals as distributions, both sides
  * per-item hit-rate deltas, with a sign test over items that moved
  * per-check round-trip stability, both sides
  * a targeted section for the defect the new prompt was written to fix

A sign test is deliberately modest. It assumes only that, under the null, an
item is equally likely to move either way — no normality, no independence
between runs of the same item. With ~89 items it is weak but honest, which is
the right trade when the alternative has been eyeballing two numbers.
"""
import importlib.util
import json
import math
import pathlib
import statistics as st
import sys
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[2]


def load_measure():
    spec = importlib.util.spec_from_file_location("measure", ROOT / "scripts/dev/measure.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def grade_collection(path, measure, goldens):
    """Per-item hit counts and per-run totals for one collection."""
    runs = sorted(d for d in path.iterdir() if d.is_dir() and d.name.startswith("run-"))
    hits, seen = defaultdict(int), defaultdict(int)
    recalls, crits = [], []
    for rd in runs:
        measure.FIX = rd
        rh = rt = rc = 0
        for memo, g in goldens.items():
            f = rd / f"{memo}.json"
            if not f.exists():
                continue
            gr = measure.Grader(memo, g, json.loads(f.read_text()))
            gr.grade()
            rh += gr.required_hit; rt += gr.required_total; rc += len(gr.criticals)
            for lab in gr.hits:
                hits[f"{memo}:{lab}"] += 1; seen[f"{memo}:{lab}"] += 1
            for lab in gr.misses:
                hits.setdefault(f"{memo}:{lab}", 0); seen[f"{memo}:{lab}"] += 1
        if rt:
            recalls.append(rh / rt); crits.append(rc)
    return {"hits": hits, "seen": seen, "recalls": recalls,
            "crits": crits, "runs": len(runs)}


def sign_test(up, down):
    """Two-sided exact binomial p for `up` successes in `up+down` at p=0.5."""
    n = up + down
    if n == 0:
        return 1.0
    k = min(up, down)
    tail = sum(math.comb(n, i) for i in range(k + 1)) / (2 ** n)
    return min(1.0, 2 * tail)


def residence_claims(path):
    """The FN-40 defect, counted directly: residence assertions per run."""
    out = []
    for rd in sorted(d for d in path.iterdir() if d.is_dir() and d.name.startswith("run-")):
        n = 0
        for f in rd.glob("*.json"):
            try:
                p = json.loads(f.read_text())["payload"]
            except Exception:
                continue
            n += sum(1 for a in p.get("assertions") or []
                     if a.get("predicate") == "location"
                     and str(a.get("object_value") or "").lower() == "residence")
        out.append(n)
    return out


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    a_path, b_path = (ROOT / p if not pathlib.Path(p).is_absolute() else pathlib.Path(p)
                      for p in sys.argv[1:3])
    measure = load_measure()
    goldens = measure.load_goldens()
    A = grade_collection(a_path, measure, goldens)
    B = grade_collection(b_path, measure, goldens)

    def spread(v, pct=False):
        if not v:
            return "—"
        f = (lambda x: f"{x:.1%}") if pct else (lambda x: f"{x:g}")
        return f"{f(st.median(v))}  ({f(min(v))}–{f(max(v))})"

    print(f"# Paired comparison — {a_path.name} vs {b_path.name}\n")
    print(f"| | {a_path.name} | {b_path.name} |")
    print("| --- | --- | --- |")
    print(f"| runs | {A['runs']} | {B['runs']} |")
    print(f"| recall, median (min–max) | {spread(A['recalls'], True)} | {spread(B['recalls'], True)} |")
    print(f"| criticals, median (min–max) | {spread(A['crits'])} | {spread(B['crits'])} |")

    # --- paired per item -----------------------------------------------------
    shared = [k for k in A["seen"] if k in B["seen"] and A["seen"][k] and B["seen"][k]]
    up = down = same = 0
    moves = []
    for k in shared:
        ra = A["hits"][k] / A["seen"][k]
        rb = B["hits"][k] / B["seen"][k]
        if rb > ra:
            up += 1
        elif rb < ra:
            down += 1
        else:
            same += 1
        if ra != rb:
            moves.append((rb - ra, k, ra, rb))
    p = sign_test(up, down)

    print(f"\n## Paired item-level change ({len(shared)} required items)\n")
    print(f"- improved: **{up}**")
    print(f"- regressed: **{down}**")
    print(f"- unchanged: {same}")
    print(f"- sign test over the {up+down} that moved: **p = {p:.3f}**"
          + ("  — the difference is not distinguishable from noise"
             if p > 0.05 else "  — unlikely to be noise"))

    moves.sort()
    if moves:
        print("\n| Δ | required item | A | B |")
        print("| --- | --- | --- | --- |")
        for d, k, ra, rb in (moves[:10] + moves[-10:] if len(moves) > 20 else moves):
            print(f"| {d:+.0%} | `{k[:56]}` | {ra:.0%} | {rb:.0%} |")

    # --- the targeted defect -------------------------------------------------
    ra, rb = residence_claims(a_path), residence_claims(b_path)
    print(f"\n## FN-40: `location = residence` assertions per run\n")
    print(f"- {a_path.name}: {spread(ra)}  · total {sum(ra)}")
    print(f"- {b_path.name}: {spread(rb)}  · total {sum(rb)}")
    if ra and rb:
        delta = st.median(rb) - st.median(ra)
        print(f"\nMedian change: **{delta:+g} per run**. This counts every "
              "residence claim, right or wrong — a drop is only good if the "
              "correct ones survived, so read it beside the recall table above "
              "rather than on its own.")


if __name__ == "__main__":
    main()
