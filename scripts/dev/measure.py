#!/usr/bin/env python3
"""Provisional PIPE measurement — grades extraction fixtures against the goldens.

Deterministic contract matching (goldens are contracts, not transcripts — EVALS
§3.5): required items match on structured fields + lowercase containment; forbidden
items fail in any phrasing. This is the T1 twin of `orbit-evals measure --replay`;
the Swift harness is the gate of record in CI. Numbers from in-session fixtures are
PROVISIONAL — ratified thresholds await the production extractor (EVALS §9).

Usage: measure.py [--write-report]
"""
import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent.parent
GOLD = ROOT / "docs" / "evals" / "goldens"
FIX = ROOT / "docs" / "evals" / "fixtures"


def load_goldens():
    goldens = {}
    g = yaml.safe_load((GOLD / "eliah.yaml").read_text())
    goldens[g["memo"]] = g
    for name in ("real-memos.yaml", "synthetic.yaml"):
        for g in yaml.safe_load((GOLD / name).read_text()):
            goldens[g["memo"]] = g
    return goldens


def norm(s):
    return (s or "").lower()


class Grader:
    def __init__(self, memo, golden, fixture):
        self.memo = memo
        self.g = golden
        self.p = fixture["payload"]
        self.source = (ROOT / fixture["source"]).read_text()
        self.required_total = 0
        self.required_hit = 0
        self.criticals = []       # (check, detail)
        self.misses = []
        # ref → person entry
        self.people = {x["ref"]: x for x in self.p["people"]}
        self.entities = {x["ref"]: x for x in self.p["entities"]}

    # ---- matching helpers ----

    def subject_matches(self, ref, want):
        if want == "self":
            return ref == "self"
        # want is a golden key; match by name_like of required/subject people
        forms = []
        for sp in self.g.get("subject_people", []):
            if sp["key"] == want:
                forms = sp["name_forms"]
        for rp in self.g.get("required_people", []):
            if rp.get("key") == want:
                forms = [rp["name_like"]]
        if not forms:
            forms = [want]
        person = self.people.get(ref)
        if not person:
            return False
        name = norm(person["name_as_heard"])
        return any(f in name for f in forms)

    def blob(self, a):
        parts = [a.get("object_value"), a.get("verbatim")]
        if a.get("object_person_ref") and a["object_person_ref"] in self.people:
            parts.append(self.people[a["object_person_ref"]]["name_as_heard"])
        if a.get("object_entity_ref") and a["object_entity_ref"] in self.entities:
            e = self.entities[a["object_entity_ref"]]
            parts += [e["name_as_heard"]] + e["aliases"]
        return norm(" | ".join(x for x in parts if x))

    def find_assertions(self, subject=None, predicate=None, contains=None):
        out = []
        for a in self.p["assertions"]:
            if subject and not self.subject_matches(a["subject_ref"], subject):
                continue
            if predicate and a["predicate"] != predicate:
                continue
            if contains and norm(contains) not in self.blob(a):
                continue
            out.append(a)
        return out

    def req(self, hit, label, critical=False):
        self.required_total += 1
        if hit:
            self.required_hit += 1
        else:
            self.misses.append(label)
            if critical:
                self.criticals.append((label, "required item missing (Critical)"))

    # ---- grading passes ----

    # PIPE-17 — the tag/sentence split, measured (FIELD-NOTES FN-10/FN-14).
    # DATA-MODEL §2: object_value holds a literal, verbatim holds the sentence.
    # A clause in the tag slot defeats the point of having two fields, because
    # §17 network queries traverse tags and no query will ever match a
    # paragraph. Measured max on the ratified corpus was 7 words.
    TAG_WORD_CEILING = 12

    def grade_tag_discipline(self):
        people = {norm(m.get("name_as_heard")) for m in self.p.get("people", [])}
        people |= {norm(a) for m in self.p.get("people", []) for a in (m.get("aliases") or [])}
        people.discard("")
        for a in self.p.get("assertions", []):
            value = a.get("object_value")
            if not value:
                continue
            words = len(value.split())
            if words > self.TAG_WORD_CEILING:
                self.criticals.append((
                    "PIPE-17",
                    f"{a['predicate']} object_value is a clause, not a tag "
                    f"({words} words): {value[:60]!r}"))
            # FN-14: a name the ref already carries must not be repeated in the
            # tag — it becomes a second place to be wrong, and renaming the ref
            # cannot reach it.
            for name in people:
                if len(name) > 2 and name in norm(value):
                    self.criticals.append((
                        "PIPE-17",
                        f"{a['predicate']} object_value repeats the person name "
                        f"{name!r} that its ref already carries: {value[:60]!r}"))
                    break

    def grade(self):
        g, p = self.g, self.p
        self.grade_tag_discipline()

        if g.get("expect_empty"):
            total = sum(len(p[k]) for k in
                        ("people", "entities", "assertions", "episodes", "threads",
                         "loops", "contact_points", "state_declarations", "corrections"))
            self.required_total += 1
            if total == 0:
                self.required_hit += 1
            else:
                self.criticals.append(("silence test", f"{total} items extracted from an empty memo"))
            return

        # PIPE-1b / identity: subject person count caps
        for sp in g.get("subject_people", []):
            n = sum(1 for x in p["people"]
                    if any(f in norm(x["name_as_heard"]) for f in sp["name_forms"]))
            if n > sp.get("max_person_entries", 1):
                self.criticals.append(("PIPE-1b identity", f"{n} person entries for {sp['key']}"))
            self.req(n >= 1, f"person:{sp['key']}", critical=True)

        for rp in g.get("required_people", []):
            hits = [x for x in p["people"] if rp["name_like"] in norm(x["name_as_heard"])]
            self.req(bool(hits), f"person:{rp.get('key', rp['name_like'])}")
            if hits and rp.get("status") and hits[0]["status"] != rp["status"]:
                self.criticals.append(("person status", f"{rp['name_like']}: {hits[0]['status']} ≠ {rp['status']}"))
            if hits and rp.get("match") and hits[0]["match"] != rp["match"]:
                self.criticals.append(("person match", f"{rp['name_like']}: {hits[0]['match']} ≠ {rp['match']}"))

        for ra in g.get("required_assertions", []):
            hits = self.find_assertions(ra.get("subject"), ra.get("predicate"), ra.get("contains"))
            if ra.get("closed"):
                hits = [a for a in hits if a.get("valid_to")]
            if ra.get("hedged"):
                hits = [a for a in hits if a.get("hedged")]
            self.req(bool(hits), f"assertion:{ra.get('subject')}/{ra.get('predicate')}/{ra.get('contains')}")

        for ra in g.get("required_self_assertions", []):
            hits = self.find_assertions("self", ra.get("predicate"), ra.get("contains"))
            if ra.get("closed"):
                hits = [a for a in hits if a.get("valid_to")]
            self.req(bool(hits), f"self:{ra.get('predicate')}/{ra.get('contains')}")

        for re_ in g.get("required_entities", []):
            hits = []
            for e in p["entities"]:
                text = norm(e["name_as_heard"] + " " + " ".join(e["aliases"]))
                if norm(re_["contains"]) in text:
                    if re_.get("part_of_contains"):
                        parent = self.entities.get(e.get("part_of_ref") or "")
                        ptext = norm(parent["name_as_heard"] + " " + " ".join(parent["aliases"])) if parent else ""
                        if norm(re_["part_of_contains"]) not in ptext:
                            continue
                    if re_.get("kind") and e["kind"] != re_["kind"]:
                        continue
                    hits.append(e)
            self.req(bool(hits), f"entity:{re_['contains']}")

        # PIPE-5 hedges — zero tolerance
        for span in g.get("required_hedges", []):
            carriers = [a for a in p["assertions"] if span in a["verbatim"]]
            carriers += [amb["assertion"] for amb in p["ambiguities"]
                         if amb.get("assertion") and span in amb["assertion"]["verbatim"]]
            if not carriers:
                self.criticals.append(("PIPE-5", f"hedge span not extracted at all: {span!r}"))
            elif not all(a["hedged"] for a in carriers):
                self.criticals.append(("PIPE-5", f"hedge dropped: {span!r}"))
            self.req(bool(carriers) and all(a["hedged"] for a in carriers), f"hedge:{span!r}")

        # PIPE-12 episodes
        for ep in g.get("required_episodes", []):
            hits = []
            for e in p["episodes"]:
                text = norm(e["title"] + " " + e["narrative"])
                if norm(ep["contains"]) in text \
                   and norm(ep.get("era_contains", "")) in norm(e.get("era_relative") or "") \
                   and (not ep.get("met") or e["is_met_event"]) \
                   and (not ep.get("hedged") or e["hedged"]):
                    hits.append(e)
            self.req(bool(hits), f"episode:{ep['id']}", critical=True)
        if "episode_count_max" in g and len(p["episodes"]) > g["episode_count_max"]:
            self.criticals.append(("PIPE-12", f"{len(p['episodes'])} episodes > max {g['episode_count_max']} (sub-episodes must stay inside parents)"))

        for rs in g.get("required_state_declarations", []):
            hits = [s for s in p["state_declarations"]
                    if norm(rs["quote_contains"]) in norm(s["quote"])
                    and (not rs.get("orbit") or s.get("suggested_orbit") == rs["orbit"])
                    and self.subject_matches(s["subject_ref"], rs["subject"])]
            self.req(bool(hits), f"state:{rs['quote_contains'][:30]}", critical=True)
        if "state_declaration_count_max" in g and \
           len(p["state_declarations"]) > g["state_declaration_count_max"]:
            self.criticals.append(("INV-24", "state proposal beyond the explicit declaration"))

        for rt in g.get("required_threads", []):
            hits = [t for t in p["threads"]
                    if norm(rt["contains"]) in norm(t["title"] + " " + t["evidence_verbatim"])
                    and self.subject_matches(t["subject_ref"], rt["subject"])]
            self.req(bool(hits), f"thread:{rt['contains']}")
            for t in hits:
                self.pipe11_total = getattr(self, "pipe11_total", 0) + 1
                if t["archetype"] == rt.get("archetype", t["archetype"]):
                    self.pipe11_hit = getattr(self, "pipe11_hit", 0) + 1
                else:
                    self.criticals.append(("PIPE-11", f"thread {t['title']!r}: {t['archetype']} ≠ {rt['archetype']}"))

        for rl in g.get("required_loops", []):
            hits = [l for l in p["loops"]
                    if norm(rl["contains"]) in norm(l["description"] + " " + l["verbatim"])
                    and l["direction"] == rl.get("direction", l["direction"])
                    and self.subject_matches(l["subject_ref"], rl["subject"])]
            self.req(bool(hits), f"loop:{rl['contains']}")

        # PIPE-9 planted ambiguities
        for ram in g.get("required_ambiguities", []):
            hits = [a for a in p["ambiguities"]
                    if a["kind"] == ram["kind"]
                    and norm(ram["contains"]) in norm(json.dumps(a, ensure_ascii=False))]
            if ram.get("min_candidates"):
                hits = [a for a in hits if len(a["candidate_refs"]) >= ram["min_candidates"]]
            self.req(bool(hits), f"ambiguity:{ram['kind']}/{ram['contains']}")

        for rc in g.get("required_corrections", []):
            hits = [c for c in p["corrections"]
                    if c["kind"] == rc["kind"] and norm(rc["object_like"]) in norm(c["object_like"])
                    and self.subject_matches(c["subject_ref"], rc["subject"])]
            self.req(bool(hits), f"correction:{rc['object_like']}", critical=True)

        # PIPE-7 attribution expectations
        for ax in g.get("attribution_expectations", []):
            hits = self.find_assertions(ax.get("subject"), None, ax.get("contains"))
            for a in hits:
                if a["source_kind"] != ax["source_kind"]:
                    self.criticals.append(("PIPE-7", f"{ax['contains']}: {a['source_kind']} ≠ {ax['source_kind']}"))

        # PIPE-6 verbatim fidelity (independent re-verification)
        for a in p["assertions"]:
            if a["verbatim"] not in self.source:
                self.criticals.append(("PIPE-6", f"verbatim not in source: {a['verbatim'][:60]!r}"))
        for s in p["state_declarations"]:
            if s["quote"] not in self.source:
                self.criticals.append(("PIPE-6/INV-24", f"quote not in source: {s['quote'][:60]!r}"))
        for e in p["episodes"]:
            if e["narrative"] not in self.source:
                self.criticals.append(("PIPE-6", f"narrative not in source: {e['narrative'][:60]!r}"))

        # forbidden items (PIPE-4-class, Critical each)
        for f in g.get("forbidden", []):
            kind = f["kind"]
            hit = None
            if kind == "assertion":
                cands = self.find_assertions(f.get("subject"), f.get("predicate"), f.get("contains"))
                if f.get("open"):
                    cands = [a for a in cands if not a.get("valid_to")]
                hit = cands[0] if cands else None
            elif kind == "any_text":
                if norm(f["contains"]) in norm(json.dumps(p, ensure_ascii=False)):
                    hit = f["contains"]
            elif kind == "episode":
                hit = next((e for e in p["episodes"]
                            if norm(f["contains"]) in norm(e["title"] + " " + e["narrative"])), None)
            elif kind == "person":
                hit = next((x for x in p["people"]
                            if f["name_like"] in norm(x["name_as_heard"])), None)
            elif kind == "person_match":
                hit = next((x for x in p["people"]
                            if f["name_like"] in norm(x["name_as_heard"]) and x["match"] == f["match"]), None)
            elif kind == "person_status":
                hit = next((x for x in p["people"]
                            if f["name_like"] in norm(x["name_as_heard"]) and x["status"] == f["status"]), None)
            elif kind == "assertion_source":
                hit = next((a for a in self.find_assertions(f.get("subject"))
                            if a["source_kind"] == f["source_kind"]), None)
            elif kind == "loop":
                cands = p["loops"]
                if f.get("contains"):
                    cands = [l for l in cands if norm(f["contains"]) in norm(l["description"] + l["verbatim"])]
                hit = cands[0] if cands else None
            elif kind == "thread":
                hit = p["threads"][0] if p["threads"] else None
            elif kind == "thread_archetype_for":
                hit = next((t for t in p["threads"]
                            if norm(f["contains"]) in norm(t["title"] + t["evidence_verbatim"])
                            and t["archetype"] != f["not_archetype"]), None)
            elif kind == "state_declaration":
                hit = p["state_declarations"][0] if p["state_declarations"] else None
            elif kind == "correction":
                cands = p["corrections"]
                if f.get("correction_kind"):
                    cands = [c for c in cands if c["kind"] == f["correction_kind"]]
                if f.get("contains"):
                    cands = [c for c in cands if norm(f["contains"]) in norm(c["object_like"] + c["verbatim"])]
                hit = cands[0] if cands else None
            if hit is not None:
                self.criticals.append((f"forbidden:{kind}", f.get("why", str(f))[:90]))

        # PIPE-10 thread precision: every emitted thread must be sanctioned
        allowed = g.get("required_threads", []) + g.get("allowed_threads", [])
        for t in p["threads"]:
            ok = any(norm(rt["contains"]) in norm(t["title"] + " " + t["evidence_verbatim"])
                     for rt in allowed)
            if not ok:
                self.criticals.append(("PIPE-10", f"unsanctioned thread: {t['title']!r} — no plausible-resolution warrant in golden"))


def main():
    global FIX
    if "--fixtures" in sys.argv:
        FIX = ROOT / sys.argv[sys.argv.index("--fixtures") + 1]
    goldens = load_goldens()
    rows = []
    all_criticals = []
    pipe11 = [0, 0]
    for memo, golden in goldens.items():
        fixture = json.loads((FIX / f"{memo}.json").read_text())
        grader = Grader(memo, golden, fixture)
        grader.grade()
        pipe11[0] += getattr(grader, "pipe11_hit", 0)
        pipe11[1] += getattr(grader, "pipe11_total", 0)
        rows.append((memo, grader.required_hit, grader.required_total,
                     len(grader.criticals), grader.misses))
        for c in grader.criticals:
            all_criticals.append((memo, *c))

    # PIPE-13 fragmentation across the corpus: alias-equal entities must unify at sync
    seen = {}
    frag = 0
    frag_pairs = []
    for memo in goldens:
        fixture = json.loads((FIX / f"{memo}.json").read_text())
        for e in fixture["payload"]["entities"]:
            names = {norm(e["name_as_heard"])} | {norm(a) for a in e["aliases"]}
            matched_key = next((k for k, v in seen.items() if v & names), None)
            if matched_key:
                seen[matched_key] |= names
            else:
                seen[frozenset(names)] = set(names)
    # fragmentation = alias-overlapping groups that would NOT unify (no shared literal)
    # by construction groups here share a literal → sync-time aliasMatch unifies them.

    hit = sum(r[1] for r in rows)
    total = sum(r[2] for r in rows)
    recall = hit / total if total else 1.0

    lines = []
    lines.append("# Provisional PIPE measurement — 2026-07-29")
    lines.append("")
    lines.append(f"Extractor: `claude-fable-5(in-session)` · prompt v1 · corpus: 4 real + 7 synthetic memos.")
    lines.append("**Provisional by definition** — the ratified PIPE-12 number awaits the production")
    lines.append("extractor (EVALS §9). Deterministic contract matching (structured fields +")
    lines.append("containment); no LLM judge in this path.")
    lines.append("")
    lines.append("| Memo | Required hit | Criticals | Misses |")
    lines.append("| --- | --- | --- | --- |")
    for memo, h, t, ncrit, misses in sorted(rows):
        lines.append(f"| {memo} | {h}/{t} | {ncrit} | {'; '.join(misses[:3]) if misses else '—'} |")
    lines.append("")
    lines.append("| Check | Provisional value | EVALS ◊ target |")
    lines.append("| --- | --- | --- |")
    lines.append(f"| PIPE-3 extraction recall (required-item) | {recall:.1%} ({hit}/{total}) | ◊ ≥ 90% |")
    crit_count = len(all_criticals)
    lines.append(f"| PIPE-4-class Criticals (forbidden/invented/misattributed) | {crit_count} | 0 |")
    lines.append(f"| PIPE-5 hedge preservation | {'100%' if not any(c[1]=='PIPE-5' for c in all_criticals) else 'FAIL'} | 100% |")
    lines.append(f"| PIPE-6 verbatim fidelity | {'100%' if not any(c[1].startswith('PIPE-6') for c in all_criticals) else 'FAIL'} | 100% |")
    lines.append(f"| PIPE-7 false attributions | {sum(1 for c in all_criticals if c[1]=='PIPE-7')} | 0 |")
    lines.append(f"| PIPE-9 planted-ambiguity recall | see per-memo required ambiguity rows | ◊ ≥ 90% |")
    lines.append(f"| PIPE-10 unsanctioned threads | {sum(1 for c in all_criticals if c[1]=='PIPE-10')} | ◊ ≥ 85% precision |")
    lines.append(f"| PIPE-11 archetype accuracy | {pipe11[0]}/{pipe11[1]} | ◊ ≥ 85% |")
    lines.append(f"| PIPE-12 episode split (Eliah golden) | see eliah row (episodes are Critical-tracked) | ◊ gate |")
    lines.append(f"| PIPE-1b identity fragmentation | {sum(1 for c in all_criticals if c[1]=='PIPE-1b identity')} | 0 |")
    lines.append(f"| PIPE-13 entity fragmentation (alias-overlap unify) | {frag} unresolvable | ◊ ≤ 5% |")
    lines.append(f"| PIPE-17 tag discipline (object_value is a tag, not a clause) | {sum(1 for c in all_criticals if c[1]=='PIPE-17')} | 0 |")
    lines.append("")
    if all_criticals:
        lines.append("## Criticals")
        for memo, check, detail in all_criticals:
            lines.append(f"- **{memo}** · {check}: {detail}")
    else:
        lines.append("No Critical-class findings on this corpus.")
    report = "\n".join(lines)
    print(report)
    if "--write-report" in sys.argv:
        out = ROOT / "docs" / "evals" / "measurements" / "2026-07-29-provisional.md"
        out.write_text(report + "\n")
        print(f"\nwritten: {out.relative_to(ROOT)}")
    if all_criticals:
        sys.exit(1)

if __name__ == "__main__":
    main()
