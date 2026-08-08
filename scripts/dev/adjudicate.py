#!/usr/bin/env python3
"""True extraction precision — MEASUREMENT-REWORK Phase 2, finding A1.

    python3 scripts/dev/adjudicate.py <fixtures-dir> [--judge] [--sample N]

EVALS defines PIPE-4 as *"extraction precision (no invented facts) ◊ ≥ 97%"* — a
rate. `measure.py` implements it as a count of hits against a hand-enumerated
`forbidden:` list in each golden. That has no denominator and never looks at the
emitted facts, so **only inventions somebody predicted in advance are
detectable**. An invented fact nobody anticipated is not scored badly; it is not
scored at all. For a product whose central promise is that it does not invent,
that is the most important metric in the framework going unmeasured.

This computes the rate. Every claim the model emitted is adjudicated for support
against its own transcript:

  precision = supported claims / all emitted claims

Two stages, in the order EVALS §3.5 prescribes — mechanical where the property is
mechanical, judged only for the semantic residue:

  Stage A (free, deterministic, always runs)
      Structural unsupport: a subject that resolves to nobody, a verbatim that
      is not a contiguous slice of the transcript, a hedge dropped from a hedged
      sentence. These need no judgment and cost nothing.

  Stage B (--judge, costs API)
      Everything Stage A cannot settle. Prompted adversarially — the judge is
      told to REFUTE and to default to unsupported when uncertain — per §3.5's
      judge-governance rule that critical judged metrics use refutation rather
      than agreement.

Honest limitations, stated because a precision number is worthless without them:

  * **The judge is the same model family as the extractor.** Orbit now runs a
    single provider (BUILD §1.3), so a cross-family judge is not available. A
    model grading its own output is a real bias and the adversarial prompt only
    dampens it. Treat Stage B as an upper bound on precision.
  * **The judge is unvalidated until it is checked against Abdoul.** Use
    `--sample N` to dump N adjudications for human review. Until that agreement
    number exists, this reports a measurement, not a ratified one.

Verdicts are cached by (transcript, claim, judge model, prompt version), so
re-running is free and a grader change re-scores collected runs without
re-billing — the same collection/grading split the k-run harness is built on.
"""
import hashlib
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
CACHE = ROOT / "docs/evals/judge-cache"
JUDGE_PROMPT_VERSION = "j1"
JUDGE_MODEL = os.environ.get("ORBIT_JUDGE_MODEL", "gpt-5.1")

# Deliberately conservative. The first run of this file flagged "reserved with
# strangers" as a dropped hedge because the quote contained the word "around" —
# in "around people that he doesn't know", where it is a preposition, not a
# hedge. A mechanical check is reported as definitive, so it may only contain
# markers that cannot mean anything else. Context-dependent ones ("around",
# "or so", "something like") are the judge's problem, not Stage A's.
HEDGES = ["i think", "i believe", "i want to say", "i'd say", "i'm not sure",
          "pretty sure", "if i remember", "i forget", "maybe", "probably"]

JUDGE_SYSTEM = """You audit fact-extraction for a personal-memory product whose \
first promise is that it never invents.

You will be given a transcript and ONE extracted claim. Decide whether the \
transcript SUPPORTS that exact claim.

Your job is to REFUTE. Look for the ways the claim overreaches:
- says more than the speaker said, or states as fact what was hedged
- attributes to the wrong person, or turns hearsay into firsthand
- converts a wish, plan or joke into a fact
- imports outside knowledge the transcript does not contain
- changes the meaning of the relation ("wants to move to Atlanta" is NOT \
"lives in Atlanta"; "interned at" is NOT "works at")

A claim is supported ONLY if a careful reader of this transcript alone would \
agree it is exactly what was said. Paraphrase is fine; added meaning is not.

If you are uncertain, answer unsupported. Reply with JSON only:
{"supported": true|false, "why": "<12 words or fewer>"}"""


def sha(*parts):
    return hashlib.sha256("||".join(parts).encode()).hexdigest()[:32]


def claims_of(payload):
    """Every claim-bearing item the model emitted, flattened for adjudication."""
    out = []
    for a in payload.get("assertions") or []:
        subject = a.get("subject_ref")
        obj = a.get("object_value") or a.get("object_entity_ref") or a.get("object_person_ref")
        out.append({
            "kind": "assertion",
            "text": f"{subject} — {a.get('predicate')} — {obj}",
            "verbatim": a.get("verbatim") or "",
            "subject_ref": subject,
            "hedged": bool(a.get("hedged")),
            "raw": a,
        })
    for e in payload.get("episodes") or []:
        out.append({
            "kind": "episode",
            "text": f"episode: {e.get('title')} ({e.get('occurred_at')})",
            "verbatim": e.get("narrative") or "",
            "subject_ref": None, "hedged": False, "raw": e,
        })
    for s in payload.get("state_declarations") or []:
        out.append({
            "kind": "state_declaration",
            "text": f"state: {s.get('state')}",
            "verbatim": s.get("quote") or "",
            "subject_ref": s.get("person_ref"), "hedged": False, "raw": s,
        })
    return out


def stage_a(claim, source, people):
    """Mechanical support. Returns (verdict, reason) or (None, None) if undecided.

    Only *definite* unsupport is decided here. Everything else is deferred —
    a mechanical check that guesses is worse than one that abstains.
    """
    ref = claim["subject_ref"]
    if ref and ref != "self" and ref not in people:
        return False, f"subject_ref {ref!r} resolves to nobody in the payload"
    v = claim["verbatim"]
    if not v:
        return False, "no verbatim — nothing anchors this claim to the transcript"
    if v not in source:
        return False, "verbatim is not a contiguous slice of the transcript"
    low = v.lower()
    if not claim["hedged"] and claim["kind"] == "assertion":
        hit = next((h for h in HEDGES if h in low), None)
        if hit:
            return False, f"hedge {hit!r} in the quote but hedged=false"
    return None, None


def judge(claim, source, cache_only=False):
    key = sha(sha(source), json.dumps(claim["raw"], sort_keys=True),
              JUDGE_MODEL, JUDGE_PROMPT_VERSION)
    CACHE.mkdir(parents=True, exist_ok=True)
    hit = CACHE / f"{key}.json"
    if hit.exists():
        return json.loads(hit.read_text())
    if cache_only:
        return None
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        return None
    body = {
        "model": JUDGE_MODEL,
        "messages": [
            {"role": "system", "content": JUDGE_SYSTEM},
            {"role": "user", "content":
             f"TRANSCRIPT:\n<<<\n{source}\n>>>\n\nCLAIM:\n{claim['text']}\n"
             f"QUOTED AS:\n{claim['verbatim']}"},
        ],
        "response_format": {"type": "json_object"},
        "seed": 20260807,
    }
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {api_key}"})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            text = json.loads(r.read())["choices"][0]["message"]["content"]
        verdict = json.loads(text)
    except (urllib.error.URLError, KeyError, json.JSONDecodeError, TimeoutError) as e:
        return {"supported": None, "why": f"judge unavailable: {type(e).__name__}"}
    hit.write_text(json.dumps(verdict))
    return verdict


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    fixtures = pathlib.Path(sys.argv[1])
    if not fixtures.is_absolute():
        fixtures = ROOT / fixtures
    use_judge = "--judge" in sys.argv
    sample_n = 0
    if "--sample" in sys.argv:
        i = sys.argv.index("--sample")
        sample_n = int(sys.argv[i + 1]) if len(sys.argv) > i + 1 else 20

    total = 0
    unsupported = []
    undecided = 0
    sample = []

    for f in sorted(fixtures.glob("*.json")):
        fixture = json.loads(f.read_text())
        if "payload" not in fixture:
            continue
        source = (ROOT / fixture["source"]).read_text()
        payload = fixture["payload"]
        people = {p["ref"] for p in payload.get("people") or []}
        for claim in claims_of(payload):
            total += 1
            verdict, reason = stage_a(claim, source, people)
            if verdict is False:
                unsupported.append((f.stem, claim, reason, "mechanical"))
                continue
            if use_judge:
                v = judge(claim, source)
                if v is None or v.get("supported") is None:
                    undecided += 1
                elif not v.get("supported"):
                    unsupported.append((f.stem, claim, v.get("why", ""), "judge"))
                if len(sample) < sample_n:
                    sample.append({"memo": f.stem, "claim": claim["text"],
                                   "verbatim": claim["verbatim"][:160],
                                   "judge": v})
            else:
                undecided += 1

    # Stage A abstains rather than approves, so "undecided" is not the same as
    # "unmeasured": every claim WAS checked structurally and survived. Dividing
    # by only the decided claims turns 1 mechanical catch out of 80 into
    # "precision 0.0%", which is arithmetically true and grossly misleading —
    # the first run of this file printed exactly that. The denominator is every
    # claim emitted; what changes with --judge is how much of the semantic
    # question has been asked.
    precision = (total - len(unsupported)) / total if total else 0.0

    print(f"# PIPE-4 precision — {fixtures.name}\n")
    print(f"claims emitted            : {total}")
    print(f"structurally unsupported  : {sum(1 for u in unsupported if u[3] == 'mechanical')}")
    if use_judge:
        print(f"judged unsupported        : {sum(1 for u in unsupported if u[3] == 'judge')}")
        print(f"judge unavailable         : {undecided}")
    print(f"\n**precision = {precision:.1%}**   (EVALS PIPE-4 target ◊ ≥ 97%)")
    if not use_judge:
        print(f"\n⚠️  Stage A only — a CEILING, not the measurement. {total - len(unsupported)} "
              "claims passed the structural checks (resolvable subject, real "
              "quote, hedge intact) and were never asked the semantic question: "
              "*does the transcript actually support this?* Run with --judge.")
    else:
        print(f"\nJudge: {JUDGE_MODEL} / prompt {JUDGE_PROMPT_VERSION}, adversarial. "
              "Same model family as the extractor, so treat this as an upper "
              "bound until validated against Abdoul (--sample N).")

    if unsupported:
        print(f"\n## Unsupported claims ({len(unsupported)})\n")
        for memo, claim, reason, how in unsupported[:40]:
            print(f"- **{memo}** [{how}] `{claim['text'][:70]}`")
            print(f"    → {reason}")

    if sample:
        out = fixtures / "judge-sample.json"
        out.write_text(json.dumps(sample, indent=2))
        print(f"\n{len(sample)} adjudications written for human review: {out}")
        print("A judge nobody has checked is an opinion with a percentage sign.")


if __name__ == "__main__":
    main()
