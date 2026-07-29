#!/usr/bin/env python3
"""Builds the extraction fixtures for the eval corpus.

These payloads were produced by a Claude model operating in-session against
extraction-prompt-v1 + extraction-schema-v1 (model_id below is honest about
that). They are PROVISIONAL measurement fixtures: the ratified PIPE-12 number
awaits the production endpoint (EVALS §9), which `orbit-evals measure --live`
will produce once an API key exists. Every verbatim/quote/narrative field is
asserted to be an exact substring of its transcript at build time (PIPE-6 by
construction on the fixture side; measured independently by measure.py).
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
TR = ROOT / "mock_memos" / "transcripts"
SYN = ROOT / "docs" / "evals" / "corpus" / "synthetic"
OUT = ROOT / "docs" / "evals" / "fixtures"

MODEL_ID = "claude-fable-5(in-session)"
PROMPT_VERSION = "v1"

def A(subject_ref, predicate, verbatim, *, object_value=None, object_entity_ref=None,
      object_person_ref=None, valid_from=None, valid_to=None, date_precision="fuzzy",
      source_kind="firsthand", attributed_to_ref=None, hedged=False, confidence=None,
      thread_ref=None):
    return {
        "subject_ref": subject_ref, "predicate": predicate,
        "object_entity_ref": object_entity_ref, "object_person_ref": object_person_ref,
        "object_value": object_value, "verbatim": verbatim,
        "valid_from": valid_from, "valid_to": valid_to, "date_precision": date_precision,
        "source_kind": source_kind, "attributed_to_ref": attributed_to_ref,
        "hedged": hedged, "confidence": confidence, "thread_ref": thread_ref,
    }

def P(ref, name, match="new", status="active", existing=None, rationale=None):
    return {"ref": ref, "name_as_heard": name, "match": match,
            "existing_person_id": existing, "match_rationale": rationale, "status": status}

def E(ref, name, kind, part_of=None, aliases=(), existing=None):
    return {"ref": ref, "name_as_heard": name, "kind": kind,
            "existing_entity_id": existing, "part_of_ref": part_of, "aliases": list(aliases)}

def EP(occurred, precision, era, kind, title, narrative, participants, met=False, hedged=False):
    return {"occurred_at": occurred, "date_precision": precision, "era_relative": era,
            "kind": kind, "title": title, "narrative": narrative,
            "participant_refs": participants, "is_met_event": met, "hedged": hedged}

def payload(**kw):
    base = {"people": [], "entities": [], "assertions": [], "episodes": [], "threads": [],
            "thread_closures": [], "loops": [], "contact_points": [],
            "state_declarations": [], "corrections": [], "ambiguities": []}
    base.update(kw)
    return base

FIXTURES = {}

# ───────────────────────────── Eliah portrait ─────────────────────────────
# Era anchor stated in source: "we're going into our senior year right now"
# (capture July 2026) → freshman fall = 2023; sophomore spring = 2025-03;
# internship summer = 2025; junior fall = 2025-10; senior year starts 2026-08.
FIXTURES["eliah"] = ("Eliah.txt", payload(
    people=[
        P("p_eliah", "Elia Tapia", rationale="one person despite several spellings in the transcript (Elia/Ilya/Aaliyah)"),
        P("p_philly", "Philly"),
        P("p_roger", "Roger", rationale="known only slightly — mentioned as Philly's summer housemate"),
    ],
    entities=[
        E("e_cmu", "Carnegie Mellon", "school"),
        E("e_tartan", "Tartan Scholars", "organization"),
        E("e_google", "Google", "organization"),
        E("e_microsoft", "Microsoft", "organization"),
        E("e_riverbank", "Riverbank", "place", aliases=["Riverbank State Park"]),
    ],
    assertions=[
        # education — "we" splits (§7.12): same verbatim, two subjects
        A("p_eliah", "education", "we go to Carnegie Mellon, and we both study computer science",
          object_entity_ref="e_cmu", object_value="computer science", valid_from="2023-09", date_precision="month"),
        A("self", "education", "we go to Carnegie Mellon, and we both study computer science",
          object_entity_ref="e_cmu", object_value="computer science", valid_from="2023-09", date_precision="month"),
        A("p_eliah", "education", "we're both part of this program called Tartan Scholars",
          object_entity_ref="e_tartan", object_value="Tartan Scholars"),
        A("self", "education", "we're both part of this program called Tartan Scholars",
          object_entity_ref="e_tartan", object_value="Tartan Scholars"),
        # origins
        A("p_eliah", "location", "he was from Washington Heights", object_value="Washington Heights, NYC"),
        A("self", "location", "I was from the Bronx", object_value="the Bronx, NYC"),
        A("self", "location", "I lived on 167th and Grand Concourse", object_value="167th and Grand Concourse"),
        A("p_eliah", "location", "We're both from New York City", object_value="New York City"),
        A("self", "location", "We're both from New York City", object_value="New York City"),
        # shared interests — split pairs
        A("p_eliah", "interest", "we have like all of the same interests we uh love like sports we love anime we love um like video games",
          object_value="sports"),
        A("self", "interest", "we have like all of the same interests we uh love like sports we love anime we love um like video games",
          object_value="sports"),
        A("p_eliah", "interest", "defined our childhoods and our current lives", object_value="anime"),
        A("self", "interest", "defined our childhoods and our current lives", object_value="anime"),
        A("p_eliah", "interest", "we have like all of the same interests we uh love like sports we love anime we love um like video games",
          object_value="video games"),
        A("self", "interest", "we have like all of the same interests we uh love like sports we love anime we love um like video games",
          object_value="video games"),
        A("p_eliah", "interest", "when he was in high school and stuff, he would play ball at Riverbank",
          object_entity_ref="e_riverbank", object_value="basketball",
          valid_from="2019", valid_to="2023", date_precision="fuzzy"),
        # traits
        A("p_eliah", "trait", "he's super smart. He's funny.", object_value="smart, funny"),
        A("p_eliah", "trait", "he has, like, a very reserved personality, usually, um, around people that, like, he doesn't know",
          object_value="reserved with strangers"),
        A("p_eliah", "trait", "he was a lot more uh like calm and reserved than I was", object_value="calm"),
        A("self", "trait", "I was a lot more like um like all over the place and like really excited and really energetic",
          object_value="energetic, all over the place"),
        A("p_eliah", "trait", "he's Dominican, you know, black, Dominican", object_value="Dominican, Black"),
        A("p_eliah", "trait", "we're the same exact age", object_value="same age as owner"),
        A("p_eliah", "trait", "both of our families are predominantly immigrants", object_value="family predominantly immigrants"),
        A("self", "trait", "both of our families are predominantly immigrants", object_value="family predominantly immigrants"),
        # closed internships — the tense trap, both directions
        A("p_eliah", "employment", "He was interning at Google and I was interning at Microsoft.",
          object_entity_ref="e_google", object_value="intern",
          valid_from="2025-06", valid_to="2025-08", date_precision="month"),
        A("self", "employment", "He was interning at Google and I was interning at Microsoft.",
          object_entity_ref="e_microsoft", object_value="intern",
          valid_from="2025-06", valid_to="2025-08", date_precision="month"),
        # periods & habits → intervals, never episodes
        A("p_eliah", "life_event", "we started rooming together um a sophomore year",
          object_person_ref="self", object_value=None,
          valid_from="2024-08", valid_to="2025-05", date_precision="fuzzy"),
        A("p_eliah", "life_event", "We would do homework together. We would study together.",
          object_person_ref="self",
          valid_from="2023-09", valid_to="2024-05", date_precision="fuzzy"),
        A("p_eliah", "life_event", "We were living separately. We both had singles",
          object_person_ref="self",
          valid_from="2025-08", valid_to="2026-05", date_precision="fuzzy"),
        A("p_eliah", "education", "Sometimes we were taking like two of the same courses, I want to say, like one or two. I think it was actually maybe one.",
          object_value="one shared course, junior fall", valid_from="2025-09", valid_to="2025-12",
          date_precision="fuzzy", hedged=True, confidence=0.5),
        A("p_eliah", "education", "Aaliyah was actually taking it with 213, which was, like, our intro to computer systems course",
          object_value="took the hard course concurrently with 213", valid_from="2025-09", valid_to="2025-12",
          date_precision="fuzzy", hedged=True, confidence=0.6),
        A("p_eliah", "life_event", "we were in the library, like, late night with Philly",
          object_person_ref="p_philly",
          valid_from="2025-09", valid_to="2025-12", date_precision="fuzzy"),
        # upcoming arrangement → interval, NOT an episode
        A("p_eliah", "life_event", "we're going to be living together this upcoming year again because we were both like, nah, we got to run it back one last time",
          object_person_ref="self", valid_from="2026-08", date_precision="fuzzy"),
        # Philly
        A("p_philly", "relation", "a really good friend of ours, uh, Philly", object_person_ref="self"),
        A("p_philly", "trait", "I think I got a lot closer to him as well", object_value="grew closer junior year",
          hedged=True, confidence=0.6),
        A("p_philly", "location", "Philly was also in, um, like the Pacific Northwest, like Seattle, Redmond, Bellevue with us",
          object_value="Pacific Northwest", valid_from="2025-06", valid_to="2025-08", date_precision="month"),
        A("p_philly", "education", "Philly was also taking the course", object_value="took the same hard course",
          valid_from="2025-09", valid_to="2025-12", date_precision="fuzzy"),
    ],
    episodes=[
        EP("2023-08", "month", "freshman fall", "encounter", "Met at Tartan Scholars early move-in",
           "that's when we met and I knew of him, but we didn't really hang out much",
           ["p_eliah", "self"], met=True, hedged=True),
        EP("2025-03", "month", "sophomore spring", "encounter", "Japan trip over spring break",
           "it was spring break, and we went with a few others of our friends as well, and we all had, like, a blast",
           ["p_eliah", "self"]),
        EP("2025-10", "month", "junior fall", "encounter", "Colombia fall-break trip",
           "our junior year fall, we went on a fall break trip to Colombia together",
           ["p_eliah", "self"]),
    ],
    state_declarations=[
        {"subject_ref": "p_eliah",
         "quote": "he would be in the inner, inner, inner circle, um, like right there along with my family",
         "suggested_orbit": "inner",
         "suggested_intent": "grow even closer through senior year",
         "mapping_rationale": "explicit circles-of-influence declaration; he also calls him a brother and his best friend"},
    ],
    ambiguities=[
        {"question": "Who lived together that summer in the Pacific Northwest — Eliah with Philly and Roger, or just Philly and Roger?",
         "candidate_refs": ["p_eliah", "p_philly", "p_roger"],
         "assertion": A("p_philly", "life_event",
                        "he, they actually lived together like over that summer. So it was him, Philly, and this other guy named Roger.",
                        object_value="lived together, summer 2025", valid_from="2025-06", valid_to="2025-08",
                        date_precision="month", hedged=True, confidence=0.4),
         "kind": "attendance"},
    ],
))

# ───────────────────────────── Nikos ─────────────────────────────
FIXTURES["nikos"] = ("Nikos.txt", payload(
    people=[P("p_nikos", "Nikos")],
    entities=[
        E("e_ycss", "Y Combinator Startup School", "event_series", aliases=["startup school"]),
        E("e_picnic", "Y Combinator Startup School Picnic", "event_series",
          part_of="e_ycss", aliases=["the picnic"]),
    ],
    assertions=[
        A("p_nikos", "location", "Nikos is from Greece", object_value="Greece"),
        A("p_nikos", "life_event", "He was there for startup school", object_entity_ref="e_ycss",
          object_value="attended Y Combinator Startup School", date_precision="month", valid_from="2026-07"),
        A("p_nikos", "trait", "He was a very down-to-earth guy, super nice to talk to, very kind",
          object_value="down-to-earth, kind"),
    ],
))

# ───────────────────────────── Dom ─────────────────────────────
FIXTURES["dom"] = ("Dom.txt", payload(
    people=[
        P("p_dom", "Dom"),
        P("p_leon", "Leon", match="existing", existing="person-leon",
          rationale="referenced as an established mutual — matches known contact Leon"),
        P("p_sekou", "Sekou", match="existing", existing="person-sekou",
          rationale="matches known contact Sekou"),
    ],
    entities=[
        E("e_umich", "University of Michigan", "school"),
        E("e_ycss", "Y Combinator Startup School", "event_series", aliases=["startup school"]),
    ],
    assertions=[
        A("p_dom", "relation", "who was Leon's friend", object_person_ref="p_leon"),
        A("p_leon", "relation", "Leon is Sekou's roommate", object_person_ref="p_sekou"),
        A("p_dom", "preference", "He's vegan", object_value="vegan"),
        A("p_dom", "education", "He goes to University of Michigan", object_entity_ref="e_umich",
          object_value="University of Michigan"),
        A("p_dom", "education", "he's also a senior just like me", object_value="senior"),
        A("self", "education", "he's also a senior just like me", object_value="senior"),
        A("p_dom", "education", "Definitely computer science", object_value="computer science"),
        A("p_dom", "education", "I think, computer science and, like, policy or something like that",
          object_value="possibly policy", hedged=True, confidence=0.4),
        A("p_dom", "interest", "We ended up talking about a lot of philosophy", object_value="philosophy"),
        A("p_dom", "trait", "he got pretty upset at somebody that was kind of very, like, not, did not really care about animals much",
          object_value="cares deeply about animal welfare"),
        A("p_dom", "trait", "we were both very social", object_value="very social"),
        A("self", "trait", "we were both very social", object_value="very social"),
        A("p_dom", "trait", "his energy really matched mine", object_value="high energy, matches owner"),
    ],
))

# ───────────────────────────── Futureforce dinner ─────────────────────────────
FIXTURES["futureforce"] = ("Futureforce Dinner.txt", payload(
    people=[
        P("p_cj", "CJ"),
        P("p_grace", "Grace"),
        P("p_abdul", "Abdul", match="self_collision", rationale="namesake of the owner — never merged silently (§7.7)"),
        P("p_lake", "Lake"),
        P("p_lucas", "Lucas"),
    ],
    entities=[
        E("e_futureforce", "Salesforce, Future Force, Tech Accelerator", "event_series",
          aliases=["Futureforce", "Future Force", "Salesforce Futureforce Tech Accelerator"]),
    ],
    assertions=[],
    ambiguities=[
        {"question": "The memo lists “Abdul” among the dinner guests — a different person from you, or a mis-transcription of your own name?",
         "candidate_refs": ["p_abdul"], "assertion": None, "kind": "self_collision"},
        {"question": "Did Lake join the bike ride back, or only the dinner?",
         "candidate_refs": ["p_lake"],
         "assertion": A("p_lake", "life_event", "And also Lake, I believe",
                        object_value="joined the late-night bike ride", hedged=True, confidence=0.5),
         "kind": "attendance"},
    ],
))

# ───────────────────────────── Synthetics ─────────────────────────────
FIXTURES["hardship"] = ("hardship.txt", payload(
    people=[P("p_maya", "Maya")],
    entities=[E("e_figma", "Figma", "organization")],
    assertions=[
        A("p_maya", "employment", "She's still at Figma, still on the design systems team",
          object_entity_ref="e_figma", object_value="design systems team"),
        A("p_maya", "concern", "her mom was diagnosed with early-stage Parkinson's last month",
          object_value="mother's Parkinson's diagnosis", source_kind="secondhand",
          attributed_to_ref="p_maya", valid_from="2026-06", date_precision="month"),
        A("p_maya", "life_event", "she's been flying home every other weekend to help out",
          object_value="flying home biweekly to help her mother"),
    ],
    threads=[
        {"ref": "t_mom", "subject_ref": "p_maya", "title": "Her mother's Parkinson's",
         "archetype": "condition_hardship", "expected_resolution_at": None,
         "expected_resolution_precision": None,
         "evidence_verbatim": "She didn't want to make a big thing of it, but I could tell it's been weighing on her a lot"},
    ],
))

FIXTURES["correction"] = ("correction.txt", payload(
    people=[P("p_priya", "Priya", match="existing", existing="person-priya",
              rationale="matches known contact Priya")],
    entities=[E("e_deepmind", "DeepMind", "organization")],
    assertions=[
        A("p_priya", "employment", "She was at DeepMind the whole time before her current thing",
          object_entity_ref="e_deepmind", object_value="DeepMind", valid_to="2026-01", date_precision="fuzzy"),
    ],
    corrections=[
        {"subject_ref": "p_priya", "predicate": "employment", "object_like": "google",
         "kind": "never_true",
         "verbatim": "She never actually worked at Google, I must have mixed her up with someone else",
         "valid_to": None},
    ],
))

FIXTURES["homonym"] = ("homonym.txt", payload(
    people=[
        P("p_sarah_o", "Sarah Okafor", match="new",
          rationale="explicitly distinguished from known contact Sarah Chen (“Not Sarah Chen”) — met at the climbing gym"),
    ],
    entities=[
        E("e_ucsf", "UCSF General", "organization"),
        E("e_dogpatch", "Dogpatch", "place", aliases=["Dogpatch Boulders"]),
    ],
    assertions=[
        A("p_sarah_o", "life_event", "She just passed her nursing boards", object_value="passed nursing boards"),
        A("p_sarah_o", "employment", "she's starting at UCSF General in September",
          object_entity_ref="e_ucsf", object_value="nurse", valid_from="2026-09", date_precision="month"),
        A("p_sarah_o", "interest", "the Sarah I met at the climbing gym", object_value="climbing"),
    ],
    loops=[
        {"subject_ref": "p_sarah_o", "direction": "abdoul_owes",
         "description": "organize climbing at Dogpatch next month", "due_at": "2026-08",
         "due_precision": "month", "verbatim": "We talked about maybe climbing together at Dogpatch next month"},
    ],
))

FIXTURES["secondhand-chain"] = ("secondhand-chain.txt", payload(
    people=[
        P("p_alex", "Alex", match="existing", existing="person-alex", rationale="known contact"),
        P("p_leon", "Leon", match="existing", existing="person-leon", rationale="known contact"),
        P("p_marcus", "Marcus", status="known_of",
          rationale="never met — Leon's roommate, heard about through Alex"),
    ],
    entities=[E("e_shopify", "Shopify", "organization"),
              E("e_atlanta", "Atlanta", "place")],
    assertions=[
        # deep chain: Alex heard it from Leon — attribution is to the teller (Alex),
        # with the chain preserved in the verbatim
        A("p_marcus", "life_event", "apparently just sold his company to Shopify",
          object_entity_ref="e_shopify", object_value="sold his company to Shopify",
          source_kind="secondhand", attributed_to_ref="p_alex", hedged=True, confidence=0.4),
        A("p_marcus", "relation", "Leon's roommate, I think his name is Marcus",
          object_person_ref="p_leon", source_kind="secondhand", attributed_to_ref="p_alex",
          hedged=True, confidence=0.5),
        A("p_leon", "goal", "Leon himself is thinking about moving back to Atlanta",
          object_entity_ref="e_atlanta", object_value="moving back to Atlanta",
          source_kind="secondhand", attributed_to_ref="p_alex", hedged=True, confidence=0.5),
    ],
    threads=[
        {"ref": "t_leon_atl", "subject_ref": "p_leon", "title": "Moving back to Atlanta?",
         "archetype": "decision", "expected_resolution_at": None, "expected_resolution_precision": None,
         "evidence_verbatim": "Leon himself is thinking about moving back to Atlanta"},
    ],
))

FIXTURES["group-ramble"] = ("group-ramble.txt", payload(
    people=[
        P("p_tunde", "Tunde"),
        P("p_ama", "Ama"),
        P("p_marcus", "Marcus"),
        P("p_jen", "Jen"),
        P("p_kevin", "Kevin", match="existing", existing="person-kevin",
          rationale="“Kevin from my old job” — matches known contact"),
        P("p_deji", "Deji"),
        P("p_unknown_49ers", "(name not caught — 49ers jersey)", status="provisional",
          rationale="name never captured; provisional row awaiting identification"),
        P("p_unknown_2", "(name not caught — second guest)", status="provisional",
          rationale="name never captured"),
    ],
    entities=[
        E("e_oakland", "Oakland", "place"),
        E("e_chicago", "Chicago", "place"),
        E("e_berkeley", "Berkeley", "place"),
    ],
    assertions=[
        A("p_tunde", "life_event", "it's his new place in Oakland", object_entity_ref="e_oakland",
          object_value="moved to a new place in Oakland"),
        A("p_ama", "relation", "His sister Ama was there", object_person_ref="p_tunde"),
        A("p_ama", "location", "she flew in from Chicago", object_entity_ref="e_chicago",
          object_value="Chicago"),
        A("p_ama", "skill", "she does something in public health, I want to say epidemiology",
          object_value="public health — possibly epidemiology", hedged=True, confidence=0.5),
        A("p_jen", "relation", "Marcus and his girlfriend Jen", object_person_ref="p_marcus"),
        A("p_jen", "employment", "Jen just started a pottery studio in Berkeley",
          object_value="pottery studio founder", valid_from="2026", date_precision="year"),
        A("p_deji", "employment", "builds drones for a vineyard company",
          object_value="drone engineering for a vineyard company", hedged=True, confidence=0.6),
        A("p_kevin", "goal", "he's finally leaving his job to do woodworking full time",
          object_value="leaving his job for full-time woodworking"),
        A("p_tunde", "life_event", "his mom is visiting next month", object_value="mother visiting",
          valid_from="2026-08", date_precision="month"),
        A("p_unknown_49ers", "employment", "works in biotech I think", object_value="biotech",
          hedged=True, confidence=0.4),
    ],
    threads=[
        {"ref": "t_kevin_wood", "subject_ref": "p_kevin", "title": "Leaving his job for woodworking",
         "archetype": "decision", "expected_resolution_at": None, "expected_resolution_precision": None,
         "evidence_verbatim": "Kevin said he's finally leaving his job to do woodworking full time, we'll see"},
    ],
    loops=[
        {"subject_ref": "p_tunde", "direction": "abdoul_owes",
         "description": "help cook the dinner for his mom's visit", "due_at": "2026-08",
         "due_precision": "month",
         "verbatim": "he wants to host a dinner, I said I would help him cook it"},
    ],
    ambiguities=[
        {"question": "Someone at the party used to play professional rugby — the biotech guest in the 49ers jersey, or the other guest you couldn't name?",
         "candidate_refs": ["p_unknown_49ers", "p_unknown_2"],
         "assertion": A("p_unknown_49ers", "life_event",
                        "used to play professional rugby, or maybe that was the other one",
                        object_value="former professional rugby player",
                        source_kind="secondhand", attributed_to_ref="p_tunde",
                        hedged=True, confidence=0.3),
         "kind": "subject"},
    ],
))
# NOTE on the rugby attribution: "someone said" — teller unknown. Attributing to the
# host is itself a guess; the honest output is teller-unknown, but the schema requires
# an attributed_to for secondhand. Route: hedged + low confidence + the ambiguity carries
# it. Logged as a v2 prompt/schema refinement candidate (teller_unknown flag).

FIXTURES["silence"] = ("silence.txt", payload())

FIXTURES["contradiction"] = ("contradiction.txt", payload(
    people=[
        P("p_james", "James", match="existing", existing="person-james", rationale="known contact"),
        P("p_omar", "Omar", status="known_of",
          rationale="“that guy Omar he always talks about” — never met"),
    ],
    entities=[E("e_anthropic", "Anthropic", "organization")],
    assertions=[
        A("p_james", "employment", "he's at Anthropic now, started two weeks ago",
          object_entity_ref="e_anthropic", object_value="Anthropic",
          valid_from="2026-07", date_precision="month"),
        A("p_james", "trait", "he seems really energized by it", object_value="energized by the new role"),
        A("p_omar", "relation", "Same team as that guy Omar he always talks about",
          object_person_ref="p_james", source_kind="secondhand", attributed_to_ref="p_james"),
    ],
))

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    import jsonschema
    schema = json.loads((ROOT / "Sources/OrbitPipeline/Resources/extraction-schema-v1.json").read_text())
    errors = 0
    for key, (source, body) in FIXTURES.items():
        path = (TR / source) if (TR / source).exists() else (SYN / source)
        transcript = path.read_text()

        def check_verbatim(text, where):
            nonlocal errors
            if text and text not in transcript:
                errors += 1
                print(f"  ✗ {key}: {where} not a substring: {text[:70]!r}")

        for a in body["assertions"]:
            check_verbatim(a["verbatim"], "assertion.verbatim")
        for e in body["episodes"]:
            check_verbatim(e["narrative"], "episode.narrative")
        for t in body["threads"]:
            check_verbatim(t["evidence_verbatim"], "thread.evidence")
        for l in body["loops"]:
            check_verbatim(l["verbatim"], "loop.verbatim")
        for s in body["state_declarations"]:
            check_verbatim(s["quote"], "state.quote")
        for c in body["corrections"]:
            check_verbatim(c["verbatim"], "correction.verbatim")
        for amb in body["ambiguities"]:
            if amb.get("assertion"):
                check_verbatim(amb["assertion"]["verbatim"], "ambiguity.assertion.verbatim")
        try:
            jsonschema.validate(body, schema)
        except jsonschema.ValidationError as e:
            errors += 1
            print(f"  ✗ {key}: schema: {e.message[:120]}")

        fixture = {"model_id": MODEL_ID, "prompt_version": PROMPT_VERSION,
                   "source": str(path.relative_to(ROOT)), "payload": body}
        (OUT / f"{key}.json").write_text(json.dumps(fixture, indent=1, ensure_ascii=False) + "\n")
    if errors:
        sys.exit(f"{errors} fixture error(s)")
    print(f"{len(FIXTURES)} fixtures written + verbatim-verified + schema-valid")

if __name__ == "__main__":
    main()
