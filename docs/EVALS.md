# Orbit — Evaluation Framework

**Status:** Ratified 2026-07-28. Binding on all build work; the ratchet rule (§6) governs all future changes.
**Audience:** the agents (or humans) building Orbit. This document is your contract: it defines what success is, how it is measured, and what you may never break. Read [ORBIT.md](../ORBIT.md), [DATA-MODEL.md](DATA-MODEL.md), and [DESIGN.md](DESIGN.md) first — this document compiles their promises into checks.
**Companion:** every check here carries an ID (`INV-*`, `PIPE-*`, `J-*`, `D-*`, `PRIV-*`, `PERF-*`, `R-*`). Reference IDs in commits, PRs, and test names.

---

## 0. The central insight

Orbit is unusually evaluable, because its specification documents are unusually falsifiable. The constitution says *never silently rewrite history* — that is a property test. The design language says *no red anywhere* — that is a rendered-output lint. The data model says *notes never count as contact* — that is an invariant over a query. The product spec says *the Abdul ambiguity must become a question, never a guess* — that is a golden test with a known input sitting in `mock_memos/`.

**Evaluation for Orbit is therefore not a metrics dashboard bolted on after the fact. It is the systematic compilation of three documents' promises into executable checks.** When a promise cannot be compiled — "does it feel like memory?" — it is assigned to the one structured human evaluation loop (Layer 3) rather than silently dropped.

The corollary that makes this framework durable: **when the docs and the checks disagree, one of them is wrong, and the discrepancy is itself a finding.** Agents must never "fix" a failing check by weakening it to match behavior without a ratified doc change.

---

## 1. The four layers

| Layer | What it checks | Runs | Failure means |
| --- | --- | --- | --- |
| **L0 — Invariants** | Things that must never be false: data-model properties, schema lints, guard rules | Every commit, seconds | Build is broken. Nothing ships. |
| **L1 — Pipeline quality** | Transcription, extraction, classification, ranking — against golden datasets with thresholds | Every PR touching the pipeline | Quality regression. Nothing ships until threshold restored or doc-ratified. |
| **L2 — Journeys & design law** | End-to-end user flows with asserted end-states, friction budgets, rendered-output design lints, latency budgets | Every PR touching UI/flow | The app stopped serving a use case, or broke a design law. |
| **L3 — The human rubric** | What cannot be automated: does it *feel* like memory; is the brief's ranking humanly right | Weekly, by Abdoul, structured | Direction correction. Findings convert to L0–L2 checks wherever possible. |

Cross-cutting suites: **PRIV** (privacy/egress), **PERF** (latency budgets), and the **principle traceability matrix** (§7).

**Definition of Done for any feature:** L0 green · relevant L1 goldens at-or-above threshold · relevant journeys updated and green · design lint green · principle matrix row updated if the feature touches a principle · new capabilities arrive eval-first (§5.4).

---

## 2. L0 — Invariants

Property-based tests and schema lints. Each is small, fast, and absolute. Numbered for reference; grouped by the promise they enforce.

### History is never rewritten (P2)

- **INV-1** No UPDATE or DELETE ever executes against confirmed events or accepted assertions. Corrections exist only as Amendment/AssertionAmendment rows and CLOSE/CORRECT operations. *(Enforced at the storage layer — triggers or repository-pattern guard — not by convention.)*
- **INV-2** Retracted assertions remain queryable in the audit view; excluded everywhere else.
- **INV-3** CLOSE sets `valid_to` and never touches any other field; CORRECT sets `status=retracted` + reason and never deletes.
- **INV-4** Every read model (`current_state`, `timeline`, `network_graph`, `contact_rhythm`) can be dropped and rebuilt from the log to an identical state. *(Run nightly: rebuild and diff.)*

### Nothing is final without confirmation (P5)

- **INV-5** No code path writes an assertion, closes a thread, changes a profile, or creates a person except through an accepted Proposal or an explicit user action. *(Static check: the write API is only reachable from the proposal-resolution and user-edit modules.)*
- **INV-6** Re-extraction (any `extraction_version` > 1) produces only new pending proposals; it can never mutate accepted rows.
- **INV-7** A rejected proposal is never re-proposed **from the same source evidence**: re-running extraction (any version) over a transcript must not resurrect what Abdoul rejected from that transcript. **New evidence may legitimately re-propose** — facts become true later, and a rejection is a verdict on a claim *at a time from a source*, not on the claim forever (P11: things change). A new-evidence re-proposal must disclose its history: *"you passed on something like this before — mentioned again at Tuesday's dinner."* Silent re-proposal of previously rejected content without new evidence is the failure (PIPE-8).

### Uncertainty is stored, not resolved (P4)

- **INV-8** An assertion with `subject_candidates` (unresolved subject) never appears in any read model, search result, or brief.
- **INV-9** Provisional and `known_of` people never receive relationship state, orbit, cadence, maintenance prompts, or reach-out suggestions.
- **INV-10** Secondhand assertions always carry `attributed_to_person_id`; firsthand never do.

### Contact is sacred (§7.11 guards)

- **INV-11** Events where a person's attendance is `about` never count toward that person's contact rhythm, "last seen," or `conversations_since_mention` increment.
- **INV-12** Events with `derived_from_event_id` set never enter rate math or derivative comparisons.
- **INV-13** Co-attendance (knows-each-other) edges derive only from present-attendance events.
- **INV-14** `first_met_event_id` never references a note-kind event.

### Relationships are not scores (P6)

- **INV-15** Schema lint: no numeric column whose name or semantics aggregate relationship quality (`strength`, `closeness`, `health`, `score`) exists on any person- or relationship-shaped table. No query in the codebase aggregates per-person fact metrics into a single ranking of people. *(Grep + code-review gate; the lint names the forbidden patterns.)*
- **INV-16** No API exists that returns people sorted by contact rate or any composite metric.

### Structural safety

- **INV-17** Merge sets `merged_into` only; zero assertion rows are rewritten. Unmerge restores the pre-merge query results exactly.
- **INV-18** Every assertion, thread, loop, and contact point carries a resolvable `source_event_id` (provenance is total).
- **INV-19** Every event has ≥1 participant of any attendance kind.
- **INV-20** `condition_hardship` threads never generate proactive prompts of any kind — no suggestion object is ever constructed from one. *(This is the "never cheerfully raise grief" rule; it gets its own invariant because its failure mode is the worst in the product.)*
- **INV-21** Bitemporal correctness fuzz: generate random assert/close/correct/amend sequences; verify that validity-time queries and observation-time queries each reconstruct the correct view at every point. *(Property-based, the workhorse test of Decision 1.)*

---

## 3. L1 — Pipeline quality

### 3.1 The corpus

- **Real captures** (`mock_memos/`): the three ratified memos + confirmed transcripts, plus every future real capture Abdoul reviews. Real memos are the *validity* anchor — messy, disfluent, true.
- **Synthetic captures**: authored to cover cases too rare or too important to wait for — and some cases we *hope* never to capture live. Required synthetic coverage: hardship disclosure (grief, illness — tests INV-20 and extraction tone), a correction memo ("actually, I was wrong — she never worked at Google" → CORRECT not CLOSE), homonym collisions, deep secondhand chains ("Alex said that Leon's roommate thinks…"), a maximally rambling group event (8+ people), a memo that contains nothing extractable (silence test: zero proposals is the correct output), a memo contradicting established facts (must propose CLOSE/CORRECT, never silently overwrite). **Grief-handling is validated on synthetic data before launch, never discovered on real grief.**
- **Golden format**: each corpus item = audio (or text) + verified transcript + expected proposal set (op, subject, claim-essence, flags) + expected *non*-proposals (things that must NOT be extracted or asserted).

### 3.2 The review flow is a labeling machine — with correctly scoped labels

Every real review session generates ground truth, but the label must be scoped to what the decision actually judged. A rejection is **not** "this claim is false forever" — it is *"this extraction, from this source, was wrong or unwanted at this time."* Facts become true later; interests emerge; a rejection may mean mis-attribution, overstatement, or just "not worth keeping," each a different training signal.

Therefore:

- **Labels attach to (source-event, claim) pairs**, never to bare claims. A rejection is a hard negative *for extraction from that transcript* — valid and permanent as an extraction-quality label, silent about the world's future.
- **Suppression follows the same scope** (INV-7): same-source re-proposal forbidden; new-evidence re-proposal allowed, with disclosed history.
- **Optional one-tap rejection reason** — *not true · wrong person · not worth keeping* — sharpens both the suppression scope and the eval label. Strictly optional and skippable: a bare "No" must stay one tap (P3), and the reason prompt must never nag.
- Accepts are positives; edits are correction pairs (what the model said → what was true) — the richest signal of the three.

The eval set grows with usage by design; the build must implement review-outcome export from day one (journey J-12).

### 3.3 Metrics and thresholds

Thresholds are **provisional until first measured** (marked ◊), then become ratchets: they may tighten, never loosen, without a ratified doc change.

| ID | Metric | Threshold | Notes |
| --- | --- | --- | --- |
| PIPE-1 | Transcription proper-noun recall (primed) | ◊ ≥ 95% | Names are the product; measured on names/orgs only, not general WER |
| PIPE-2 | Transcription WER, conversational | ◊ ≤ 12% | Secondary to PIPE-1 |
| PIPE-3 | Extraction fact recall | ◊ ≥ 90% | Missed facts are recoverable later (re-extraction); recall matters but is not critical |
| PIPE-4 | Extraction precision (no invented facts) | ◊ ≥ 97% | **Asymmetric by design (P4): inventing is far worse than missing.** A hallucinated fact that survives to a proposal is a Critical failure regardless of aggregate score |
| PIPE-5 | Hedge preservation | **100%** | Every "I think / probably / maybe" in source survives into the proposal's confidence framing. Binary and cheap to check — zero tolerance |
| PIPE-6 | Verbatim fidelity | **100%** | Every `verbatim` field is an exact substring of the transcript. Purely mechanical |
| PIPE-7 | Attribution: false-attribution count | **0** | A fact assigned to the wrong person, or hearsay marked firsthand, is Critical. The Abdul case must yield DISAMBIGUATE — this exact memo is in the golden set |
| PIPE-8 | Same-source re-proposal of rejected content | **0** | Scoped per §3.2; new-evidence re-proposals are legitimate and must disclose history |
| PIPE-9 | DISAMBIGUATE recall on planted ambiguities | ◊ ≥ 90% | Synthetic memos plant known ambiguities; the extractor must ask |
| PIPE-10 | Thread-bar precision | ◊ ≥ 85% | No thread proposed without a plausible resolution ("she likes sushi" must not thread) |
| PIPE-11 | Archetype classification vs. Abdoul's review decisions | ◊ ≥ 85% | Ambiguous cases must default to the slower archetype (tie-break rule is itself asserted) |
| PIPE-12 | Episodic/semantic split accuracy | ◊ pending portrait memo | Gate for the onboarding build |
| PIPE-13 | Entity resolution: fragmentation rate | ◊ ≤ 5% | Same real-world context spawning duplicate entities across the corpus |
| PIPE-14 | Recall-ranking sanity (brief assembly) | rule-based, 100% | Open threads present; hero slot = top unsurfaced item; `muted` absent; `pinned` wins; hardship threads render as context, never as suggested openers |

LLM-judged metrics (rationale faithfulness, proposal-claim ≤ source-meaning) use a fixed judge model + rubric per metric, with judge outputs spot-audited in L3. Judge prompts are versioned artifacts in the repo.

### 3.5 Evaluating nondeterminism: contracts, consistency, metamorphosis

The extraction layer is an LLM; exact-match evaluation is both brittle and wrong. The framework takes **both** of the available paths, allocated by what each output layer *is* — and turns the model's variance from a nuisance into an instrument:

**Deterministic where the property is mechanical.** Verbatim-substring (PIPE-6), hedge-word presence (PIPE-5), structural validity, every INV: these admit no variance and get exact checks. Model and decode parameters are pinned per release for CI reproducibility — pragmatic determinism, cheap where it's available.

**Contract-based where the content is semantic.** Goldens are **contracts, not transcripts**: a required-facts set (matched semantically, not verbatim), a forbidden-content set, required flags, structural rules. Two phrasings of "Sarah wants to learn videography" both pass; an invented detail fails regardless of phrasing. This is already implicit in the golden format (§3.1, "claim-essence"); it is now explicit policy.

**Variance as a confidence signal — the LLM-native move.** Run extraction k times (k=5–10) over the same transcript:

- Facts appearing in ~all runs are the **stable core**.
- Facts that *flicker* across runs are exactly the ones the model is unsure of — and P4 already defines the correct product behavior for uncertainty: hedge it or ask.
- **PIPE-15 (calibration):** flicker-rate must correlate with uncertainty handling — a fact appearing in <70% of runs must carry reduced confidence or arrive as DISAMBIGUATE; a stable-core fact must not be needlessly hedged. *The model's own variance becomes the uncertainty meter that the product's confirmation machinery was built to consume.* Under this frame, nondeterminism is not a defect to suppress but a free ensemble.

**Metamorphic testing — invariance without exact matching.** Apply meaning-*preserving* perturbations (sentence reorder, filler words, consistent name substitution) → decision-relevant output must not change. Apply meaning-*changing* perturbations (insert "I think"; swap who-said-what) → output must change *in the required direction* (hedge appears; attribution follows). **PIPE-16:** the metamorphic suite passes when invariants hold under preservation and sensitivities fire under change. This tests the pipeline's *judgment*, not its phrasing — and name-substitution doubles as an attribution-robustness probe.

**Judge governance for the judged metrics:** critical judged metrics use a small panel rather than one judge, with an adversarial second judge prompted to *refute*; disagreement escalates to L3. Judges are spot-audited against Abdoul's rubric scores quarterly — a judge that drifts from the owner's judgment is replaced, not argued with.

### 3.4 Eval-first for new capabilities

Before building a capability, write its goldens. Search is the model case: the corpus already contains known answers — "greece picnic guy" → Nikos, "who do I know at Google" → the James/Maya fixtures, "who did I meet through Alex" → provenance chains. A capability without goldens is not ready to be built. (This is the agent-facing north star in practice: *you know what done looks like before you start.*)

---

## 4. L2 — Journeys, design law, and budgets

### 4.1 Journey suite

Each journey is an executable UI test: scripted steps → asserted **end-state in the database** (not just screen state) → friction budget (taps/inputs to complete). Journeys map directly to the ORBIT.md §18 inventory.

| ID | Journey | Key end-state assertions | Friction budget ◊ |
| --- | --- | --- | --- |
| J-1 | Capture → transcript → review → sync, single person (Nikos memo) | Event confirmed; audio deleted **only after** full-model transcript confirmed; N accepted assertions with provenance | ≤ 12 taps |
| J-2 | Group event with ambiguity (Futureforce memo) | Abdul DISAMBIGUATE resolved or deferred; per-person grouping rendered; partial resolution persists correctly | ≤ 20 taps |
| J-3 | Defer everything | Event sits half-reviewed indefinitely; **zero** badges/counters/nags anywhere afterward (assert absence) | ≤ 3 taps |
| J-4 | Transcript edit + name fix | Edit persists as the transcript; name correction propagates to all of that person's proposals |  |
| J-5 | Typed micro-note | Text-as-transcript; subject gets `about` attendance; INV-11 holds in rhythm queries |  |
| J-6 | Profile after 3 captures | Desk sections show correct content in fixed order; empty sections absent, not placeholder'd |  |
| J-7 | Walk-me-in deck | Card order matches Desk order; `last_surfaced_at` written; ends on "Go be present." |  |
| J-8 | Search: name / question / fragment | Known-answer queries return their goldens; results render as-you-type (no submit affordance exists) |  |
| J-9 | Secondhand → reconfirmation | `known_of` person promoted on first real meeting; secondhand facts flagged `needs_reconfirmation`; nothing quarantined |  |
| J-10 | Merge + unmerge | INV-17 verified through the UI path |  |
| J-11 | Sync-later | Unsynced event resumable from home footer; proposals identical to immediate-sync case |  |
| J-12 | Review-outcome export | Every accept/reject/edit lands in the eval-harvest log (feeds §3.2) |  |

Friction budgets are ◊ provisional: measure the built flow once, ratify the number, then ratchet.

### 4.2 Design-law lint

Automated checks against **rendered output** (snapshot/DOM/style census), not stylesheets — the law is about what ships to the eye. Run on every UI PR, both rooms.

- **D-1** No red: no rendered color within the forbidden hue band, anywhere, ever.
- **D-2** No badges or unread counters exist in any view hierarchy.
- **D-3** Two-voices census: serif families appear only on memory-content nodes (names, verbatim, memory items, transcripts, deck mains, "Go be present."); interface chrome is sans. Violations listed by node.
- **D-4** Ember is alone: rendered accent colors ∉ {ember, ember-wash, ember-ink} ⇒ fail. Ember-family coverage ≤ ◊5% of any screen's pixels.
- **D-5** Night: ≤ 4 star-dust nodes, top 10% of screen only, exactly one ember-tinted, none animated. Day: zero.
- **D-6** Exactly ≤ 1 tilted element per screen; tilt only in the day room; glow only in the night room.
- **D-7** Emphasis inside memory text is ember-wash underline only — no bold/italic emphasis nodes within memory content.
- **D-8** No empty-state filler: sections with no content are absent from the tree, not rendered with placeholder copy.
- **D-9** Counts shown anywhere equal true counts (no rounding, no "99+").
- **D-10** Token conformance: every rendered color/radius/font resolves to a token from `v3-mockup.html`; no literal values.
- **D-11** Copy lint: forbidden lexicon ("remaining", "overdue", "pending review", "streak") absent; required hedge-words present when the underlying assertion carries uncertainty.

### 4.3 Performance budgets (PERF)

All ◊ provisional, measured on target hardware, p95:

- **PERF-1** Search keystroke → results: ≤ 150ms (set by the mid-conversation check).
- **PERF-2** Brief assembly (Desk, 50k-assertion store): ≤ 400ms.
- **PERF-3** Capture start: mic tap → recording: ≤ 300ms.
- **PERF-4** Transcription: ≤ 1.5× realtime on-device, full model.
- **PERF-5** Extraction round-trip: ≤ 20s for a 3-minute memo (async, with honest progress UI).
- **PERF-6** Cold launch → home interactive: ≤ 1.5s.

### 4.4 Privacy suite (PRIV) — the trust promises, mechanically

- **PRIV-1** **Audio never egresses.** Network interception during full capture flows: zero requests containing audio bytes, in any encoding. Absolute.
- **PRIV-2** **Single-endpoint budget.** The only permitted network destination carrying user content is the extraction API. Any second content-carrying destination = Critical. (Analytics, crash reporters carrying content: forbidden.)
- **PRIV-3** Audio deletion verified at the filesystem level after confirmation (full-model gate honored — J-1 asserts the *only after* condition).
- **PRIV-4** Extraction payloads contain the transcript + necessary context only — audited schema for the request body; nothing beyond it.
- **PRIV-5** Export produces a complete, human-readable archive; a fresh install restored from export passes INV-4 equivalence.

---

## 5. L3 — The human rubric

What automation cannot reach, structured so it still produces signal. Weekly during active building; after every major flow change. Abdoul scores 1–5 with a written note per item:

1. **The memory test** — open a brief for someone real: did anything come back that you'd genuinely forgotten? ("I can't believe you remembered that" is a 5.)
2. **The paperwork test** — after a real capture+review: did it feel like remembering, or like filing expenses?
3. **The 90-second test** — brief read under real time pressure: did the fixed skeleton deliver orientation, or did you scan?
4. **The confidence test** — anything the system asserted that overstated what you actually said? (Any yes = automatic finding, feeds PIPE-4/5.)
5. **The tone test** — any moment the app felt like a CRM, a game, or a nag?

**Protocol:** findings are triaged into (a) a new automated check (always preferred), (b) a doc change proposal, or (c) a logged judgment call. A rubric finding that recurs twice must become (a) or (b) — feelings that persist are specifications in disguise.

---

## 6. Failure severity and the ratchet

| Severity | Definition | Examples | Policy |
| --- | --- | --- | --- |
| **Critical** | A constitutional promise broken | False memory created (invented fact, wrong attribution); silent write without confirmation; audio egress; INV-20 violation; history rewritten | Ship-blocking. Fix before any other work. Postmortem note in the PR. |
| **Major** | Quality regression below threshold | PIPE metric under threshold; journey broken; design-law violation; budget blown | Ship-blocking for the affected surface. |
| **Minor** | Polish deviation | Copy tone, sub-threshold latency drift, lint warnings | Fix-forward, tracked. |

**The ratchet:** thresholds move in one direction. Loosening any threshold or weakening any invariant requires a ratified change to the source document that the check compiles from — never a test edit alone. Agents: if a check blocks you and seems wrong, *the check might be right* — escalate with a doc-change proposal instead of routing around it.

---

## 7. Principle traceability matrix

Every constitutional principle maps to its enforcing checks. A PR touching a principle's territory cites the row. Gaps in this matrix are themselves findings.

| Principle | Enforced by |
| --- | --- |
| P1 Human authority | INV-5, INV-6, J-2, J-9 |
| P2 Never rewrite history | INV-1..4, INV-21, J-10 |
| P3 Effortless capture | J-1/J-3/J-5 friction budgets, PERF-3/4 |
| P4 Accuracy > automation | PIPE-4/5/7/9, INV-8/10, rubric #4 |
| P5 Nothing final without confirmation | INV-5/6/7, J-3, J-11 |
| P6 Not scores | INV-15/16, D-9 |
| P7 Small details matter | PIPE-5/6, D-3/D-7, rubric #1 |
| P8 Show up better | anti-metrics (§8), INV-16, rubric #5 |
| P9 Context before contact | PIPE-14, "Today"-zone reason-required (type-level: suggestion objects have non-null reason) |
| P10 Memory, not administration | D-2/D-8/D-11, J-3, rubric #2/#5 |
| P11 Change is visible | INV-3 (CLOSE preserves), timeline journeys, RelationshipState versioning check |
| P12 Human meaning | The rubric, in total. Not automatable; deliberately owned by a person. |

---

## 8. Metrics discipline: observed for the owner, never optimized by the builder

Usage metrics serve two different masters, and the policy differs by master:

**For build evaluation (this framework): usage metrics are inadmissible.** No PIPE/J/D check may reference usage volume, session counts, or engagement. "People used it more" is never evidence that a build is good — the builds are judged by L0–L3 only. Agents must not instrument, report, or optimize against engagement, and engagement-shaped *mechanics* (streaks, badges, activity goals) remain forbidden outright (D-2, D-11).

**For product direction (the owner's learning): a private usage journal is legitimate and useful.** Local-only, surfaced to Abdoul alone, framed as questions rather than scores — which door gets used, which brief sections get opened, which search shapes recur, what gets captured vs. what gets asked about. This is how "what should be expanded?" gets answered with evidence instead of vibes. Rules that keep it safe:

- Local device only; never leaves; never in CI; never visible to building agents as a target.
- Feature-level, never person-level — it may say "the fragment search is used daily," never "you interact with Sarah most."
- Surfaced as periodic reflection ("you've opened briefs 9 times this month, mostly before dinners"), never as goals, comparisons, or nudges.

The line, stated once: **metrics may inform the owner's judgment; they may never substitute for it, and they may never become a builder's objective.** The product's success metric remains rubric #1 on real relationships: an Orbit opened twice a month before meaningful reunions, producing "I can't believe you remembered that" both times, is succeeding.

---

## 9. Open items

- All ◊ thresholds: provisional until first measurement on the built system, then ratified and ratcheted.
- PIPE-12 blocked on the portrait memo (in progress).
- PIPE-15's k (consistency runs) and the 70% flicker boundary: provisional; calibrate against the real-memo corpus.
- Judge-model selection, panel composition, and prompt versioning scheme for LLM-judged metrics.
- Friction-budget numbers: set after first implementation pass, not before.
- Whether J-suite runs on-device in CI (simulator matrix) — build-infrastructure decision.
- Usage-journal surface design (the §8 owner reflection) — a product surface, deferred to DESIGN.md's register once the policy is ratified.
