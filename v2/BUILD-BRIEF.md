# Orbit v2 — One-Shot Build Brief

You are building **Orbit v2** from scratch, in a clean space. Your sole input is the
constitution: `ORBIT.md`, ratified 2026-08-31, sitting next to this brief. Read it in
full before writing anything. It is the spec, the design authority, and — once the
build ships — the runtime instructions of the system itself.

**Do not consult, reference, or imitate any prior Orbit implementation.** No earlier
code, schema, design language, mockup, eval, or document exists as far as this build
is concerned. Where the constitution is silent, derive the answer from its principles
and chart your own course. Where the constitution is ambiguous or a requirement proves
costly, register the divergence in `RATIFICATION.md` for Abdoul and build the
uncontested parts — never silently code around it (constitution, status block).

## Mission

Deliver a working agent-native relationship memory: a private repository of plain-text
memory that Abdoul owns, operated entirely through conversation with Claude, covering
all four modes — **Capture → Recall → Discover → Connect** — with the ambient surfaces
(evening-before briefs, morning-brief lines, weekly gardening) wired up as scheduled
routines.

## Deliverables

Derive the design yourself from the constitution; the list below is the *what*, not
the *how*.

1. **The memory store.** A repository layout for people, Abdoul's own quiet profile,
   immutable event memos, deferred proposals, saved questions (lists), groups, and the
   ratification queue. Plain text, human-readable, git-versioned. Design the file
   schema fresh — the constitution's §3 and §6 state the structural requirements
   (observation time from commit history, validity time in text, tombstoned
   corrections, no numeric score fields anywhere).

2. **The agent's operating instructions.** A `CLAUDE.md` (or equivalent entrypoint)
   that binds the agent to the constitution on every action, and defines the
   conversational flows: capture with one-considered-reading review (§9), the
   who-question (§16), brief generation (§14), discovery (§15), and connection
   suggestions with the consent test (Pillar Four).

3. **Skills** for the recurring verbs — at minimum: capture, brief, who, and the
   weekly gardening session. Skills encode flow and tone; the constitution governs
   substance.

4. **Routines / scheduled automation.** The evening-before brief from calendar
   matches, the morning-brief connection/loop lines, and the weekly gardening
   session — all honoring §16's two-voices rules: Orbit speaks first only inside
   these rituals, always with context, never as pings.

5. **CI: the ratchet.** Automated checks on every commit enforcing the constitutional
   invariants: committed event memos are never modified; every stored quote is a
   byte-exact substring of a committed memo; no numeric relationship-score field
   exists; corrections are tombstones, not deletions.

6. **A fresh evaluation suite.** Synthetic conversational memos and goldens written
   for this medium (typed notes, dictated monologues, and multi-turn voice-style
   captures), measuring extraction against Principle 4 — including the
   flickering-miss vs. stable-miss distinction — and fidelity against Pillar Three.

7. **Onboarding.** The backfill-portrait flow (§16 inventory): seeding the memory
   with people Abdoul has known for years, splitting what he says the way memory
   splits — episodes to the timeline, ongoing truths to facts.

## Constraints

- **The constitution is supreme.** Every "never" in it is a hard constraint. The
  build conforms to the document, not the reverse.
- **Nothing enters the record without Abdoul's yes** — capture review (§9, P5),
  ingestion offers (§9), relationship state (§11), groups (§12).
- **Suggest only, everywhere.** The system drafts no outreach and contacts no one
  (Pillar Four).
- **Store is text-only and Abdoul's.** No audio in the record, no third-party
  services beyond the model provider, exportable by clone (§8's four absolutes).

## Definition of Done

- A new person can be met, captured, reviewed, and recalled end-to-end in
  conversation, and the memo survives verbatim in the store.
- A brief renders in the constitution's six-section shape with a glanceable layer.
- A discovery question is answered with cited evidence from the record.
- A connection suggestion fires only with concrete evidence on both sides and passes
  the consent test; never-raised threads provably never surface in one.
- CI is green, the invariant checks demonstrably fail when violated, and the eval
  suite runs with documented baseline results.
- `RATIFICATION.md` contains every open question the build raised, and nothing was
  silently decided that the constitution reserves for Abdoul.
