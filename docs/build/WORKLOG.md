# Build Worklog

Append-only. Each entry: date · phase · what/why · verification tier (T1 local / T2 CI / T3 device-or-secret) · check IDs touched. Newest last.

---

## 2026-07-29 · Phase 0 · Environment + scaffold

- **Mandate:** full build on `feature/initial_build` (Abdoul, in-session). BUILD.md outline ratified same day; "planning/build" branch instruction was stale and is superseded.
- **Environment found:** Ubuntu 24.04 container; libsqlite3 3.45.1 + headers (FTS5 confirmed); clang/gcc; Python 3.11; Node 22; **no Swift toolchain and no path to install one** (proxy policy denies `download.swift.org` and GitHub release assets; only npm/PyPI/crates/golang registries + this repo's git remote are reachable).
- **Consequence:** Swift verification is T2 (CI) for this session; the SQL fast-loop (`scripts/dev/sql_check.py`, T1) carries local correctness for the ledger's DDL/triggers/read-model SQL against the same SQLite engine. Recorded as BUILD.md §1.4/risk 10.
- **Scaffold landed:** SPM package (module boundaries per BUILD §2), `scripts/check.sh` single gate, write-path lint (INV-5/INV-15/SwiftUI containment), CI workflows (`core.yml` ubuntu / `app.yml` macos).
- **BLOCKER (open):** all pushes to `MaximusAnax/orbit` return 403 — both the session git gateway and the GitHub App API ("Resource not accessible by integration"). Reads work. The remote was reorganized after session start (session branch deleted; `planning/evaluation` appeared), so write permission likely changed then. **Needs Abdoul:** restore write access for the Claude GitHub integration on this repo. Until then: commits accumulate locally; push retried at every phase gate. CI (T2) is unreachable, so Swift code is verified-by-construction + SQL fast-loop only — every such claim is tiered honestly in this log.
- Also: `.github/workflows/` pushes may additionally require the `workflow` scope on the integration once write access returns — verify then.

## 2026-07-29 · Phase 1 · BUILD.md ratified content written

- `docs/BUILD.md` written per the ratified outline + environment deltas. Notable deltas from the pre-ratification outline, both argued in the doc: **no GRDB** (first-party `OrbitSQLite` wrapper — GRDB has no Linux support, and zero third-party deps in the trust core is a privacy posture, §1.2); **verification tiers** formalized (§1.4).
- README map updated to include BUILD.md. Tier: T1 (docs).

## 2026-07-29 · Phase 2 (M0) · The Ledger

- **SQL trust core (T1, executed green here):** full DATA-MODEL §2 DDL (`001_schema.sql`), immutability/scope triggers (`002_triggers.sql`), read models + timeline view (`003`), deterministic rebuild (`004`). `scripts/dev/sql_properties.py`: **49 checks green** — INV-1/2/3/4/8/9/10/11/12/13/14/17/21(fuzz: 40 ops × 30 probes)/22/23, proposal state machine, thread rules, §3 worked example ("where did Sarah work in 2024" → Google).
- Two bugs caught by the rig before they shipped: `IN (NULL,…)` CHECK constraints are inert in SQLite (4 fixed); INV-9 needed a DB trigger, not just service checks.
- **Swift layer (T2-pending; CI unreachable while the push blocker stands):** OrbitSQLite wrapper (reader/writer split, `openWriter` lint-fenced), OrbitCore domain + payload vocabulary, OrbitStore (schema-from-resources, StoreReader incl. bitemporal + audit queries, derived sync status per Decision 4), OrbitWrite (UserEditService + ProposalResolutionService — INV-7 same-source suppression, INV-24 quote gate, §7.3 promote-and-flag, J-12 harvest rows on every decision, incremental read-model maintenance). `Tests/OrbitInvariantTests`: 20 test cases covering INV-1..24 + Decision-4 partial resolution + the worked example through the funnel.
- Design choice: reconstructed-event acceptance confirms in-transaction (the review IS the confirmation); reflected in CREATE_EVENT apply.

## 2026-07-29 · Phase 3 (M1) · Pipeline in a harness

- **Extraction seam (§7.9)**: `Extractor` protocol; `RemoteExtractor` (Claude API, `claude-opus-5`, structured outputs, ZDR-required — Fable-tier excluded, BUILD §1.3); `ReplayExtractor` (fixtures). Prompt v1 + JSON schema shipped as versioned resources. Payload schema covers people/entities/assertions(+we-splits, object persons)/episodes/threads(+closures)/loops/contact points/state declarations/corrections/ambiguities.
- **SyncEngine**: payload → pending proposals through the funnel; §7.7 identity branches (new / existing / ambiguous / self_collision → DISAMBIGUATE, never a guess); §7.10 sync-time alias matching (PIPE-13 defense in depth); contradiction → CLOSE proposal; corrections → CORRECT vs CLOSE (Decision 2); §7.3 promote-and-flag on first present meeting; INV-24 quote gate live.
- **Corpus**: 7 synthetic memos authored per EVALS §3.1 (grief validated on synthetic data, never real grief). **11 extraction fixtures** produced in-session against prompt v1, every verbatim mechanically substring-verified + schema-validated (T1). Model honestly recorded as `claude-fable-5(in-session)`.
- **Goldens**: `eliah.yaml` compiled 1:1 from the ratified prose golden (prose stays canonical); draft goldens for nikos/dom/futureforce + all synthetics (await Abdoul's ratification).
- **PROVISIONAL MEASUREMENT (T1)**: `scripts/dev/measure.py` → `docs/evals/measurements/2026-07-29-provisional.md`. **PIPE-3 100% (90/90) · Criticals 0 · PIPE-5 100% · PIPE-6 100% · PIPE-7 0 · PIPE-10 0 unsanctioned · PIPE-11 3/3 · PIPE-1b 0 · Eliah episode contract (PIPE-12 shape) fully met.** Grading is deterministic contract matching; the extractor and the fixture author are the same in-session model, so these numbers are floor-setting, not ratifiable — the ratified PIPE-12 number still awaits the production extractor (EVALS §9), unchanged.
- Eval loop earned its keep immediately: first run caught a fixture hedge miss, a matcher gap (relation objects), and a golden omission (Leon/Atlanta thread) — fixed, re-run green.
- **Swift harness** (`orbit-evals`, T2-pending): `measure --replay` = fixtures through the REAL SyncEngine into the real ledger with round-trip checks (silence→0, INV-24 once, episodes non-future, namesake→DISAMBIGUATE, CLOSE-not-overwrite, CORRECT-not-CLOSE); `harvest` = J-12 outcome export as (source-event, claim) labels. `Tests/OrbitPipelineTests`: Eliah full-review E2E (accept-all → ledger assertions incl. closed-Google audit, INV-12 rhythm zero, §7.13 authored_by=human, INV-4 after the whole flow) + INV-7 suppression through re-sync.
- `docs/evals/thresholds.yaml`: the ratchet's executable mirror; all ◊ null pending ratification.

## 2026-07-29 · Phase 4 (M2) · The Loop — app layer

- **Tokens (D-10)**: `scripts/dev/gen_tokens.py` parses the CSS custom properties out of `docs/prototype/v3-mockup.html` → `Tokens.gen.swift` (15 colors × 2 rooms, DO-NOT-EDIT) + `tokens.gen.json`; `--check` mode fails the gate if either drifts from the mockup. The mockup stays canonical.
- **Two-Rooms components** (`OrbitDesign`): every component is one definition rendering both rooms via the `RoomColor` token pair — the translation principle as a type, not a convention. Star-dust obeys D-5 structurally (4 nodes, top band, one ember, none animated).
- **Screens + view models** (`OrbitApp`): Home (three doors: search pill, Today ≤ 2 reasoned items that collapse to nothing, mic; set-asides as a plain-ink footer line, never a badge), Capture (mic + typed micro-note — typed text IS the transcript, §7.11), Transcript review (name-match fixes from the PIPE-1 post-pass, §7.5 audio notice honest about the full-model gate), Proposal review (person-grouped cards, verbatim in memory voice with ember-wash rule, hearsay chips, DISAMBIGUATE ask-cards on note material, settled grey lines, per-person accept-all, frictionless "Later"). All user-facing copy in one lintable catalog (`Copy.swift`, ratified lexicon).
- **Recording/transcription seams**: `AudioRecording` (DeviceRecorder AAC-mono-16k on iOS / mock elsewhere) and `TranscriptionService` have **no network implementation and never will** (PRIV-1 by construction); `ModelManager` bundles the floor model, downloads the ceiling; §7.5 deletion gated on `usedFullModel`. `scripts/build-whisper.sh` (T3, needs a Mac): pinned whisper.cpp xcframework + both model tiers, decode flags from the 2026-07-27 findings recorded in the header.
- **Design lint live**: `scripts/dev/design_lint.py` in `check.sh` — static tier of D-1 (token hue sweep + source scan), D-2, D-3, D-9, D-10 (token drift + literal-color ban), D-11 (forbidden lexicon + debt-language patterns); snapshot-tier checks (D-4..D-7 pixel census) are REPORTED as graded-elsewhere, not skipped silently. Currently: **0 violations**.
- **Journey suite**: `JourneyModelTests` — J-1 (E2E capture→accepted facts with total provenance; §7.5 both branches incl. tiny-model retention), J-2 persistence slice, J-3 (defer-everything: ledger untouched, true-count footer only, Today silent), J-4 (name fix becomes the record), J-5, J-11 (sync-later ≡ immediate sync), J-12 (every decision → harvest row) — DB end-state assertions through the same AppModel/view-model path the screens call. `JourneyUITests` — tap-level halves with ◊ friction budgets (J-1 ≤ 12, J-3 ≤ 3) and the J-3 badge-absence assertion. UI-test boot: in-memory store + canned transcript + replayed payload via launch env; production code path everywhere past the seams.
- **XcodeGen** `project.yml` (app + OrbitDesign framework + both test bundles); `.xcodeproj` stays generated, never committed. `app.yml` CI can now run.
- Fix along the way: `pendingProposals` ordered by random UUID → arbitrary review order and dependency-broken accept-all; now `ORDER BY rowid` (sync engine emits dependency-first).
- **Tier honesty:** everything Swift in this phase is T2-pending (push blocker still standing — see Phase 0 entry; retried this gate, still 403); design lint + token check + SQL suite are T1 green. PERF-3/4/5 and the D-4..D-7 pixel census are T2/T3 and remain open M2 items, listed in the deferred register.

## 2026-07-29 · Phase 5 (M3) · Desk & Deck

- **OrbitRecall / `BriefAssembler`**: DATA-MODEL §8 implemented literally — no global score exists anywhere in the module (Decision 7); fixed skeleton, per-section bounded queries; ranking = query-time structural signals with the tiebreak chain (pinned → never-surfaced → oldest-surfaced → oldest-known → id). Every ranked item carries its plain-words reason (P9). `muted` rows are filtered in the one pool query so nothing downstream can leak them; "worth having back" is unbounded by ratified decision with era grouping (>6 → grouped, first-met year reads "when you first met"). Changed-since-last-seen counts only real contact (`about` excluded, INV-11) and includes closes ("no longer: …"). Thread staleness is displayed, not hidden (§9.1).
- **Deck**: card order = Desk order (teaches the map); 5–7 cards; hardship threads render as *context* cards ("let them bring it up"), never suggested openers (PIPE-14); always ends `That's everything · Go be present.`; surfaced assertion ids returned to the caller so `last_surfaced_at` is written **through the funnel** (`markSurfaced`, INV-5 — OrbitRecall itself stays read-only).
- **Screens**: `BriefScreen` (fixed tile order 0–8, half/full width semantics, collapse rows → pushed mini-pages never accordions, empty sections absent), `DeckScreen` (tap-advance, progress bars, no timers), Timeline + Reach mini-pages, `SearchScreen` placeholder that says honestly it arrives with M4. Home's Desk door now lands on the real brief.
- **Tests** (`Tests/OrbitRecallTests`, all data through the production funnel): PIPE-14 ×5 (open-threads-present, hero-is-top-unsurfaced, muted-absent-everywhere, pinned-wins-outright, hardship-context-never-opener), J-6 ×2 (three-capture desk incl. INV-11 last-seen, sparse profile collapses + pill hides), J-7 ×2 (deck order/end-card/surfacing-writes, surfacing-rotates-the-hero).
- **New T1 rig**: `sql_check.py` now EXPLAIN-prepares every triple-quoted SQL statement embedded in Swift sources against the real schema — 40 statements, 0 failures. Caught the exact class of bug it was built for during this phase (a query referencing a nonexistent `reconstructed` column, fixed to `derived_from_event_id IS NULL` before commit).
- **Tier honesty:** Swift is T2-pending (push still 403 — retried at this gate); embedded SQL + design lint + ledger suite are T1 green. PERF and pixel-census items unchanged from Phase 4.

## 2026-07-29 · Phase 6 (M4) · Search & Discover

- **Goldens FIRST** (EVALS §3.4): `docs/evals/goldens/search.yaml` — S-1..S-10 over a canonical corpus (name w/ provenance anchor + misspelling, who-at-Google with the "And maybe —" band citing Alex, where-does-James-work fact lookup, who-through-Alex provenance chain, ask-about-visas, greece-picnic-guy fragment with 2-atom evidence, unknown-company → empty). `Tests/OrbitSearchTests` is the executable form, corpus seeded through the funnel, one test per golden id + a muted-stays-invisible check.
- **`rm_search`**: FTS5 (porter unicode61) read model — same derivability contract as every read model (005_search_rebuild.sql; wired into `ReadModels.rebuild`, the three incremental hooks, and person create/rename). Porter behavior the goldens rely on ("visas"→visa clinic, "diving"→free-dives) **verified T1 in this session's SQLite before writing the Swift**.
- **`Searcher`** (OrbitSearch): three shapes, one field. Name → edit-distance people with provenance anchors ("met 2024-06 · through Alex · last seen…"). Question → an answer: `through <name>` walks introduced_by edges (firsthand) + known-of-attributed-to (maybe); `where does X work` predicate lookup with dated evidence; generic → FTS + entity-alias pass, banded firsthand vs "And maybe —" (every maybe cites its teller). Fragment → "Probably Nikos — here's why" with the matched atoms as evidence. **Embeddings deliberately absent**: all goldens pass on FTS5+structure, so per BUILD.md the sqlite-vec decision is NO for now — revisit only when a golden demands semantic recall.
- **SearchScreen**: as-you-type (no submit affordance exists, J-8), answer-count first, And-maybe on note material, fragment evidence underlined ember-wash, empty results render nothing (D-8).
- **INV-19 enforcement point moved (design fix, caught by the golden corpus work):** a mic/typed capture legitimately doesn't know its people yet — the old capture-time guard made the ratified capture flow impossible (Phase 4's mic path would have thrown). Now: no participants AND no extractable material → refused at capture (a diary entry); otherwise allowed, and **every accepted assertion attaches its subject to the source event as an 'about' participant** (conservative — P4: presence is never invented; 'about' stays out of rhythm, INV-11; participant INSERT stays legal post-confirmation by design, UPDATE/DELETE remain frozen). This is also exactly J-5's ratified "subject gets about attendance". InvariantTests INV-19 updated to the full contract. EVALS INV-19 wording ("every event has ≥1 participant") still holds at rest — the enforcement is capture-or-review, documented here.
- **Tier honesty:** FTS retrieval assumptions + all embedded SQL + design lint are T1 green; Searcher/tests are T2-pending (push blocker unchanged, retried at this gate).

## 2026-07-29 · Phase 7 (M5) · Portraits, self-profile, PROPOSE_STATE UI

- **PortraitCaptureView** (§7.11): one pausable recording, skippable serif prompts, never queued — entry from the Desk as a tertiary invitation, plus the onboarding invite line. Downstream is the unchanged capture flow (kind: portrait).
- **OnboardingView** (§7.12): one name creates the single `is_self` row (INV-22) and the app opens into the room — no tour, no forms. The era-anchor registry grows from self-portrait assertions through the ordinary flow.
- **Review additions**: PROPOSE_STATE cards render "In your words" + the verbatim quote in memory voice with the orbit/intent mapping rendered explicitly as `suggested:` (never as fact, §7.13); CREATE_EVENT episode cards carry "This is when we met" — `acceptAsFirstMet` accepts the reconstruction and links `first_met_event_id` to it (no special case in the model, §7.11).
- **SyncEngine INV-24 hardening** (found writing the M5 tests): an unquotable state declaration used to abort the entire sync run; now the funnel's refusal drops that one op and the memo's review survives — the gate stops the overreach, not the user.
- **Tests** (`PortraitFlowTests`, through the AppModel/view-model path): full portrait E2E — episode → reconstructed event (fuzzy month, confirmed-on-acceptance, no transcript of its own, present attendance, INV-12 rhythm zero), first-met linked via the card affordance, we-split lands the same verbatim on subject AND self (INV-22 scope), PROPOSE_STATE → `authored_by: human` with provenance; INV-24 doctored-quote test (op refused, review survives); INV-23 surface test (self absent from search results and Today; zero relationship machinery on the self row).
- **Tier honesty:** unchanged — UI/tests are T2-pending (push retried at this gate, still 403); lint + embedded SQL T1 green.

## 2026-07-29 · Phase 8 · Ship

- **PRIV-5 closed in code**: `Export.dump`/`Export.restore` — the archive carries the log (rm_* excluded by design), pretty-printed JSON with verbatims in the clear; `ExportTests` proves restore-into-fresh-install passes INV-4 fingerprint equivalence. Export UI entry point registered as a deferred surface.
- **docs/build/PRIV-AUDIT.md**: PRIV-1…5, each split into enforced-by-construction / tested / open-with-runbook. The honest residue: interception runs and file-level deletion are T3.
- **docs/evals/RATIFICATION.md**: the full ◊ queue for Abdoul — ratify-now provisional numbers (with the in-session-model caveat restated), machinery-ready checks awaiting key/device, and the five in-build decisions to ratify or veto (INV-19 enforcement point, INV-24 refusal scope, embeddings-not-yet, no-GRDB, review order).
- **BUILD.md §8**: state-of-build table (per-milestone status × verification), standing blockers, deferred-surfaces register. README updated.
- **Constitution sweep** (P1–P12 × DESIGN §13, final pass): no violations found; design_lint scope extended to OrbitRecall/OrbitSearch strings (the copy law follows user-facing strings out of the app layer) — still 0 violations; embedded-SQL rig now prepares 54 statements, 0 failures.
- **Final gate:** `scripts/check.sh` fully green at T1. Push retried at this gate — still 403 (the standing access blocker); every phase is committed locally on `feature/initial_build`, and the branch is push-ready the moment access returns.

## 2026-07-29 · Post-ship · OpenAI extraction provider (ratified: Abdoul, in chat)

- **`OpenAIExtractor`** behind the unchanged §7.9 seam: same versioned prompt, same JSON schema (chat/completions structured outputs), model `OPENAI_MODEL` env (default `gpt-5.1`), key via keychain `openai-api-key` / `OPENAI_API_KEY`. The shared `ExtractionMessage.user` builder is now the single PRIV-4 audit surface for both providers. Selection: Anthropic key wins when both exist; no key → sync-later, as ever.
- **`orbit-evals measure --live` implemented for real** (was a stub awaiting a key): corpus memos → configured endpoint → fixtures recorded under `docs/evals/fixtures/live-<model>/` (Decision 3) → round-tripped through the real SyncEngine → graded via `measure.py --fixtures <dir>`. Works with either provider.
- Docs updated: BUILD §1.3 (alternate provider + retention bar), PRIV-AUDIT PRIV-2, RATIFICATION PIPE-12 row. **Open item for Abdoul:** verify the OpenAI org/project data-retention posture — the ZDR-equivalent bar applies to whichever endpoint is live.
- CI loop running in parallel: round 1 failed on an untracked-empty `Tests/OrbitCoreTests` (fixed, real OrbitCore tests landed, f322250); round 2 in flight.

## 2026-07-29 · Post-ship · CI green (T2 verification landed)

- **Both workflows green on `d738737`**: `core` (Linux — full build, 52/52 tests across the invariant/pipeline/recall/search/export/domain suites, replay measurement, 50-check SQL property suite, embedded-SQL rig, design lint) and `app` (macOS — full iOS-simulator build + 16/16 hosted tests: design-law, journey-model J-1..J-5/J-11/J-12, portrait flow incl. INV-22/23/24).
- The loop from first compile to green took ~10 CI rounds (~90 min wall clock, ~2-min core cycles). The tiering claim held up: **everything T1-verified in-session passed CI unchanged**; every CI failure was in territory T1 could not reach.
- **Three real defects found and fixed by the T2 layer** (each now pinned by a test):
  1. `sync_entity_ref` had an FK to entity(id) but is a polymorphic ref map by design — every thread/episode acceptance through the funnel failed (fixed + T1 property pin, 50 checks).
  2. The worked example's J-12 harvest count was global where it meant per-run (the seed decision is harvested too — correct behavior, imprecise assertion).
  3. **Per-person accept-all could silently strand a cross-group dependency** (assertion referencing an entity whose LINK card lives in another group). Real UX defect; fixed with dependency-queue-and-retry in ReviewViewModel — accept order no longer matters.
- Mechanical fixes along the way: missing OrbitCoreTests dir (git doesn't track empty dirs), public SQLiteError init, CFNumberIsFloatType → objCType (Linux), CaptureDraft arg order, OrbitSQLite exported as product, Swift 6 concurrency (Copy closures → funcs; @MainActor on XCUI tests), Text-extension modifier order.
- **Workflow restructure**: the single app test step (rebuild + first simulator boot + hosted + UI suites) exceeded 30 min; now the push gate = build + hosted `OrbitAppTests` with per-test timeouts, and the **UI journey suite is a dispatch-only job** (`app.yml` → run workflow → journeys: true) with its own 60-min budget — lean and batched per BUILD.md. App workflow also triggers on `Sources/**` so package changes rebuild the app.
- Verification-tier ledger update: everything previously marked T2-pending is now **T2 green** except the UI journey suite (compiled, dispatchable, awaiting a deliberate run) and the T3 items (device PERF, audio quality, live extraction — unchanged).

## 2026-07-29 · Post-CI-green · Device bring-up: the last six code gaps

- **WhisperBridge implemented** (was the `bridgeUnavailable` stub): real whisper.cpp C calls behind `#if canImport(whisper)` — greedy decode at temperature 0, `no_context=true`, `entropy_thold 2.8`, names via `initial_prompt` (the 2026-07-27 discipline), AAC→16k mono PCM via AVAudioConverter. Inactive until `scripts/build-whisper.sh` vendors the xcframework on the Mac; without it, capture parks memos for sync-later (P3), unchanged.
- **Ceiling model download implemented** (`ModelManager.downloadCeilingIfNeeded`): URLSession fetch of the pinned HuggingFace artifact into Application Support/models; fired from app start (`warmModels`) so it rides onboarding dead time. Inbound-only — carries no user content (PRIV-2 unaffected). Floor model bundles via an `optional:` project.yml resource once vendored.
- **Real keychain** (`KeychainLite` → Security.framework where available): device-only accessibility (`AfterFirstUnlockThisDeviceOnly` — never rides iCloud Keychain); env-var fallback kept for the headless harness. **Keys sheet added** (the missing surface): faint key glyph on Home → two secure fields → keychain. Provider selection unchanged (§7.9).
- **PRIV-3's filesystem half closed**: `deleteAudioFile` removes the recording on full-model confirm, upgrade pass, and discard — outside the ledger transaction (a commit must not depend on disk). `AudioDeletionTests` (3 cases) asserts file-level behavior in CI, both gate branches.
- **Signing knob**: `ORBIT_TEAM=<id> xcodegen generate` sets `DEVELOPMENT_TEAM`; CI unaffected (never signs).
- Session note: the container restored from a pre-CI-loop snapshot mid-work; local history re-synced from origin (`git reset --hard origin/feature/initial_build` onto 583a9f0 — the CI-green head) before these changes. Nothing was lost; everything relevant was already pushed.

## 2026-07-31 · Full-build review pass ("verify it is the best it can possibly be")

An 8-dimension adversarially-verified review of the entire build (ledger, write
funnel, pipeline, recall, search, app layer, tests/CI, docs), then a fix pass
over every confirmed finding worth its diff. The load-bearing fixes:

- **Ledger / store:** `Export.restore` now runs as ONE transaction with
  `defer_foreign_keys` and a dependency-honest table order (event_participant
  before person — the INV-14 trigger subqueries both); partial restores can no
  longer strand a half-written archive. `facts(of:knownBy:)` had a bind-count
  bug (2 placeholders, 1 binding) — fixed, and `Statement.bind` now refuses any
  count mismatch outright instead of silently under-binding. `canonicalPerson`
  follows merge pointers to fixpoint with a cycle guard.
- **Write funnel:** merges flatten at write time to the canonical winner (and
  re-point earlier losers), with legality guards (self rows, already-merged,
  loser==winner); the proposal path's `.merge` now delegates to the same code.
  Reconstructed episodes enforce INV-19 (≥1 participant), enter the read models
  on acceptance, and key the ref map by event id so same-dated episodes never
  collide. INV-7 suppression compares SEMANTIC claim keys (predicate+verbatim
  for content ops, canonical names for creation ops) — a reworded re-extraction
  of a rejected claim stays rejected; byte-compare would have resurrected it.
  Unresolved thread refs surface as a "accept the thread card first" pending
  dependency instead of a hard error. Assertion amendments now flow into
  `rm_current_state` on write AND rebuild (INV-4 twin queries kept identical).
- **Pipeline:** held DISAMBIGUATE assertions keep every field (entity/person
  objects, validity window, attribution, thread ref); contradiction detection
  matches on entity identity or case-folded value, not exact strings. The
  extraction schema is strict-mode for both providers (additionalProperties
  false everywhere, every DDL CHECK enum pinned); all 11 fixtures still
  validate.
- **Recall / search:** hearsay stays attributed end-to-end — heroes, forgotten
  items and fact answers carry their teller; secondhand facts answer as
  "X told you…" maybes, never as flat facts. Known-of people: banner on the
  desk, excluded from the Deck and Today. Six recall queries made
  merge-tolerant. `introduced_by` direction fixed (was reversed). "Changed
  since you last saw them" now requires an actual supersession observed after
  the last meeting.
- **App layer:** recording is genuinely pausable (portraits §7.11); leaving a
  capture screen cancels cleanly; a failed save keeps the typed note on screen;
  transcription-failure persists an audio-only memo and Home shows plain
  resume doors for every parked stage (J-11). Store-open failure gets a
  visible plain-ink screen — nothing pretends to work. Review cards gained the
  P5 edit affordance (mapped value/since/orbit editable; the quote untouchable).
  applyFix is range-aware (no more first-occurrence collisions). Dynamic Type
  reaches everything: memory voice scales via `relativeTo: .body`, interface
  voice through UIFontMetrics.
- **Tests/CI honesty:** `measure.py` joined `check.sh` (the T1 PIPE twin ran
  only ad hoc before); XCTSkip in flow helpers became XCTFail (a stalled
  journey is a failure, not a silent skip); design_lint's ELSEWHERE notes no
  longer cite a snapshot job that doesn't exist (honest tier: device/T3, or
  the dispatch-only journey job). New pins: rich export round-trip (first-met
  + contact point + merge), knownBy observation-time semantics, merge-chain
  flattening, INV-7 reworded-claim suppression, INV-19 for reconstructed
  episodes, Today's known-of exclusion.
- **Registered for ratification, not coded around** (RATIFICATION §4.6–4.10):
  iOS 17 target vs BUILD's "iOS 26 minimum", journey-suite cadence, undo
  deferral, §10.5 pronoun handling (name over guess), model-download checksum.
- Session note: the container restored from a stale snapshot mid-pass; local
  state was re-synced from `origin/feature/initial_build` (nothing pushed was
  lost) before the fixes landed.

## 2026-07-31 · Documentation currency pass

Abdoul flagged ORBIT.md as out of date; a sweep of every doc followed. The rule
applied throughout: **the ratified specs are the constitution — the build
conforms to them, not the reverse.** So normative text was not rewritten to
match code anywhere. What changed was status metadata, registers that had
become factually wrong about what exists, and honesty about where checks
actually run.

- **ORBIT.md** — the one genuinely stale line: "Planning complete… Next phase:
  build" became a built/CI-green status, plus an explicit restatement that the
  document is the constitution and divergences go to RATIFICATION. No
  constitutional text touched.
- **README.md** — built → built *and CI-green*, with what actually remains
  (device bring-up, the ◊ queue).
- **BUILD.md** — §8 rewritten against reality: T2-green per milestone instead
  of "T2-pending", 50 SQL checks (was 49), the CI shape spelled out (what runs
  per push vs on dispatch), post-M5 work recorded (OpenAI provider, whisper
  bridge, model download, keychain + Keys sheet, PRIV-3 file deletion, signing
  knob, review pass), and the standing-blockers block replaced: no code
  blockers remain; the honest constraint now is that this environment has
  neither an Apple nor a Swift toolchain (`download.swift.org` is blocked by
  the egress policy), so **all Swift verification is CI's**. §1.4's T2 row no
  longer claims a snapshot job exists; the T1 row now lists what actually runs.
- **PRIV-AUDIT.md** — header re-tiered (T2 is green, not blocked). PRIV-1's
  "the only URLSession use is RemoteExtractor" was factually wrong once the
  OpenAI client and the model download landed: now enumerated as exactly three
  call sites, two text-only egress and one inbound-only GET with no body, with
  a house rule that a fourth is a review item. PRIV-5 updated for the
  transactional restore and the richer round-trip test.
- **DESIGN.md** — §14's deferred register claimed screens that shipped in M3/M5
  (timeline and contact mini-pages, portrait onboarding) and omitted four
  surfaces that shipped without design ratification (Keys sheet, store-failure
  screen, Home resume doors, review edit sheet); both corrected, the latter in
  a clearly-labeled section pointing at RATIFICATION §4.11. The `ink-faint`
  open question is marked resolved (darken, at M2). Undo-on-settled-lines and
  §10.5 pronouns are recorded as open with their registered decisions.
- **EVALS.md** — the four-layer table keeps its spec; an "as built" note now
  records where the rigs sit against it: no nightly job exists (per-push
  instead), the XCUI halves of L2 are dispatch-only, and the rendered-pixel
  design checks have **no automated tier at all** — they are device-graded,
  which is what design_lint now prints instead of naming a snapshot job that
  was never built.
- **DATA-MODEL.md** — Decision 6 gains an "as built" note: write-time chain
  flattening keeps the pointer graph one hop deep, reads still resolve to a
  fixpoint with a cycle guard, self-row merges are refused.
- **RATIFICATION.md** — item 11 added (the four undesigned surfaces).

## 2026-08-06 · Device bring-up defects (Abdoul's first real memo)

Three defects, found by the only tier that could find them — a person holding
the phone (T3):

- **Mic refused to start: `kAudio_ParamError` (-50, logged as 4294967246).**
  The capture session paired the `.record` category with the `.spokenAudio`
  mode; that mode is for *playing* spoken content and the pair is invalid, so
  every recording attempt failed into the mic-unavailable line. Now `.record` +
  `.measurement` (the speech-recognition mode, which also disables the system
  signal processing that would reshape input before whisper hears it), with
  fallbacks to `.default` and a bare category. `record()`'s return is checked
  (a false return no longer leaves the UI claiming it is listening),
  `prepareToRecord()` runs first, and the session is deactivated with
  `notifyOthersOnDeactivation` so other apps aren't left ducked.
- **No transcription on the phone at all.** `#if canImport(whisper)` is false
  until `scripts/build-whisper.sh` vendors the xcframework, so every memo
  parked as audio-only. Added `CascadingTranscriber`: whisper first, **Apple's
  on-device recognizer as the floor** (`requiresOnDeviceRecognition = true`,
  `supportsOnDeviceRecognition` checked, no server path to fall into — PRIV-1
  unchanged). Floor transcripts report `usedFullModel: false`, so §7.5 keeps
  the audio until the ceiling model re-listens and the upgrade pass replaces
  them. Registered as a divergence from DATA-MODEL §6's iOS-26
  `SpeechTranscriber` (RATIFICATION §4.12); `NSSpeechRecognitionUsageDescription`
  added.
- **"1 memo waiting · tap to pick it up" did nothing when tapped.** The retry
  hit the same missing transcriber and swallowed the error. A tap that fails
  now states why (`captureNotice`, one plain line under the footer, no red),
  distinguishing a denied permission, a refused off-device path, missing audio,
  and "nothing here can do this yet". `CaptureFailureTests` pins all four plus
  the cascade's fall-through — a silent dead end is now a test failure.

## 2026-08-06 · Session 2 · Working the field-notes queue

Abdoul hand-tested on device and wrote up sixteen findings; this pass implements
them. Two of the sixteen were already closed by him mid-session (FN-7, FN-11's
main half), three need his decision or his hardware, and the rest landed here.

**Verification tooling first, because it was measuring less than it claimed:**

- **FN-4** — `sql_check.py` harvested only triple-quoted Swift literals: 56 of
  243 embedded statements, reported as "56 prepared, 0 failed", which reads
  like coverage. Single-line literals are now harvested too — **186 → 190
  statements**, most of `StoreReader` and every ad-hoc app lookup among them.
  Verified with a planted typo rather than by assertion. Also tightened: a
  statement now needs a clause keyword as well as a leading verb, because
  `"with"` is an English stopword in the search module and was being harvested
  as a CTE.
- **FN-3** — nothing the gate ran compiled `apps/OrbitApp/**`, which is how an
  `AppleSpeechTranscriber` hang sat in a fully green tree. `check.sh` now
  builds the app target when Xcode and xcodegen are present, and when they are
  not it **names the tier it could not run** instead of printing an
  unqualified pass. (Skips are tracked in a newline-joined string: macOS ships
  bash 3.2, where an empty array under `set -u` is an unbound-variable error.)

**The funnel:**

- **FN-9** — two contradicting claims in one memo passed each other unseen; the
  check read only stored facts and only ran for already-existing subjects, so a
  person's *first* memo could never be checked against itself. Drafts are now
  compared to each other. A draft has no assertion row to CLOSE, so the
  superseded one is proposed with its end date already set and a rationale
  quoting what ended it — both cards still go to review (P5). Only dated claims
  pair up: undated, there is no order to infer, and inferring one is what P4
  forbids.
- **FN-2** — `location` carries origin *and* residence, so a birthplace and a
  current city raised a contradiction between two facts that are both true. A
  location fact now only closes another when both sides state a start. The
  modelling question (a separate `origin` predicate) is **not** taken here: it
  needs a CHECK-constraint migration, and FN-17 below says why that is not
  currently possible.
- **FN-16** — the same conversation captured twice wrote two assertions for one
  truth, unnoticed (INV-7 suppresses *rejected* claims, and only within one
  event). A draft matching a live fact now says so on the card. Deliberately a
  note and not a suppression: two independent observations are evidence, and
  collapsing them silently would destroy it.

**Correcting what is already saved (FN-13, FN-15, and FN-14/FN-11's tail):**

`renamePerson` had zero call sites, entities had no rename method at all, and
`amendAssertion` was wired to nothing — so a name was frozen at first write and
a wrong fact could only be answered by recording another memo. `renameEntity`
now exists behind the write funnel (INV-5) and keeps the old name **as an
alias**, which is both the audit trail and what keeps §7.10 guarantee 3 working:
the next voice note using the shorthand still resolves. On the Desk the name is
tappable and the hero fact carries a quiet "Fix this"; one sheet serves both,
showing the quote untouchable (P5) and writing over `object_value` as an
amendment so the original stays readable (INV-1).

**Extraction (FN-10, FN-12, FN-14, FN-8) — one defect wearing five shirts:**

`object_value` used as a free-text summary. A 27-word clause in the tag slot
defeats the point of two fields, because §17 network queries traverse tags.
The prompt is golden-gated (BUILD §1.3) and no key or Swift toolchain exists in
the cloud session, so **v1 is untouched and stays the default** — every recorded
fixture and every ratified provisional number was produced under it. `v2` adds
the rule as *one* rule with concrete cases (never a clause; never a name a ref
already carries; never a restatement of the date; status for education; role
title alone for employment), plus origin-vs-residence marking that the narrowed
contradiction rule keys on, plus `part_of` nesting for places instead of any
lookup (PRIV-2 unchanged). `ORBIT_PROMPT_VERSION=v2` runs the candidate so the
golden run can happen on Abdoul's Mac.

**PIPE-17** makes it measurable rather than aspirational: a tag over twelve
words, or one repeating a person name its ref already carries, is a Critical.
The ratified corpus passes at a measured max of seven words; both planted
defect shapes are caught.

**FN-5 + a regression it exposed:** the ceiling download now counts consecutive
failures and, after three launches *with recordings actually piling up*, says
so in one plain line — never as a progress report (P10). Implementing it
surfaced **FN-18**: `warmModels` and `upgradeRetainedAudio` reached for the
whisper stage with `transcription as? WhisperTranscriber`, and wrapping the
transcriber in `CascadingTranscriber` the day before made both casts fail
silently. No error, no log — just a model that never downloaded and a §7.5
re-listen that never ran. Both now resolve through `AppModel.whisperTranscriber`.

**New field notes raised by this pass:** FN-17 (no migration path for a
populated database — blocks FN-2 and FN-11's remainder, and matters now that
his phone holds real memos) and FN-18 (above, closed).

**Tier honesty:** everything here is T1-verified (SQL rig, design lint, PIPE
measurement, negative controls on both new checks) plus Swift tests written for
the new behaviour. No Swift compiler and no Apple toolchain exist in this
environment, and GitHub Actions has not picked up a job since 07-31, so the
Swift halves are **unbuilt** until Abdoul's Mac runs them.

### 2026-08-06 (later) · Prompt v2 promoted — golden gate waived by Abdoul

Abdoul waived BUILD §1.3's golden-run requirement in chat so the FN-10 fix
(`object_value` as a tag, not a summary) reaches the device now. v2 is the
active prompt; `ORBIT_PROMPT_VERSION=v1` restores the measured one.

Registered in three places rather than taken quietly, because the waiver has a
consequence that outlives the decision: **the provisional PIPE numbers were all
measured on v1 fixtures, so the ratification packet's §1 table now describes the
previous prompt.** It remains a valid CI ratchet — the fixtures it grades did
not change — but it no longer describes what the app does. `orbit-evals measure
--live` clears that debt.

Noted for the record: the rule stands for future bumps. This is an exception the
owner took deliberately with the cost stated, not a precedent that the gate is
optional. The narrower protection still runs on every commit — PIPE-17 grades
tag discipline in `check.sh`, so the specific defect v2 targets cannot return
unnoticed even without a live run.

## 2026-08-07 · Session 3 · FN-17, FN-19, and half of FN-20

- **FN-17 (migration runner) — closed, and it unblocks two others.** `ensure`
  created the schema only when the database was empty, and `schema_version` was
  written once and never read, so every schema change reached fresh installs
  only. `Schema.migrate` now applies numbered `migration_XXX.sql` files in
  order, each **in one transaction with its own version bump** — a failure
  leaves the database where it was, and the retry on next launch is safe
  because migrations are idempotent. Migration 002 adds `person_alias`, the
  table FN-19 found missing on the person side. The T1 rig proves each
  migration applies to a database *without* it (objects dropped first, standing
  in for the older database it will meet), re-runs cleanly, and leaves the
  INV-4 rebuild intact; Swift tests cover the populated-database path. FN-2's
  `origin` predicate and FN-11's entity-ambiguity kind are decisions again
  rather than blockers.
- **FN-19 (pointer-shaped names) — closed at two layers.** The funnel refuses a
  possessed relationship word, including the name-possessive form ("John's
  friend from work") that a pronoun-only check would have missed — I caught
  that one by running the heuristic against its own test cases rather than
  trusting it. Bare relationship words are deliberately left alone: "Mother
  Teresa", "Brother Ali" and "Dad" are names people are called. v2 rule 19
  tells the extractor to ask instead of inventing a label, and
  `knownNamesPrimer` filters pointer names so one that predates the guard is
  never fed back to whisper or the extractor.
- **FN-20 — prompt half done.** v2 rule 20: a meeting place is not a fact about
  the person. The routing half is still open and now recorded precisely —
  `event.location_entity_id` exists and no extraction path ever sets it, so the
  venue is currently dropped rather than misfiled. That is a payload + prompt
  change, no schema work.
- Left open deliberately: FN-1 and FN-6 (device), FN-2's modelling question and
  FN-11's card type (both now unblocked, both his call), and the
  `person.display_name NOT NULL` question FN-19 surfaced — an unnamed known-of
  person cannot currently be represented as a row.
- **Tier honesty unchanged:** T1 rigs and negative controls are green here; no
  Swift compiled in this environment and Actions has still not picked up a job
  since 07-31, so the Swift halves are unbuilt until his Mac runs them.

## 2026-08-08 · Session 5 · Review threads, and one portability class paid for four times

Two strands, both driven by what CI and Bugbot flagged rather than by a plan.

**Eight review threads, all confirmed, all fixed.** Six landed earlier
(`e6e02f8`): export omitting `person_retirement` and `person_alias` (a PRIV-5
archive restored on a fresh database lost who was retired), search answering
qualifiers instead of places, merge-blind last-seen and nondeterministic
first-met, job-vs-company query routing, the FN-5 status line hiding its own
backlog, `measure.py` ignoring golden forbidden kinds, resume overwriting
manifest failures, and missing fixtures skewing recall by moving the
denominator. Two more arrived on the fixes themselves (`3087aba`): the status
line counted every retained recording while the re-listen pass only touches
`confirmed` rows — so a memo in review was reported as waiting on the model in
one place and waiting on Abdoul in another — and the manifest merge read
`total_seconds` through `as? Double` alone, which JSON's single number type
turns into nil, silently restarting the cumulative clock the resume fix existed
to protect.

**Five of the ten were introduced by the previous round's fix.** That is the
number worth keeping. Each was a correct fix to the reported defect that moved
the defect one layer over, and none would have been caught by re-reading the
change — only by something adversarial reading it fresh.

**FN-38 (renumbered from a collision with FN-37) cost four red `core` runs for
one finding.** Foundation's URL path accessors and its bundle resource listings
are different types on Darwin and Linux; three consecutive fixes each replaced
the spelling that had just been reported with another Darwin-only one. Closed
by asking a different question — `ExtractionPrompt.latestVersion` now probes
`Bundle.url(forResource:)` rather than listing and filtering — plus one shim in
OrbitCore for the accessor uses, and a lint guard covering all five APIs rather
than the one last reported. The lesson is cheap and was available every time:
sweep for the siblings of a reported failure before pushing.

**A third strand, opened by the first test failure since the build compiled
again.** Search recognised "what is Eliah's role?" as a role question and never
admitted it to a fact lookup — one list gates, the other chooses, and only one
had learned the new vocabulary. Fixing that surfaced three more layers over as
many rounds: a matcher reading words as runs of letters ("org" inside *Morgan*),
keyword tokens stripped so a contact named Job could never be asked about, and a
rescue for that which could fuzzy-match "role" to a contact named **Rose** and
answer confidently about someone never mentioned. Written up as FN-39; the
through-line is that guessing a word is a name is how you name the wrong person.

**One thing added rather than fixed.** `overnight.sh` has two stages, and only
the expensive one was unreachable from here: collection needs an API key,
grading needs nothing. Grading also had no coverage, so a defect in it would
have surfaced at the end of a paid ten-run collection — the worst possible
moment. `scripts/dev/aggregate_selftest.py` now builds a synthetic collection
from the canonical fixtures with two deliberate holes (an ordinary memo, and the
`expect_empty` golden where an absent fixture *is* a passing payload), grades it,
and asserts the denominator stays fixed across runs. Its negative control —
restoring the pre-fix skip behaviour — reproduces exactly what review reported:
a run missing five required items scoring 100% recall. In the gate now.

**Tier honesty:** T1 rigs and all three negative controls are green here; the Swift
halves are verified by CI, and nothing on this branch has run on a device.
`scripts/dev/overnight.sh` is still owed — both hosts it needs are blocked by
this session's egress policy, so the live PIPE numbers remain provisional and
must come from Abdoul's Mac.
