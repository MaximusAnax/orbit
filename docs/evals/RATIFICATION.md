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

> **Stale as of 2026-08-06.** Every number above was measured against fixtures
> produced by prompt **v1**. The live prompt is now **v2** (§4.16 — you waived
> the golden gate), so these describe the previous prompt until a live run
> re-measures them. They remain a valid CI ratchet, because the fixtures they
> grade are unchanged; they are no longer a description of what the app does.

## 2. ◊ awaiting your first ratified number (machinery ready, needs you/device/key)

| Check | ◊ item | What produces the number |
| --- | --- | --- |
| PIPE-12 | Eliah-portrait episode split quality | `orbit-evals measure --live` with `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` (retention bar per BUILD §1.3) |
| PIPE-1/2 | Transcription name accuracy / WER | `scripts/build-whisper.sh` on your Mac + audio fixtures on device |
| J-1 budget | ≤ 12 taps (measured path exists) | Run JourneyUITests once on CI/device, read the tap count |
| J-2 budget | ≤ 20 taps | same |
| J-3 budget | ≤ 3 taps (from review) | same |
| D-4 | Ember pixel coverage ≤ ◊5% | No snapshot rig exists yet — graded by eye on device (T3) until one is built |
| PERF-1…6 | All six budgets | Device runs; harness stubs note where each is measured |

## 3. The PIPE-12 caveat, restated honestly

The provisional pipeline numbers were produced by the same in-session model
that authored the fixtures (recorded as `claude-fable-5(in-session)` in every
fixture). The Eliah golden was authored independently by you, which makes the
grading legitimate — but threshold ratification for the production pipeline
still requires the production extractor (`claude-opus-5`) run against the
**live** prompt — which is now v2, not the v1 these fixtures came from — per
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
6. **Deployment target: iOS 17, diverging from BUILD §"iOS 26 minimum"** — a
   registered doc conflict, not a silent one. iOS 17 lets the app build and run
   on today's simulators/CI and any reasonably recent device; the one thing
   iOS 26 buys (SpeechTranscriber as the ratified low-storage fallback,
   DATA-MODEL §6) is currently unused — whisper.cpp is the only transcription
   path wired. Ratify iOS 17 (and amend BUILD), or veto and I raise the target
   the moment you confirm your device runs iOS 26.
7. **UI-journey cadence** — the XCUI journey suite is a dispatch-only CI job
   (app workflow → journeys: true), not per-push, because a cold simulator
   boot blows the 30-minute push budget. EVALS reads as if journeys gate every
   PR. Ratify the dispatch cadence (run before merges and after UI-touching
   changes), or veto and journeys move back into the push gate with a longer
   budget.
8. **Undo on settled lines: deferred surface** — accept/reject in review is
   final in the UI today (the ledger records everything; a wrong accept is
   correctable via amend/reject-later paths, a wrong reject via new evidence).
   A one-tap "take that back" surface is registered as deferred work, not
   pretended at.
9. **§10.5 pronouns** — the design's "Reach her" copy assumes a known pronoun.
   The build never guesses from a name: where DESIGN §10.5 wants a pronoun and
   none has been recorded, the person's name is used instead ("Reach Sana").
   A pronoun field (user-entered, never inferred) is deferred surface work.
10. **Model download integrity** — the ceiling-model download pins an exact
   HuggingFace URL but does not yet verify a checksum after download. Registered
   as hardening work; ratify the pinned-URL-only posture for now or ask for the
   checksum gate before first device install.
11. **Four surfaces built but never designed** (DESIGN §14, "Surfaces built that
   this document does not describe") — the Keys sheet, the store-failure
   screen, Home's resume doors, and the review edit sheet. Each exists because
   the app could not function without it, each is rendered in the ratified
   tokens with both room forms, and none went through design ratification.
   Ratify as-is, or send any of them back for a designed treatment.
12. **Apple on-device recognition as the transcription floor** — DATA-MODEL §6
   ratified `SpeechTranscriber` (iOS 26) for exactly this role; the build
   targets iOS 17, so the same idea is implemented on `SFSpeechRecognizer`
   with `requiresOnDeviceRecognition = true` and `supportsOnDeviceRecognition`
   checked first. **There is no server-side path to fall into**: if this phone
   cannot recognize locally, transcription fails and says so rather than
   sending the recording to Apple (PRIV-1 stays absolute). Its transcripts
   report `usedFullModel: false`, so §7.5 keeps the audio until whisper's
   ceiling model re-listens and replaces them. Ratify this as the floor, or
   veto and whisper becomes a hard prerequisite for capture.
13. **Within-run contradiction detection** (FN-9) — two contradicting claims in
   one memo now resolve against each other: the superseded one is *proposed*
   with its end date already set, quoting what ended it. This is the system
   inferring an order from stated dates, which it did not do before; both cards
   still require your yes. Ratify, or veto and both stay open for you to
   reconcile by hand.
14. **Duplicate claims are noted, never suppressed** (FN-16) — capturing the
   same conversation twice tells you the fact already exists and lets you
   decide, rather than dropping the repeat. The reasoning: two independent
   observations are evidence. Veto if you would rather repeats were dropped
   silently.
15. **`location` narrowing instead of an `origin` predicate** (FN-2) — a
   location fact now only closes another when both sides state a start, so a
   birthplace is never closed by a move. The cleaner fix is a separate
   predicate, which needs a schema migration that does not exist yet (FN-17).
   Ratify the narrowing as the interim, or prioritise the migration runner.
16. **Prompt v2 promoted, golden gate waived by you** (FN-10/12/14/2/8) — you
   waived BUILD §1.3 on 2026-08-06 so the `object_value`-as-summary fix reaches
   the device now rather than after a measurement run. v2 is the active prompt.
   The outstanding debt is measurement, not correctness: run
   `swift run orbit-evals measure --live` when you have a key, and the numbers
   in §1 below get replaced with ones that describe the prompt actually
   running. `ORBIT_PROMPT_VERSION=v1` restores the measured prompt if v2 turns
   out worse in practice.
17. **Entity disambiguation card: still not built** (FN-11's tail) — `Ambiguity.kind`
   remains person-shaped, so "is CMU Carnegie Mellon?" cannot be asked. Adding
   it means a new card type, a schema change, and a golden run; the field note
   asks whether it deserves its own kind, and that is a design call rather than
   a defect. It was left for you, not silently half-built.
18. **FN-2 resolved as a controlled qualifier, not a new predicate** (your call,
   2026-08-07) — `location.object_value` is now `origin` or `residence`, the
   same shape `education` uses for status. Supersession became exact: only a
   residence closes a residence. Prompt v3 carries the rule and was promoted
   under the same waiver as v2, so it is **also unmeasured** — one live run now
   clears both. A separate `origin` predicate remains available and is no longer
   blocked (FN-17), if querying origin structurally turns out to matter.
19. **FN-11 resolved as "not yet"** (your call, 2026-08-07) — entity
   disambiguation gets no card type; correcting an entity stays typing rather
   than asking. Revisit when you notice yourself typing the same expansion more
   than once or twice.
