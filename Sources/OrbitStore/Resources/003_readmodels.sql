-- Read models (DATA-MODEL §4): derived, disposable, rebuilt from the log.
-- current_state / network_graph / contact_rhythm are materialized tables
-- (rebuilt by 004_rebuild_readmodels.sql; maintained incrementally by OrbitWrite);
-- timeline is a view — it is a pure ordering with no aggregation worth caching.
-- INV-4: dropping these tables and re-running the rebuild must reproduce them exactly.

CREATE TABLE rm_current_state (
    assertion_id            TEXT PRIMARY KEY,
    subject_id              TEXT NOT NULL,      -- canonical (merge pointer resolved at rebuild)
    predicate               TEXT NOT NULL,
    object_entity_id        TEXT,               -- canonical entity (merge pointer resolved)
    object_value            TEXT,
    verbatim                TEXT NOT NULL,
    valid_from              TEXT,
    date_precision          TEXT NOT NULL,
    observed_at             TEXT NOT NULL,
    source_event_id         TEXT NOT NULL,
    source_kind             TEXT NOT NULL,
    attributed_to_person_id TEXT,
    needs_reconfirmation    INTEGER NOT NULL,
    thread_id               TEXT
);
CREATE INDEX rm_current_state_subject ON rm_current_state(subject_id);
CREATE INDEX rm_current_state_entity ON rm_current_state(object_entity_id);

-- person↔entity and person↔person edges, with the evidence that justifies each
-- (knows-each-other is derived and cited, never asserted — DATA-MODEL Groups §).
CREATE TABLE rm_network_edge (
    edge_kind    TEXT NOT NULL CHECK (edge_kind IN ('assertion','co_attendance','introduced_by','relation','group')),
    from_person  TEXT NOT NULL,
    to_person    TEXT,               -- person↔person edges
    to_entity    TEXT,               -- person↔entity edges
    predicate    TEXT,               -- for assertion edges
    evidence_id  TEXT NOT NULL,      -- assertion id / event id / group id
    CHECK ((to_person IS NULL) <> (to_entity IS NULL))
);
CREATE INDEX rm_network_edge_from ON rm_network_edge(from_person);
CREATE INDEX rm_network_edge_entity ON rm_network_edge(to_entity);

-- Observed contact per person per month. A per-relationship time series, never a
-- cross-person comparator (§9.5); present-attendance, real (non-reconstructed),
-- confirmed events only (INV-11, INV-12).
CREATE TABLE rm_contact_rhythm (
    person_id   TEXT NOT NULL,
    month       TEXT NOT NULL,       -- 'YYYY-MM'
    event_count INTEGER NOT NULL,
    PRIMARY KEY (person_id, month)
);

-- Per-person chronology: interactions, notes (visually distinct downstream), and
-- the moments facts were learned. Merge pointers resolved here.
CREATE VIEW v_timeline AS
SELECT
    COALESCE(p.merged_into, p.id) AS person_id,
    'event'                       AS item_kind,
    e.id                          AS item_id,
    e.occurred_at                 AS at,
    e.date_precision              AS at_precision,
    ep.attendance                 AS attendance,
    e.kind                        AS detail
FROM event e
JOIN event_participant ep ON ep.event_id = e.id
JOIN person p             ON p.id = ep.person_id
WHERE e.lifecycle = 'confirmed'
UNION ALL
SELECT
    COALESCE(p.merged_into, p.id) AS person_id,
    'assertion'                   AS item_kind,
    a.id                          AS item_id,
    a.observed_at                 AS at,
    'exact'                       AS at_precision,
    NULL                          AS attendance,
    a.predicate                   AS detail
FROM assertion a
JOIN person p ON p.id = a.subject_id
WHERE a.status = 'active';
