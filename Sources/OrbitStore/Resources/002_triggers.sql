-- Immutability triggers — INV-1/INV-3/INV-22 enforced in the database itself,
-- beneath the service layer and the compiler. "Enforced at the storage layer —
-- triggers or repository-pattern guard — not by convention" (EVALS INV-1): both.
-- NULL-safe column comparison uses IS / IS NOT throughout.

-- ───────────────────────────── Events ─────────────────────────────

-- Confirmed events are frozen. The single permitted post-confirmation change is
-- clearing raw_audio_ref (§7.5 audio deletion — removing the recording is a privacy
-- action, not a history rewrite). Everything else goes through amendment rows.
CREATE TRIGGER event_frozen_after_confirm
BEFORE UPDATE ON event
FOR EACH ROW
WHEN OLD.lifecycle IN ('confirmed','discarded')
 AND NOT (
        NEW.raw_audio_ref IS NULL
    AND NEW.occurred_at            =  OLD.occurred_at
    AND NEW.date_precision         =  OLD.date_precision
    AND NEW.kind                   =  OLD.kind
    AND NEW.location_entity_id     IS OLD.location_entity_id
    AND NEW.title                  IS OLD.title
    AND NEW.transcript             IS OLD.transcript
    AND NEW.narrative              IS OLD.narrative
    AND NEW.emotional_context      IS OLD.emotional_context
    AND NEW.lifecycle              =  OLD.lifecycle
    AND NEW.derived_from_event_id  IS OLD.derived_from_event_id
    AND NEW.captured_at            =  OLD.captured_at
    AND NEW.confirmed_at           IS OLD.confirmed_at
 )
BEGIN
    SELECT RAISE(ABORT, 'INV-1: confirmed/discarded events are immutable; corrections are amendment rows');
END;

CREATE TRIGGER event_no_delete
BEFORE DELETE ON event
BEGIN
    SELECT RAISE(ABORT, 'INV-1: events are never deleted');
END;

-- Confirmation must stamp confirmed_at.
CREATE TRIGGER event_confirm_requires_timestamp
BEFORE UPDATE ON event
FOR EACH ROW
WHEN OLD.lifecycle = 'captured' AND NEW.lifecycle = 'confirmed' AND NEW.confirmed_at IS NULL
BEGIN
    SELECT RAISE(ABORT, 'event confirmation requires confirmed_at');
END;

-- Participants of a reviewed event are part of the record.
CREATE TRIGGER event_participant_frozen_update
BEFORE UPDATE ON event_participant
FOR EACH ROW
WHEN (SELECT lifecycle FROM event WHERE id = OLD.event_id) <> 'captured'
BEGIN
    SELECT RAISE(ABORT, 'INV-1: participants of a reviewed event are immutable; corrections are amendment rows');
END;

CREATE TRIGGER event_participant_frozen_delete
BEFORE DELETE ON event_participant
FOR EACH ROW
WHEN (SELECT lifecycle FROM event WHERE id = OLD.event_id) <> 'captured'
BEGIN
    SELECT RAISE(ABORT, 'INV-1: participants of a reviewed event are immutable');
END;

-- ─────────────────────────── Assertions ───────────────────────────

-- Accepted assertions (all rows here exist only via accepted proposals) allow exactly:
--   CLOSE      valid_to NULL→value, nothing else         (INV-3)
--   CORRECT    status active→retracted + reason, nothing else
--   supersede  superseded_by NULL→value
--   resolve    subject_id NULL→value (DISAMBIGUATE resolution)
--   link       thread_id NULL→value
--   operational: needs_reconfirmation / last_surfaced_at / pinned / muted (never history)
-- Everything else — verbatim, predicate, objects, provenance, times — is frozen;
-- small fixes are assertion_amendment rows (§7.1).
CREATE TRIGGER assertion_immutable_columns
BEFORE UPDATE ON assertion
FOR EACH ROW
WHEN NOT (
        NEW.predicate               =  OLD.predicate
    AND NEW.object_entity_id        IS OLD.object_entity_id
    AND NEW.object_value            IS OLD.object_value
    AND NEW.verbatim                =  OLD.verbatim
    AND NEW.valid_from              IS OLD.valid_from
    AND NEW.date_precision          =  OLD.date_precision
    AND NEW.observed_at             =  OLD.observed_at
    AND NEW.source_event_id         =  OLD.source_event_id
    AND NEW.source_kind             =  OLD.source_kind
    AND NEW.attributed_to_person_id IS OLD.attributed_to_person_id
    AND NEW.confidence              IS OLD.confidence
    -- one-way transitions only:
    AND (NEW.valid_to      IS OLD.valid_to      OR  OLD.valid_to      IS NULL)
    AND (NEW.subject_id    IS OLD.subject_id    OR  OLD.subject_id    IS NULL)
    AND (NEW.superseded_by IS OLD.superseded_by OR  OLD.superseded_by IS NULL)
    AND (NEW.thread_id     IS OLD.thread_id     OR  OLD.thread_id     IS NULL)
    AND (NEW.status = OLD.status OR (OLD.status = 'active' AND NEW.status = 'retracted'))
    AND (NEW.retraction_reason IS OLD.retraction_reason OR NEW.status = 'retracted')
)
BEGIN
    SELECT RAISE(ABORT, 'INV-1/INV-3: assertion history columns are immutable; use CLOSE/CORRECT/amendments');
END;

CREATE TRIGGER assertion_no_delete
BEFORE DELETE ON assertion
BEGIN
    SELECT RAISE(ABORT, 'INV-1: assertions are never deleted (CORRECT retracts, CLOSE ends)');
END;

-- Candidates may exist only while the subject is unresolved (Decision 5).
CREATE TRIGGER assertion_candidate_requires_unresolved
BEFORE INSERT ON assertion_subject_candidate
FOR EACH ROW
WHEN (SELECT subject_id FROM assertion WHERE id = NEW.assertion_id) IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'candidates only exist for unresolved-subject assertions');
END;

-- ───────────────────────────── People ─────────────────────────────

CREATE TRIGGER person_no_delete
BEFORE DELETE ON person
BEGIN
    SELECT RAISE(ABORT, 'INV-1: people are never deleted (merge by pointer instead)');
END;

-- is_self is set at insert and never changes; the self row never merges (INV-22).
CREATE TRIGGER person_self_flag_immutable
BEFORE UPDATE ON person
FOR EACH ROW
WHEN NEW.is_self <> OLD.is_self
BEGIN
    SELECT RAISE(ABORT, 'INV-22: is_self is immutable');
END;

CREATE TRIGGER person_self_never_merges
BEFORE UPDATE ON person
FOR EACH ROW
WHEN OLD.is_self = 1 AND NEW.merged_into IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'INV-22: the self row never merges');
END;

-- merged_into and status='merged' move together (Decision 6).
CREATE TRIGGER person_merge_consistency
BEFORE UPDATE ON person
FOR EACH ROW
WHEN (NEW.merged_into IS NOT NULL AND NEW.status <> 'merged')
  OR (NEW.merged_into IS NULL     AND NEW.status  = 'merged')
BEGIN
    SELECT RAISE(ABORT, 'merged_into and status=merged must change together');
END;

-- ─────────────── Append-only tables (INV-1 for decisions) ───────────────

CREATE TRIGGER relationship_state_append_only_u
BEFORE UPDATE ON relationship_state
BEGIN SELECT RAISE(ABORT, 'relationship_state is append-only (new version rows)'); END;
CREATE TRIGGER relationship_state_append_only_d
BEFORE DELETE ON relationship_state
BEGIN SELECT RAISE(ABORT, 'relationship_state is append-only'); END;

-- INV-23: the self row is structurally outside relationship machinery.
CREATE TRIGGER relationship_state_never_self
BEFORE INSERT ON relationship_state
FOR EACH ROW
WHEN (SELECT is_self FROM person WHERE id = NEW.person_id) = 1
BEGIN SELECT RAISE(ABORT, 'INV-23: the self has no relationship state'); END;

CREATE TRIGGER thread_never_self
BEFORE INSERT ON thread
FOR EACH ROW
WHEN (SELECT is_self FROM person WHERE id = NEW.person_id) = 1
BEGIN SELECT RAISE(ABORT, 'INV-23: the self has no threads'); END;

CREATE TRIGGER open_loop_never_self
BEFORE INSERT ON open_loop
FOR EACH ROW
WHEN (SELECT is_self FROM person WHERE id = NEW.person_id) = 1
BEGIN SELECT RAISE(ABORT, 'INV-23: the self has no open loops'); END;

CREATE TRIGGER group_membership_never_self
BEFORE INSERT ON group_membership
FOR EACH ROW
WHEN (SELECT is_self FROM person WHERE id = NEW.person_id) = 1
BEGIN SELECT RAISE(ABORT, 'INV-23: the self has no group memberships'); END;

CREATE TRIGGER review_outcome_append_only_u
BEFORE UPDATE ON review_outcome
BEGIN SELECT RAISE(ABORT, 'review_outcome is append-only (J-12 harvest log)'); END;
CREATE TRIGGER review_outcome_append_only_d
BEFORE DELETE ON review_outcome
BEGIN SELECT RAISE(ABORT, 'review_outcome is append-only'); END;

CREATE TRIGGER amendment_append_only_u
BEFORE UPDATE ON amendment
BEGIN SELECT RAISE(ABORT, 'amendments are append-only (post a correcting entry)'); END;
CREATE TRIGGER amendment_append_only_d
BEFORE DELETE ON amendment
BEGIN SELECT RAISE(ABORT, 'amendments are append-only'); END;

CREATE TRIGGER assertion_amendment_append_only_u
BEFORE UPDATE ON assertion_amendment
BEGIN SELECT RAISE(ABORT, 'assertion amendments are append-only'); END;
CREATE TRIGGER assertion_amendment_append_only_d
BEFORE DELETE ON assertion_amendment
BEGIN SELECT RAISE(ABORT, 'assertion amendments are append-only'); END;

CREATE TRIGGER extraction_append_only_u
BEFORE UPDATE ON extraction
BEGIN SELECT RAISE(ABORT, 'extractions are versioned, never edited (Decision 3)'); END;
CREATE TRIGGER extraction_append_only_d
BEFORE DELETE ON extraction
BEGIN SELECT RAISE(ABORT, 'extractions are versioned, never deleted'); END;

-- ─────────────────────────── Proposals ────────────────────────────

-- Content is immutable; only resolution fields move, along legal transitions.
-- INV-6: re-extraction can only ever add pending rows — nothing here mutates accepted content.
CREATE TRIGGER proposal_content_immutable
BEFORE UPDATE ON proposal
FOR EACH ROW
WHEN NOT (
        NEW.sync_run_id          =  OLD.sync_run_id
    AND NEW.op                   =  OLD.op
    AND NEW.target_person_id     IS OLD.target_person_id
    AND NEW.target_assertion_id  IS OLD.target_assertion_id
    AND NEW.payload              =  OLD.payload
    AND NEW.rationale            =  OLD.rationale
    AND NEW.prior_rejection_note IS OLD.prior_rejection_note
)
BEGIN
    SELECT RAISE(ABORT, 'proposal content is immutable; only its state resolves');
END;

CREATE TRIGGER proposal_state_transitions
BEFORE UPDATE ON proposal
FOR EACH ROW
WHEN NEW.state <> OLD.state
 AND NOT (
        (OLD.state = 'pending'  AND NEW.state IN ('accepted','rejected','deferred','superseded'))
     OR (OLD.state = 'deferred' AND NEW.state IN ('accepted','rejected','superseded'))
 )
BEGIN
    SELECT RAISE(ABORT, 'illegal proposal state transition');
END;

CREATE TRIGGER proposal_no_delete
BEFORE DELETE ON proposal
BEGIN
    SELECT RAISE(ABORT, 'proposals are never deleted (rejected ones are kept — Decision 4)');
END;

-- ──────────────────────── Threads & loops ─────────────────────────

CREATE TRIGGER thread_no_delete
BEFORE DELETE ON thread
BEGIN SELECT RAISE(ABORT, 'threads are never deleted (they stop prompting instead — §9.1)'); END;

-- Threads never resolve without a recorded cause (explicit user action or accepted proposal
-- both pass a resolving event; §9 "never set automatically" is enforced in OrbitWrite).
CREATE TRIGGER thread_resolution_recorded
BEFORE UPDATE ON thread
FOR EACH ROW
WHEN OLD.state = 'open' AND NEW.state = 'resolved' AND NEW.resolved_by_event_id IS NULL
BEGIN
    SELECT RAISE(ABORT, 'thread resolution must record its resolving event');
END;

CREATE TRIGGER open_loop_no_delete
BEFORE DELETE ON open_loop
BEGIN SELECT RAISE(ABORT, 'loops are never deleted (dropped is a state, not an erasure)'); END;

CREATE TRIGGER open_loop_content_immutable
BEFORE UPDATE ON open_loop
FOR EACH ROW
WHEN NOT (
        NEW.person_id       =  OLD.person_id
    AND NEW.source_event_id =  OLD.source_event_id
    AND NEW.direction       =  OLD.direction
    AND NEW.description     =  OLD.description
)
BEGIN
    SELECT RAISE(ABORT, 'loop content is immutable; only its state moves');
END;

-- INV-14: "how we met" anchors to a real meeting — never a note/portrait, and the
-- person must have been present at it.
CREATE TRIGGER person_first_met_must_be_meeting_u
BEFORE UPDATE ON person
FOR EACH ROW
WHEN NEW.first_met_event_id IS NOT NULL
 AND ( (SELECT kind FROM event WHERE id = NEW.first_met_event_id) IN ('note','portrait')
    OR NOT EXISTS (SELECT 1 FROM event_participant
                   WHERE event_id = NEW.first_met_event_id
                     AND person_id = NEW.id
                     AND attendance IN ('confirmed','probable')) )
BEGIN
    SELECT RAISE(ABORT, 'INV-14: first_met_event must be a real meeting the person attended');
END;

CREATE TRIGGER person_first_met_must_be_meeting_i
BEFORE INSERT ON person
FOR EACH ROW
WHEN NEW.first_met_event_id IS NOT NULL
 AND ( (SELECT kind FROM event WHERE id = NEW.first_met_event_id) IN ('note','portrait')
    OR NOT EXISTS (SELECT 1 FROM event_participant
                   WHERE event_id = NEW.first_met_event_id
                     AND person_id = NEW.id
                     AND attendance IN ('confirmed','probable')) )
BEGIN
    SELECT RAISE(ABORT, 'INV-14: first_met_event must be a real meeting the person attended');
END;

-- INV-9: relationship machinery describes a relationship that exists. People known
-- only secondhand (known_of) or half-caught (provisional) never receive state.
CREATE TRIGGER relationship_state_requires_real_relationship
BEFORE INSERT ON relationship_state
FOR EACH ROW
WHEN (SELECT status FROM person WHERE id = NEW.person_id) IN ('known_of','provisional')
BEGIN
    SELECT RAISE(ABORT, 'INV-9: known_of/provisional people have no relationship state');
END;
