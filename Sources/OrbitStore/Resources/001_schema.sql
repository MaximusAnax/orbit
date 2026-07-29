-- Orbit schema v1 — compiled from docs/DATA-MODEL.md §2.
-- Conventions: TEXT ids (UUID), ISO-8601 TEXT datetimes (lexicographic order == time order),
-- 0/1 INTEGER booleans. Immutability is enforced by triggers in 002_triggers.sql (INV-1);
-- this file only declares shape and static constraints.

PRAGMA foreign_keys = ON;

-- ───────────────────────────── People ─────────────────────────────

CREATE TABLE person (
    id                  TEXT PRIMARY KEY,
    display_name        TEXT NOT NULL,
    preferred_name      TEXT,
    name_pronunciation  TEXT,
    photo_ref           TEXT,
    status              TEXT NOT NULL CHECK (status IN ('provisional','active','known_of','merged')),
    is_self             INTEGER NOT NULL DEFAULT 0 CHECK (is_self IN (0,1)),
    merged_into         TEXT REFERENCES person(id),
    system_contact_ref  TEXT,
    first_met_event_id  TEXT REFERENCES event(id),
    created_at          TEXT NOT NULL
);

-- INV-22: exactly one self row, ever.
CREATE UNIQUE INDEX person_single_self ON person(is_self) WHERE is_self = 1;
CREATE INDEX person_status ON person(status);

CREATE TABLE contact_point (
    id              TEXT PRIMARY KEY,
    person_id       TEXT NOT NULL REFERENCES person(id),
    kind            TEXT NOT NULL CHECK (kind IN ('phone','email','instagram','linkedin','x','website','other')),
    value           TEXT NOT NULL,
    label           TEXT,
    is_primary      INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0,1)),
    valid_from      TEXT,
    valid_to        TEXT,
    source          TEXT NOT NULL CHECK (source IN ('linked_contact','manual','voice','import')),  -- §7.8
    source_event_id TEXT REFERENCES event(id)          -- provenance; NULL only for source='linked_contact'/'manual' quick-add
);
CREATE INDEX contact_point_person ON contact_point(person_id);

-- ───────────────────────────── Events ─────────────────────────────

CREATE TABLE event (
    id                    TEXT PRIMARY KEY,
    occurred_at           TEXT NOT NULL,
    date_precision        TEXT NOT NULL DEFAULT 'exact' CHECK (date_precision IN ('exact','month','year','fuzzy')),
    kind                  TEXT NOT NULL CHECK (kind IN
        ('dinner','coffee','call','text','conference','party','meeting','introduction','encounter','note','portrait')),
    location_entity_id    TEXT REFERENCES entity(id),
    title                 TEXT,
    raw_audio_ref         TEXT,               -- cleared on §7.5 deletion gate; the ONLY post-confirmation mutable column
    transcript            TEXT,               -- immutable once confirmed (Decision 3)
    narrative             TEXT,
    emotional_context     TEXT,
    lifecycle             TEXT NOT NULL DEFAULT 'captured' CHECK (lifecycle IN ('captured','confirmed','discarded')),
    derived_from_event_id TEXT REFERENCES event(id),   -- §7.11 reconstructed events; never enters rate math (INV-12)
    captured_at           TEXT NOT NULL,
    confirmed_at          TEXT
);
CREATE INDEX event_occurred ON event(occurred_at);
CREATE INDEX event_lifecycle ON event(lifecycle);

CREATE TABLE event_participant (
    event_id   TEXT NOT NULL REFERENCES event(id),
    person_id  TEXT NOT NULL REFERENCES person(id),
    attendance TEXT NOT NULL CHECK (attendance IN ('confirmed','probable','about')),  -- 'about' = subject, not present (§7.11)
    role       TEXT,                                    -- e.g. 'introducer'
    PRIMARY KEY (event_id, person_id)
);
CREATE INDEX event_participant_person ON event_participant(person_id);

-- Ledger corrections for confirmed events (applied in order at read time).
CREATE TABLE amendment (
    id         TEXT PRIMARY KEY,
    event_id   TEXT NOT NULL REFERENCES event(id),
    field      TEXT NOT NULL,
    new_value  TEXT,
    reason     TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX amendment_event ON amendment(event_id);

-- ─────────────────────────── Assertions ───────────────────────────

CREATE TABLE assertion (
    id                      TEXT PRIMARY KEY,
    subject_id              TEXT REFERENCES person(id),          -- NULL while unresolved (Decision 5)
    predicate               TEXT NOT NULL CHECK (predicate IN
        ('employment','education','location','interest','skill','goal','concern','relation','life_event','preference','trait')),
    object_entity_id        TEXT REFERENCES entity(id),
    object_value            TEXT,
    verbatim                TEXT NOT NULL,                       -- the original phrasing, always (P7)
    valid_from              TEXT,
    valid_to                TEXT,                                 -- NULL = still true
    date_precision          TEXT NOT NULL DEFAULT 'fuzzy' CHECK (date_precision IN ('exact','month','year','fuzzy')),
    observed_at             TEXT NOT NULL,
    source_event_id         TEXT NOT NULL REFERENCES event(id),  -- provenance is total (INV-18)
    source_kind             TEXT NOT NULL CHECK (source_kind IN ('firsthand','secondhand')),
    attributed_to_person_id TEXT REFERENCES person(id),
    needs_reconfirmation    INTEGER NOT NULL DEFAULT 0 CHECK (needs_reconfirmation IN (0,1)),
    status                  TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','retracted')),
    retraction_reason       TEXT,
    superseded_by           TEXT REFERENCES assertion(id),
    confidence              REAL,
    last_surfaced_at        TEXT,
    pinned                  INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0,1)),
    muted                   INTEGER NOT NULL DEFAULT 0 CHECK (muted IN (0,1)),
    thread_id               TEXT REFERENCES thread(id),
    -- INV-10: hearsay carries its source; firsthand never does.
    CHECK ((source_kind = 'secondhand' AND attributed_to_person_id IS NOT NULL)
        OR (source_kind = 'firsthand'  AND attributed_to_person_id IS NULL)),
    -- CORRECT leaves a reason (Decision 2).
    CHECK (status = 'active' OR retraction_reason IS NOT NULL)
);
CREATE INDEX assertion_subject ON assertion(subject_id);
CREATE INDEX assertion_predicate ON assertion(predicate);
CREATE INDEX assertion_source_event ON assertion(source_event_id);
CREATE INDEX assertion_thread ON assertion(thread_id);

-- Unresolved-subject candidates (Decision 5). Rows exist only while assertion.subject_id IS NULL.
CREATE TABLE assertion_subject_candidate (
    assertion_id TEXT NOT NULL REFERENCES assertion(id),
    person_id    TEXT NOT NULL REFERENCES person(id),
    PRIMARY KEY (assertion_id, person_id)
);

CREATE TABLE assertion_amendment (
    id           TEXT PRIMARY KEY,
    assertion_id TEXT NOT NULL REFERENCES assertion(id),
    field        TEXT NOT NULL,
    new_value    TEXT,
    reason       TEXT,
    created_at   TEXT NOT NULL
);
CREATE INDEX assertion_amendment_assertion ON assertion_amendment(assertion_id);

-- ─────────────────────── Extraction & review ──────────────────────

CREATE TABLE extraction (
    id                 TEXT PRIMARY KEY,
    event_id           TEXT NOT NULL REFERENCES event(id),
    extraction_version INTEGER NOT NULL,
    model_id           TEXT NOT NULL,
    prompt_version     TEXT NOT NULL,
    created_at         TEXT NOT NULL,
    payload            TEXT NOT NULL,      -- structured JSON (the cache, never the truth — Decision 3)
    ambiguities        TEXT                -- JSON array of open questions
);
CREATE INDEX extraction_event ON extraction(event_id);

CREATE TABLE sync_run (
    id            TEXT PRIMARY KEY,
    event_id      TEXT NOT NULL REFERENCES event(id),
    extraction_id TEXT NOT NULL REFERENCES extraction(id),
    created_at    TEXT NOT NULL,
    completed_at  TEXT
);
CREATE INDEX sync_run_event ON sync_run(event_id);

CREATE TABLE proposal (
    id                   TEXT PRIMARY KEY,
    sync_run_id          TEXT NOT NULL REFERENCES sync_run(id),
    op                   TEXT NOT NULL CHECK (op IN
        ('ASSERT','CLOSE','CORRECT','MERGE','LINK','CREATE_PERSON','CREATE_EVENT','OPEN_LOOP','PROPOSE_STATE','DISAMBIGUATE','OPEN_THREAD','CLOSE_THREAD','CONTACT_POINT')),
    target_person_id     TEXT REFERENCES person(id),
    target_assertion_id  TEXT REFERENCES assertion(id),
    payload              TEXT NOT NULL,    -- JSON: the proposed operation content
    rationale            TEXT NOT NULL,    -- shown to the user, always (P9)
    prior_rejection_note TEXT,             -- INV-7: new-evidence re-proposals disclose history
    state                TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','accepted','rejected','deferred','superseded')),
    edited_payload       TEXT,             -- set when accepted-with-edits
    resolved_at          TEXT
);
CREATE INDEX proposal_sync_run ON proposal(sync_run_id);
CREATE INDEX proposal_state ON proposal(state);
CREATE INDEX proposal_person ON proposal(target_person_id);

-- J-12: every review decision, harvested for the eval corpus (EVALS §3.2). Append-only.
CREATE TABLE review_outcome (
    id              TEXT PRIMARY KEY,
    proposal_id     TEXT NOT NULL REFERENCES proposal(id),
    action          TEXT NOT NULL CHECK (action IN ('accepted','rejected','edited','deferred')),
    rejection_reason TEXT CHECK (rejection_reason IS NULL OR rejection_reason IN ('not_true','wrong_person','not_worth_keeping')),
    edited_payload  TEXT,
    created_at      TEXT NOT NULL
);
CREATE INDEX review_outcome_proposal ON review_outcome(proposal_id);

-- ─────────────────── Relationship state & upkeep ───────────────────

-- Append-only versions; latest is current. Never AI-written without confirmation.
CREATE TABLE relationship_state (
    id               TEXT PRIMARY KEY,
    person_id        TEXT NOT NULL REFERENCES person(id),
    narrative        TEXT,                                -- Abdoul's own words — authoritative
    orbit            TEXT CHECK (orbit IS NULL OR orbit IN ('inner','close','active','extended','outer')),
    maintenance_mode TEXT NOT NULL DEFAULT 'unset' CHECK (maintenance_mode IN ('resilient','deliberate','dormant_by_choice','unset')),
    desired_cadence  TEXT,                                -- NULL is meaningful: no cadence set ≠ neglected
    intent           TEXT,
    authored_by      TEXT NOT NULL CHECK (authored_by IN ('human','ai_suggested')),
    source_event_id  TEXT REFERENCES event(id),           -- set when arrived via PROPOSE_STATE (§7.13)
    created_at       TEXT NOT NULL
);
CREATE INDEX relationship_state_person ON relationship_state(person_id);

CREATE TABLE open_loop (
    id                  TEXT PRIMARY KEY,
    person_id           TEXT NOT NULL REFERENCES person(id),
    source_event_id     TEXT NOT NULL REFERENCES event(id),
    direction           TEXT NOT NULL CHECK (direction IN ('abdoul_owes','person_owes')),
    description         TEXT NOT NULL,
    due_at              TEXT,
    due_precision       TEXT CHECK (due_precision IS NULL OR due_precision IN ('exact','month','year','fuzzy')),
    state               TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open','resolved','dropped','expired')),
    resolved_by_event_id TEXT REFERENCES event(id)
);
CREATE INDEX open_loop_person ON open_loop(person_id);

CREATE TABLE thread (
    id                          TEXT PRIMARY KEY,
    person_id                   TEXT NOT NULL REFERENCES person(id),
    title                       TEXT NOT NULL,
    state                       TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open','resolved')),      -- never set automatically (§9)
    prompt_state                TEXT NOT NULL DEFAULT 'active' CHECK (prompt_state IN ('active','context_only')),
    archetype                   TEXT NOT NULL CHECK (archetype IN
        ('event_pending','decision','project','condition_process','condition_hardship','aspiration')),
    opened_event_id             TEXT NOT NULL REFERENCES event(id),
    expected_resolution_at      TEXT,
    expected_resolution_precision TEXT CHECK (expected_resolution_precision IS NULL OR expected_resolution_precision IN ('exact','month','year','fuzzy')),
    conversations_since_mention INTEGER NOT NULL DEFAULT 0,
    last_mentioned_at           TEXT,
    resolution_note             TEXT,
    resolved_by_event_id        TEXT REFERENCES event(id)
);
CREATE INDEX thread_person ON thread(person_id);
CREATE INDEX thread_state ON thread(state, prompt_state);

-- ───────────────────────── Groups & lists ─────────────────────────

CREATE TABLE person_group (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    notes      TEXT,
    created_at TEXT NOT NULL
    -- Created by Abdoul, and only by Abdoul: no proposal op targets this table (§13).
);

CREATE TABLE group_membership (
    group_id        TEXT NOT NULL REFERENCES person_group(id),
    person_id       TEXT NOT NULL REFERENCES person(id),
    valid_from      TEXT,
    valid_to        TEXT,
    source_event_id TEXT REFERENCES event(id),
    PRIMARY KEY (group_id, person_id, valid_from)
);

-- Lists are saved queries, never membership rows (DATA-MODEL, Groups section).
CREATE TABLE saved_list (
    id               TEXT PRIMARY KEY,
    name             TEXT NOT NULL,
    query_definition TEXT NOT NULL,
    created_at       TEXT NOT NULL
);

-- ────────────────────────── Entities ──────────────────────────────

CREATE TABLE entity (
    id             TEXT PRIMARY KEY,
    kind           TEXT NOT NULL CHECK (kind IN ('organization','school','place','topic','skill','event_series')),
    canonical_name TEXT NOT NULL,
    part_of        TEXT REFERENCES entity(id),   -- one level: sub-event → umbrella (§7.10)
    merged_into    TEXT REFERENCES entity(id),   -- pointer-merge, like people (§7.10 / Decision 6)
    metadata       TEXT
);
CREATE INDEX entity_kind ON entity(kind);

CREATE TABLE entity_alias (
    entity_id TEXT NOT NULL REFERENCES entity(id),
    alias     TEXT NOT NULL,
    PRIMARY KEY (entity_id, alias)
);

-- ─────────────── Sync-run reference maps (operational) ───────────────
-- Extraction payloads name not-yet-existing people/entities by run-local refs
-- ("p1", "org2"). Accepting a CREATE_PERSON / entity-creating LINK records the
-- materialized id here so sibling proposals resolve their refs without mutating
-- proposal content (which is immutable).

CREATE TABLE sync_person_ref (
    sync_run_id TEXT NOT NULL REFERENCES sync_run(id),
    ref         TEXT NOT NULL,
    person_id   TEXT NOT NULL REFERENCES person(id),
    PRIMARY KEY (sync_run_id, ref)
);

-- Run-scoped ref→id map. POLYMORPHIC by design: entity refs, thread refs
-- ("thread:<ref>"), and reconstructed-event refs ("event:reconstructed:…")
-- share the namespace (ProposalResolutionService), so entity_id carries ids
-- from three tables and deliberately has no FK. Rows are sync bookkeeping,
-- not ledger content.
CREATE TABLE sync_entity_ref (
    sync_run_id TEXT NOT NULL REFERENCES sync_run(id),
    ref         TEXT NOT NULL,
    entity_id   TEXT NOT NULL,
    PRIMARY KEY (sync_run_id, ref)
);

-- Store metadata (schema version, model download state, …).
CREATE TABLE orbit_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
