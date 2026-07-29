# Privacy audit — PRIV-1…5 (EVALS §4.4)

State as of 2026-07-29, end of the in-session build. Each promise is listed
with what is **mechanically enforced in code today**, what is **tested**, and
what still needs a **device run** to close. Verification tiers per BUILD.md
§1.4 (T1 = executed locally this session; T2 = CI, currently blocked by repo
push access; T3 = device/secret-gated).

## PRIV-1 — Audio never egresses (absolute)

**Enforced by construction:**
- `TranscriptionService` and `AudioRecording` are protocols with **no network
  implementation** (Transcription.swift states this as a contract; whisper.cpp
  runs in-process; `ModelManager` downloads models *in*, never uploads).
- The only `URLSession` use in the entire codebase is `RemoteExtractor`
  (text JSON body). `scripts/lint-writepath.sh` + design review keep it that way.
**Tested:** §7.5 gating at the DB level (J-1 model tests, both branches).
**Open (T3):** network interception during a real capture on device — zero
requests containing audio bytes. Runbook: proxy the device, run J-1, inspect.

## PRIV-2 — Single content-carrying endpoint

**Enforced:** one egress site (`RemoteExtractor.extract`, api.anthropic.com);
no analytics, no crash reporter, no telemetry of any kind exists in the code.
**Tested:** code audit (this session); grep-level check is trivially green —
there is exactly one URLRequest construction in the product.
**Open (T3):** same interception run as PRIV-1 confirms at runtime.
**Standing requirement:** the API org must be zero-data-retention (BUILD §1.3).

## PRIV-3 — Audio deletion at the filesystem level, full-model gate honored

**Enforced:** `raw_audio_ref` cleared only via `confirmEvent(fullModelTranscribed:
true)` (§7.5); DB triggers make the ref the *only* mutable column post-confirm.
**Tested:** J-1 both branches (deleted after full model; retained after tiny
model) through the production path.
**Open (T3):** the file-delete half (`FileManager.removeItem` at the cleared
ref) ships in `UserEditService.confirmEvent`'s device path and must be verified
on device (simulator filesystems lie about little).

## PRIV-4 — Extraction payload contains transcript + necessary context only

**Enforced:** `RemoteExtractor.userMessage` is auditable in one screen: capture
context line, owner name + era anchors, known-name/entity primers, transcript.
Nothing else exists in the request body; the JSON schema constrains the reply.
**Tested:** the prompt/message builder is deterministic; fixtures show payloads.
**Open:** none mechanical — re-audit whenever `userMessage` changes (house rule:
any diff touching it cites PRIV-4 in the commit).

## PRIV-5 — Export: complete, human-readable, restore passes INV-4

**Enforced + tested (this phase):** `Export.dump` archives the full log
(pretty-printed JSON, verbatims in the clear, rm_* excluded by design);
`Export.restore` into a fresh schema rebuilds read models; `ExportTests`
asserts fingerprint equivalence and log row-count round-trip.
**Open (T2):** run in CI once push access returns. UI entry point for export
is a deferred surface (registered in BUILD.md §8) — the capability ships first.

## Residual risks

- iOS file-protection class (complete-until-first-auth) is asserted in
  AppModel.production comments but only verifiable on device.
- The keychain shim (`KeychainLite`) is env-var backed off-device; the real
  Security.framework wiring is part of the device bring-up punch list.
