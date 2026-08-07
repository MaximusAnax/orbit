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

### FN-37 · One run is not a measurement — open · blocks every ◊ number

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
