# Field notes — deferred work from hand testing

Things found while using the app on a real phone that were **not** fixed in the
moment, because fixing them mid-session would have been the wrong shape of work:
prompt changes that need a golden run (BUILD.md §1.3), gate changes that need CI
thought, or anything where the fix is larger than the session it interrupted.

This is a queue, not a changelog — what got fixed lands in WORKLOG.md instead.

**Each entry:** date found · what · why it matters · what closing it needs ·
verification tier (T1 local / T2 CI / T3 device-or-secret).

Status: `open` · `in progress` · `closed (→ WORKLOG date)` · `won't fix (reason)`

---

## 2026-08-06 · Session 1 — first device run, whisper vendored mid-session

### FN-1 · Assertions may be dropping their entity — **needs re-checking** · T3

**Original note (2026-08-06 17:xx):** "he went to Harvard and he graduated in
2022" rendered as `education · graduated in 2022 (2022)`, read as the extractor
dropping Harvard entirely.

**Correction (2026-08-06 18:xx):** that diagnosis is unsafe. The review card was
choosing `object_value` *or* the linked entity, never both — so an assertion that
correctly linked Harvard would have rendered identically, with the school hidden
by the UI. The display bug is fixed (cards now render
`education · Harvard — graduated in 2022`), which means **this entry cannot be
confirmed or dismissed until a fresh capture is reviewed on the fixed build.**

What is still suspicious and worth watching on the next run:
- `object_value: "graduated in 2022"` restates the date rather than naming a
  degree or status, which is not what "a role title, a date, a name"
  (DATA-MODEL §2) intends.
- `valid_from == valid_to == 2022` for something that lasted four years.

**To close:** re-review one capture on the fixed build. If the entity is present,
downgrade this to the `object_value` phrasing issue only. If it is genuinely
absent, it is prompt work + golden run (BUILD.md §1.3).

*Lesson worth keeping: a display that silently drops a field produces
false bug reports about the layer underneath it.*

### FN-2 · `location` is doing three different jobs — **contradiction half closed 2026-08-06; modelling question open** · T3

One memo produced three `location` assertions: born and raised in New York,
from the Upper East Side, in San Francisco since 2022. The first two are origin,
the third is current residence.

This is more than untidy. `location` is one of the three predicates
(`SyncEngine.swift:186`, with `employment` and `education`) where a new open fact
raises a **CLOSE proposal** against an existing open one. Accepting all three in
order can generate contradiction proposals between a birthplace and a current
city, which are not contradictory. The ledger stays correct — CLOSE is a
proposal, never an overwrite, and the user can say no — but the review fills
with questions that shouldn't have been asked.

Two candidate fixes, and the choice is a data-model decision, not a prompt tweak:
either the prompt distinguishes origin from residence (a new predicate, which
touches DATA-MODEL), or the contradiction rule stops treating every `location`
as mutually exclusive.

**To close:** decide the modelling question first, then prompt + golden run.
Fixture: one memo carrying birthplace and current city together.

### FN-3 · `scripts/check.sh` never builds the iOS app target — **closed 2026-08-06** · T2

The one gate runs `swift build` / `swift test` over the SPM package only.
Everything under `apps/OrbitApp/` — the entire app: `Transcription.swift`,
`AppModel.swift`, `Screens.swift`, `ViewModels.swift` — is compiled by **nothing**
the gate runs. `.github/workflows/app.yml` does build it, so this is a
local-gate hole rather than a CI hole, but "check.sh is green" reads as "the app
is fine" and it does not mean that.

Found the hard way: a hang bug in `AppleSpeechTranscriber` (continuation never
resumed when a recognition task ended without a result or an error) sat in the
tree with the gate fully green.

**To close:** decide whether check.sh gains a macOS-only stage (`xcodegen
generate && xcodebuild build`, skipped when Xcode is absent, the same shape as
the existing `command -v swift` guard) or whether the gap gets stated loudly in
the script's own output so nobody reads green as more than it is.

### FN-4 · The SQL fast-loop checks 23% of the SQL — **closed 2026-08-06** · T1

`scripts/dev/sql_check.py` harvests embedded SQL with a single regex over
**triple-quoted** Swift literals (`"""…"""`). Single-line SQL string literals are
never seen.

Measured 2026-08-06: **56 triple-quoted statements checked, 187 single-line
statements unchecked.** The check reports "56 statement(s) prepared, 0 failed",
which sounds like coverage and is roughly a quarter of it. A typo in any
single-line query — most of `StoreReader`, most of the app's ad-hoc lookups —
reaches the device.

**To close:** extend the harvester to single-line literals. Interpolated SQL
already has a skip path (`\(` → excluded), so the same escape applies. Expect
real failures on first run; that is the point.

### FN-5 · Whisper ceiling model is a 547MB first-run download — **visibility added 2026-08-06; device observation still owed** · T3

`ModelManager.downloadCeilingIfNeeded()` fetches `large-v3-turbo-q5_0` (547MB)
during onboarding dead time, unmetered and unannounced. Until it lands, every
transcript comes back `usedFullModel: false`, so §7.5 retains **every** recording
and `upgradeRetainedAudio()` cannot run (it early-returns on a nil `ceilingURL`).

Working as designed, and the floor model keeps capture honest meanwhile. Worth
watching rather than fixing: if the download quietly fails on cellular or a full
disk, the symptom is unbounded audio growth with no user-visible cause, and the
current failure path is a silent `catch` that retries next launch.

**To close:** device observation first — does it complete on a normal
connection? Then decide whether a failure that persists across N launches
deserves a line the user can see.

### FN-16 · Nothing dedupes facts across two captures of the same thing — **closed 2026-08-06 (as a note, not a merge)**

Two "Memos waiting" rows looked identical, and going through one surfaced what
appeared to be the same memo again. Two separate things were going on:

**A bug (fixed same day):** the `needsProposalReview` query returned one row per
*sync run*. Re-extraction is supported — `openSyncRun` always creates a new run,
`extractionVersion` exists — so an event extracted twice appeared twice, as two
`WaitingMemo`s sharing one id (also a duplicate-id `ForEach`). Now deduped by
event, opening the oldest unanswered run.

**The open issue:** INV-7 suppression is narrower than it sounds. It drops a
claim only when *the same claim was previously **rejected** for the same event*
(`p.state = 'rejected'` AND `s1.event_id = s2.event_id`). It does not suppress
claims that were **accepted**, and it does not reach across events at all.

So recording the same conversation twice produces two full reviews of the same
facts, and accepting both writes **two assertions for one truth**. Nothing in the
pipeline notices. The ledger is not wrong — both are honestly-sourced
observations — but recall will surface the same fact twice, and no merge path
exists for assertions (people and entities merge by pointer; assertions do not).

**To close:** decide whether duplicate-claim detection belongs at propose time
(compare against `rm_current_state` for an identical live claim and mark the
proposal as a repeat rather than a new fact) or is better left to a dedupe pass
in recall. Note the honest tension: two independent observations of the same
fact *are* evidence, and collapsing them silently would lose that.

*Correction to an earlier note in this session: the empty-review screen (FN
entry below) was attributed to INV-7 "dropping every claim already saved." That
was wrong — INV-7 only drops previously rejected claims. The user-facing copy has
been corrected to match.*

### FN-15 · Review is the only moment anything can be corrected — **mostly closed 2026-08-06** · write path

Raised as "should I confirm now and fix it later, or edit the entry manually?"
The honest answer is that the second option does not exist.

`UserEditService.amendAssertion`, `setPinned`, and `setMuted` are implemented and
wired to **zero** UI. Nothing in the app edits a saved fact. The typed-note box
creates a new event; it does not edit an existing one. Combined with FN-13 (no
rename after save), the rule today is: **say yes and the fact is frozen** — the
only correction path is recording another memo about it.

For a memory system whose whole premise is that details matter, "you get one
chance to get it right, at review, or you re-record" is a real constraint.

Mitigations that already exist and should be pointed at first:
- **Per-card "Later" (`setAside`)** is a per-fact defer, not a whole-memo one —
  accept what is certain, set aside only the doubtful card. Returns via the
  set-aside footer.
- **Out-of-order pick-up** exists via long-press on the waiting footer.

Both are invisible. The set-aside footer at least announces itself; the
long-press has no affordance at all, and was proposed back to us as a missing
feature the same evening it shipped — which is the clearest possible evidence it
is undiscoverable.

**To close:** two separable pieces. (a) Surface amend on the Desk so a saved
fact can be corrected in place, through the write funnel with an amendment row
(INV-1 keeps the original). (b) Decide whether the waiting list deserves a
visible affordance instead of a hidden gesture.

### FN-14 · A name inside `object_value` cannot be corrected by renaming — **fix written, golden run owed**

`relation · Amaad — really good friends with Ahmad`. Correcting the person fixed
the first half and left the second, because a name lives in up to three places
per card and a ref-rename only reaches one:

| Where | Reached by rename? | Should it be? |
| --- | --- | --- |
| The resolved ref (subject, object person/entity) | **yes** | yes |
| `object_value` free text | no | **it should not exist there at all** |
| `verbatim` quote | no | no — the quote is the record (P5) |

The `verbatim` column is correct and must stay untouched. The middle row is the
defect, and it is **FN-10 wearing a different shirt**: `object_value` on a
`relation` should be the person link plus at most a literal like "close friend",
not the sentence "really good friends with Ahmad". A ref-rename cannot rewrite
transcript prose, and should not try — prose belongs in `verbatim`.

So this closes with FN-10 rather than separately: fix `object_value` to hold a
tag and the stale name disappears from it, because the name will no longer be in
it. Recorded separately only because the *symptom* is a rename problem and would
otherwise be re-diagnosed as one.

**Partially addressed 2026-08-06:** renames now also answer under the id a ref is
bound to, so accepting the person card no longer makes the old name reappear on
every other card in the run. That was a genuine propagation bug; the
`object_value` half remains and belongs to FN-10.

### FN-13 · Nothing already saved can be renamed — **closed 2026-08-06** · write path

Found by asking what happens to a rename *after* it lands. Three separate holes,
all in the same direction:

1. **`UserEditService.renamePerson` exists and is wired to no UI.** Grep finds
   the definition and zero call sites. A person whose name is wrong after
   acceptance cannot be corrected anywhere in the app.
2. **Entities have no rename method at all.** There is no `UPDATE entity SET
   canonical_name` anywhere in OrbitWrite — not unwired, absent.
3. Consequently the inline rename shipped 2026-08-06 only applies to refs that
   *create* a row. A LINK card that matched an existing entity applies through
   the `if let existing = p.existingEntityID` branch, which reuses the row and
   ignores `canonical_name` entirely.

(3) briefly shipped as a silent no-op — the sheet appeared, the review re-rendered
with the corrected name, and acceptance wrote nothing. Fixed the same day by
withholding the affordance where it cannot be honoured, which is honest but
leaves the underlying gap: **the second time a shorthand comes up, it matches the
existing entity and can no longer be corrected.** So a name has exactly one
moment where it can be fixed — the capture that introduces it.

Note this is asymmetric with the alias machinery, which works properly: aliases
accumulate on every subsequent mention, so *matching* keeps improving while the
*canonical name* is frozen after first write.

**To close:** an entity rename through the write funnel (INV-5), probably
alongside an amendment row so the change is auditable like every other
correction; then surface both it and `renamePerson` somewhere — the Desk is the
natural home, not the review screen.

### FN-10 · `object_value` is absorbing whole transcript spans — **fix written, golden run owed** · prompt

`skill` on a Bob capture came back as the entire clause: *"specializes in like
finding spotting patterns and data, collecting that data, interpreting it and
kind of helping clients essentially figure out how to better use AI systems for
their workflows"* — disfluencies and all — as the `object_value`.

That is the verbatim wearing the tag's clothes. DATA-MODEL §2 is explicit about
the split: **"tag the concept, keep the sentence"** — `object_value` holds a
literal (a role title, a date, a name), `verbatim` holds the sentence. A
paragraph in the tag slot defeats the point of having two fields: §17 network
queries traverse tags, and no query will ever match that string.

Entity kinds already include `skill` and `topic`, so the structured form exists:
`skill → entity(pattern recognition)` with the rambling clause preserved as
verbatim underneath.

Same shape as the `education · alumni` and `employment · <role only>` cases —
the extractor is treating `object_value` as a free-text summary field rather than
a tag. Worth fixing as **one prompt change with one rule**, not three.

**To close:** prompt work + golden run. Fixture should include a deliberately
rambling skill description and assert the tag stays short.

### FN-11 · Spoken shorthand can't be corrected to the real entity — **mostly closed 2026-08-06**

"Colorstack conference" in a voice note means *ColorStack StackedUp Summit '26* —
but nobody says the full name aloud, so the entity is created under the
shorthand and the real identity is never recorded.

§7.10 already has the mechanism: guarantee 3 says each confirmed variant becomes
an `EntityAlias`, so resolution converges as more phrasings arrive. What is
missing is the one-time correction that seeds it — a way at review to say "this
is actually X," keeping the shorthand as an alias so both forms resolve forever
after.

**This is the concrete use case that decides FN-7.** An editable canonical name
on entity cards is not polish here; it is the only place the real identity can
enter the system, because the voice note will never contain it.

Related but separate: "CMU" → "Carnegie Mellon University" is the same problem
with a known answer, and might be better served by asking than by editing. Note
that `Ambiguity.kind` is currently `subject | self_collision | attendance` —
all person-shaped. **Entity disambiguation has no card type**, so an
"is CMU Carnegie Mellon?" question cannot currently be asked at all.

**Resolved 2026-08-06** by inline renaming (see FN-7). Correcting "Colorstack
conference" to "ColorStack StackedUp Summit '26" at review now writes the real
name while `aliases` keeps the spoken form, so the next voice note saying it the
short way still resolves to the same entity — §7.10 guarantee 3, working as
designed, with the missing seed step supplied.

**Still open, and genuinely separate:** "CMU" → "Carnegie Mellon University" is
better *asked* than typed, and `Ambiguity.kind` is `subject | self_collision |
attendance` — all person-shaped. **Entity disambiguation has no card type**, so
that question cannot be asked at all. Decide whether it deserves its own kind.

### FN-12 · Education has no way to say undergrad / grad / alumni — **fix written (option 1), golden run owed** · design

Raised during review: "He was also a CMU alumni" — the school is the object, and
*alumni* is a status. Where does the status live?

It is representable today with **no schema change**: DATA-MODEL §2 designates
`object_value` for literals explicitly including a role title, so
`education → entity(CMU)` + `object_value: "alumni"` is the intended shape, and
the fixed card renders it as `education · CMU — alumni`.

The sharper observation from testing is the one worth recording: **status is not
always derivable from the interval.** `valid_to` non-null implies finished, but
plenty of captures state a status with no dates at all ("he's a CMU alumni",
"she's doing her PhD there") — and an open interval alone cannot distinguish
"currently enrolled" from "we simply never learned when it ended." Those are
different facts and today they look identical.

Options, cheapest first:
1. **Prompt discipline only** — require `object_value` to carry the stated status
   for `education`. Zero schema change; leaves the ambiguity above unresolved
   but makes the status *present* rather than inferred.
2. **Controlled vocabulary** for education `object_value`
   (`undergrad | grad | alumni | attended`), which makes it queryable rather
   than free text.
3. **A real qualifier column.** Touches the ledger and INV-1 immutability;
   should not be considered until 1 and 2 are proven insufficient.

**To close:** try (1), see whether the ambiguity actually bites in practice.

### FN-9 · Contradictions inside a single memo are never detected — **closed 2026-08-06** · T1 testable

Asked during review: "born and raised in New York" and "in San Francisco since
2022" both landed as open `location` facts — how does that resolve? It doesn't.
Two guards in `SyncEngine.swift:186` each independently prevent it:

1. **`if case .id(let subjectID) = subject`.** A person who is new in this memo
   is a `.ref`, never an `.id`, so the whole contradiction block is skipped.
   **The first memo about anyone can never raise a CLOSE proposal**, by
   construction — and the first memo about someone is exactly where a life story
   gets told, contradictions and all.
2. **`store.reader.currentState(of:)` reads stored facts.** Both claims are
   proposals in the same run, neither committed. So even for a person who
   already exists, two contradicting claims *inside one memo* never see each
   other; only claims contradicting an already-saved fact do.

`rm_current_state` is keyed by `assertion_id` with no uniqueness on
(subject, predicate), so both rows sit open and recall reports both.

For David the outcome happens to be right — origin and residence are both true —
but that is luck, not judgement: the check was skipped, not passed. Change the
memo to "he lived in New York, then moved to San Francisco in 2022" and the same
two guards leave two open residence facts, so "where does David live" answers
with two cities and no way to tell which is current.

Note this interacts with FN-2: if origin and residence had distinct predicates,
there would be no contradiction to resolve here at all. Fixing FN-2 may shrink
this problem without solving it — guard 1 still means a new person's first memo
is never checked against itself.

**To close:** decide whether within-run contradiction detection is wanted at all
(it means comparing drafts against each other before anything is stored, which is
a real change to how sync sequences). If yes, guard 1 needs the ref case handled
too. Testable at T1 with a two-contradicting-facts fixture through the replay
harness — no device needed.

### FN-7 · Entity cards can be rejected but not corrected — **closed 2026-08-06**

A LINK card offers Yes / No / Later. `ProposalCardView` gates Edit on
`op == .assert || op == .proposeState`, so if the extractor calls Harvard an
`organization` instead of a `school`, or misses a `part_of` edge, the only move
is No — which throws away a correct entity to avoid a wrong classification.

DESIGN §356 lists what the edit sheet covers: "the mapped value, the since-date,
or the suggested orbit." Entity `kind` and `part_of` are not in that list, so
adding them is a **design extension, not a bug fix** — it needs a decision about
whether classification is something Abdoul curates or something the system owns
and heals later (§7.10 guarantee 4: duplicates merge by pointer, retroactively,
so a wrong entity is recoverable without an edit affordance).

Worth weighing against: the merge path already makes mistakes healable, which is
an argument for keeping review cheap and *not* adding another editable surface.

**Resolved 2026-08-06** — and the design question answered itself once the right
shape appeared. Rather than adding entity fields to the assert edit sheet, the
correction attaches to the **ref**: tap the name on a CREATE_PERSON or LINK card,
fix it once, and every card in the run that mentions that ref updates, because
they all resolve names through the same map. The correction rides to the ledger
via `acceptEdited` on acceptance, so nothing is written until he says yes (P5),
and verbatim quotes stay untouchable (assert cards carry no ref, so they never
become tappable).

Two properties worth keeping in mind if this is revisited:
- Renames are **display-only until accepted**. Set the card aside and the
  correction goes with it, unwritten.
- Only refs *introduced in this run* are renameable. Correcting an already-saved
  person still needs `UserEditService.renamePerson`, which has no UI here.

### FN-8 · "Map places to real-world locations" runs into PRIV-2 — **route (1) taken 2026-08-06** · privacy

Asked during testing: could New York / Upper East Side / Harvard resolve to real
geographic entities rather than free-standing strings?

The obvious implementations are all **content egress**. A geocoder, a places API,
or any gazetteer lookup over the network sends the user's spoken place names to a
third party — and PRIV-2 permits exactly one content-carrying egress, the
extraction endpoint. A second one is not a config change; it is a change to the
privacy promise.

Privacy-safe routes, roughly in order of cost:
1. **Nothing new.** `part_of` already expresses "Upper East Side is in New York"
   when the extractor emits it, and §7.10's alias convergence already collapses
   spoken variants. This may be most of what was actually wanted.
2. **Bundled offline gazetteer.** A shipped dataset of cities/regions, resolved
   on device. No egress. Costs app size and staleness, and needs a decision about
   scope (cities only? neighborhoods? worldwide?).
3. **Network lookup.** Would require re-opening PRIV-2. Not recommended.

**To close:** confirm whether (1) plus a prompt nudge toward `part_of` covers the
real need before considering (2).

### FN-6 · This session's UI changes are build-verified only — open · T3

Shipped without a device run: the working/collapse screen, the waiting-list
long-press sheet, the mapped-fact card line, and the ref-name resolution. All
compile and pass the static design tier; none has been touched on hardware.

Highest-risk of the four, in order:
1. **Collapse** — record, collapse, wait: the result must land in the waiting
   footer, not jump back over whatever you moved on to.
2. **Long-press** — needed `simultaneousGesture` because a `Button` swallows a
   plain long-press modifier. It compiled fine either way; only the device can
   say whether it fires.
3. **Sheet-to-cover handoff** — resuming from the waiting list sets
   `pendingCapture` while that sheet is still dismissing.

**To close:** one deliberate pass on device.

---

## 2026-08-06 · Session 2 — implementing the session-1 queue

### FN-17 · There is no migration path for a database that already has data — open · **blocks FN-2**

Found while looking for somewhere to record an entity rename. `Schema.ensure`
creates the schema **only when the database is empty**:

```swift
if exists.intValue == 0 { try create(on: db) }
```

`schema_version` is written into `orbit_meta` at creation and never read again,
and there is no migration runner. So every schema change from here is a change
only a *fresh* install receives. Abdoul's phone now holds real memos, which
makes this the difference between evolving the model and losing his data.

This is why FN-2 was closed at the contradiction rule rather than at the model:
a separate `origin` predicate means altering a `CHECK` constraint, which in
SQLite means rebuilding the table — with the INV-1/INV-3 triggers and every
foreign key pointing at it — under a live database. Same for FN-11's entity
ambiguity kind, and for anything else the field notes eventually want.

**To close:** a versioned migration runner keyed on `orbit_meta.schema_version`
— numbered files applied in order, each in one transaction, with a test that
migrates a populated v1 database and re-runs the INV-4 rebuild equivalence
check afterwards. Cheap to build now, expensive to retrofit after the second
schema change.

### FN-18 · `warmModels` silently stopped working when the cascade shipped — closed 2026-08-06

Caught while implementing FN-5, and worth recording because it is a *pattern*,
not a one-off: `warmModels` and `upgradeRetainedAudio` both reached for the
whisper stage with `transcription as? WhisperTranscriber`. Wrapping the
transcriber in `CascadingTranscriber` the day before made both casts fail
silently — no error, no log, just a ceiling model that never downloaded and a
§7.5 re-listen pass that never ran, which would have shown up on device only as
audio accumulating forever.

A conditional cast at a seam is a silent coupling: it compiles, it type-checks,
and it stops matching the moment anything wraps the thing it points at. Both
now resolve through `AppModel.whisperTranscriber`, which looks inside the
cascade.

*Lesson worth keeping alongside FN-1's: the layer that silently drops something
produces no bug report at all — which is worse than a false one.*
