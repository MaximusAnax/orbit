#!/usr/bin/env python3
"""Audit the judge against the owner — EVALS §3.5 judge governance.

    python3 scripts/dev/judge_audit.py build <collection-dir> [--n 40]
    python3 scripts/dev/judge_audit.py score <collection-dir>

EVALS: *"Judges are spot-audited against Abdoul's rubric scores quarterly — a
judge that drifts from the owner's judgment is replaced, not argued with."*

That has never happened, and everything the judge has produced so far is
therefore an opinion with a percentage sign on it. We already know these judges
are wrong often: hand-review of the recall judge's recoveries found a **30%
false-positive rate**, and the precision judge needed four prompt revisions
before its refutations stopped being mostly artifacts. Neither of those reviews
was Abdoul's, and on his own memos his judgment is the only ground truth there
is — he is the one who knows whether Leon lives in Atlanta.

`build` writes a self-contained HTML page. Two properties matter:

  **It is blind.** The judge's verdict is not in the page, not in the DOM, not
  in a comment. Showing it would anchor the answer and the agreement number
  would measure suggestibility instead of agreement.

  **It is local.** These are real transcripts about real people. The page is a
  file on disk that never leaves the machine — same rule as PRIV-1/2.

`score` reads the saved answers back and reports agreement, including Cohen's
kappa, which is the number that matters: raw agreement looks impressive when one
verdict dominates, and most claims are supported.
"""
import hashlib
import json
import pathlib
import sys
import html as htmllib

ROOT = pathlib.Path(__file__).resolve().parents[2]
CACHE = ROOT / "docs/evals/judge-cache"


def load_judged(collection):
    """Every claim with a cached judge verdict, with its transcript context."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("adj", ROOT / "scripts/dev/adjudicate.py")
    adj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(adj)

    seen, out = set(), []
    runs = sorted(d for d in collection.iterdir() if d.is_dir() and d.name.startswith("run-"))
    for rd in runs:
        for f in sorted(rd.glob("*.json")):
            try:
                fx = json.loads(f.read_text())
            except json.JSONDecodeError:
                continue
            if "payload" not in fx:
                continue
            source = (ROOT / fx["source"]).read_text()
            people = {p["ref"] for p in fx["payload"].get("people") or []}
            for claim in adj.claims_of(fx["payload"]):
                sig = (f.stem, claim["text"])
                if sig in seen:
                    continue
                verdict, reason = adj.stage_a(claim, source, people)
                if verdict is False:
                    continue          # mechanical; not the judge's call to audit
                v = adj.judge(claim, source, cache_only=True)
                if not v or v.get("supported") is None:
                    continue
                seen.add(sig)
                ctx, _ = adj.window(source, claim["verbatim"], radius=500)
                out.append({
                    "id": hashlib.sha256(f"{f.stem}{claim['text']}".encode()).hexdigest()[:12],
                    "memo": f.stem,
                    "claim": claim["text"],
                    "quote": claim["verbatim"],
                    "context": ctx,
                    "judge": bool(v["supported"]),
                    "judge_why": v.get("why", ""),
                })
    return out


def build(collection, n):
    items = load_judged(collection)
    if not items:
        sys.exit("no cached judge verdicts — run adjudicate.py --judge first")

    # Stratify: half the judge called unsupported, half supported, spread over
    # memos. An audit drawn only from what the judge disliked measures its false
    # positives and nothing else.
    no = [i for i in items if not i["judge"]]
    yes = [i for i in items if i["judge"]]
    def spread(pool, k):
        by = {}
        for i in pool:
            by.setdefault(i["memo"], []).append(i)
        out, idx = [], 0
        while len(out) < k and any(v[idx:] for v in by.values()):
            for v in by.values():
                if idx < len(v) and len(out) < k:
                    out.append(v[idx])
            idx += 1
        return out
    sample = spread(no, n // 2) + spread(yes, n - n // 2)
    sample.sort(key=lambda i: i["id"])          # order carries no signal

    rows = []
    for k, it in enumerate(sample, 1):
        rows.append(f"""
<section class="c" id="{it['id']}">
  <div class="n">{k} of {len(sample)} · <span class="memo">{htmllib.escape(it['memo'])}</span></div>
  <div class="claim">{htmllib.escape(it['claim'])}</div>
  <div class="lbl">quoted as</div>
  <blockquote>{htmllib.escape(it['quote'])}</blockquote>
  <details><summary>transcript around it</summary><p>{htmllib.escape(it['context'])}</p></details>
  <div class="ask">Does the transcript support this claim, exactly as written?</div>
  <div class="opts">
    <label><input type="radio" name="{it['id']}" value="yes"> Supported</label>
    <label><input type="radio" name="{it['id']}" value="no"> Not supported</label>
    <label><input type="radio" name="{it['id']}" value="unsure"> Unsure</label>
  </div>
</section>""")

    # The verdicts are NOT embedded — the page cannot leak what the judge said.
    page = f"""<!doctype html><meta charset="utf-8">
<title>Judge audit — {len(sample)} claims</title>
<style>
 body{{font:16px/1.55 -apple-system,BlinkMacSystemFont,sans-serif;max-width:760px;
      margin:0 auto;padding:32px 20px 120px;color:#1a1a1a;background:#faf9f7}}
 h1{{font-size:22px;margin:0 0 6px}} .sub{{color:#666;margin:0 0 28px;font-size:14px}}
 .c{{background:#fff;border:1px solid #e6e2dc;border-radius:10px;padding:18px 20px;margin:0 0 16px}}
 .n{{font-size:12px;color:#999;margin-bottom:8px}} .memo{{color:#b06a2c}}
 .claim{{font-size:17px;font-weight:600;margin-bottom:12px}}
 .lbl{{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:#999}}
 blockquote{{margin:4px 0 12px;padding:8px 14px;border-left:3px solid #e0dbd3;
   color:#444;font-style:italic;background:#fcfbfa}}
 details{{margin-bottom:14px}} summary{{cursor:pointer;font-size:13px;color:#777}}
 details p{{font-size:13.5px;color:#555;background:#f6f4f1;padding:10px 12px;border-radius:6px}}
 .ask{{font-size:13px;color:#555;margin-bottom:8px}}
 .opts{{display:flex;gap:18px;flex-wrap:wrap}} label{{cursor:pointer;font-size:14.5px}}
 #bar{{position:fixed;left:0;right:0;bottom:0;background:#fff;border-top:1px solid #e6e2dc;
   padding:12px 20px;display:flex;gap:14px;align-items:center;justify-content:center}}
 button{{font:inherit;padding:9px 20px;border-radius:8px;border:1px solid #b06a2c;
   background:#b06a2c;color:#fff;cursor:pointer}}
 #count{{font-size:14px;color:#666}}
 @media(prefers-color-scheme:dark){{
   body{{background:#14140f;color:#ece7df}} .c{{background:#1c1c16;border-color:#2e2e26}}
   blockquote{{background:#191913;color:#c9c3b8;border-color:#38382e}}
   details p{{background:#191913;color:#b8b2a8}} #bar{{background:#1c1c16;border-color:#2e2e26}}
 }}
</style>
<h1>Judge audit</h1>
<p class="sub">{len(sample)} extracted claims from your memos. For each: does the
transcript support it <em>exactly as written</em>? Not "is it roughly right" —
does it say more than you said, or attach a fact to the wrong person?
<br><br>You are not being shown what the automated judge decided. That is
deliberate: seeing it first would make this measure agreement with a suggestion
rather than your own reading.</p>
{''.join(rows)}
<div id="bar"><span id="count">0 of {len(sample)}</span>
<button onclick="save()">Download answers</button></div>
<script>
const N={len(sample)};
function tally(){{document.getElementById('count').textContent=
  document.querySelectorAll('input:checked').length+' of '+N;}}
document.addEventListener('change',tally);
function save(){{
  const a={{}};document.querySelectorAll('input:checked').forEach(i=>a[i.name]=i.value);
  const b=new Blob([JSON.stringify(a,null,1)],{{type:'application/json'}});
  const u=URL.createObjectURL(b),l=document.createElement('a');
  l.href=u;l.download='judge-audit-answers.json';l.click();URL.revokeObjectURL(u);
}}
</script>"""

    (collection / "judge-audit.html").write_text(page)
    (collection / "judge-audit-key.json").write_text(json.dumps(
        {i["id"]: {"judge": i["judge"], "why": i["judge_why"],
                   "memo": i["memo"], "claim": i["claim"]} for i in sample},
        indent=1, sort_keys=True))
    print(f"{len(sample)} claims ({len(spread(no, n//2))} the judge refuted, "
          f"{len(sample)-len(spread(no, n//2))} it supported)")
    print(f"  review page : {collection/'judge-audit.html'}")
    print(f"  hidden key  : {collection/'judge-audit-key.json'}")
    print("\nOpen the page, answer, hit Download, and drop the file next to the key.")


def score(collection):
    key = json.loads((collection / "judge-audit-key.json").read_text())
    ans_path = collection / "judge-audit-answers.json"
    if not ans_path.exists():
        sys.exit(f"no answers yet — expected {ans_path}")
    ans = json.loads(ans_path.read_text())

    both = [(k, v) for k, v in ans.items() if k in key and v in ("yes", "no")]
    if not both:
        sys.exit("no comparable answers")
    agree = sum(1 for k, v in both if (v == "yes") == key[k]["judge"])
    n = len(both)

    # Cohen's kappa — raw agreement flatters a lopsided distribution, and most
    # claims are supported, so a judge that said "yes" to everything would score
    # well on raw agreement alone.
    jy = sum(1 for k, _ in both if key[k]["judge"]) / n
    hy = sum(1 for _, v in both if v == "yes") / n
    pe = jy * hy + (1 - jy) * (1 - hy)
    po = agree / n
    kappa = (po - pe) / (1 - pe) if pe < 1 else 1.0

    print(f"# Judge audit — {collection.name}\n")
    print(f"claims adjudicated by both : {n}")
    print(f"raw agreement              : {po:.1%}")
    print(f"Cohen's kappa              : {kappa:.2f}", end="  ")
    print("(<0.4 poor · 0.4-0.6 moderate · 0.6-0.8 substantial · >0.8 strong)")
    unsure = sum(1 for v in ans.values() if v == "unsure")
    if unsure:
        print(f"owner marked unsure        : {unsure} (excluded)")

    fp = [(k, key[k]) for k, v in both if v == "yes" and not key[k]["judge"]]
    fn = [(k, key[k]) for k, v in both if v == "no" and key[k]["judge"]]
    if fp:
        print(f"\n## Judge refused what you accepted ({len(fp)}) — over-strict\n")
        for k, m in fp[:15]:
            print(f"- [{m['memo']}] `{m['claim'][:64]}`\n    judge: {m['why']}")
    if fn:
        print(f"\n## Judge accepted what you refused ({len(fn)}) — the dangerous direction\n")
        for k, m in fn[:15]:
            print(f"- [{m['memo']}] `{m['claim'][:64]}`")
        print("\nThese matter most: claims the automated pass would have let through "
              "as supported and you would not. Every one is a precision number "
              "that reads better than the truth.")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    mode, target = sys.argv[1], pathlib.Path(sys.argv[2])
    if not target.is_absolute():
        target = ROOT / target
    if mode == "build":
        n = int(sys.argv[sys.argv.index("--n") + 1]) if "--n" in sys.argv else 40
        build(target, n)
    elif mode == "score":
        score(target)
    else:
        sys.exit(__doc__)
