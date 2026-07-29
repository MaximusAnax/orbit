import Foundation
import OrbitCore
import OrbitSQLite
import OrbitStore

public enum WriteError: Error, Equatable {
    case notFound(String)
    case invalidState(String)
    case pendingDependency(String)     // e.g. ASSERT accepted before its CREATE_PERSON
    case constitutionViolation(String) // e.g. PROPOSE_STATE without a verbatim quote (INV-24)
}

/// The write side of Orbit. Owns the sole writer connection (INV-5); every mutation
/// is a transaction that also maintains the read models incrementally (INV-4's
/// equivalence with full rebuild is a tested property).
public final class WriteStore {
    public let db: Database
    public let clock: OrbitClock
    public let reader: StoreReader

    public init(db: Database, clock: OrbitClock = SystemClock()) throws {
        self.db = db
        self.clock = clock
        self.reader = StoreReader(db)
        try Schema.ensure(on: db)
    }

    public static func inMemory(clock: OrbitClock = SystemClock()) throws -> WriteStore {
        try WriteStore(db: try Database.openWriterInMemory(), clock: clock)
    }

    public static func at(path: String, clock: OrbitClock = SystemClock()) throws -> WriteStore {
        try WriteStore(db: try Database.openWriter(path: path), clock: clock)
    }

    // MARK: - Read-model incremental maintenance
    // Small ops maintain rm_* in place; structural ops (merge/unmerge) rebuild.
    // INV-4 tests assert incremental == rebuild after every service operation.

    func rmInsertAssertion(_ id: String) throws {
        try db.run(
            """
            INSERT INTO rm_current_state
            SELECT a.id, COALESCE(ps.merged_into, ps.id), a.predicate,
                   COALESCE(en.merged_into, en.id), a.object_value, a.verbatim,
                   a.valid_from, a.date_precision, a.observed_at, a.source_event_id,
                   a.source_kind, a.attributed_to_person_id, a.needs_reconfirmation, a.thread_id
            FROM assertion a
            JOIN person ps ON ps.id = a.subject_id
            LEFT JOIN entity en ON en.id = a.object_entity_id
            WHERE a.id = ? AND a.status='active' AND a.valid_to IS NULL AND a.subject_id IS NOT NULL
            """, [.text(id)])
        // person→entity network edge
        try db.run(
            """
            INSERT INTO rm_network_edge (edge_kind, from_person, to_person, to_entity, predicate, evidence_id)
            SELECT 'assertion', cs.subject_id, NULL, cs.object_entity_id, cs.predicate, cs.assertion_id
            FROM rm_current_state cs
            WHERE cs.assertion_id = ? AND cs.object_entity_id IS NOT NULL
            """, [.text(id)])
        try db.run(
            """
            INSERT INTO rm_network_edge (edge_kind, from_person, to_person, to_entity, predicate, evidence_id)
            SELECT 'relation', cs.subject_id, COALESCE(p2.merged_into, p2.id), NULL, cs.predicate, cs.assertion_id
            FROM rm_current_state cs
            JOIN person p2 ON p2.id = cs.object_value
            WHERE cs.assertion_id = ? AND cs.predicate = 'relation' AND cs.object_value IS NOT NULL
            """, [.text(id)])
        try rmSearchRebuild()
    }

    func rmRemoveAssertion(_ id: String) throws {
        try db.run("DELETE FROM rm_current_state WHERE assertion_id=?", [.text(id)])
        try db.run("DELETE FROM rm_network_edge WHERE edge_kind IN ('assertion','relation') AND evidence_id=?",
                   [.text(id)])
        try rmSearchRebuild()
    }

    func rmEventConfirmed(_ eventID: String) throws {
        // contact rhythm (INV-11/12 filters are in the SQL predicates)
        try db.run(
            """
            INSERT INTO rm_contact_rhythm (person_id, month, event_count)
            SELECT COALESCE(p.merged_into, p.id), substr(e.occurred_at,1,7), 1
            FROM event e
            JOIN event_participant ep ON ep.event_id = e.id AND ep.attendance IN ('confirmed','probable')
            JOIN person p ON p.id = ep.person_id
            WHERE e.id = ? AND e.lifecycle='confirmed' AND e.derived_from_event_id IS NULL
            ON CONFLICT(person_id, month) DO UPDATE SET event_count = event_count + 1
            """, [.text(eventID)])
        // co-attendance edges for small events (INV-13)
        try db.run(
            """
            INSERT INTO rm_network_edge (edge_kind, from_person, to_person, to_entity, predicate, evidence_id)
            SELECT DISTINCT 'co_attendance', COALESCE(pa.merged_into,pa.id), COALESCE(pb.merged_into,pb.id), NULL, NULL, e.id
            FROM event e
            JOIN event_participant a ON a.event_id=e.id AND a.attendance IN ('confirmed','probable')
            JOIN event_participant b ON b.event_id=e.id AND b.attendance IN ('confirmed','probable') AND b.person_id<>a.person_id
            JOIN person pa ON pa.id=a.person_id
            JOIN person pb ON pb.id=b.person_id
            WHERE e.id = ? AND e.lifecycle='confirmed' AND e.derived_from_event_id IS NULL
              AND (SELECT COUNT(*) FROM event_participant ep
                   WHERE ep.event_id=e.id AND ep.attendance IN ('confirmed','probable')) <= 6
            """, [.text(eventID)])
        try db.run(
            """
            INSERT INTO rm_network_edge (edge_kind, from_person, to_person, to_entity, predicate, evidence_id)
            SELECT 'introduced_by', COALESCE(pi.merged_into,pi.id), COALESCE(po.merged_into,po.id), NULL, NULL, e.id
            FROM event e
            JOIN event_participant intro ON intro.event_id=e.id AND intro.role='introducer'
            JOIN event_participant other ON other.event_id=e.id AND other.person_id<>intro.person_id
                                         AND other.attendance IN ('confirmed','probable')
            JOIN person pi ON pi.id=intro.person_id
            JOIN person po ON po.id=other.person_id
            WHERE e.id = ? AND e.lifecycle='confirmed'
            """, [.text(eventID)])
        try rmSearchRebuild()
    }

    /// Structural change → full rebuild (rare: merge/unmerge, group edits).
    func rmRebuild() throws {
        try ReadModels.rebuild(on: db)
    }

    /// Search index refresh — a full re-derivation (personal-scale corpora make
    /// this milliseconds; correctness beats cleverness in the trust core).
    /// Callers: assertion insert/remove, event confirmation, person/entity
    /// name changes.
    func rmSearchRebuild() throws {
        try ReadModels.rebuildSearch(on: db)
    }
}
