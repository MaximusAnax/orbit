-- Full rebuild of the materialized read models from the log. Deterministic:
-- running this twice, or after incremental maintenance, must yield identical
-- tables (INV-4 diffs exactly that). Merge pointers are resolved here — the log
-- is never rewritten by a merge (Decision 6).

DELETE FROM rm_current_state;
INSERT INTO rm_current_state
SELECT
    a.id,
    COALESCE(ps.merged_into, ps.id),
    a.predicate,
    COALESCE(en.merged_into, en.id),
    -- §7.1: the latest amendment wins in read models; the log keeps the original
    COALESCE((SELECT aa.new_value FROM assertion_amendment aa
              WHERE aa.assertion_id = a.id AND aa.field = 'object_value'
              ORDER BY aa.created_at DESC, aa.id DESC LIMIT 1), a.object_value),
    COALESCE((SELECT aa.new_value FROM assertion_amendment aa
              WHERE aa.assertion_id = a.id AND aa.field = 'verbatim'
              ORDER BY aa.created_at DESC, aa.id DESC LIMIT 1), a.verbatim),
    a.valid_from,
    a.date_precision,
    a.observed_at,
    a.source_event_id,
    a.source_kind,
    a.attributed_to_person_id,
    a.needs_reconfirmation,
    a.thread_id
FROM assertion a
JOIN person ps      ON ps.id = a.subject_id
LEFT JOIN entity en ON en.id = a.object_entity_id
WHERE a.status = 'active'
  AND a.valid_to IS NULL
  AND a.subject_id IS NOT NULL;          -- INV-8: unresolved subjects never enter a read model

DELETE FROM rm_network_edge;
-- person → entity edges from current state
INSERT INTO rm_network_edge (edge_kind, from_person, to_person, to_entity, predicate, evidence_id)
SELECT 'assertion', cs.subject_id, NULL, cs.object_entity_id, cs.predicate, cs.assertion_id
FROM rm_current_state cs
WHERE cs.object_entity_id IS NOT NULL;

-- person ↔ person relation assertions (sibling, colleague, introduced_by-as-fact…)
INSERT INTO rm_network_edge (edge_kind, from_person, to_person, to_entity, predicate, evidence_id)
SELECT 'relation', cs.subject_id, COALESCE(p2.merged_into, p2.id), NULL, cs.predicate, cs.assertion_id
FROM rm_current_state cs
JOIN person p2 ON p2.id = cs.object_value
WHERE cs.predicate = 'relation' AND cs.object_value IS NOT NULL;

-- co-attendance at small events: present attendance only (INV-13), confirmed and
-- real events only (INV-12), ≤ 6 present people ("small" — a dinner, not a conference).
INSERT INTO rm_network_edge (edge_kind, from_person, to_person, to_entity, predicate, evidence_id)
SELECT DISTINCT 'co_attendance',
       COALESCE(pa.merged_into, pa.id),
       COALESCE(pb.merged_into, pb.id),
       NULL, NULL, e.id
FROM event e
JOIN event_participant a ON a.event_id = e.id AND a.attendance IN ('confirmed','probable')
JOIN event_participant b ON b.event_id = e.id AND b.attendance IN ('confirmed','probable')
                         AND b.person_id <> a.person_id
JOIN person pa ON pa.id = a.person_id
JOIN person pb ON pb.id = b.person_id
WHERE e.lifecycle = 'confirmed'
  AND e.derived_from_event_id IS NULL
  AND (SELECT COUNT(*) FROM event_participant ep
       WHERE ep.event_id = e.id AND ep.attendance IN ('confirmed','probable')) <= 6;

-- introduced_by roles
INSERT INTO rm_network_edge (edge_kind, from_person, to_person, to_entity, predicate, evidence_id)
SELECT 'introduced_by',
       COALESCE(pi.merged_into, pi.id),
       COALESCE(po.merged_into, po.id),
       NULL, NULL, e.id
FROM event e
JOIN event_participant intro ON intro.event_id = e.id AND intro.role = 'introducer'
JOIN event_participant other ON other.event_id = e.id AND other.person_id <> intro.person_id
                             AND other.attendance IN ('confirmed','probable')
JOIN person pi ON pi.id = intro.person_id
JOIN person po ON po.id = other.person_id
WHERE e.lifecycle = 'confirmed';

-- current group co-membership
INSERT INTO rm_network_edge (edge_kind, from_person, to_person, to_entity, predicate, evidence_id)
SELECT DISTINCT 'group',
       COALESCE(pa.merged_into, pa.id),
       COALESCE(pb.merged_into, pb.id),
       NULL, NULL, ga.group_id
FROM group_membership ga
JOIN group_membership gb ON gb.group_id = ga.group_id AND gb.person_id <> ga.person_id
JOIN person pa ON pa.id = ga.person_id
JOIN person pb ON pb.id = gb.person_id
WHERE ga.valid_to IS NULL AND gb.valid_to IS NULL;

DELETE FROM rm_contact_rhythm;
INSERT INTO rm_contact_rhythm (person_id, month, event_count)
SELECT COALESCE(p.merged_into, p.id) AS pid,
       substr(e.occurred_at, 1, 7)   AS month,
       COUNT(DISTINCT e.id)
FROM event e
JOIN event_participant ep ON ep.event_id = e.id
                          AND ep.attendance IN ('confirmed','probable')  -- INV-11: 'about' never counts
JOIN person p ON p.id = ep.person_id
WHERE e.lifecycle = 'confirmed'
  AND e.derived_from_event_id IS NULL                                    -- INV-12: reconstructed never counts
GROUP BY pid, month;
