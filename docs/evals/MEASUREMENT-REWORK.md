# Measurement rework — scoping

**Status:** Part 1 stands as the assessment. Part 2 Phase 0+1 **built
2026-08-07**; Phase 2–3 remain proposals. Part 3's decisions were taken the same
day and are recorded inline below.
**Companion:** [EVALS.md](../EVALS.md) is the contract. This document does not
propose changing it. It argues that **the implementation does not yet compile
it**, and scopes the work to close that gap.

---

## Part 1 — Is the current method good enough?

**No — but the fault is almost entirely in the implementation, not the design.**

EVALS §3.5 is genuinely ahead of where most eval harnesses land: it already
rejects exact-match grading, already specifies contract-based semantic matching,
already treats model variance as a *free ensemble* rather than a nuisance, and
already specifies judge panels with an adversarial refuter. Very little below
argues with any of that.

The problem is that the grader implements a cruder thing than the document
describes, and the gap is not conservative — it is **biased**, in a direction
that makes a good extractor look bad and makes an invented fact invisible.

### A. Where the grader does not compile the spec

**A1 — PIPE-4 measures a count; the spec defines a rate. This is the serious one.**

| | |
| --- | --- |
| Spec | "Extraction precision (no invented facts) ◊ ≥ 97%" |
| Code | count of hits against a hand-enumerated `forbidden:` list, reported against a target of 0 |

There is no denominator and no pass over emitted facts. **The harness can only
detect inventions that someone predicted and wrote down.** An invented fact
nobody anticipated is not scored as a failure — it is not scored at all.

For a product whose central promise is that it does not invent — where P4 says
in as many words that inventing is far worse than missing — the most important
metric in the framework currently does not exist. Everything else in this
document is secondary to that.

**A2 — Required facts are matched by substring and exact predicate, though §3.5
ratifies semantic matching.**

§3.5: *"a required-facts set (matched semantically, not verbatim) … Two
phrasings of 'Sarah wants to learn videography' both pass."*

The code: `norm()` is `.lower()`, matching is Python `in`, and the predicate must
be string-equal. Measured on the live fixtures — relaxing **only** the predicate
requirement, changing nothing else:

| | required assertions hit |
| --- | --- |
| exact predicate (what we report) | 26 / 39 — **66.7%** |
| predicate ignored | 30 / 39 — **76.9%** |

So roughly **10 points of the headline recall gap is taxonomy disagreement, not
missing facts.** The four recovered items:

```
eliah             wanted 'interest'    model said 'life_event'   (basketball)
eliah             wanted 'life_event'  model said 'relation'     (rooming together)
secondhand-chain  wanted 'goal'        model said 'location'     (atlanta)
group-ramble      wanted 'goal'        model said 'employment'   (woodworking)
```

**And this is exactly why the fix is not a looser matcher.** Basketball as
`life_event` rather than `interest` is a fair equivalence. Atlanta as `location`
rather than `goal` is **not** — "wants to move to Atlanta" and "lives in Atlanta"
are different claims, and collapsing them is precisely the kind of silent
meaning-drift the constitution exists to prevent. A blind relaxation would
forgive a real error; the strict matcher punishes a fair one. Only adjudication
separates them, which is what §3.5 already asks for and what is not built.

Net: **true recall is unknown within about a 10-point band.** Against a ◊ ≥ 90%
gate, a 10-point measurement band is disqualifying on its own.

**A3 — The reference fixtures are self-graded, and have been functioning as a
ceiling.** They were authored in-session by a model that could see the goldens,
so they align with the goldens' phrasing *and* their predicate choices — the two
things A2 shows the grader is most sensitive to. The "100% reference vs 62% live"
comparison reported on 2026-08-07 is contaminated by that mechanism and should
not be repeated without adjudication. BUILD already calls these fixtures
provisional by definition; in practice they have been read as a baseline.

**A4 — Coverage drift, both directions.** Specified but unimplemented: PIPE-1,
PIPE-2 (transcription entirely), PIPE-8, PIPE-14, PIPE-15, PIPE-16. Implemented
but unspecified: **PIPE-17** (tag discipline) exists in the grader and is absent
from the EVALS table — it should be registered there or removed.

### B. Where the measurement is unreliable

**B1 — Single-run point estimates on a stochastic system.** Two consecutive runs
of the identical prompt: round-trip 7/10 then 9/10, criticals 32 then 14, PIPE-6
FAIL then 100%. Already recorded as FN-37.

**B2 — Decode parameters are not pinned, though §3.5 requires it.** Only
`max_tokens` is set; temperature is the provider default. §3.5: *"Model and
decode parameters are pinned per release for CI reproducibility."* This is the
cheapest available lever on B1 and it has never been pulled.

**B3 — No per-check flicker classification.** Without it there is no way to tell
a real regression from a coin flip, and **a gate built on a flickering check is a
lottery** — which is how teams learn to ignore their own CI.

**B4 — Prompt comparisons are unpaired.** A/B is currently two independent point
estimates, the least sensitive design available. The same items run under both
conditions should be compared pairwise.

### C. Where the setup is not valid

**C1 — Harness/production skew, structurally.** Two instances found on
2026-08-07 (FN-36): every memo labelled `portrait`, and a seeded ledger hidden
from the extractor. Both silent, both invalidating. Vigilance is not the fix —
the harness and the app should build their extraction context through **the same
code path**, so skew becomes impossible rather than merely noticed.

**C2 — Train/test contamination, committed on 2026-08-07.** Prompts v4/v5/v6
were tuned against the same 11 memos they were scored on, with the goldens in
context. There is no holdout. Any apparent gain is partly overfitting and should
not be cited as evidence.

**C3 — A stress suite is being scored as if it were a representative sample.**
The corpus is deliberately adversarial by design (§3.1: homonyms, contradiction,
hardship, an 8-person ramble, a silence test). A ◊ ≥ 90% target was presumably
imagined for typical input. One number over both kinds of memo answers neither
"is it safe on the hard cases" nor "is it good on ordinary ones."

**C4 — The corpus is small.** 12 transcripts, ~3.3k words, 90 required items.
Binomial noise alone is several points before run-level variance is added.

**C5 — No model-wrong vs golden-wrong triage.** EVALS §0 states the principle —
"when the docs and the checks disagree, one of them is wrong, and the discrepancy
is itself a finding" — but the report format has nowhere to record it, so every
disagreement silently scores against the model. The eliah episode count (golden
says 3, model said 5, two of them arguably periods) is an open instance.

---

## Part 2 — The rework

### The architectural move that matters

**Separate collection from grading.**

Persist every run's raw output, with the request, the decode parameters, token
usage, latency, prompt hash, and git SHA. Grade offline from that store.

This is what makes the overnight job worth running *before* the grader is fixed:
the expensive, slow, API-billed part is collection, and **collected runs can be
re-graded for free, forever.** Every validity fix in Part 1.A can then be applied
retroactively to data already on disk, and old runs can be re-scored under new
graders to see whether a conclusion was ever real.

Without this split, every grader improvement costs another full API run and
every historical number becomes unrecoverable.

### Phase 0 — make an overnight job survivable and honest

Small, and all of it is prerequisite to trusting anything the job produces.

- **Pin and record decode parameters** — temperature, top_p, seed where the
  provider supports it. Record what was used in every fixture (§3.5 compliance).
- **Capture per-extraction telemetry** — prompt/completion tokens, wall-clock
  latency, retry count. Latency feeds PERF-5 (≤ 20s) for free.
- **Retry with backoff** on transient failures. A timeout killed a full run on
  2026-08-07; over k runs unattended, that is a certainty, not a risk.
- **Checkpoint and resume** — a job that dies at run 7 of 10 must not discard 7.
- **Share the context-builder with the app** (C1) so harness skew cannot recur.

### Phase 1 — the k-run collector

- `measure --live --runs k --model M --out DIR`, bounded concurrency, per-run
  fixtures under run-indexed directories.
- Aggregation: per-check pass **rate** across runs; per-required-item hit rate;
  distribution (median, min, max, IQR) for every PIPE metric.
- **Flicker classification** per check: stable-pass, stable-fail, or flickering,
  using PIPE-15's provisional 70% boundary. Gates may only be built on stable
  checks; flickering checks report but never block until calibrated.
- Machine-readable JSON alongside the markdown report.

### Phase 2 — grader validity (this is what changes the numbers)

- **True precision (A1):** iterate every emitted assertion and adjudicate
  support against the transcript. Mechanical first pass (is the verbatim a real
  substring, does the object appear); judge panel for the semantic residue, per
  §3.5's existing judge-governance rules. This creates PIPE-4's missing
  denominator.
- **Semantic required-fact matching (A2):** adjudicate equivalence rather than
  loosening the string match — explicitly preserving the Atlanta distinction.
  Validate the judge against the strict matcher on the items where they agree,
  and hand-review every disagreement the first time.
- **Suite split (C3):** `stress` and `representative`, separate targets.
- **Frozen holdout (C2):** touched only at ratification, never during tuning.
- **Layer attribution:** round-trip failures name the layer that owns them —
  two of the five on 2026-08-07 were SyncEngine, not extraction.
- **Golden-disagreement channel (C5):** a first-class report row.

### Phase 3 — the PIPE-15 payoff

Phase 1's per-item flicker rates are exactly the input PIPE-15 was specified to
consume. Once they exist, the calibration claim becomes testable for the first
time: *do items appearing in <70% of runs actually arrive hedged or as
DISAMBIGUATE, and are stable-core items left unhedged?*

Worth stating plainly, because it changes what this work is: **§3.5's ensemble is
not only a measurement device — it is a candidate product mechanism.** Running
extraction k times and routing low-agreement items to a question is a real design
option, not just an eval technique. It would cost k× on latency and spend against
PERF-5, so it is a genuine tradeoff rather than a free win, and it deserves its
own decision once the flicker data exists.

### What the overnight job is, concretely

Phase 0 + Phase 1. Collection only, graded afterward and re-gradable.

Rough shape — **estimates, and instrumenting them is part of Phase 0:** ~3k input
tokens per extraction (v6 prompt ≈ 2.5k plus a short transcript), a few thousand
out; 11 memos × k=10 × 2 models ≈ 220 extractions, on the order of 2M tokens and
25–90 minutes depending on concurrency. Cheap enough that k is not the binding
constraint — **rate limits and provider keys are.**

---

## Part 3 — Open decisions

1. ~~**The model matrix.**~~ **Decided 2026-08-07: OpenAI only.** Abdoul's
   credits are OpenAI, so the Anthropic path could never be measured, and an
   unmeasurable code path is worse than an absent one. `gpt-5.1` is now the sole
   ratified provider (BUILD §1.3) and the Anthropic client was removed. The
   provider comparison this document argued for will not happen — which also
   means every existing number describes the extractor that ships, rather than
   an alternate.
2. **k.** 10 gives both usable error bars and the per-item flicker rates PIPE-15
   needs; 5 is the cheap floor. Cost is not the constraint.
3. **Decode policy.** Pinning low temperature tightens A/B comparisons but
   measures a configuration the app does not ship, and PIPE-15 explicitly *wants*
   shipping-config variance. Likely both: pinned for mechanical CI checks,
   ship-config for the ensemble and calibration.
4. ~~**Grader-first or collect-first.**~~ **Decided: collect first**, with
   grading in the same job so a cloud agent needs one command
   (`scripts/dev/overnight.sh`). The first report therefore still carries Part
   1.A's biases on its face, and `aggregate.md` says so in its own footer. The
   runs are on disk and re-gradable when Phase 2 lands.
