#!/usr/bin/env python3
"""Semantic required-fact matching — MEASUREMENT-REWORK Phase 2, finding A2.

    python3 scripts/dev/regrade.py <collection-dir> [--workers N] [--runs N]

EVALS §3.5 ratifies contract-based grading: *"a required-facts set (matched
semantically, not verbatim) … Two phrasings of 'Sarah wants to learn videography'
both pass."* `measure.py` matches by lowercased substring **and requires the
predicate to be string-equal**. Those are not the same thing, and the gap is not
small: relaxing only the predicate rule moved assertion recall from 66.7% to
76.9% on a single run.

But a looser matcher is the wrong fix, and this is the whole argument:

    eliah             wanted 'interest'   model said 'life_event'  (basketball)   <- fair
    secondhand-chain  wanted 'goal'       model said 'location'    (atlanta)      <- NOT fair

"Played basketball" as a life event rather than an interest is a taxonomy
quibble. "Wants to move to Atlanta" recorded as *living* in Atlanta is a
different claim about a person's life, and collapsing it is exactly the silent
meaning-drift the constitution exists to prevent. Blind relaxation forgives the
second; the strict matcher punishes the first. Only adjudication separates them.

So: for every required assertion the strict matcher missed, gather the
candidates the model actually produced about that subject and ask whether any of
them *means the same thing*. The judge is told that a related fact is not a
match — near-misses must fail, because the point is to find the grader's false
negatives, not to inflate recall.

Reports strict recall and semantic recall side by side. The difference is the
measurement error the ◊ ≥ 90% target has been sitting on.
"""
import importlib.util
import json
import os
import pathlib
import re
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("adj", ROOT / "scripts/dev/adjudicate.py")
adj = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adj)

MATCH_PROMPT_VERSION = "m3"

SYSTEM = """You grade fact-extraction against a required-facts contract.

You are given a REQUIRED FACT and several CANDIDATE facts a model extracted from \
the same transcript. Decide whether any candidate *records* the required fact.

Judge the CANDIDATE CLAIM — its subject, its category and its object. The quote \
shown beside each candidate is context for what the speaker said; it is NOT the \
claim. A candidate whose quote mentions the required fact while the claim itself \
records something else does NOT match. What gets stored is the claim.

A candidate matches when it means the same thing. Different wording is fine, and \
a different category label is fine WHEN THE CLAIM IS UNCHANGED — "played \
basketball" recorded as a life event rather than an interest is the same fact.

A candidate does NOT match when the category changes what is being asserted:
- required "goal: move to Atlanta" vs candidate "location: residence" — NO. One \
says where someone wants to go, the other says where they live, and the quote \
saying "thinking about moving" does not rescue it: the stored claim is a \
residence.
- required "goal: X" vs candidate "life_event: X" — NO if it asserts X happened \
rather than is wanted.
- "interned at Google" vs "works at Google" — NO.
- a fact about the wrong person, however similar — NO.
- a broader or narrower claim than the required one — NO.

If nothing matches, say so. Defaulting to no-match is correct when unsure.

Reply with JSON only: {"match": <index or null>, "why": "<12 words or fewer>"}"""


def overlap(a, b):
    ta = set(re.findall(r"\w+", (a or "").lower()))
    tb = set(re.findall(r"\w+", (b or "").lower()))
    return len(ta & tb) / max(1, len(ta | tb))


def ask(required, candidates, source):
    key = adj.sha(adj.sha(source), json.dumps(required, sort_keys=True),
                  json.dumps(candidates, sort_keys=True),
                  adj.JUDGE_MODEL, MATCH_PROMPT_VERSION)
    adj.CACHE.mkdir(parents=True, exist_ok=True)
    hit = adj.CACHE / f"m-{key}.json"
    if hit.exists():
        return json.loads(hit.read_text())
    if not os.environ.get("OPENAI_API_KEY"):
        return None
    listing = "\n".join(f"{i}. {c}" for i, c in enumerate(candidates))
    body = {
        "model": adj.JUDGE_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content":
             f"REQUIRED FACT:\n{required['text']}\n\nCANDIDATES:\n{listing}"},
        ],
        "response_format": {"type": "json_object"},
        "seed": 20260807,
    }
    import urllib.request
    import time
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180, context=adj.SSL_CTX) as r:
                out = json.loads(json.loads(r.read())["choices"][0]["message"]["content"])
            hit.write_text(json.dumps(out))
            return out
        except Exception:
            if attempt == 3:
                return None
            time.sleep(2 ** attempt * 1.5)


def main():
    target = pathlib.Path(sys.argv[1])
    if not target.is_absolute():
        target = ROOT / target
    workers = 8
    if "--workers" in sys.argv:
        workers = int(sys.argv[sys.argv.index("--workers") + 1])
    limit = None
    if "--runs" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--runs") + 1])

    mspec = importlib.util.spec_from_file_location("measure", ROOT / "scripts/dev/measure.py")
    measure = importlib.util.module_from_spec(mspec)
    mspec.loader.exec_module(measure)
    goldens = measure.load_goldens()

    runs = sorted(d for d in target.iterdir() if d.is_dir() and d.name.startswith("run-"))
    if limit:
        runs = runs[:limit]

    work = []
    strict_hits = strict_total = 0
    for rd in runs:
        measure.FIX = rd
        for memo, g in goldens.items():
            f = rd / f"{memo}.json"
            if not f.exists():
                continue
            fixture = json.loads(f.read_text())
            gr = measure.Grader(memo, g, fixture)
            source = (ROOT / fixture["source"]).read_text()
            # Resolve refs to names. Showing the judge "education = attended
            # [entity_2]" asks it to grade a string it cannot read — the same
            # defect the precision pass hit at j1.
            names = {e["ref"]: e.get("name_as_heard") or e["ref"]
                     for e in fixture["payload"].get("entities") or []}
            names.update({pp["ref"]: pp.get("name_as_heard") or pp["ref"]
                          for pp in fixture["payload"].get("people") or []})
            for ra in g.get("required_assertions", []):
                subj, pred, cont = ra.get("subject"), ra.get("predicate"), ra.get("contains")
                strict_total += 1
                if gr.find_assertions(subj, pred, cont):
                    strict_hits += 1
                    continue
                # Candidates: everything the model said about this subject.
                cands = gr.find_assertions(subj, None, None)
                scored = sorted(
                    cands,
                    key=lambda a: -overlap(cont, f"{a['predicate']} {a.get('object_value')} {a.get('verbatim')}"))
                top = [f"CLAIM: {a['predicate']} = {a.get('object_value')}"
                       + (f" [{names.get(a.get('object_entity_ref') or a.get('object_person_ref'), a.get('object_entity_ref') or a.get('object_person_ref'))}]"
                          if (a.get('object_entity_ref') or a.get('object_person_ref')) else "")
                       + f"   | supporting quote (context only): \"{(a.get('verbatim') or '')[:90]}\""
                       for a in scored[:5]]
                if not top:
                    continue
                work.append(({"text": f"{subj} — {pred} — {cont}"}, top, source,
                             rd.name, memo, f"{subj}/{pred}/{cont}"))

    print(f"strict recall: {strict_hits}/{strict_total} = {strict_hits/strict_total:.1%}",
          file=sys.stderr)
    print(f"adjudicating {len(work)} strict misses with {workers} workers...", file=sys.stderr)

    recovered = []
    def run_one(item):
        required, top, source, run, memo, label = item
        return item, ask(required, top, source)

    with ThreadPoolExecutor(max_workers=workers) as pool:
        for (required, top, source, run, memo, label), v in pool.map(run_one, work):
            if v and v.get("match") is not None:
                try:
                    idx = int(v["match"])
                except (TypeError, ValueError):
                    continue
                if 0 <= idx < len(top):
                    recovered.append((run, memo, label, top[idx], v.get("why", "")))

    sem_hits = strict_hits + len(recovered)
    print()
    print("# Semantic re-grade — required assertions\n")
    print(f"| | hits | recall |")
    print(f"| --- | --- | --- |")
    print(f"| strict (substring + exact predicate) | {strict_hits}/{strict_total} | "
          f"**{strict_hits/strict_total:.1%}** |")
    print(f"| semantic (adjudicated) | {sem_hits}/{strict_total} | "
          f"**{sem_hits/strict_total:.1%}** |")
    print(f"\nThe gap — **{(sem_hits-strict_hits)/strict_total:.1%}** — is grader "
          "measurement error, not model failure: facts the model extracted "
          "correctly and the substring-plus-exact-predicate matcher could not see.")

    from collections import Counter
    freq = Counter(label for _, _, label, _, _ in recovered)
    if freq:
        print(f"\n## Recovered required facts ({len(recovered)} across {len(runs)} runs)\n")
        print("| runs | required fact | matched by | why |")
        print("| --- | --- | --- | --- |")
        seen = {}
        for run, memo, label, cand, why in recovered:
            seen.setdefault(label, (cand, why))
        for label, n in freq.most_common(30):
            cand, why = seen[label]
            print(f"| {n} | `{label[:44]}` | `{cand[:52]}` | {why[:40]} |")


if __name__ == "__main__":
    main()
