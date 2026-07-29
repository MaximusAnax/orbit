# Golden: Eliah portrait (first portrait-class golden)

**Status:** GROUND TRUTH — reviewed and confirmed by Abdoul 2026-07-28, including the source/world divergence case (audio verified by ear: it says "Google").
**Source:** `mock_memos/Eliah.m4a` (10:28) · transcript `mock_memos/transcripts/Eliah.txt` (unconfirmed).
**Format:** contract, not transcript (EVALS §3.5) — required facts match semantically; forbidden items fail in any phrasing.
**Era anchor stated in source:** "we're going into our senior year right now" → freshman year resolvable to 2023–24. Extraction MAY resolve era-relative dates against this stated anchor; it must NOT invent calendar dates beyond it.

---

## People

| Required | Contract |
| --- | --- |
| Exactly **one** new person for the subject | Four transcription spellings (Elia / Ilya / Aaliyah / alia) must resolve to a single person. **Two or more subject-persons created = Critical fail** (identity fragmentation). Display name per Abdoul's fix at review: "Eliah Tapia". |
| Philly — new person, friend | Must be a *person*, never confused with the city. |
| Roger — new person | Known only slightly ("this other guy named Roger"); minimal facts. |

## Episodes (→ CREATE_EVENT proposals, past occurrences only)

| ID | Episode | When-ish (era-relative) | Notes |
| --- | --- | --- | --- |
| EP-1 | Met at Tartan Scholars early move-in days | freshman fall | The met-event candidate — though the source itself hedges its status: "that's when we met… but we didn't really hang out much." The hedge must survive into the proposal. |
| EP-2 | Japan trip over spring break, with friends | sophomore spring | Sub-moments (day-one exploring, shared flight) stay **inside** this episode's narrative — one event, not three. |
| EP-3 | Colombia fall-break trip | junior fall | |

**Borderline, flagged (flicker proxies — either classification acceptable, must be consistent):**
- The "run it back" decision (agreeing to live together senior year): a *future arrangement* — belongs as thread/upcoming interval, **not** a reconstructed event (episodes are past). If proposed as an event: fail.

## Periods & habits (→ interval assertions)

- Roomed together, sophomore year (interval).
- Same classes + habitual studying/homework together, freshman year (habit).
- Eliah interned at **Google** *per the source* — see the source/world divergence case below. (Employment, **closed interval** — see Forbidden.)
- Junior year: lived separately (singles); shared one very difficult course (count hedged in source: "maybe one"); late-night library sessions with Philly (habit).
- Eliah played basketball at Riverbank park — high-school era, fuzzy interval.
- Upcoming: living together again, senior year (interval, `valid_from` ≈ fall 2026) — and/or a thread; not an event.

## Facts & traits (→ plain assertions)

Education: CS at Carnegie Mellon; Tartan Scholars (both). Origin: Washington Heights, NYC. Identity: Dominican, Black; same age as Abdoul. Interests: anime (childhood-formative — verbatim-worthy), sports, video games, basketball. Personality: reserved with strangers, funny once known; complements Abdoul's energy. Family: predominantly immigrants. Concurrent-with-213 course load, junior fall (with the source's own "I don't know how he managed that").

## Required flags

- Hedges preserved (PIPE-5, zero tolerance): "I'm not even really sure how it started" · "I want to say" · "I think it was actually maybe one" · "I believe".
- DISAMBIGUATE (or probable-marking) accepted for: the summer living arrangement ("he, they actually lived together… him, Philly, and this other guy named Roger" — who lived with whom is fuzzy).

## Forbidden (fail in any phrasing)

- **"Eliah works at Google"** as a current fact — it was an internship, closed interval. The classic tense trap.
- The Riverbank crossed-paths speculation ("we probably ran into each other at some point") as an event or fact — it is a joke/speculation; at most a verbatim-preserved color detail on the relationship, never an assertion of a meeting.
- Any second subject-person from the name variants.
- A reconstructed event for anything future.
- Any invented calendar date not derivable from the stated senior-year anchor.

## Known source/world divergence — the internship employer

Eliah's actual internship was at **Uber** (world-truth, per Abdoul); the audio at ~4:37 says **"Google"** — confirmed by every ASR probe *and by Abdoul listening to 4:34–4:44*. A verified speaker misstatement: the corpus's first natural instance of source-truth ≠ world-truth. The contract grades all three layers:

1. **Transcript**: "Google" — faithful to what was said. Correcting the transcript to Uber = fail (source falsification).
2. **Extraction**: must propose Google. An extractor that outputs Uber has consulted something other than the source — silent "fixing" is the P4 nightmare. Extraction fidelity is to the source, never the world.
3. **Expected edit-pair**: at review, Abdoul edits Google → Uber; the accepted assertion carries Uber with the edit recorded (`edited_payload`). The world enters through the human, nowhere else.

*(If listening proves the audio says Uber, this section converts to a Critical PIPE-1 substitution finding and the transcript fixture is corrected — flag it and the golden updates.)*

## Self-profile requirements (graded as of 2026-07-28 — was ungraded region 1)

Required, targeting the `is_self` row (DATA-MODEL §7.12) — **never a newly created person** (a new "Abdoul" person = INV-22 fail):

- Origin: the Bronx — lived at 167th and Grand Concourse (verbatim-worthy).
- CS at Carnegie Mellon; Tartan Scholars.
- Interned at **Microsoft**, same summer (closed interval — same tense trap as Eliah's).
- Trait: energetic, "all over the place" (his own words).
- **"We" splits**: "we both love anime" and kin produce paired assertions — one for Eliah, one for self, same verbatim.
- Era anchor: "going into our senior year right now" registers on the self timeline; it is what makes every era-relative date in this memo resolvable.

## Relationship-state requirements (graded as of 2026-07-28 — was ungraded region 2)

Required: **one `PROPOSE_STATE` proposal for Eliah** whose narrative quotes an explicit declaration verbatim — "he would be in the inner, inner, inner circle, right there along with my family" (or the best-friend declaration), with **Inner Orbit** as the mapped suggestion, mapping shown as suggestion, not fact.

Forbidden: any state proposal citing anything other than a verbatim explicit declaration (INV-24) — ten minutes of warmth is not a declaration; "I'm excited for us to grow closer" is intent color, not an orbit statement, and must not independently trigger the op.
