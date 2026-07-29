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
