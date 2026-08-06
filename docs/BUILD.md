# Orbit — Build Plan

**Status:** Ratified 2026-07-29 (outline approved by Abdoul; full-build mandate same day). Governed by the EVALS ratchet — milestone gates cite EVALS check IDs and never invent success criteria of their own.
**Derives from:** [ORBIT.md](../ORBIT.md) (constitution), [DATA-MODEL.md](DATA-MODEL.md) (schema + policy), [DESIGN.md](DESIGN.md) (Two Rooms), [EVALS.md](EVALS.md) (the contract this plan is graded by).
**Companion:** [build/WORKLOG.md](build/WORKLOG.md) — append-only decision and progress log for the build itself.

---

## 0. What this document is for

The four ratified documents say what Orbit is, what its data means, what it looks like, and what counts as working. This one says **how it gets built**: the stack, the module boundaries that make the constitution structurally enforceable, the order of construction, how the evaluation layers actually execute, and the risks carried forward. Where a decision costs something, the cost is stated; where a decision is provisional (◊), it awaits measurement, and the ratchet applies once measured.

---

## 1. Stack

### 1.1 Decisions

| Layer | Decision | Notes |
| --- | --- | --- |
| App | Swift / SwiftUI, iOS-only, iOS 26 minimum | Personal device; iOS 26 unlocks `SpeechTranscriber` as the ratified low-storage transcription fallback (DATA-MODEL §6) |
| Storage | SQLite via **`OrbitSQLite`**, a thin first-party wrapper over the C API | See §1.2 — no ORM, no third-party dependency in the trust core |
| Transcription | whisper.cpp `large-v3-turbo`, on-device, bundled-floor/downloaded-ceiling | Ratified in DATA-MODEL §6; decode tuning (`-mc 0`, entropy threshold) is a first-class concern; the **name-match post-pass is the primary correctness mechanism** |
| Extraction | One LLM API endpoint behind the swappable §7.9 seam: **Anthropic Claude API, `claude-opus-5`, structured outputs (JSON schema)** | See §1.3 |
| Eval harness | Swift (`orbit-evals`), exercising the production modules directly | A harness that doesn't run the real pipeline can't gate it |
| CI | GitHub Actions: `core.yml` (ubuntu, every push) + `app.yml` (macos, app paths + manual) | §4.3 |

### 1.2 Why a first-party SQLite wrapper (and not GRDB / SwiftData / CoreData)

- **SwiftData/CoreData** cannot express the model's load-bearing storage-layer guarantees: `RAISE(ABORT)` triggers for INV-1, FTS5 virtual tables, raw DDL control, reader/writer connection separation.
- **GRDB** could, but supports Apple platforms only — which would make the invariant suite unrunnable on Linux CI and in Linux dev environments. The trust core must be verifiable everywhere.
- Orbit's needs map directly onto the C API: raw DDL, triggers, prepared statements, read-only connections, FTS5. iOS ships `libsqlite3` natively; Linux installs it. **Zero third-party runtime dependencies in the trust core** is itself a privacy posture (PRIV-2's single-egress budget is easier to audit when the dependency graph is one item long).
- Cost: we own ~500 lines of wrapper. Accepted; the wrapper is deliberately thin and boring.

### 1.3 The extraction endpoint

- **Model:** `claude-opus-5` to start — quality ceiling first, so the first PIPE measurements say what the metrics *can* be. `claude-sonnet-5` is measured against the same goldens afterwards and the numbers decide; the seam + `model_id` on every Extraction row makes this a config change.
- **Zero-data-retention is a hard constraint** (DATA-MODEL §7.9, PRIV-2): the org whose key ships must have a ZDR agreement. Consequence discovered while planning: **Fable-tier models are structurally excluded** — they require 30-day retention and return 400 under ZDR. This is recorded so nobody "upgrades" the extractor into a privacy violation.
- **Setup prerequisite (Abdoul):** ZDR agreement on the API org; key never committed (injected via device keychain in-app, `ANTHROPIC_API_KEY` env for the harness).
- **Alternate provider (ratified by Abdoul, 2026-07-29): OpenAI.** `OpenAIExtractor` runs the same versioned prompt + JSON schema through `chat/completions` structured outputs (model via `OPENAI_MODEL`, default `gpt-5.1`; key via keychain `openai-api-key` / `OPENAI_API_KEY`). Provider selection is by which key exists — the Anthropic key wins when both are present. The §7.9 seam means nothing else in the system knows which provider ran; the single-egress budget (PRIV-2) and the retention-posture requirement apply to whichever endpoint is configured — **verify the OpenAI org/project's data-retention settings before production use**, same bar as ZDR.
- The extraction prompt is a **versioned artifact** (`Sources/OrbitPipeline/Resources/extraction-prompt-v*.md`), bumped only with a golden run attached — the ratchet spirit applied to prompt changes.
  - **Waived once, deliberately (Abdoul, 2026-08-06):** v2 was promoted to default *without* its golden run, to get the FIELD-NOTES FN-10 fix (`object_value` as a tag, not a summary) onto the device immediately. The rule stands for every future bump; this is a recorded exception, not a precedent, and it carries a debt: **the provisional PIPE numbers in the ratification packet were measured on v1 fixtures and therefore describe the previous prompt.** The first `swift run orbit-evals measure --live` clears it. `ORBIT_PROMPT_VERSION=v1` runs the measured prompt for comparison.

### 1.4 Verification tiers

Every component carries one of three verification tiers, recorded here and in WORKLOG entries:

| Tier | Meaning | Components |
| --- | --- | --- |
| **T1 — locally verifiable** | Runs in any Linux/macOS dev environment with no Apple toolchain: the SQL fast-loop (`scripts/dev/sql_check.py` + `sql_properties.py`, same SQLite engine), the embedded-SQL prepare rig, `design_lint.py`, and `measure.py` (the Python twin of the replay measurement) | Schema DDL, triggers, read-model SQL, embedded Swift SQL, design-law statics, golden compilation, fixtures |
| **T2 — CI-verifiable** | Compiled + tested by GitHub Actions (`core.yml` on Linux for the whole SPM package incl. L0/L1; `app.yml` on macOS for the iOS app build + hosted tests each push, journeys on dispatch) | All Swift targets, SwiftUI app, hosted model-level journeys, XCUITest tap budgets (dispatch) |
| **T3 — device/secret-gated** | Needs Abdoul's hardware or credentials; ships as a runnable harness + instructions | Transcription quality (PIPE-1/1b/2 — audio fixtures live only on Abdoul's devices, by design), on-device PERF budgets, **live** extraction runs (API key) |

Nothing is reported as "verified" above its tier. T3 items produce their numbers the first time Abdoul runs the provided harness on real hardware; the ◊ thresholds ratify then.

---

## 2. Architecture

One SPM package (platform-neutral, Linux-buildable) plus an app project. Module boundaries are the enforcement mechanism:

| Target | Responsibility | Enforcement it carries |
| --- | --- | --- |
| `CSQLite` | System-library interop | — |
| `OrbitSQLite` | Connections (reader/writer split), statements, migrations runner | `openWriter` is the only writable constructor |
| `OrbitCore` | Pure domain types, ops, lifecycle state machines — no DB import | Four-state lifecycle truthfulness (Decision 4) lives in types |
| `OrbitStore` | Schema DDL + triggers (as versioned `.sql` resources), all read-side queries, the four read models | **INV-1 in the database itself**: triggers abort UPDATE/DELETE on confirmed events / accepted assertions. INV-8/9/23 scope exclusions at the query layer |
| `OrbitWrite` | `ProposalResolutionService` + `UserEditService` — **the only target that opens a writer** | **INV-5 by construction**; everything else gets read-only connections |
| `OrbitPipeline` | `Extractor` seam (§7.9) + sync engine (payload → proposals): identity rules §7.7, entity resolution §7.10, thread bar, archetypes, episodic/semantic split §7.11, self-profile §7.12, `PROPOSE_STATE` quote gate §7.13 | INV-6/7 (re-extraction proposes, never mutates; same-source suppression), INV-24 (verbatim-substring check is mechanical) |
| `OrbitRecall` | Brief assembly: per-section bounded queries, ranking signals (DATA-MODEL §8), Deck selection | PIPE-14 rules; no global score exists to violate INV-15/16 |
| `OrbitSearch` | FTS5 + alias/entity graph traversal + fragment search | Evidence-cited answers (knows-each-other is derived, never asserted) |
| `OrbitEvals` | The EVALS harness CLI (§4) | — |
| `apps/OrbitApp` (+`OrbitDesign`) | SwiftUI shell + Two-Rooms design system | Only place SwiftUI may be imported (linted); D-checks target its output |

**Triple enforcement of the two structural invariants:**

- **INV-1** (never rewrite history): SQL triggers (database) → append-only service APIs (compiler) → test suite (CI).
- **INV-5** (nothing final without confirmation): single-writer target (compiler) → `scripts/lint-writepath.sh` (CI, greps for `openWriter` outside `OrbitWrite`) → triggers beneath it all (database).

The same lint enforces INV-15 (no score-shaped identifiers) and SwiftUI containment.

---

## 3. Build sequence

Milestones with gates; every gate cites EVALS IDs. Sequencing principles: (1) eval-first — a capability's checks land with or before it; (2) real-data validation precedes ratifying anything pipeline-shaped; (3) the highest-risk unknown (extraction quality) is front-loaded, headless, before any UI; (4) capture ships before recall, because recall is only as good as what has been captured and early capture compounds the eval corpus (§3.2 of EVALS: the review flow is a labeling machine).

| # | Milestone | Contents | Gate |
| --- | --- | --- | --- |
| M0 | **The Ledger** | Schema, triggers, ops, amendments, read models, write funnel | Full L0: INV-1…24 named tests, INV-21 fuzz, INV-4 rebuild-diff, DATA-MODEL §3 worked example green |
| M1 | **Pipeline in a harness** (headless) | Extractor seam + client, sync engine, golden compilation, synthetic corpus, measurement runner | First measurement report incl. **PIPE-12 vs `eliah-portrait`**; Critical classes (PIPE-4/5/6/7-style) at zero on corpus |
| M2 | **The Loop** (capture→review→sync, on device) | Capture (voice+typed), transcript review, proposal review, sync-later, **J-12 export from the first review build**, whisper wiring, audio-deletion gate | J-1…J-5, J-11, J-12; PRIV-1…4; design-lint live (D-1…11); PERF-3/4/5 first measurements |
| M3 | **Desk & Deck** | Brief (fixed skeleton §8), Deck, Home (three doors + Today) | PIPE-14 at 100%; J-6, J-7; PERF-2 |
| M4 | **Search & Discover** | Search goldens *first* (EVALS §3.4), FTS5 + graph + fragment, known-of band | J-8 known-answer goldens green; PERF-1; embeddings decision recorded |
| M5 | **Portraits & onboarding** | Portrait flow, reconstructed events, self-profile + era anchors, PROPOSE_STATE UI | INV-22/23/24 through the UI path; PIPE-12 at its ratified threshold |

Post-M5: remaining DESIGN §14 deferred surfaces by felt need (timeline/contact mini-pages come early — cheap; merge flow, gardening session, export, brokering later).

---

## 4. Evaluation infrastructure

### 4.1 The harness (`orbit-evals`)

Subcommands: `measure` (run corpus → metrics report; `--replay` uses recorded fixtures, `--live` calls the endpoint), `compile-goldens` (prose golden → machine-readable YAML; divergence = failure), `harvest` (review-outcome log → labeled (source-event, claim) pairs per EVALS §3.2), `consistency` (k-run flicker, PIPE-15), `metamorphic` (PIPE-16 perturbations).

### 4.2 Goldens: prose is canonical, YAML is compiled

The ratified goldens are prose contracts (`docs/evals/goldens/*.md`). Each gets a compiled YAML companion the harness consumes. Rules: the `.md` stays canonical; the YAML was reviewed by Abdoul once at compilation; CI fails if they diverge on required/forbidden items. Extraction outputs (live or otherwise) are recorded under `docs/evals/fixtures/` tagged with `model_id` + prompt version — deterministic CI, and model-vs-model diffs stay possible forever (Decision 3 applied to the eval layer).

### 4.3 CI topology

- **`core.yml`** (ubuntu, every push): `scripts/check.sh` = write-path lint → SQL fast-loop → build → full test suite (L0 + L1-replay + unit) → `orbit-evals measure --replay`.
- **`app.yml`** (macos, app paths + manual dispatch): XcodeGen → simulator build → unit/view-model tests → snapshot design-lint → journeys. macOS minutes are 10×-billed; jobs stay lean and batched.
- **Nightly** (once live credentials exist): `measure --live`, k=5 consistency, metamorphic suite, deep INV-21 fuzz, INV-4 rebuild-diff.

### 4.4 Thresholds and the ratchet, operationalized

`docs/evals/thresholds.yaml` is the executable mirror of EVALS §3.3/§4. Every ◊ starts `null` (report-only). Ratification: `orbit-evals measure` emits a dated report → Abdoul ratifies → the number lands in EVALS.md **and** thresholds.yaml in the same commit. CI enforces direction: a loosened threshold without an EVALS.md diff in the same commit fails.

### 4.5 Judged metrics

Semantic contract matching and rationale-faithfulness use a fixed judge model + versioned rubric prompt (repo artifacts), adversarial second judge on Critical metrics, disagreement escalates to L3 — per EVALS §3.5. Judge calls share the API client and are nightly-only for cost.

### 4.6 What runs where (honesty ledger)

| Check family | Runs | Notes |
| --- | --- | --- |
| INV-1…24, INV-21 fuzz, INV-4 | Linux CI, every push | plus SQL fast-loop locally |
| PIPE-3…14 (replay) | Linux CI, every push | recorded fixtures |
| PIPE-3…16 (live) | Nightly, once key exists | T3 until then |
| PIPE-1/1b/2 | Abdoul's machine (`--audio-fixtures`) | audio never enters the repo — correct, permanent |
| J-suite, D-suite | macOS CI | simulator; on-device pass pre-release |
| PERF-1…6 | Device harness | T3; ◊ ratify on first device run |
| PRIV-1…4 | macOS CI (interception) + code audit | PRIV-5 with export feature |

---

## 5. First milestone detail (M0+M1)

Deliverables: full DDL for every DATA-MODEL §2 entity; triggers; ops engine (ASSERT/CLOSE/CORRECT/MERGE/LINK/CREATE_PERSON/CREATE_EVENT/OPEN_LOOP/PROPOSE_STATE/DISAMBIGUATE); Amendment/AssertionAmendment application at read time; four read models + rebuild; thread lifecycle clocks; complete L0; extractor seam + Claude client + ReplayExtractor; extraction prompt v1; sync engine with all §7 policy rules; compiled goldens (4 real + 7 synthetic per EVALS §3.1); measurement runner; **the first measurement report, including the PIPE-12 number**.

Explicitly out of scope for M0/M1: all UI, audio handling, on-device anything.

**Provisional-measurement note:** until a production API key exists, extraction fixtures may be produced by a Claude model operating in-session against the same versioned prompt + schema, recorded with an honest `model_id`. Numbers from that path are provisional by definition; **PIPE-12's ratified number awaits the production extractor**, exactly as EVALS §9 already requires.

---

## 6. Risks

Inherited (already registered): group-event review flow untested end-to-end (J-2 gate, M2); `project`-thread milestones deferred; multi-device sync out of scope (log stays CRDT-friendly); DESIGN §14 deferred surfaces; `ink-faint` contrast decision forced at M2 design-lint; real-photo portrait treatment needs real photos.

New, registered here:

1. **Audio fixtures exist only on Abdoul's devices** — transcription metrics are unautomatable by design. Mitigation: documented local-fixtures layout + an encrypted backup Abdoul owns.
2. **The harness's semantic matching depends on an LLM judge** — meta-circularity. Mitigation: EVALS judge governance + maximizing the deterministic-check share (verbatim, hedges, structure, attribution are all mechanical).
3. **ZDR agreement prerequisite** for the endpoint; Fable-tier excluded (§1.3).
4. **whisper.cpp on-device perf/thermals unmeasured** on target hardware (PERF-4); decode tuning interacts with quality. M2 device task.
5. **Embeddings/`sqlite-vec` unproven on iOS**; deferred behind the M4 decision; FTS5+aliases may suffice.
6. **Single-reviewer throughput** — every ratification routes through Abdoul. Mitigation: batched per-milestone packets.
7. **Token drift** — canonical tokens live in an HTML mockup. Mitigation: generated tokens + D-10 diffs rendered output against the parsed mockup.
8. **Eval API cost** (k×corpus×nightly). Mitigation: nightly-only live runs, replay in CI, Batches API (50%) for bulk runs.
9. **Extraction prompt drift** — prompt changes are golden-gated and versioned (§1.3).
10. **Environment variance for build agents** — dev environments may lack Apple toolchains or even Swift; the T1/T2/T3 tier system (§1.4) exists so verification claims stay honest anywhere the repo is worked on.

---

## 7. Working agreements (for any builder, human or agent)

- `scripts/check.sh` green before any push; no phase advances red.
- Commits cite EVALS check IDs (house rule from EVALS preamble).
- Every WORKLOG entry records what changed, why, and its verification tier.
- When a check blocks and seems wrong: **the check might be right** — escalate a doc-change proposal; never weaken a check to match behavior (EVALS §6).
- Usage metrics are never build evidence (EVALS §8).
- Before every push: constitution sweep — diff the changeset against ORBIT.md P1–P12 and DESIGN §13 anti-patterns.

---

## 8. State of the build — 2026-07-31 (CI green, post-review-pass)

All six milestones M0–M5 are **built, pushed, and CI-green** on
`feature/initial_build`. Verification is tiered honestly (§1.4); everything
below marked T2 is verified by a workflow run, not by assertion. Detail in
docs/build/WORKLOG.md.

| Milestone | Status | Verified |
| --- | --- | --- |
| M0 Ledger | Built | **T1+T2 green**: 50 SQL property checks + embedded-SQL prepare rig (T1); full Swift L0 invariant suite passing in CI (T2) |
| M1 Pipeline | Built | **T1+T2 green**: provisional PIPE report (criticals 0, recall 100% on the 11-memo replay corpus; fixtures from the in-session model, labeled as such); Swift replay harness runs in CI; live number still needs a key (T3) |
| M2 Loop | Built | design-lint **T1 green** (0 violations); J-1…J-5, J-11, J-12 model suites **T2 green**; XCUI tap-budget halves dispatch-only; PERF-3/4/5 = T3 |
| M3 Desk & Deck | Built | PIPE-14 ×5 + J-6/J-7 suites **T2 green**; ranking SQL T1-prepared |
| M4 Search | Built | Goldens S-1…S-10 authored FIRST, **T2 green**; embeddings: deferred (recorded, no golden demands them) |
| M5 Portraits | Built | INV-22/23/24 through-the-UI suites **T2 green**; PIPE-12 machinery wired E2E (live number needs a key, T3) |
| PRIV | Audited | docs/build/PRIV-AUDIT.md — PRIV-5 export/restore and PRIV-3's filesystem half built + tested in CI; PRIV-1/3 device halves = T3 |

**CI shape:** `core` (Linux) runs `scripts/check.sh` — write-path lint, SQL
fast-loop + property suite, design lint, provisional PIPE measurement, full
build, full test suite, replay measurement — on every push. `app` (macOS) runs
the iOS-simulator build plus the hosted `OrbitAppTests` suite on every push
touching `apps/**` or `Sources/**`. The **XCUI journey suite is dispatch-only**
(Actions → app → Run workflow → journeys: true): a cold simulator boot blows
the 30-minute push budget. That cadence diverges from EVALS §L2's "every PR"
and is registered for ratification (RATIFICATION §4.7).

**Post-M5 work landed since the milestone table was first written:**
OpenAI as a second extraction provider behind the unchanged §7.9 seam; the real
whisper.cpp bridge (inactive until `scripts/build-whisper.sh` vendors the
xcframework); ceiling-model download; Security.framework keychain + the Keys
sheet; PRIV-3's filesystem deletion; the `ORBIT_TEAM` signing knob; and a
full-build review pass (WORKLOG 2026-07-31) that fixed 176 confirmed findings
across every layer and added six regression pins.

**Standing blockers:** none in code. Repo push access and CI are both working;
the OpenAI key is in the environment (its org data-retention posture still
needs Abdoul's check per §1.3). What remains is **device bring-up on Abdoul's
Mac** — Xcode + XcodeGen, `scripts/build-whisper.sh`, signing team, install,
first capture — and the ◊ ratification queue. No Apple toolchain and no Swift
toolchain exist in the build agent's environment (`download.swift.org` is
blocked by the egress policy), so Swift compilation is verified exclusively by
CI; every T1 claim above is from the Python/SQL rigs that do run locally.

**Deferred surfaces register (post-M5, by felt need — DESIGN §14):**
merge/unmerge review flow UI (ledger op is built + tested), gardening session,
export UI entry point (capability built, PRIV-5), brokering/hosting search
recipes, groups & saved lists UI, rejection-reason picker surfacing
(`RejectionReason` wired in the funnel), Deck reachability actions
(tap-to-call/text), set-aside triage as its own surface (today it reuses
review), undo on settled review lines, usage journal. Built and **not** in
DESIGN's ratified list — awaiting ratification (RATIFICATION §4): the Keys
sheet, the store-failure screen, Home's resume doors, and the review edit
sheet.

**Ratification queue:** docs/evals/RATIFICATION.md.
