# ◊ Ratification packet — for Abdoul

Everything marked ◊ in EVALS.md is a provisional number that becomes binding
only when you ratify it (the ratchet rule: measure once honestly, ratify, then
never regress). This packet lists every open ◊ with the best measurement the
session could produce and what's blocking a real number where one is missing.

## 1. Ready to ratify now (provisional numbers exist)

| Check | Provisional value | Source | Notes |
| --- | --- | --- | --- |
| PIPE-3 (fact recall vs goldens) | 100% (90/90) | `measurements/2026-07-29-provisional.md` | In-session extractor — floor-setting, see §3 below |
| PIPE-5 (hedge preservation) | 100% | same | |
| PIPE-6 (verbatim fidelity) | 100% | same | Mechanically substring-checked |
| PIPE-7 (invented facts) | 0 | same | Critical class — must stay 0 |
| PIPE-11 (archetype defaults) | 3/3 | same | |
| Critical classes (invention/false attribution/verbatim) | 0 | same | |

**Suggested ratification:** adopt these as the ratchet floor *for the replay
corpus*, marked "in-session model" — they bind CI immediately (any regression
on the same fixtures fails) without pretending to be production numbers.

## 2. ◊ awaiting your first ratified number (machinery ready, needs you/device/key)

| Check | ◊ item | What produces the number |
| --- | --- | --- |
| PIPE-12 | Eliah-portrait episode split quality | `orbit-evals measure --live` with `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` (retention bar per BUILD §1.3) |
| PIPE-1/2 | Transcription name accuracy / WER | `scripts/build-whisper.sh` on your Mac + audio fixtures on device |
| J-1 budget | ≤ 12 taps (measured path exists) | Run JourneyUITests once on CI/device, read the tap count |
| J-2 budget | ≤ 20 taps | same |
| J-3 budget | ≤ 3 taps (from review) | same |
| D-4 | Ember pixel coverage ≤ ◊5% | Snapshot job (macOS CI) |
| PERF-1…6 | All six budgets | Device runs; harness stubs note where each is measured |

## 3. The PIPE-12 caveat, restated honestly

The provisional pipeline numbers were produced by the same in-session model
that authored the fixtures (recorded as `claude-fable-5(in-session)` in every
fixture). The Eliah golden was authored independently by you, which makes the
grading legitimate — but threshold ratification for the production pipeline
still requires the production extractor (`claude-opus-5`, prompt v1) per
EVALS §9. Add the key; `orbit-evals measure --live` produces the packet's
missing column in minutes.

## 4. Decisions taken during the build that you should ratify or veto

1. **INV-19 enforcement point** — capture-or-review instead of capture-only:
   material-less, participant-less captures are refused; accepted assertions
   attach their subject as an `about` participant. (WORKLOG Phase 6.)
2. **INV-24 refusal scope** — an unquotable PROPOSE_STATE drops that op, not
   the whole sync run. (WORKLOG Phase 7.)
3. **Embeddings: not yet** — all search goldens pass on FTS5 + structure;
   sqlite-vec deferred until a golden demands semantic recall. (WORKLOG Phase 6.)
4. **No GRDB** — first-party `OrbitSQLite` wrapper; zero third-party runtime
   deps in the trust core. (BUILD §1.2, already in the ratified BUILD.md.)
5. **Review order** — proposals render dependency-first (insertion order),
   person card before its facts. (WORKLOG Phase 4.)
