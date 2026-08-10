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

Findings from the 2026-08-06/07 device sessions — one entry each, in number
order, status stated in the heading. How a fix was actually made lives in
WORKLOG.md, which is the chronology.

### FN-1 · Assertions may be dropping their entity — **closed 2026-08-07 (was the display)**

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

**Resolved by evidence rather than a device run.** Every education assertion in
the fixture corpus carries an entity ref — `e_cmu` twice, `e_umich`, `e_tartan` —
so the extractor links schools reliably and has all along. The original reading
("Harvard absent entirely") was the review card choosing `object_value` *or* the
entity and never both, which is fixed. No prompt work is owed here.

What remains from the original note is the `object_value` *phrasing* — "graduated
in 2022" restating the date rather than naming a degree — and that is FN-10's
subject, not a separate finding. Folded there.

### FN-2 · `location` is doing three different jobs — **closed 2026-08-07 (option B: controlled qualifier)** · T3

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

### FN-5 · Whisper ceiling model is a 547MB first-run download — **state now visible 2026-08-07; observation still owed** · T3

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

**2026-08-07 — Abdoul cannot say whether the download finished, which is the
finding.** The only signal was a notice that requires three consecutive failures
before it appears, so "is the model here, and what is waiting on it" had no
answer short of reading the filesystem. State you can only infer is state you
cannot check.

Settings now carries a plain line: whether the full model is on the phone, how
many recordings are being kept until it arrives, and how many download attempts
have failed. That turns the §7.5 retention gate from something invisible into
something answerable at a glance.

**Still owed:** the observation itself, now that it can be made — open Settings
on the device and read it. If the model is absent with failures climbing, this
escalates, because every recording is being retained with no user-visible cause.

### FN-6 · This session's UI changes are build-verified only — **mostly closed 2026-08-07** · T3

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

**Verified on simulator 2026-08-07**, running the real app against a seeded
database rather than reading the code:

- **Long-press → waiting list** — fires. This was the one flagged highest-risk,
  because `simultaneousGesture` vs `onLongPressGesture` compiles identically and
  only the device can tell them apart.
- **"Let it go"** — writes: the event became `discarded` with its audio ref
  nulled, and the memo beside it was untouched.
- **Sheet-to-cover handoff** — resuming from the list dismissed the sheet and
  raised the working screen cleanly, no race, no stuck state.
- Incidentally exercised: the working screen renders and returns, the failure
  produced exactly the `audioUnreadable` line (FN-31's classification working on
  a real failure), and the footer count fell to a true "1 memo waiting" (D-9).

**Still owed:** the collapse *action* — tapping "Leave it running" and confirming
the result lands in the footer instead of seizing the screen. The simulator's
transcription fails too fast to hold the screen long enough to press it. Needs
either a real slow transcription on device, or a test seam.

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

### FN-8 · "Map places to real-world locations" runs into PRIV-2 — **closed 2026-08-07 (route 1)**

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

**Closed on Abdoul's call 2026-08-07: route (1) is enough.** `part_of` already
expresses "Upper East Side is in New York", and §7.10's alias convergence already
collapses spoken variants onto one entity — between them that is most of what
"map to real-world locations" was reaching for.

The offline gazetteer (route 2) stays recorded rather than built, with the reason
it would ever be revisited: a need that `part_of` cannot express, not a wish for
tidier names. Route 3 — any network lookup — remains refused, since it would open
a second content-carrying egress and PRIV-2 permits exactly one.

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

### FN-10 · `object_value` is absorbing whole transcript spans — **closed 2026-08-10 (measured, k=10)** · prompt

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

**2026-08-07 live evidence, not yet conclusive.** PIPE-17 (tag discipline —
`object_value` is a tag, not a clause) reached **0 violations** on live output,
down from 4, which is the first sign the fix holds outside the replay corpus.
Held open deliberately: FN-37 showed the same prompt scoring 7/10 and 9/10 on
consecutive runs, so one clean sample of a noisy signal is not a pass. Closes
when PIPE-15's k-run distribution is available.

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

**Decided 2026-08-07 — not building it (option A).** Left as typing, not asking; the tell that would change this is finding yourself typing the same expansion repeatedly. Recorded in RATIFICATION §4.17. Original note below.

**Still open, and genuinely separate:** "CMU" → "Carnegie Mellon University" is
better *asked* than typed, and `Ambiguity.kind` is `subject | self_collision |
attendance` — all person-shaped. **Entity disambiguation has no card type**, so
that question cannot be asked at all. Decide whether it deserves its own kind.

### FN-12 · Education has no way to say undergrad / grad / alumni — **closed 2026-08-10 (option 1 holds at k=10)** · design

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

**2026-08-07:** rides FN-10's evidence — same PIPE-17 check, same reason for
staying open (FN-37).

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

### FN-14 · A name inside `object_value` cannot be corrected by renaming — **open · rescoped 2026-08-10, its premise falsified**

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

**2026-08-07:** rides FN-10's evidence — same PIPE-17 check, same reason for
staying open (FN-37).

### FN-15 · Review is the only moment anything can be corrected — **closed 2026-08-07**

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

**Both halves now done.** (a) The Desk carries rename-a-person and fix-a-fact,
so review stopped being the only moment anything could be corrected. (b) The
waiting list is no longer behind an invisible gesture: the footer opens the list
when more than one memo is waiting and resumes directly when only one is, which
is what its own copy already said — "tap to pick it **up**" versus "pick **one**
up". The long-press still works, and the VoiceOver action remains.

The evidence that settled (b): the list was proposed back to us as a missing
feature the same evening it shipped. A gesture nobody can find is not a door.

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

### FN-17 · There is no migration path for a database that already has data — **closed 2026-08-07** · unblocks FN-2/FN-11

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


A versioned migration runner now exists. `orbit_meta.schema_version` is read as
well as written, `Schema.migrate` applies numbered `migration_XXX.sql` files in
order, and each runs **in one transaction with its own version bump**, so a
failure leaves the database exactly where it was rather than half-migrated.
`Schema.ensure` migrates an existing database instead of skipping it; a fresh
one is born at `latestVersion`, because `001_schema` already contains
everything the migrations add.

Migration 002 adds `person_alias` — the table FN-19 noticed was missing on the
person side, where entities have had one since 001.

The T1 rig checks each migration three ways: it **applies to a database that
does not have it** (the objects are dropped first, standing in for the older
database it will actually meet), it is **idempotent** (a failed version bump
gets retried on next launch), and the **INV-4 rebuild still works afterwards**.
Swift tests cover the populated-database path directly.

*What this unblocks:* FN-2's `origin` predicate and FN-11's entity-ambiguity
kind both need schema changes against a database holding real memos. That is
now a solved problem rather than a reason to defer, so both are decisions again
rather than blockers.

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

### Update 2026-08-06 (later) · FN-10/12/14/2/8 — v2 promoted, golden gate waived

Abdoul waived BUILD §1.3 explicitly so the fix ships now rather than after a
measurement run. **v2 is the active prompt.** The correctness work is done; what
remains is measurement, and it is tracked rather than forgotten:

- Every provisional PIPE number was measured on v1 fixtures, so the packet's §1
  table now describes the *previous* prompt. It is still a valid CI ratchet —
  the fixtures it grades are unchanged — but it is no longer a description of
  what the app does.
- `swift run orbit-evals measure --live` clears the debt and produces numbers
  for the prompt actually running.
- `ORBIT_PROMPT_VERSION=v1` restores the measured prompt if v2 reads worse in
  practice on real memos.

The one check that *is* live for this: **PIPE-17** (tag discipline) runs in the
gate on every commit, so the specific defect v2 targets cannot silently return.

---

### FN-19 · A person can be named by their relationship, and the name then carries identity — **closed 2026-08-07**

A capture produced a person whose `display_name` is **"his brother"**, with a
group header and cards to match.

That string is not a name; it is a pointer that only resolves inside the sentence
that produced it. Three consequences, in worsening order:

1. Two different people's brothers both become "his brother", and person matching
   is by `display_name` — there is no `person_alias` table (see FN-13's notes).
   So the *second* memo's brother can match the *first* one's, silently merging
   two unrelated people.
2. One person with two brothers cannot be represented at all.
3. "his brother" enters `knownNamesPrimer`, so it is fed to whisper as a name to
   listen for and to the extractor as an existing contact to match against.

DATA-MODEL §7.10 states the principle for entities — *strings never carry
identity* — and this is the same failure on the person side, where there is no
alias/merge safety net at capture time.

The model already has the right shape: `relation` is a person↔person predicate
(sibling, colleague, introduced_by), and §7.3 has `known_of` for people known
only through others. So the correct output is an **unnamed** known-of person
joined by `relation(John, sibling, ·)` — not a person literally called "his
brother".

**To close:** decide how an unnamed person is represented and displayed (a
placeholder that reads honestly — "John's brother" as *rendering*, not as a
stored name), then prompt work so relationship phrases stop becoming
`display_name`. Until then, matching on such names should probably be refused
outright — a wrong merge is worse than a duplicate.


Two layers, because a prompt is guidance and this is an identity guarantee:

- **The funnel refuses it.** `createPerson` rejects a possessed relationship
  word — "his brother", "her boss", **"John's friend from work"** (a
  name-possessive points exactly as hard as a pronoun). A bare relationship
  word is left alone: "Mother Teresa", "Brother Ali" and "Dad" are names people
  are actually called, and a guard that ate them would be doing harm.
- **The prompt is told** (v2 rule 19): use the spoken name; if none was spoken,
  emit `match: "ambiguous"` with an `ambiguities` entry asking who they are,
  and carry the connection as a `relation` assertion on the person who *does*
  have a name.
- **The primer no longer spreads it.** `knownNamesPrimer` filters
  pointer-shaped names, so one that predates this guard is never fed back to
  whisper as a name to listen for or to the extractor as a contact to match.

**Still open, and worth naming:** `person.display_name` is `NOT NULL`, so the
"unnamed known-of person" the note asks for cannot be represented as such —
today the honest fallback is a question at review rather than a row. Whether an
unnamed person deserves a real representation is a modelling decision, and it is
now cheap to act on (FN-17).

### FN-20 · Where an event happened is being stored as where a person lives — **prompt half closed 2026-08-07; routing still open**

"met John at a coffee shop in Pittsburgh" produced `location · Pittsburgh —
coffee shop` **as an assertion about John**.

Meeting someone in a city is close to no evidence about where they live, and the
schema already has the right home for it: `event.location_entity_id` (DATA-MODEL
§2, Event). A meeting place belongs to the event; a residence belongs to the
person. Conflating them pollutes the one predicate that recall trusts for "where
is this person now", and it does so with a fact the speaker never asserted.

This is the third distinct job `location` has been asked to do (FN-2: origin vs
residence; now venue), which strengthens the case that the modelling question in
FN-2 is the real one and should be settled before more prompt patches.

Also note `object_value: "coffee shop"` alongside `object_entity: Pittsburgh`
reads as "Pittsburgh — coffee shop", which is not a fact about anything: the
venue is not a qualifier of the city.

**To close:** with FN-2. Decide the predicate split, and route venues to
`event.location_entity_id` where they belong.


v2 rule 20 tells the extractor that a meeting place is not a fact about the
person: only "lives / moved / is from / is based / grew up" produce a
`location` assertion. That stops the invention.

**Still open:** nothing *routes* the place to where it belongs.
`event.location_entity_id` exists in the schema and no extraction path ever
sets it, so "met John at a coffee shop in Pittsburgh" now correctly produces no
location assertion — and also records nothing about where the meeting was. The
payload has no field for it outside portrait episodes.

**To close:** add an event-location to the extraction payload and set
`event.location_entity_id` on confirm. Schema-free (the column exists); it is
payload + prompt + a golden run.

*And the note's own argument stands: `location` has now been asked to do three
different jobs — origin, residence, and venue. That is the strongest case yet
for settling FN-2's modelling question rather than narrowing the rule again.*

---

### FN-21 · The search placeholder never rotated — closed 2026-08-07

§12 ratifies "an omnisearch pill whose placeholder **rotates** through real
query shapes (a name, a company, a fragment — teaching that they're one box)".
The build rendered `searchPlaceholders[0]` and nothing else, so the box taught
only "type a name" — the one shape a user would already assume. All three
shapes now rotate on a 4.5s cut (no slide: §8 motion is a cut, not a carousel).

### FN-22 · `DashedDivider` was built and never used — closed 2026-08-07

§5.6: "dashes separate memory items, never interface elements." The component
existed in OrbitDesign with **zero call sites** anywhere in the app, so the two
memory lists — "Since you last saw them" and "Worth having back" — ran their
items together with plain spacing, which is how an interface list looks, not
how a memory list looks. Dashes now separate items in both (and inside era
groups), never above the first item and never between interface elements.

### FN-23 · The Deck's end card had no way back — closed 2026-08-07

§7: "The end card is always `That's everything · Go be present.` — serif, the
tool's one sentence in the memory voice. **Sub links to the full profile.**"
The serif sentence was right; the sub was empty and the only affordance was a
tertiary button repeating the tag it sat under. The sub now names the way back.

**Not divergences, checked and confirmed correct:** hero is exactly one item;
`N more ›` on threads; the owe-sticky flips its tag and tilts by day only;
"Worth having back" grows era-grouped past 6 rather than truncating (the
ratified unbounded decision, which reads as a contradiction with the same
row's "2–3 items" phrasing — the unbounded clause is the later ratification);
star dust at night only; the portrait's print border by day and ember ring by
night.

**Still not built, and now recorded rather than assumed:** every surface in
§14's deferred register (gardening session, merge flow, brokering, groups,
export UI, set-aside triage as its own screen, usage journal). Those are
deliberate deferrals with data-model support, not gaps — but "the app isn't
fully built" is a fair description of them, and they are the honest answer to
that reading.

---

### FN-24 · Home rendered on the system background, not `room` — closed 2026-08-07

Measured, not eyeballed: Home's background sampled `(255,255,255)` in day and
`(0,0,0)` at night. The tokens were always right — `#f2efe9` / `#101423` — they
were never reaching the screen.

`NavigationStack` paints an opaque system background over anything merely
stacked *behind* it, and Home is the only surface that sits inside one.
Every other surface (review, capture, settings) lives directly in
`RoomBackground` and looked correct, which is exactly why this survived: the app
looked plausible everywhere you compared it against itself, and only wrong
against the mockup.

At night it also cost D-5 outright — star dust renders in that layer, so there
was none to see.

Fixed by splitting `RoomBackdrop` out of `RoomBackground` so the colour field
can be applied as a `.background` *inside* the stack. Verified by sampling both
rooms: exact match, and star dust present at night only.

*Worth keeping: "it looks dark, so dark mode works" is not a check. Pure black
and `#101423` are indistinguishable at a glance and differ at every pixel.*

### FN-25 · The settings glyph and the mockup's footer word disagree — **closed 2026-08-07 (footer word wins)**

DESIGN §353 ratifies "a faint key glyph on Home" as the door to the Keys sheet.
The home mockup (`prototype/home-search-mockup.html`) has no glyph: its footer
row reads `2 set aside · settings`, a plain underlined word.

The mockup predates §353, so this is a real conflict rather than drift. Built to
the mockup on 2026-08-07 — footer word, glyph removed — because the brief was
"exactly the way it was mocked up". If §353 wins instead, the doc and the build
now disagree in the other direction.

**To close:** pick one, make the other match.

**Decided by Abdoul 2026-08-07: the footer word.** DESIGN §353 now describes
the Keys sheet as reached from Home's footer row as `settings`, and records that
this supersedes the earlier "faint key glyph" wording, which the mockup predates.
Build and document agree.

### Home structure, brought to the mockup — closed 2026-08-07

The mic was parked at the bottom under a `Spacer()` with Today above it; the
mockup puts the mic in the middle as the room's single large object, with Today
below. Also added: the kicker, the search glyph and its teaching hint, the mic's
note-stock ring and label pair, Today's section label and portrait-initial
cards, and the centred footer row. `Today` with real items is **not** verified —
the simulator had no data.

### FN-26 · Contact points could be written but never entered — closed 2026-08-07

`UserEditService.addContactPoint` shipped in M3 and was wired to **zero** UI. The
only way a handle could exist was the extractor lifting one out of a voice memo —
which is the worst possible input for it. "@ j dash smith underscore 92" survives
no transcriber, and unlike a remembered fact, a near-miss handle is worthless
rather than merely vague. DESIGN §338 records tap-to-act as deferred; *entry* was
not recorded as deferred anywhere. It was simply missing.

Added on the Desk, `source: .manual` so hand-typed handles skip the §7.8
unverified-until-used mark that voice-derived ones carry. The kind list is
`ContactPointKind` verbatim, so the sheet cannot invent a category the ledger has
no column for.

One trap worth recording: the Reach collapse row renders only when a handle
already exists (D-8 — empty sections are absent), so an add button living only
inside that page would have been unreachable for exactly the person who needed
it. The Desk carries its own entry point for that reason.

Verified on device: `Bob | instagram | @bob_makes_things | manual` in
`contact_point`, and the Reach row appearing afterward.

### FN-27 · No way to browse everyone saved — closed 2026-08-07

Search answers "where is this person"; nothing answered "who do I have". Every
Desk was unreachable unless you already knew the name to type, which is the
wrong way round for a memory system — the names you have forgotten are exactly
the ones you cannot search for.

Added as the empty state of Search rather than a fourth door, so Home stays the
ratified three (§12). A typed query that finds nothing still renders nothing at
all (D-8); only a *blank* field browses.

Sorted A–Z deliberately. P6 forbids people lists "sorted by anything" that
implies ranking — recency, frequency, closeness are all scores wearing an order.
Alphabetical is an index: it carries no judgement and is the one order that says
nothing about anybody. Merged rows are excluded (pointers, not people) and so is
the self row (§7.12).

### FN-28 · The room field stopped filling the screen — closed 2026-08-07

Two bugs, one root, and the second was a regression from fixing the first.

FN-24 moved the room from a ZStack **sibling** into a `.background(...)`. A
background is sized to its content and clips `ignoresSafeArea`, so any screen
whose content is narrower than the display got bars down both sides — visible
first on the portrait screen. A `Color` sibling expands and carries the stack
with it, which is why the original shape worked; restored, with `RoomBackdrop`
kept separately available for the one place that cannot use a sibling (inside a
`NavigationStack`, which paints over anything behind it).

Second: `ReachMiniPage` and `TimelineMiniPage` are pushed straight into the
NavigationStack and never carried the room at all, so both rendered on system
black. `DeskView` and `SearchView` are wrappers that do carry it, which is why
the screens either side of them looked right and these two did not.

Verified by sampling all four edges plus the centre of the portrait screen, the
Reach page, and Home: `#101423` everywhere.

*Pattern worth naming, now seen three times: this codebase's backgrounds fail
by being **almost** right — the screen looks dark, so it passes a glance. Sample
the pixels.*

### FN-29 · No way to remove a person — **closed 2026-08-07 (retire only; erase declined)**

The roster made it visible: a mis-extracted row (`"his brother"`, from before the
FN-19 guard) sat in the list with no way to remove it. `mergePerson` needs a
winner to merge into; nothing else touched a person row.

**Built:** retirement. `person_retirement` (migration 003) withdraws someone from
the roster, search, the whisper primer and the extraction context while the
ledger keeps every fact and event they anchor. Reversible.

**Declined, deliberately: the hard erase.** It was designed and half-built before
the cost became clear — **twelve `BEFORE DELETE` triggers** enforce INV-1 in the
database itself (`assertion_no_delete`, `event_no_delete`, `person_no_delete`,
and nine more), so erasing would have required a named exception in every one of
them. That is INV-1 weakened permanently, and Abdoul's read was the right one:
the case that motivated it is a *mistake*, and for a mistake hiding is enough.
Storage was the other argument, and it does not survive either — audio is the
only large payload, and it is already deleted on the §7.5 full-model gate.

**If it ever comes back** it will be a privacy demand rather than a typo. Three
mechanisms were costed and are recorded so the work is not redone: gate the
triggers behind a sanctioned flag; delete only the audio and leave the ledger;
or rebuild the database by export/restore minus that person, which leaves the
triggers untouched because a fresh database is built by insertion. The second is
cheapest, the third is safest for INV-1, the first is the only one that is a
true erase.

*Worth keeping: the ledger refused to be deleted from, at the storage engine,
without anyone having to remember the rule. That is the constitution working —
the design cost showed up as twelve failing triggers rather than as a regret.*

### FN-30 · Adding an associated value silently withdrew an Equatable conformance — closed 2026-08-07

*(Numbered FN-25 in commit `fa98c87`'s message, colliding with the
settings-glyph note already published under that number; renumbered here.
Dropped entirely by a botched stash-pop conflict resolution on 2026-08-07
and restored — see FN-34.)*

`WaitingMemo.Stage` gained `needsProposalReview(syncRunID: String)`. Swift
synthesises `==` for an enum **only while it has no associated values**, so that
one addition quietly removed the conformance, and
`XCTAssertEqual(memo.stage, .needsTranscription)` in `CaptureFailureTests`
stopped compiling. The app target went red and stayed red across five commits.

Two things worth keeping:

1. **The failure was invisible from the cloud session.** `check.sh` here skips
   the app target entirely (no Xcode), and it now says so out loud — but saying
   so is not the same as catching it. Every app-layer change made from this
   environment is unverified until a Mac or CI compiles it, and five commits of
   red proved the gap is real rather than theoretical.
2. **The break was at a distance.** The enum and the test were changed by
   different people in different commits, and neither change was wrong on its
   own. `Stage` now declares `Equatable` explicitly, which is the durable fix:
   the conformance no longer depends on the enum happening to stay
   value-free.

*Related, and already fixed by Abdoul before I saw it:* the same commit pair
broke `testResidenceSupersedesResidence` for a similar
change-at-a-distance reason. Putting the qualifier (`residence`) into
`object_value` made two different residences share an object value, so the
"same object, not a contradiction" check swallowed them. `objectValueNamesTheObject`
now distinguishes a value that *names* the object from one that *classifies* it.

### FN-31 · An inferred date rendered as though it had been stated — closed 2026-08-07 (display); extraction half open

"I met Gladys at YC Startup School 2026 **a few weeks ago or like two weeks ago
I want to say**" produced a card reading `a remembered episode (2026-07-15)`. A
bare ISO day, from a sentence that gave a range and then hedged the range.

**The display half, fixed.** `date_precision` (`exact | month | year | fuzzy`)
has been in the ledger since M0 and was rendered by **nothing** — grep found
zero references across every app source. So a day the extractor inferred looked
exactly like a day someone said out loud. That is P4 inverted: the model stores
its uncertainty carefully and the screen throws it away. Cards now render at the
stated precision and say which it is — a `month` record shows "July 2026 — no
exact day was said" even when `occurred_at` carries a day, and a fuzzy one says
it was worked out rather than stated. The era phrase ("sophomore spring") leads
when the source gave one, because those are his words.

**Editable now too.** `CREATE_EVENT` had no Edit button (gated to `assert` and
`proposeState`), so a wrong date could only be rejected wholesale. The edit
sheet takes a year, a month, or a day, and sets `date_precision` from what was
actually typed — Orbit will not re-sharpen a year into a day afterwards.

**Still open: what the extractor should emit.** The eliah fixtures show it doing
this right — `occurred_at: 2023-08`, `precision: month`, era phrase kept — so
day-level output from "a couple of weeks ago" is a regression against its own
behaviour, not a missing rule (prompt rule 11 already forbids inventing a
calendar date). Whether "two weeks ago" counts as an anchor the capture date can
resolve is the real question: the arithmetic is defensible, the *precision* it
claims afterwards is not. Needs a fixture and a golden run.

*Third time this shape: the ledger records a distinction and the display drops
it (object_value vs entity, FN-14's name in prose, now precision). Worth a
standing check that every rendered field either shows its qualifier or says why
it doesn't.*

### FN-32 · Three real bugs from PR #1 review, and one that wasn't — closed 2026-08-07

Cursor Bugbot raised four findings on `1aafefe`. Three were real and are fixed;
the fourth was wrong, and checking it was worth the time.

**Real — the archive silently forgot two tables.** `Export.tables` never gained
`person_alias` (migration 002) or `person_retirement` (migration 003), so a
PRIV-5 restore would have come back with every retirement undone and every
person alias gone — the aliases that make person matching work at all. Nothing
failed; the loss would surface only on a restore, which nobody performs until
they need it. Fixed, and the durable half is a test that enumerates the live
schema and fails on any table that is neither exported nor deliberately excluded
(`rm_*` are rebuilt, INV-4). Verified it fails without the fix, naming both.

**Real — search answered the qualifier instead of the place.** `factAnswer` read
`object_value` alone, and `object_value` is the literal *beside* the object
(DATA-MODEL §2: "a role title, a date, a name"). So "where does Eliah work?"
answered **"intern"** where the employment linked Google — and after prompt v3
put `origin`/`residence` there, "where does James live?" answered
**"residence"**. Worth noting this was live before v3: the eliah fixture has
carried `object_value: "intern", entity: e_google` all along. The search goldens
passed because the fixtures they use happen to put the company in
`object_value` — the bug hid on exactly the fixtures that follow the
*documented* shape.

**Real — the provenance line ignored merge pointers.** Decision 6 is a pointer
merge: the loser's rows are never rewritten, so every read must follow the
pointer. `OrbitRecall` does this in eight queries; `Searcher.provenanceAnchor`
did it in none, so after a merge the Desk and the search result disagreed about
when you last saw the same person. Bugbot flagged last-seen; the first-met
lookup had it too, and both are fixed.

**Not real — name-fix ranges do not drift on extra spaces.** The claim was that
`offset += rawToken.count + 1` assumes single spaces. It does not:
`split(separator: " ", omittingEmptySubsequences: false)` yields an empty token
per extra space, each consuming exactly one offset, so the arithmetic is exact
for any run of spaces. Checked in Swift rather than by reading — one, two and
three spaces all land on the intended token.

*The nearby thing that IS true, and was not raised: a name after a tab or
newline is never suggested at all, because `split(separator: " ")` leaves it
glued to the previous word and the `first?.isUppercase` guard then rejects the
pair. A missed suggestion, not a wrong edit — recorded rather than fixed, since
transcripts from both engines are space-separated prose.*

### FN-33 · Both fixes for FN-32 were half-right — closed 2026-08-07

The second Bugbot pass on `1ffdae4` found two faults, and both were introduced by
the previous round's fixes rather than by the original code. Worth recording as a
pair, because they fail the same way: a fix aimed at one case quietly asserted
itself over a case nobody restated.

**Preferring the entity was right for "where", wrong for "what".** One predicate
serves two questions — "where does Eliah work?" wants Google, "what is Eliah's
job?" wants intern. FN-32 made the entity win unconditionally, which fixed the
first and broke the second. The interrogative decides now, with one override: a
controlled qualifier (`origin`, `residence`, `undergrad`, `grad`, `alumni`,
`attended`) is never an answer to anything, so a "what city…" question still
gets the place rather than the word "residence".

**Resolving the merge pointer made first-met nondeterministic.** `WHERE
COALESCE(p.merged_into, p.id) = ?` matches the winner *and* every merged loser,
and it was read with `scalar` — no aggregate, no ORDER BY — so whichever row
SQLite handed back first won, and the provenance line could differ between reads
of the same database. Before the fix it was deterministic and merge-blind; after,
correct-ish and unstable. Now `MIN(occurred_at)`: deterministic, and the honest
answer, since you met the person rather than the row.

That one also had a third symptom nobody reported: Recall read the winner's
`first_met_event_id` directly, so Desk and Search could disagree about the same
person for a *different* reason than FN-32's. Both now call one
`StoreReader.firstMetDate(person:)` — the shared implementation is the actual
fix, since these two had already diverged once.

*Pattern: three rounds of review on the same forty lines, each fix creating the
next finding. Every one of them was a case-analysis miss — entity vs literal,
winner vs identity — not a coding error. Where a value can play two roles, the
question has to select the role, and a test has to pin each role separately.*

### FN-34 · A conflict resolution silently deleted a field note — closed 2026-08-07

Resolving the stash-pop conflict in this file on 2026-08-07 ended with
`git checkout --theirs .` as a tidy-up step. During a stash pop `--theirs` means
the *stashed* side, so it discarded the upstream half of a conflict I had just
merged by hand — taking FN-30 (the `Equatable` note from `fa98c87`) with it. The
commit went out with a field note that had existed an hour earlier simply gone,
and nobody noticed until the notes were enumerated for closure.

Restored from `fa98c87`.

Two things worth keeping:

1. **The earlier restructure of this same file was verified and the later edit
   was not.** When the file was rebuilt into one-entry-per-finding, a check
   asserted that zero content lines were lost. The conflict resolution an hour
   later had no such check, and that is exactly where the loss happened. The
   guard was written for the risky-looking operation, not the risky one.
2. **`--theirs`/`--ours` invert during a stash pop**, and reaching for either
   after hand-merging a file discards the hand-merge. The habit that would have
   caught it: after resolving, diff against both parents before staging.

### FN-35 · A validation silently substituted a different prompt — closed 2026-08-07

`RemoteExtractor.promptVersion` ran a hardcoded allow-list:

```swift
let requested = env["ORBIT_PROMPT_VERSION"] ?? "v4"
return ["v1", "v2", "v3"].contains(requested) ? requested : "v3"
```

Promoting v4 changed the default, the build succeeded, a live measurement ran to
completion, and every fixture came back stamped `prompt_version: v3`. The new
prompt was never sent to the model once. It was caught only because three
substantially different prompts produced *identical* failures, which is not a
thing prompts do.

**A validation that quietly swaps in a different input is worse than no
validation**, because its output is indistinguishable from the thing working.
The allow-list existed to stop a typo selecting a wrong prompt — and did so by
selecting a wrong prompt.

Now derived: the default is the highest `extraction-prompt-vN.md` actually
bundled, so adding a prompt is one file rather than a file plus two lists to
remember, and an unrecognised version fails loudly at `systemPrompt()` naming the
resource it wanted.

### FN-36 · The eval harness lied to the model in two ways — closed 2026-08-07

Both found while measuring, and both had been inflating every "the extractor is
bad" reading. Neither is a model failure; each made a correct answer
*impossible*.

1. **Every memo was extracted as a `portrait`.** `eventKind` was hardcoded.
   Episodes are portraits-only (rule 11), so labelling ordinary captures as
   portraits invited reconstructed episodes that the goldens then counted as
   inventions. Only Eliah is a portrait. Fixing it alone: round-trip 5→6,
   criticals 24→21.

2. **The round-trip seeded a ledger and then hid it.** Priya was seeded as
   already employed at Google, James at Stripe — then extraction ran
   primer-less, so both returned `match: "new"`. `SyncEngine` skips corrections
   and contradictions whose subject is an unresolved ref, so CORRECT and CLOSE
   could never be emitted no matter how good the extraction was. The harness was
   seeding a person and denying them in the same breath. It now sends the primer
   the app sends on device (§7.7). Round-trip 6→9.

*The pattern worth keeping: when a measurement says the model is failing, check
what the measurement told the model first. Two of the five original failures
were the harness contradicting itself.*

### FN-37 · One run is not a measurement — **closed 2026-08-10 (harness built and in use)** · evals

Two consecutive runs of the **identical** prompt, same corpus, same model,
nothing changed:

| | run 1 | run 2 |
| --- | --- | --- |
| round-trip | 7/10 | 9/10 |
| PIPE-4 criticals | 32 | 14 |
| PIPE-6 verbatim | FAIL | 100% |

A two-check swing and a 2× swing in criticals, from nothing. Every
prompt-vs-prompt comparison made on 2026-08-07 is a single sample, and the
differences between adjacent prompt versions sit inside that spread — they are
recorded as history, not as evidence that any rule helped.

EVALS already anticipates this: **PIPE-15 specifies k consistency runs and a 70%
flicker boundary**, marked ◊, and it has never been operationalized. Until it is,
no ◊ target can be honestly assessed from this harness, because one run does not
measure a stochastic system. The ratchet rule assumes numbers that mean
something.

**To close:** make `measure --live` take `--runs k`, report the distribution
(median, min, max, and which checks flicker) rather than a point, and re-baseline
every ◊ against that. Only then is a provider or prompt comparison meaningful.

*Nearly drew four false conclusions from single samples tonight before running
the same prompt twice.*

### FN-38 · Foundation path APIs that are a different type on each platform — closed 2026-08-08

`ExtractionPrompt.latestVersion` derived the newest bundled prompt by calling
the URL path-extension member. That call **compiles on macOS and does not
compile on Linux**, where Foundation exposes it as a `URL?` property:

```
error: cannot call value of non-function type 'URL?'
```

So the `app` workflow (macOS) went green while `core` (Linux) failed, on two
consecutive commits. The asymmetry is the lesson: **macOS-only verification is
not verification of this package**, because the trust core is built on Linux by
design (BUILD §1.2 — the invariant suite must run without an Apple toolchain).

The first fix reached for `lastPathComponent` and produced a *third* red run:

```
error: value of optional type 'String?' must be unwrapped to refer to member
'hasPrefix' of wrapped base type 'String'
```

`lastPathComponent` and `pathExtension` are `String` on Darwin and `String?` on
Linux, so the fix had swapped one Darwin-only spelling for another. A sweep then
found a fourth instance queued behind it — `orbit-evals` sorted memo URLs by
`lastPathComponent`, which `String?` cannot do either.

The shim that replaced all of those then produced a **fourth** red run, on the
same line as the first:

```
error: value of type 'NSURL' has no member 'fileNamePortable'
```

`Bundle.urls(forResourcesWithExtension:subdirectory:)` vends `[NSURL]` on Linux
and `[URL]` on Darwin. So the element type itself diverges, and *no* accessor
written against `URL` — portable shim included — can be read off it. The listing
call was the actual defect, not the accessor; three fixes in a row had been
treating the symptom.

**The correction that generalizes:** fixing the reported line is not fixing the
class, and neither is fixing the reported *accessor*. Two changes close it.
`URL.path` is `String` on both platforms, so one shim in OrbitCore —
`fileNamePortable` / `fileStemPortable` — replaces the accessor uses, and
`ExtractionPrompt.latestVersion` stops listing the bundle at all: it probes
`Bundle.url(forResource:withExtension:)`, which returns `URL?` on both, for each
candidate version. Asking for the name you want is the same question as listing
and filtering for it, minus the platform-divergent collection. It scans past a
gap rather than stopping at the first miss, so deleting an intermediate prompt
cannot silently pin the default to an older one.

`scripts/lint-writepath.sh` now bans all three divergent accessors *and* both
bundle-listing calls across `Sources/` and `Tests/` (everything Linux CI
compiles), rather than just whichever spelling was last reported; the guard
skips comment lines, since its own explanation names the APIs. Each guard was
verified by planting a violation: the lint fails and names the file and line,
and passes once it is removed.

*Worth keeping: this is the same shape as FN-25 (an enum gaining an associated
value silently withdrew Equatable). Both were changes that type-check in one
configuration and not another, and neither could be caught from the cloud
session, where no Swift compiler exists at all. Four red runs for one finding,
because each of the first three fixes addressed the line that was reported
instead of the class it belonged to. The cheap move — sweep for every sibling
of the reported failure before pushing — was available every time.*

### FN-39 · A list that recognises and a list that admits — closed 2026-08-08

Search's fact lookup has two lists. `predicateKeywords` decides whether a
question reaches a fact lookup at all; `entitySeekingCues` then decides which
half of the fact answers it. Adding vocabulary to the second without the first
produces a question the code *recognises* and never *admits*: "what is Eliah's
role?" was read as a role question and then fell through to the generic search,
which answers no fact. The test that caught it had been written in the same
round as the bug and had never run, because the build was red on FN-38 — three
commits of green-looking work sitting on a suite nobody had executed.

Fixing it opened a sequence, each round finding the next layer down:

1. **The gate didn't know the vocabulary.** Fixed by admitting the role words,
   and by sweeping the siblings rather than the reported line — "what
   university" and "which college" had the identical gap.
2. **The matcher read words as runs of letters.** `contains` finds "position"
   inside "disposition", "title" inside "entitled", "company" inside
   "accompany", and — the one that matters — "org" inside **Morgan**. Adding
   vocabulary made the collisions likelier, so the fix was the matcher, not a
   trimmed vocabulary: single words match whole tokens, phrases stay substring.
3. **The vocabulary is also names.** Keyword tokens were dropped before person
   matching, so the one contact whose name is a keyword could never be asked
   about — every token in "where does Job work?" is vocabulary.
4. **The rescue for (3) could name the wrong person.** `peopleMatching`
   tolerates edit distance 2, and **"role" is one character from Rose**. A
   fuzzy rescue turns a no-answer into a confident answer about someone who was
   never mentioned. It now runs only when there are no name-shaped tokens at
   all, and matches exact/prefix only.

**What generalizes.** Two lists that must agree, where only one of them is a
gate, is a shape that fails silently — the symptom is a feature quietly not
working, never an error. And every fix in the sequence converged on the same
principle: *guessing that a word is a name is how you answer confidently about
the wrong person*, which is the one failure this app exists to refuse. The
narrowing in (4) costs "where does Job work in SF?", and that is the right
trade — it was never answerable before, and no answer beats a wrong one.

Worth noting who found what. (1) came from CI; (2)–(4) came from review, each
one a defect in the fix posted minutes earlier, and none of them surfaced by
re-reading my own change.

### FN-40 · The verbatim promise is enforced nowhere in the product — **closed 2026-08-10 (snap-to-source shipped)**

`ExtractionPayload.swift:112` says it plainly: `verbatim` is an *"exact substring
of the transcript (PIPE-6)"*. Nothing checks that. Not the schema, not the
funnel, not `SyncEngine`. The only thing that has ever verified it is the eval
grader, which is not in the product. `SyncEngine` interpolates the model's string
straight into the proposal rationale — curly-quoted — and the review card renders
it, so whatever the model returns is shown to Abdoul as his own words.

**What the model actually returns, measured over 10 runs (979 quoted fields):**

| | count | |
| --- | --- | --- |
| byte-exact substring | 889 | 90.8% |
| identical after whitespace normalisation | 11 | |
| near-identical — a filler or connector differs | 69 | |
| altered wording | 9 | |
| no close match (candidate fabrication) | **1** | lowest similarity anywhere: **0.780** |

**Zero fabrications.** The first pass through this data claimed two, at
similarity 0.29 and 0.53. Both were artifacts of a strided window search that
never tested the right offset — re-checked exhaustively, one is an exact match
differing only by a newline (1.000) and the other is 0.961, where the model wrote
*"but yeah, so we we we went to japan"* against a source reading *"and yeah so we
we we went to japan"*. It kept the stutter and changed the connector.

So the honest reading, which is not the one PIPE-6 has been reporting:

**The extractor is faithful.** It reproduces disfluent speech — stutters
included — and misses byte-exactness on connectives and filler words. PIPE-6
scores a dropped "um" identically to an invented sentence, which is why
"PIPE-6: FAIL" has read as a catastrophe for two days while describing hygiene.

**The exposure is still real, and is the actual defect.** The observed
fabrication rate is zero, but that is a property of this model on this corpus,
not of the system. Nothing would stop a fabricated quote reaching the review
card, because nothing looks. The guard is warranted by the absence of a check,
not by the presence of a failure.

**Fix — snap-to-source at ingestion.** Do not trust the model's copy. Find the
best-matching window in the transcript and store *the transcript's own slice*.
Above threshold the record is exact by construction; below it, the claim is
rejected as unsupported. The threshold is derivable rather than guessed: every
observed near-miss sits at ≥ 0.78 and 89 of 90 at ≥ 0.85, so **0.85 accepts every
faithful quote in this corpus while still rejecting genuine invention.**
Ambiguity risk is low — across a full run, zero exact quotes occurred more than
once in their transcript, so snapping cannot silently relocate provenance;
11 quotes under 25 characters are the only cases worth a length guard.

This makes PIPE-6 true by construction rather than by measurement, which is
worth more than a check only the eval harness runs.

**Implemented 2026-08-08** — `VerbatimSnapper`, applied inside the extractor
where the transcript is already in hand, so the guarantee holds for everything
downstream without threading a transcript through `SyncEngine`. Comparison is
punctuation-insensitive: the hardest real near-miss scored 0.812 with commas
attached and 0.938 without, so a transcription comma in "yeah," was the whole
difference between keeping a faithful quote and dropping it. Snap counts ride on
the telemetry, because a rising `rejected` is the only signal that the model has
started inventing.

**Deliberately not applied to `ReplayExtractor`.** Recorded fixtures stay raw, so
the eval keeps measuring what the *model* produced while the product ships what
the *snapper* guarantees. Conflating those would hide a degrading extractor
behind a working guard.

*Was deferred while a k=10 collection was in flight: its grading stage rebuilds the
Swift target, so editing the pipeline would have changed the code under a running
measurement.*

*The display question this raises is a real DESIGN decision — whether a memory
card shows "we we we went to japan" or a cleaned rendering. Snap-to-source is
what makes it safe to answer either way: the record stays exact, the rendering is
free to be kind.*

### FN-41 · The round-trip gate was a lottery; it now gates on measured stability — closed 2026-08-08

The k=10 collection scored 9 · 8 · 8 · 7 · 10 · 9 · 10 · 9 · 8 · 9 on an
all-or-nothing round-trip. Nothing changed between those runs. A gate demanding
10/10 fails eight times in ten, and **a gate that fails at random is one a team
learns to ignore** — the worst outcome available, because it disarms every real
regression the gate would otherwise catch.

Measured per check across the same 10 runs:

| pass rate | check |
| --- | --- |
| 100% | 7 checks — silence, INV-5, self-row routing, Stripe untouched, CORRECT-not-CLOSE, hardship archetype, Abdul DISAMBIGUATE |
| 80% | eliah: `PROPOSE_STATE` exactly once (INV-24) |
| 60% | contradiction: contradicted fact draws CLOSE |
| 30% | eliah: three `CREATE_EVENT` episodes |

**Seven of ten checks are perfectly stable.** The gate now blocks on those and
reports the other three with their measured rate. A check absent from
`docs/evals/check-stability.json` is treated as must-pass, so new checks are
blocking by default and the safe direction is the default.

Two things this is *not*:

**It is not a licence.** The rate is a ratchet, exactly like every EVALS §6
threshold: it may rise, never fall. A flickering check whose rate drops has
regressed even though no single run can prove it.

**It is not acceptance of the three.** INV-24 passing 80% of runs means a
*constitutional* guarantee is violated in one run out of five. That is worse
than a check that fails outright, because it will reach production
unpredictably. It is recorded so it stays visible while it is fixed — the
episode check at 30% is the extraction defect prompt rule 34 was written for and
plainly is not landing.

*The general shape, worth keeping: when a check flickers, the question is never
"should CI tolerate this" but "is the thing underneath it a defect or is the
check wrong". Here it was a defect, three times.*

### FN-42 · `residence` is asserted from anywhere a person was mentioned — mostly closed 2026-08-08

The clearest product defect in the k=10 data, and it reproduces across four
different memos. The model handles `origin` correctly — Elia from New York City
(10/10), the speaker from the Bronx (10/10), Nikos from Greece (8/10) are all
right. It is `residence` that goes wrong, and always the same way: **any place
associated with a person becomes a place they live.**

| claim | runs | what the transcript actually says |
| --- | --- | --- |
| Leon — residence [Atlanta] | 9/10 | he is *thinking about moving* back there |
| Ama — residence [Chicago] | 8/10 | she *flew in from* Chicago |
| Jen — residence [Berkeley] | 6/10 | her *studio* is in Berkeley |
| Philly — residence [Pacific Northwest] | 4/10 | he *interned* there one summer |
| Roger — residence [Pacific Northwest] | 4/10 | same summer, same internship |

Thirty-one wrong residence claims across ten runs, on a corpus of eleven memos.

This is not a taxonomy quibble. Where someone lives is a load-bearing fact in
Orbit — it drives who is nearby, what a reunion means, whether "when are you next
in town" is a sensible thing to surface. A goal to move recorded as an address is
a false memory of the ordinary kind: plausible, specific, and wrong.

Two prompt rules already aim near this and neither lands. **Rule 17** ("Origin is
not residence — say which, every time") governs origin, which is exactly the
case that already works. **Rule 20** ("A meeting place is not a fact about the
person") covers where an encounter happened. Neither covers *travelled from*,
*works in*, *interned in*, or *intends to move to* — and those are four of the
five failures.

The rule that would: **a `location` assertion requires the speaker to say where
the person IS — lives, moved, is based, is from, grew up. Somewhere they went,
worked, studied, or hope to go is not where they live.** A stated intention to
move is a `goal`, and the Atlanta case is simultaneously this defect and a missed
required fact (`leon/goal/atlanta`), which is what a category error looks like
from both sides of the ledger.

*Found by the precision pass rather than the recall pass — the goldens never
enumerated these as forbidden, so the enumerated-forbidden design could not have
caught them. This is the first defect that only existed because PIPE-4 got a
denominator.*

**Fixed by prompt v7 rule 35, measured over a second k=10 collection.** Residence
assertions fell from 51 to 17 (median 5 → 1 per run). Leon/Atlanta 9/10 → 0,
Ama/Chicago 8/10 → 0, Roger/Pacific-Northwest 4/10 → 0, Jen/Berkeley 6/10 → 1.
Tunde/Oakland survives at 6/10, correctly — *"it's his new place in Oakland"*.

Best of all, Atlanta was not merely suppressed: `leon/goal/atlanta` went from 10%
to **100%**, so the fact landed in the category it always belonged to. A fix that
recategorises beats a fix that deletes.

**Left open because the rule overcorrected.** "I lived on 167th and Grand
Concourse" is a residence by any reading and v7 now drops it nine times in ten
(60% → 10%). The rule taught the model to distrust place-mentions and it does not
distinguish the good ones. Rule 35 needs a clause admitting first-person
"I lived at X" before this closes.

### FN-43 · The hardship thread degraded from an unrelated prompt edit — **closed 2026-08-10 (recovered to 100%)**

v7 changed three rules, all about residence, hedge spans, and closeness. None
touches hardship. `condition_hardship` threads on the hardship memo nonetheless
went from **10/10 runs to 6/10** — and not misclassified into another archetype,
absent entirely. In four runs out of ten, Maya's father's Parkinson's produces no
thread at all.

INV-20 is not violated: a thread that does not exist raises no prompts, so the
"never cheerfully raise grief" guarantee holds. This is recall, not safety. But
it is the highest-stakes content in the corpus, EVALS calls its failure mode the
worst in the product, and it got worse from an edit that had nothing to do with it.

The suspected mechanism is dilution. The prompt has grown from 15 rules and 621
words at v1 to 37 rules and 2,872 words at v7 — nearly five times — and the
paired comparison shows the marginal rule now trading one item for another: 21
items improved, 20 regressed, sign test p = 1.000. Each rule works on the case it
was written for while competing for attention with thirty-six others.

That is a hypothesis and this comparison cannot test it, because it changed three
rules at once and cannot separate "rule 35 did this" from "the prompt got
longer". The experiment is cheap now the harness exists: v6 plus *only* rule 35,
and v7 with the oldest rules pruned, each paired against the collections already
on disk.

*The general worry, which outlives this instance: a prompt that is only ever
appended to will eventually regress something every time it is improved, and
single-run evaluation cannot see it happening. This one was visible only because
two ten-run collections were compared item by item.*

### FN-44 · A running measurement can be switched onto a different prompt by an unrelated edit — **closed 2026-08-10**

`ExtractionPrompt.latestVersion` resolves from the bundled resources **at
runtime**, on every call. That is the fix from FN-35 and it is the right design —
adding a prompt is one file, and an unknown version fails loudly. It also means:

- write `extraction-prompt-v9.md` into `Sources/` while a v8 collection is
  running — harmless, the bundle is untouched
- then build, for any reason at all — and the running job starts extracting with
  v9 partway through the corpus

And the trigger is not exotic. `overnight.sh`'s grading stage calls
`aggregate.py --roundtrip`, which shells into `swift run`, which **rebuilds on
any source change**. So editing any Swift file, or adding a prompt, during a job
is sufficient. The collection would finish, report cleanly, and contain two
prompts' output under one label — with the per-fixture `prompt_version` stamp as
the only evidence, which nothing currently checks.

Caught before it bit: v9 was written to `Sources/` mid-v8-run, and the build was
deliberately withheld until the job finished. Verified at the time that the
bundle held only v8 and all fixtures were stamped `v8`.

Same family as FN-35 and the CA-bundle failure in adjudicate.py: **a
configuration that changes underneath you, produces plausible output, and gives
you no way to tell from the result.** Three instances now, which makes it a
pattern in this codebase rather than three accidents.

**Fix:** resolve the prompt version once at collection start, write it into the
manifest, and have every extraction assert the resolved version still matches —
failing loudly on drift. The aggregator should refuse to grade a collection whose
fixtures disagree about `prompt_version`. Deferred while the v8/v9 collections
run, for exactly the reason this note describes.

### FN-45 · Three of the thirteen permanent misses, diagnosed — open · deliberately not fixed yet

The k=10 aggregate found 13 required items the extractor never produces in any
run. Three of those turned out to be the dropped hedges (fixed in v7, now 70–90%).
Three more are diagnosed here. **No rule is being written for them yet**, and
that restraint is the point — see the bottom of this note.

**1. `correction: priya/employment/deepmind` — a tense failure, not a recall one.**
The model emits the DeepMind employment in **10/10 runs**. It fails the golden
because the golden wants `closed: true` and the model leaves `valid_to` null, so
a job Priya *had* is recorded as a job she *has*. Rule 13 already says exactly
this ("'he interned at Google' is a CLOSED interval… never promote a past stint
to a current fact") and it is not landing. Worth noting the shape: this reads as
a missing fact in the recall column while actually being a wrong fact, which is
the more serious of the two.

**2. `futureforce: ambiguity attendance/lake` — hedged attendance recorded as
certain.** The transcript: *"So if I remember correctly, it was CJ, Grace, Abdul,
and Lake. Yeah, and I believe that was all."* The speaker is explicitly unsure
who was there. The golden wants an `attendance` ambiguity; the model produces a
confident participant list.

This one is more than a missed item. Attendance drives contact rhythm, "last
seen", and co-attendance edges (INV-11, INV-13) — so a guessed attendee quietly
becomes a fact about a relationship that never happened. P4 says uncertainty is
stored, not resolved, and a hedged guest list is precisely uncertainty.

**3. `eliah: ambiguity attendance/roger` — mentioned versus present.** *"So it was
him, Philly, and this other guy named Roger… Roger and Philly are also really
great, but this is about Elia."* Roger is named inside a portrait about someone
else. Whether he was *there* is genuinely unclear, and the golden wants the
question asked rather than an attendance assumed either way.

**Why nothing is being written for these now.** FN-43 raised the possibility that
this prompt has grown long enough that each new rule costs an old one — 21 items
up, 20 down at v7, and a hardship regression from an edit that never touched
hardship. The dilution experiment is running. Writing three more rules into a
prompt suspected of being too long, while measuring whether it is too long, would
confound the only test that can answer it and would be the accretion reflex the
hypothesis is about.

If dilution is real, these three get folded into existing rules — 1 into rule 13
where it already belongs, 2 and 3 into a single statement about uncertain
attendance. If it is not, they can be appended. **The experiment decides the
form, not just the content.**

### FN-46 · The judge does not agree with Abdoul — κ = 0.14 — open · invalidates every precision number

The audit EVALS §3.5 has always specified finally ran. Abdoul adjudicated 40
claims blind, with rationales. Against the j4 judge:

| | |
| --- | --- |
| claims both scored | 31 (9 marked unsure, excluded) |
| raw agreement | 58.1% |
| **Cohen's kappa** | **0.14** — poor (<0.4) |

Barely above chance. **Every precision figure in this repo is therefore
provisional**, including the 70.5% in the k=10 report, and the direction of the
error is now known rather than guessed.

**The judge is over-strict, 11 times to 2.** It refuses reasonable reading:

| claim | judge's objection | Abdoul |
| --- | --- | --- |
| `Elia — education — major [computer science]` | "says he studies CS, not that it's his major" | supported |
| `Dom — life_event — attendee [YC Startup School]` | "shows Dom present, not an attendee" | supported |
| `Abdoul — education — undergrad [Carnegie Mellon]` | "no enrollment dates stated" | supported |
| `Sarah Okafor — employment — nurse [UCSF]` | "starting a job is not current employment" | supported |
| `Ama — location — residence [Chicago]` | "flew in from Chicago, not resides" | supported |

The last one is the instructive one — **I had cited it as one of the judge's
strongest catches**, and FN-42 leans on the same reading. Abdoul, who was in the
room, reads it as supported. The owner's standard is *"does this fairly
represent what I said"*; my adversarial prompt ("default to unsupported when
uncertain") built something meaningfully stricter, and I then read its strictness
as rigour.

**Two in the dangerous direction — accepted by the judge, refused by Abdoul.**

1. `Maya — concern — (no object)` on the hardship memo. His note: *"The concern
   is her mother's disease."* The assertion has **no object at all** — no value,
   no entity, no person — so it records that Maya is concerned about nothing.
   Rule 27 forbids exactly this, the extractor did it anyway, the judge waved it
   through, and Stage A had no check for it. Three layers, and the one that
   caught it was the human. 3 of 908 assertions corpus-wide, two of them on the
   most sensitive content there is.
2. `Marcus — life_event — sold company [Shopify]`. His note: *"the company that
   Marcus sold was TO Shopify. It wasn't Shopify itself that was sold."* The
   object slot holds the buyer. A structurally valid, well-quoted, entirely
   wrong fact — and nothing mechanical can see it.

**His rationales, which are the real deliverable.** Four confirm findings reached
independently, which is the best evidence they are real:

- *"he's thinking about moving back to atlanta, which means he doesnt live there
  now"* — FN-42, in one line.
- *"this is previous employment though"* (Priya/DeepMind) — FN-45's tense
  finding, found without seeing it.
- *"Startup School was an event, not actual education"*, and again on Salesforce
  Futureforce: *"Its not education but it was an event yes."* **A new defect:
  attending an event is being recorded as `education`.** Twice, in two memos.
  Quantified afterwards across the three collections — 5/81 education assertions
  in v6 (6%), 13/98 in v7 (13%), 3/81 in v8 (4%), almost all of them Y Combinator
  Startup School. Small and noisy at these counts, so the *rate* is not worth
  chasing; the defect is worth fixing because a programme someone attended for a
  weekend should not sit in a profile beside their degree.
- *"This is referencing someone that made dom get upset… the only thing about
  dom that could be derived is that he didnt like conversation surrounding fish
  farms"* — an employment claim built from a third party's job.

**Done immediately:** Stage A now enforces rule 27 mechanically. Free,
deterministic, and it would have caught the Maya case without a judge.

**Still open — and the shape of j5 is now clear.** Sorting the 11 over-strict
refusals, they are not eleven problems but two:

1. **Ordinary role inference, refused seven times.** `major` for "studies CS",
   `attendee` for "was present at", `undergrad` for "we go to Carnegie Mellon",
   `founder` for "started a studio", `nurse` for a nursing job starting,
   `climbing partner` for people who met climbing. The judge demands the exact
   word appear in the transcript. Abdoul allows the ordinary reading. The rule:
   *a claim may name the role or status that what was said ordinarily implies;
   it may not add a fact the speaker did not give.*
2. **Owner confusion, three times**, all on the futureforce memo — the judge
   rejected claims about the speaker because the transcript says "Abdul" and the
   context says "Abdoul". That memo exists *because* of that collision, and the
   judge fell into the exact trap the extractor is graded on avoiding. The rule:
   *the `Owner:` line names the speaker; first-person statements are theirs.*

Two general rules, not eleven patches — which matters, because a judge tuned
claim-by-claim against 31 audited items has been fitted to them. κ must be
re-measured on a **fresh sample** afterwards; re-scoring the same 40 would only
report how well I fitted the answer key.

*The lesson is not that the judge is bad. It is that I validated it twice against
my own reading, called that validation, and was wrong in a direction my own
review could not see — I share the model's bias toward literalism. Only the owner
had the missing information, and it took forty claims to surface it.*

### FN-47 · P5's amendment, built — and two traps found building it — closed 2026-08-08

The batched confirmation P5 now permits, with INV-5b enforced rather than
asserted. `acceptAll` takes the set of card ids the view actually rendered and
settles only those, and `Card.bulkEligible` holds back three kinds outright:

- **DISAMBIGUATE cards** — answering a question in bulk is guessing, which is
  the one thing the ask exists to prevent.
- **`PROPOSE_STATE`** — the most consequential thing the extractor proposes,
  INV-24 gated, gets its own look.
- **`condition_hardship` threads** — INV-20. Someone's illness or grief is not
  something to accept in passing, and a review flow that sweeps it up with an
  employment change has misunderstood what it is holding.

A bulk accept that leaves cards behind now says so ("two below are worth your own
look") — silence would read as a bug rather than as intent.

**Trap 1: the app tests could not run locally, and had not been.** `xcodebuild
test` fails signing the SPM resource bundles — *"bundle format unrecognized"* —
which looks exactly like a broken build. A full DerivedData wipe did not fix it.
It is not a local defect: CI passes `CODE_SIGNING_ALLOWED=NO` and has always
worked. `scripts/check.sh` only *builds* the app target, so every app test has
been green in CI and unrunnable at the desk, and nobody would notice from the
gate. `check.sh` now has an opt-in `ORBIT_APP_TESTS=1` stage carrying that flag
and a comment explaining it, so the next person loses minutes rather than an hour.

**Trap 2: my own tests passed by not running.** The first version used `XCTSkip`
when the flow stalled. Four tests skipped, zero graded, and xcodebuild printed
**TEST SUCCEEDED**. `PortraitFlowTests` already warns about exactly this — *"A
stalled flow is a FAILURE, not a skip"* — and I wrote the anti-pattern anyway
while the correct convention sat in the file next to mine. The stall was real
(my fixture used invented field names — `person_ref` for `subject_ref`,
`summary` for `title`), so the skip was hiding a genuine defect in the test.

*The recurring shape, now five instances tonight: FN-35's allow-list, the CA
bundle in adjudicate.py, FN-44's prompt swap, the judge's silent unavailability,
and this. Every one produced output indistinguishable from success. Green is not
evidence; green plus a count you looked at is.*

---

## Session notes

Context that belongs to a whole session rather than to one finding.

### 2026-08-07 · Session 4 — design conformance audit

Abdoul's read: "the app isn't fully built — it diverged from how it was mocked."
Audit method: every ratified surface in DESIGN §6/§7/§12 checked against the
built screens, plus a mechanical sweep for design components that exist and are
never used (a component with no call sites is a design decision that was
specified and then not built).

**The structure is all there.** Desk tiles 0–8 render in the ratified fixed
order with the right spans, empty sections collapse rather than placeholder,
counts are real, the Deck's anatomy (progress bars → ember caps tag → serif 24
main → sans sub) matches, both rooms translate, and the three search shapes
exist. The divergences were in the **signature moves** — the small things §5
says carry the whole feeling.

### FN-48 · A fact stated about a group lands on only one of them — **closed 2026-08-10 (v11 promoted)** · prompt

A device capture said, of two people met together, *"she goes to Harvard she
both of them go to Harvard"*. Gladys carries the fact. Whether Catherine does is
unverified — and that is the point: **the half that goes missing leaves no
trace**, so nothing on any screen says a fact was dropped rather than never
stated.

No prompt through v9 has a rule for this — `both of them|they both|plural|group`
returns nothing in any of them. Rule 8 has covered the speaker's own case since
v1 ("we both…" produces two assertions, subject and self), and nothing ever
generalised it to a group the speaker isn't in. **v10 rule 38** is rule 8 with
the speaker taken out, plus three boundaries that keep distribution from
becoming invention: neighbouring facts don't spread ("both from Montreal" ≠ both
live in Boston, which is FN-42's `residence` failure arriving by a new road),
unnamed members aren't invented to receive the fact, and a shared occasion is
one episode with N participants rather than N assertions.

**v10 is v8 + rule 38, and it ships nothing yet.** `activeVersion` stays `v8`.
Built on v8 rather than v9 deliberately — v9's lineage is the one the dilution
experiment rejected (7 points of recall for half the words), so a new rule
belongs on the prompt that won, not on the newest file.

**Reported as an `object_value` problem; it is not, and the distinction matters.**
The Desk renders `claim`, which is `verbatim` by ratified design (DESIGN §12
rows 2 and 6 both specify a *serif* claim — the memory voice). So the Desk shows
the rambling sentence whatever the tag holds, and **no Desk screenshot can
diagnose tag discipline**. PIPE-17 measured 0 violations on live output on
08-07. FN-1's lesson, second occurrence: the layer that renders a field decides
which bug you think you have.

**To close:** a paired comparison of v10 against v8 — the shape FN-41 and the
dilution experiment established, not a point estimate — then move
`activeVersion`. The `plural-attribution` golden encodes the contract: both
named members required, matched by entity ref rather than containment, because
a verbatim that merely says "Northeastern" is not a fact linking to it.
`measure.py` reports it as awaiting a fixture on every run.

**Still unverified, and cheap to settle:** whether the Gladys capture's
`object_value` was in fact clean. A review card shows the mapped fact
(`ReviewViewModel.mappedFact`), so the next capture answers it on screen. There
is no ledger export in the app, which is why this needed asking at all.

### FN-49 · A golden authored before its fixture can never be measured — **closed 2026-08-10**

`measure.py` prints, for every golden without a fixture:

> **Goldens awaiting a fixture** (authored first, measured once a live
> extraction produces one — `orbit-evals measure --live`)

That sentence is false, and it has been since goldens-first was adopted.
`measure --live` builds its corpus by enumerating `docs/evals/fixtures/*.json`
and reading each fixture's `source` (`Sources/OrbitEvals/main.swift:277-316`) —
so **the memos it collects are exactly the memos that already have fixtures**.
The run cannot produce the fixture the message says it will produce. The queue
names itself and nothing drains it.

Cost, concretely: the v10 measurement (2026-08-10, 921k tokens, 23 min) graded
rule 38's collateral damage across eleven memos and never once ran the memo the
rule was written for. `tag-discipline` has been in the same state since
2026-08-07 — authored to grade FN-10, never measured.

This is the FN-35/FN-44 family again: **a configuration that looks like it is
working, produces plausible output, and gives you no way to tell from the
result.** The report is green, the golden is listed, and the listing is the
thing that makes it look handled.

**Fix (two parts, both small):**
1. Collection should discover memos from the **goldens**, not from the fixtures
   — a golden carries `source:` already, which is all the collector reads. A
   golden with no fixture is then a memo to collect, which is the intent.
2. Failing that, `measure.py`'s message must stop naming `measure --live` as the
   remedy and say what actually produces one, or the message is the defect.

Until then, a golden is only real if a fixture exists beside it, and
"goldens-first" is a practice the harness does not support.

**2026-08-10 · v10 measured, and not promoted.** k=10 paired against v8
(docs/evals/measurements/2026-08-10-v10-paired.md): recall 72.8% → 70.0% median,
criticals 15 → 19, 26 required items regressed against 15 improved, sign test
p = 0.117. `activeVersion` stays `v8`, so **the Harvard fix does not ship.**

The regressions sit nowhere near the rule — `dom:preference/vegan` 60% → 10%,
`dom:trait/social` 90% → 40%, `group-ramble:loop/cook` 60% → 10%. That reads as
dilution, not interaction: rule 38 is ~30 lines of sub-bullets on the longest
prompt this project has had. The next attempt should be one sentence and a
single example, not four sub-bullets — and it should be measured against v8
alone, so the length change is the only variable.

And the run never tested the rule: `plural-attribution` was not collected,
because live collection enumerates *fixtures*, not goldens (FN-49). So what is
known is the cost. The benefit is still unmeasured, and cannot be measured until
FN-49 is fixed.

### FN-50 · The prompt file's developer notes are sent to the model as instructions — **closed 2026-08-10 (opt-in marker)** · prompt

`ExtractionPrompt.system()` returns the whole `.md` file. Every prompt therefore
opens by telling gpt-5.1 about golden-run policy, which waivers Abdoul granted on
which date, and what RATIFICATION §4.16 says — 189 words of it in v8, before the
first actual instruction.

It is not merely wasted context. It **confounds every prompt comparison**: v10's
delta over v8 was 494 words, of which **142 were header prose** about the
dilution experiment and `activeVersion`. The measurement that rejected v10 was
grading a rule *plus* a paragraph of project bookkeeping, and could not separate
them. v11 was built by holding the header byte-identical to v8 so the rule was
the only variable — which is the workaround, not the fix.

**Fix:** split the file. Everything above the existing `---` is for us;
`system()` should send what is below it. One line in `system()`, and the header
stops being an input. Do it *between* measurements, never during one, and treat
the split itself as a prompt change needing its own comparison — removing 189
words from the top of the system prompt is exactly the kind of edit the dilution
experiment says can move the numbers.

### FN-51 · Required-item hit rate cannot resolve a small prompt change at k=10 — **open · floor now reported; raising k still owed** · evals

Across the 89 required items present in all six k=10 collections (v6–v11):
**24% swing ≥ 60 points, 39% swing ≥ 40 points**, median swing 20 points.

The clean demonstration is `homonym:person:sarah_o` — 40 / 30 / 70 / 10 / 80 /
10 for v6 / v7 / v8 / v9 / v10 / v11. **v10 contains v11's rule and 440 words
more**, so no monotone cause explains v10 = 80% beside v11 = 10% beside v8 =
70%. The item does not respond to the prompt.

Consequence, stated plainly: **v10 and v11 produced the identical 15/26/48 split
against the same baseline with entirely different items moving.** A 494-word
edit and a 56-word edit cannot have the same effect size. That split is the
noise signature of this comparison, and it has been read as a result twice.

This does not say the metric is worthless — v9's halved prompt is legibly worse
almost everywhere, and hedge items climb exactly when v7/v8 add hedge rules. It
resolves large changes. It cannot resolve small ones, and every prompt bump from
here is a small one.

**What would fix it,** in rough order of cost: grade against a *targeted* golden
collected for the change (as `plural-attribution` was here — 0/17 regressed,
60% → 100% on the item under test, which is a legible result at k=10); raise k
for the shared corpus, which trades money for resolution; or report per-item
confidence intervals so a 15-vs-26 split is visibly inside them rather than
looking like a finding.

Related: FN-41 (round-trip gate was a lottery), FN-46 (judge κ = 0.14). Three
independent measurements of this project's instruments have now come back
saying the instrument is the limiting factor.

**2026-08-10 (later) · v11 measured; the rule works.** v11 is v8 plus rule 38 in
one sentence and one example — 56 words, header held byte-identical so the rule
is the only variable (FN-50). Against a v8 baseline collected on the same two
memos: `plural-attribution:theo/education` **60% → 100%**,
`rania/education/mechanical` 40% → 70%, **0 of 17 items regressed**. The
distributed half — the Harvard case — now lands every run.

The shared-corpus comparison says nothing either way, and FN-51 explains why:
v10 and v11 produced the identical 15/26/48 split with different items moving,
which is the noise signature rather than a result. **The v10 entry's reasoning
is retracted** — those regressions were never established as dilution.

`activeVersion` still `v8`. Promoting v11 is a decision, not a derivation: the
benefit is measured on a purpose-built golden, the cost is below the
instrument's resolution, and 56 words is the smallest form the rule has taken.

**2026-08-10 · closed — v11 promoted (Abdoul).** `activeVersion = "v11"`; probe
confirms `RESOLVED=v11` with no env override and rule 38 present in the shipped
text. The Harvard case reaches the device on the next build.

Recorded honestly, because the basis is asymmetric: the benefit is measured
(60% → 100%, 0/17 regressed, on a golden collected for it) and the cost is
**unmeasurable at this size**, not measured-and-zero. FN-51 is the reason, and it
is the thing to fix before the next bump — not this rule.

One consequence to respect: v11's header still reads "v3 is the active prompt,
promoted without that run", inherited byte-identical from v8 so that rule 38 was
the only variable. That text is model input (FN-50). **Correcting it edits the
shipped prompt and voids this measurement** — it waits for FN-50's `---` split.

---

## Resolution pass — 2026-08-10

Every open note settled or given an owner. What made it possible was FN-49: with
the corpus reachable, `tag-discipline` and `plural-attribution` finally ran, and
three notes that had waited on "a golden run" had their evidence in one k=10
collection. Dispositions below; each closed note carries its evidence in place.

**FN-10 — closed.** Across k10-v11, **zero** `object_value`-is-a-clause
violations in 10 runs (the >12-word ceiling never fires), and the memo authored
to catch it scores **7/7 required items at 100%** — including
`priya/employment → entity(anthropic)`, the case where the org used to arrive as
prose. The 2026-08-07 note read "0 violations" from a run that never included
this memo; it is now true for the reason it claimed to be.

**FN-12 — closed, option 1 holds.** `priya/education → entity(cmu)` lands
**100% of 10 runs** with the status in `object_value`. The deeper ambiguity the
note raised — an open interval cannot distinguish "currently enrolled" from
"we never learned when it ended" — is real and unresolved, but option 1 was
what closing asked for and it holds. Option 2 (controlled vocabulary) remains
available if that ambiguity ever bites.

**FN-14 — open, and its premise is falsified.** It predicted it would "close
with FN-10". FN-10 is closed and FN-14 fires **20 times across 10 runs** — about
two per run — in `relation object_value: "lived with Philly and Roger"`,
`preference: "enjoyed hanging out with Nikos"`. Fixing the clause problem did
not remove the name problem, so it needs its own rule, and a v12 written for it
should be graded against a golden built for it (FN-51's lesson) rather than the
shared corpus.

Found while measuring it: **PIPE-17's name check was over-firing by ~20%.** It
compared `object_value` against *every* person in the payload rather than the
refs the assertion itself carries, so `life_event: "visiting Tunde next month"`
held by a different subject counted as a duplicate — where the name is the only
record of who is meant. Now scoped to the assertion's own subject/object refs:
25 firings become 20, and the 20 are real. A check that reports defects the
payload does not have is the fourth instrument problem this month (FN-46,
FN-49, FN-51).

**FN-37 — closed.** Everything it asked for exists and is in daily use:
`measure --live --runs k`, distributions rather than points (`recall, median
(min–max)`), and per-check flicker classification (`stable-fail` / `FLICKER`).
Six k=10 collections are on disk and the last three decisions were made from
them. The remaining half of its ask — re-baselining every ◊ against those
distributions — is real work, but it is a *ratification* task and belongs to
RATIFICATION plus FN-51, not to a note about single-run measurement.

**FN-40 — closed.** `VerbatimSnapper.snap(decoded, to: transcript)` runs on
every extraction (`Extractor.swift:414`), the snap outcome is recorded per
fixture (`ExtractionTelemetry.verbatim`: exact / corrected / dropped), and
PIPE-6 verbatim fidelity reads **100%**. The note's own fix — "do not trust the
model's copy, find the span in the source" — is what shipped.

**FN-43 — closed.** The watch item recovered and then some:
`hardship:thread:parkinson` reads **v7 60% → v8 80% → v11 100%**, its best ever.
The general worry it raised — that an append-only prompt eventually regresses
something every time it improves — is a real and live concern, but it now has a
better home in FN-51, which quantifies the noise band that hid it.

**FN-44 — closed.** `aggregate.py` now refuses to grade a collection whose
fixtures do not all carry one prompt version, and refuses one whose fixtures
contradict the manifest. Verified by planting a violation: a single `v8`-stamped
fixture among 25 `v11` ones is rejected by name and location. A clean collection
prints `prompt-version check: all 130 fixtures stamped v11 ✓`. This is the check
whose absence the note called "the only evidence, which nothing currently
checks" — and which I performed by hand twice before writing it down.

**FN-49 — closed.** Collection discovers transcripts, not fixtures: 11 memos
became 13, `tag-discipline` unstranded after three days, and three other notes
closed on evidence it unblocked. `--dry-run` lists the corpus for free, which is
the affordance whose absence let this survive — the only way to see what a
collection would run was to buy a 900k-token look at it.

**FN-50 — closed.** `system()` splits on an opt-in `<!-- PROMPT BEGINS -->`
marker: a file carrying it sends only what follows, a file without it is sent
whole. Opt-in **because measurements are attached to prompts** — stripping
unconditionally would change what v1–v11 send and quietly void every number
attached to them, including the one v11 was promoted on. `PromptContractTests`
guards all of it: measured prompts still go whole, the marker strips, an unknown
version throws rather than substituting (FN-35).

**FN-51 — open, but no longer invisible.** `compare.py` now prints a resolution
floor beside the split, with **per-item** 95% bands (Agresti–Coull, so intervals
stay finite at 0% and 100%) rather than one worst-case number — because variance
collapses at the ends, and 60% → 100% is resolvable at k=10 where 40% → 70% is
not. The v8-vs-v11 comparison now reads "**7 of 41 moved items clear their own
band** — the rest are inside the noise and must not be read as effects", which
is the sentence whose absence let the same 15/26/48 split be read as a result
twice. Still owed: raising k for the shared corpus, which trades money for
resolution. The cheap half — grade against a golden written for the change — is
now established practice (`plural-attribution`).

**FN-5, FN-45, FN-46 — open, and each is Abdoul's, not the harness's.**
FN-5 needs a device observation nobody else can make (does a 547MB download
complete on a normal connection, and what does it cost a first run). FN-45's
three permanent misses were diagnosed and deliberately left; that decision has
not changed. FN-46's judge disagrees with Abdoul at κ = 0.14, and no amount of
harness work fixes a judge whose rubric its author does not share — it needs an
adjudication session, and until then every precision number is provisional.
These are routed, not resolved, and saying so is the honest disposition.

### FN-52 · Homonym identity is bimodal across collections, and no prompt explains it — **open · watch, highest stakes**

Surfaced by FN-51's new per-item bands, which is the point of having them.

| item | v6 | v7 | v8 | v9 | v10 | v11 |
| --- | --- | --- | --- | --- | --- | --- |
| `homonym:person:sarah_o` | 40% | 30% | **70%** | 10% | **80%** | 10% |
| `…sarah_o/employment/ucsf` | 20% | 20% | **60%** | 10% | **50%** | 0% |

The homonym memo says "Not Sarah Chen" explicitly; creating Sarah Okafor as a
distinct person is the single identity test in the corpus, and EVALS calls
merging two people the worst failure the ledger cannot undo by adding evidence.

**The v8 → v11 drop clears its own 95% band**, so it is not ordinary noise. And
**no prompt hypothesis explains it**: v10 strictly contains v11's rule plus 440
more words and sits at 80%, while v9 and v11 sit at 10%. High, low, high, low,
against monotone edits. Whatever moves this item is not the rule.

That leaves something unmodelled — collection-level drift, an endpoint-side
change between collections, or a genuine bistability in how the model resolves
the two Sarahs. It is not answerable from the aggregates on disk.

**To close:** re-collect the homonym memo alone under v8 and v11 back to back —
`--memos homonym`, two labels, ~30k tokens the pair, which `--memos` makes
affordable. If v11 reproduces low against a fresh v8 high, the promotion is
implicated and should be reconsidered on identity grounds alone. If both come
back mid, the item is bistable and the corpus needs a second identity fixture so
one coin flip cannot carry the whole check.

**Live risk, stated plainly:** v11 is the promoted prompt as of today. If this
is real rather than drift, the shipping prompt is worse at the one thing the
product must never get wrong.

**2026-08-10 · FN-52 answered: it reproduces, and v11 is the cause.** Homonym
alone, ten runs each, back to back in one session (`fn52-v8`, `fn52-v11`):

| item | fresh v8 | fresh v11 |
| --- | --- | --- |
| `homonym:person:sarah_o` | **70%** | **20%** |
| `…sarah_o/employment/ucsf` | 50% | 20% |
| `…sarah_o/life_event/nursing boards` | 40% | 20% |

v8 reproduced its k10 value exactly (70%); v11 reproduced low. All three items
move together, and 70% → 20% clears its 95% band (±35 points). Drift is
excluded — the two arms ran minutes apart against the same endpoint.

So rule 38 costs the identity test. The mechanism is plausible in hindsight: a
rule that says *a fact stated about a group belongs to each named member* pushes
toward spreading facts across the people in view, and the homonym memo's whole
difficulty is that two people who share a name must be held **apart**. v10 not
showing it is unexplained and no longer load-bearing — what matters is that the
promoted prompt reproducibly loses the one test the product cannot afford.

**Recommendation: roll `activeVersion` back to `v8`.** EVALS calls merging two
people the worst failure the ledger cannot undo by adding evidence; distributing
group facts is a recall gain. Trading the first for the second is the wrong side
of that trade. A v12 should carry rule 38 with an explicit clause that
distribution never crosses people the transcript distinguishes, and be graded on
homonym *and* plural-attribution before promotion — both goldens now exist and
`--memos` makes the pair cost ~30k tokens.
