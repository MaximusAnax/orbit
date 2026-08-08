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
import re
import ssl
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

# python.org builds on macOS ship without a usable CA bundle, so every HTTPS
# call raises CERTIFICATE_VERIFY_FAILED. The first judge run hit this and,
# because a failed verdict degraded to "judge unavailable", it kept going and
# would have printed a clean-looking precision number over 873 silent failures.
# Same defect as FN-35: a fallback you cannot distinguish from success.
try:
    import certifi
    SSL_CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    SSL_CTX = ssl.create_default_context()

ROOT = pathlib.Path(__file__).resolve().parents[2]
CACHE = ROOT / "docs/evals/judge-cache"
JUDGE_PROMPT_VERSION = "j4"
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

The transcript is one person talking — the speaker, named in the claim. Facts \
about the speaker are first-person statements ("I was from the Bronx"); do not \
refuse them for lacking a name. Pronouns resolve normally within the excerpt.

A claim is supported ONLY if a careful reader of this transcript alone would \
agree it is exactly what was said. Paraphrase is fine; added meaning is not.

Four things are CORRECT behaviour and must never be refuted:
- **A hedged claim marked "stated tentatively" has recorded the speaker's \
uncertainty properly.** Refuting it for being uncertain is backwards — that flag \
is the system doing its job.
- **Dates derived from era anchors stated in the transcript.** The capture date \
is 2026-07-29. "Started two weeks ago" legitimately becomes a mid-July date, and \
"we're going into our senior year" legitimately dates earlier years. Only refuse \
a date with no basis in the transcript at all.
- **A "we" statement split into one claim per person.** "We both study computer \
science" correctly yields a claim for each of them.
- **Pronoun references resolved using the opening of the transcript**, which \
names who is being discussed even when the excerpt does not repeat the name.

If you are uncertain, answer unsupported. Reply with JSON only:
{"supported": true|false, "why": "<12 words or fewer>"}"""


def sha(*parts):
    return hashlib.sha256("||".join(parts).encode()).hexdigest()[:32]


def claims_of(payload, owner="Abdoul"):
    """Every claim-bearing item the model emitted, rendered for adjudication.

    References are RESOLVED to names first. The j1 pass did not do this and the
    judge was shown claims like `person_3 - life_event - entity_1`, then asked
    whether the transcript supported them. It refuted things like
    "employment = intern" for "lacking the employer" when the assertion carried
    an `object_entity_ref` pointing straight at Google. Those refutations were
    artifacts of the rendering, not findings about the model — the same defect
    as the grader's own blob(), which could not see entity-shaped objects either.
    An unreadable claim is not a claim the judge can grade.
    """
    people = {p["ref"]: p.get("name_as_heard") or p["ref"]
              for p in payload.get("people") or []}
    ents = {e["ref"]: e.get("name_as_heard") or e["ref"]
            for e in payload.get("entities") or []}
    who = lambda ref: f"{owner} (the speaker)" if ref == "self" else people.get(ref, ref)

    out = []
    for a in payload.get("assertions") or []:
        parts = []
        if a.get("object_value"):
            parts.append(str(a["object_value"]))
        if a.get("object_entity_ref"):
            parts.append(f"[{ents.get(a['object_entity_ref'], a['object_entity_ref'])}]")
        if a.get("object_person_ref"):
            parts.append(f"[{who(a['object_person_ref'])}]")
        obj = " ".join(parts) or "(no object)"
        flags = []
        if a.get("hedged"):
            flags.append("stated tentatively")
        if a.get("source_kind") and a["source_kind"] != "firsthand":
            flags.append(f"source: {a['source_kind']}")
        if a.get("valid_from") or a.get("valid_to"):
            flags.append(f"from {a.get('valid_from') or '?'} to {a.get('valid_to') or 'open'}")
        suffix = f"  ({'; '.join(flags)})" if flags else ""
        out.append({
            "kind": "assertion",
            "text": f"{who(a.get('subject_ref'))} — {a.get('predicate')} — {obj}{suffix}",
            "verbatim": a.get("verbatim") or "",
            "subject_ref": a.get("subject_ref"),
            "hedged": bool(a.get("hedged")),
            "raw": a,
        })
    for e in payload.get("episodes") or []:
        out.append({
            "kind": "episode",
            "text": f"episode: {e.get('title')} (occurred {e.get('occurred_at')})",
            "verbatim": e.get("narrative") or "",
            "subject_ref": None, "hedged": False, "raw": e,
        })
    for s_ in payload.get("state_declarations") or []:
        out.append({
            "kind": "state_declaration",
            "text": f"relationship state of {who(s_.get('person_ref'))}: {s_.get('state')}",
            "verbatim": s_.get("quote") or "",
            "subject_ref": s_.get("person_ref"), "hedged": False, "raw": s_,
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
    # Rule 27: an assertion must carry at least one object. Abdoul's audit
    # caught `Maya — concern — (no object)` on the hardship memo — the judge
    # accepted it, and Stage A had no check for it either. An assertion with
    # nothing on the right-hand side asserts nothing, and this one was about the
    # most sensitive fact in the corpus.
    if claim["kind"] == "assertion":
        raw = claim["raw"]
        if not (raw.get("object_value") or raw.get("object_entity_ref")
                or raw.get("object_person_ref")):
            return False, "assertion carries no object at all (rule 27)"
    v = claim["verbatim"]
    if not v:
        return False, "no verbatim — nothing anchors this claim to the transcript"
    if v not in source and not locatable(v, source):
        return False, "quote has no anchor in the transcript, even fuzzily"
    low = v.lower()
    if not claim["hedged"] and claim["kind"] == "assertion":
        hit = next((h for h in HEDGES if h in low), None)
        if hit:
            return False, f"hedge {hit!r} in the quote but hedged=false"
    return None, None


def locatable(quote, source, threshold=0.85):
    """Mirror of Swift `VerbatimSnapper.locate` — would production find this?"""
    def toks(t):
        return [w for w in re.findall(r"[\w']+", t.lower()) if w]
    q, srcs = toks(quote), toks(source)
    if not q or not srcs or len(q) > 400:
        return False
    anchors = set(q[:3])
    starts = [i for i, w in enumerate(srcs) if w in anchors] or range(len(srcs))
    for start in starts:
        for span in (len(q), int(len(q) * 1.25) + 1):
            win = srcs[start:min(start + span, len(srcs))]
            if not win:
                continue
            # LCS length
            prev = [0] * (len(win) + 1)
            for x in q:
                cur = [0] * (len(win) + 1)
                for j, y in enumerate(win):
                    cur[j + 1] = prev[j] + 1 if x == y else max(prev[j + 1], cur[j])
                prev = cur
            if prev[len(win)] / max(len(q), len(win)) >= threshold:
                return True
    return False


def window(source, quote, radius=700):
    """The transcript around the quote, not the whole thing.

    Sending a 1,847-word portrait with each of its ~100 claims would cost about
    3M tokens for one pass. The support for a claim lives next to the sentence
    it came from, so a window is both cheaper and a sharper question. Falls back
    to the whole transcript when it is short or the quote cannot be located.
    """
    if len(source) <= 2 * radius or not quote:
        return source, False
    i = source.find(quote[:60])
    if i < 0:
        return source, False
    lo, hi = max(0, i - radius), min(len(source), i + len(quote) + radius)
    head = source[:500]
    body = ("..." if lo else "") + source[lo:hi] + ("..." if hi < len(source) else "")
    if lo > 500:
        return f"OPENING OF THE TRANSCRIPT (who is being discussed):\n{head}...\n\nEXCERPT:\n{body}", True
    return body, True


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
    ctx, windowed = window(source, claim["verbatim"])
    body = {
        "model": JUDGE_MODEL,
        "messages": [
            {"role": "system", "content": JUDGE_SYSTEM},
            {"role": "user", "content":
             ("TRANSCRIPT EXCERPT (the claim came from here):"
              if windowed else "TRANSCRIPT:")
             + f"\n<<<\n{ctx}\n>>>\n\nCLAIM:\n{claim['text']}\n"
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
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180, context=SSL_CTX) as r:
                text = json.loads(r.read())["choices"][0]["message"]["content"]
            verdict = json.loads(text)
            break
        except (urllib.error.URLError, KeyError, json.JSONDecodeError,
                TimeoutError, OSError) as e:
            if attempt == 3:
                return {"supported": None, "why": f"judge unavailable: {type(e).__name__}"}
            time.sleep(2 ** attempt * 1.5)
    hit.write_text(json.dumps(verdict))
    return verdict


def fixture_files(target):
    """Every fixture under `target` — a plain fixtures dir, or a whole k-run
    collection with run-* subdirectories."""
    runs = sorted(d for d in target.iterdir() if d.is_dir() and d.name.startswith("run-"))
    if runs:
        return [(d.name, f) for d in runs for f in sorted(d.glob("*.json"))]
    return [(target.name, f) for f in sorted(target.glob("*.json"))]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    target = pathlib.Path(sys.argv[1])
    if not target.is_absolute():
        target = ROOT / target
    use_judge = "--judge" in sys.argv
    workers = 6
    if "--workers" in sys.argv:
        workers = int(sys.argv[sys.argv.index("--workers") + 1])
    sample_n = 0
    if "--sample" in sys.argv:
        i = sys.argv.index("--sample")
        sample_n = int(sys.argv[i + 1]) if len(sys.argv) > i + 1 else 20

    total = 0
    unsupported = []
    pending = []          # survived Stage A; needs the judge
    per_run = {}          # run -> [total, unsupported]

    for run, f in fixture_files(target):
        try:
            fixture = json.loads(f.read_text())
        except json.JSONDecodeError:
            continue
        if "payload" not in fixture:
            continue
        source = (ROOT / fixture["source"]).read_text()
        people = {p["ref"] for p in fixture["payload"].get("people") or []}
        per_run.setdefault(run, [0, 0])
        for claim in claims_of(fixture["payload"]):
            total += 1
            per_run[run][0] += 1
            verdict, reason = stage_a(claim, source, people)
            if verdict is False:
                unsupported.append((run, f.stem, claim, reason, "mechanical"))
                per_run[run][1] += 1
            else:
                pending.append((run, f.stem, claim, source))

    undecided = len(pending)
    sample = []
    if use_judge and pending:
        print(f"judging {len(pending)} claims with {workers} workers "
              f"({JUDGE_MODEL}, cached)...", file=sys.stderr)
        def work(item):
            run, memo, claim, source = item
            return item, judge(claim, source)

        # Fail fast rather than reporting a number built on nothing: if the
        # first handful cannot reach the judge, the run is broken, not strict.
        probe = [judge(c, s_) for _, _, c, s_ in pending[:3]]
        if all(p is None or p.get("supported") is None for p in probe):
            why = next((p.get("why") for p in probe if p), "no response")
            sys.exit(f"FAIL: judge unreachable ({why}). Refusing to report a "
                     f"precision number that would be built on silent failures.")
        done = 0
        with ThreadPoolExecutor(max_workers=workers) as pool:
            for (run, memo, claim, source), v in pool.map(work, pending):
                done += 1
                if done % 100 == 0:
                    print(f"  {done}/{len(pending)}", file=sys.stderr)
                if v is None or v.get("supported") is None:
                    continue                      # stays undecided
                undecided -= 1
                if not v.get("supported"):
                    unsupported.append((run, memo, claim, v.get("why", ""), "judge"))
                    per_run[run][1] += 1
                # Sample REFUTATIONS, spread across memos — the j4 sample was
                # first-30-completed, so it filled with dom and eliah and caught
                # the pedantic tail while missing every strong catch. A review
                # sample that is not representative cannot validate anything.
                if sample_n and not v.get("supported"):
                    sample.append({"memo": memo, "claim": claim["text"],
                                   "verbatim": claim["verbatim"][:160], "judge": v})

    precision = (total - len(unsupported)) / total if total else 0.0
    mech = sum(1 for u in unsupported if u[4] == "mechanical")
    judged = sum(1 for u in unsupported if u[4] == "judge")

    print(f"# PIPE-4 precision — {target.name}\n")
    print(f"claims emitted            : {total}")
    print(f"structurally unsupported  : {mech}")
    if use_judge:
        print(f"judged unsupported        : {judged}")
        print(f"judge unavailable         : {undecided}")
    print(f"\n**precision = {precision:.1%}**   (EVALS PIPE-4 target \u25ca >= 97%)")

    if len(per_run) > 1:
        rates = sorted((t - u) / t for t, u in per_run.values() if t)
        print(f"\nper-run spread: median {rates[len(rates)//2]:.1%} \u00b7 "
              f"min {rates[0]:.1%} \u00b7 max {rates[-1]:.1%}  (n={len(rates)} runs)")

    if not use_judge:
        print(f"\n\u26a0\ufe0f  Stage A only \u2014 a CEILING, not the measurement. "
              f"{total - len(unsupported)} claims passed the structural checks and "
              "were never asked the semantic question. Run with --judge.")
    else:
        print(f"\nJudge: {JUDGE_MODEL} / prompt {JUDGE_PROMPT_VERSION}, adversarial. "
              "Same model family as the extractor, so treat this as an upper "
              "bound until validated against Abdoul (--sample N).")

    # Repeated failures matter more than one-offs: a claim the model gets wrong
    # in every run is a defect; one it gets wrong once is variance.
    from collections import Counter
    repeat = Counter((memo, claim["text"]) for _, memo, claim, _, _ in unsupported)
    if repeat:
        print(f"\n## Unsupported claims by persistence\n")
        print("| runs | memo | claim | why |")
        print("| --- | --- | --- | --- |")
        seen = {}
        for run, memo, claim, why, how in unsupported:
            seen.setdefault((memo, claim["text"]), why)
        for (memo, text), n in repeat.most_common(30):
            print(f"| {n} | {memo} | `{text[:58]}` | {seen[(memo, text)][:52]} |")

    if sample:
        by_memo = {}
        for x in sample:
            by_memo.setdefault(x["memo"], []).append(x)
        spread, i = [], 0
        while len(spread) < sample_n and any(v[i:] for v in by_memo.values()):
            for v in by_memo.values():
                if i < len(v) and len(spread) < sample_n:
                    spread.append(v[i])
            i += 1
        sample = spread
        out = target / "judge-sample.json"
        out.write_text(json.dumps(sample, indent=2))
        print(f"\n{len(sample)} adjudications written for human review: {out}")
        print("A judge nobody has checked is an opinion with a percentage sign.")


if __name__ == "__main__":
    main()
