-- Rebuild the search index from the log (M4). Deterministic, like 004.
DELETE FROM rm_search;

-- current facts, attributed to their canonical subject
INSERT INTO rm_search (kind, person_id, ref_id, body)
SELECT 'assertion', cs.subject_id, cs.assertion_id,
       cs.verbatim || ' ' || COALESCE(cs.object_value, '')
FROM rm_current_state cs;

-- people: display + preferred names (misspellings handled at query time)
INSERT INTO rm_search (kind, person_id, ref_id, body)
SELECT 'person', COALESCE(p.merged_into, p.id), p.id,
       p.display_name || ' ' || COALESCE(p.preferred_name, '')
FROM person p WHERE p.status != 'merged' AND p.is_self = 0;

-- entities with their aliases
INSERT INTO rm_search (kind, person_id, ref_id, body)
SELECT 'entity', NULL, e.id,
       e.canonical_name || ' ' ||
       COALESCE((SELECT GROUP_CONCAT(a.alias, ' ') FROM entity_alias a
                 WHERE a.entity_id = e.id), '')
FROM entity e WHERE e.merged_into IS NULL;

-- confirmed events (title + kind), one atom per participant
INSERT INTO rm_search (kind, person_id, ref_id, body)
SELECT 'event', COALESCE(p.merged_into, p.id), e.id,
       COALESCE(e.title, '') || ' ' || e.kind
FROM event e
JOIN event_participant ep ON ep.event_id = e.id
JOIN person p ON p.id = ep.person_id
WHERE e.lifecycle = 'confirmed';
