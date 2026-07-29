import Foundation
import OrbitCore
import OrbitSQLite
import OrbitStore

/// Direct user actions: capture, transcript review, event confirmation, amendments,
/// groups, relationship state, loops/threads resolution, merge/unmerge.
/// One of the two legal write entry points (INV-5).
public struct UserEditService {
    let store: WriteStore
    var db: Database { store.db }
    var now: String { store.clock.now() }

    public init(_ store: WriteStore) { self.init(store: store) }
    init(store: WriteStore) { self.store = store }

    // MARK: - People

    @discardableResult
    public func createPerson(displayName: String, status: PersonStatus = .active,
                             isSelf: Bool = false) throws -> String {
        let id = OrbitID.make()
        try db.run(
            "INSERT INTO person (id, display_name, status, is_self, created_at) VALUES (?,?,?,?,?)",
            [.text(id), .text(displayName), .text(status.rawValue), .from(isSelf), .text(now)])
        return id
    }

    public func renamePerson(_ id: String, displayName: String, preferredName: String? = nil) throws {
        try db.run(
            "UPDATE person SET display_name=?, preferred_name=COALESCE(?, preferred_name) WHERE id=?",
            [.text(displayName), .from(preferredName), .text(id)])
    }

    /// Merge by pointer (Decision 6): the loser's rows are never touched.
    public func mergePerson(loser: String, winner: String) throws {
        try db.transaction {
            try db.run("UPDATE person SET merged_into=?, status='merged' WHERE id=?",
                       [.text(winner), .text(loser)])
            try store.rmRebuild()
        }
    }

    /// Unmerge is one field; queries must restore exactly (INV-17).
    public func unmergePerson(_ id: String, restoredStatus: PersonStatus = .active) throws {
        try db.transaction {
            try db.run("UPDATE person SET merged_into=NULL, status=? WHERE id=?",
                       [.text(restoredStatus.rawValue), .text(id)])
            try store.rmRebuild()
        }
    }

    public func setFirstMet(person: String, event: String) throws {
        try db.run("UPDATE person SET first_met_event_id=? WHERE id=?", [.text(event), .text(person)])
    }

    // MARK: - Capture lifecycle

    public struct CaptureDraft: Sendable {
        public var kind: EventKind
        public var occurredAt: String
        public var datePrecision: DatePrecision
        public var transcript: String?
        public var audioRef: String?
        public var title: String?
        public var participants: [(person: String, attendance: Attendance, role: String?)]
        public init(kind: EventKind, occurredAt: String, datePrecision: DatePrecision = .exact,
                    transcript: String? = nil, audioRef: String? = nil, title: String? = nil,
                    participants: [(person: String, attendance: Attendance, role: String?)]) {
            self.kind = kind
            self.occurredAt = occurredAt
            self.datePrecision = datePrecision
            self.transcript = transcript
            self.audioRef = audioRef
            self.title = title
            self.participants = participants
        }
    }

    /// INV-19: an event about nobody is a diary entry, and Orbit is not a diary.
    @discardableResult
    public func captureEvent(_ draft: CaptureDraft) throws -> String {
        guard !draft.participants.isEmpty else {
            throw WriteError.constitutionViolation("INV-19: an event requires ≥1 participant")
        }
        let id = OrbitID.make()
        try db.transaction {
            try db.run(
                """
                INSERT INTO event (id, occurred_at, date_precision, kind, title, raw_audio_ref,
                                   transcript, lifecycle, captured_at)
                VALUES (?,?,?,?,?,?,?, 'captured', ?)
                """,
                [.text(id), .text(draft.occurredAt), .text(draft.datePrecision.rawValue),
                 .text(draft.kind.rawValue), .from(draft.title), .from(draft.audioRef),
                 .from(draft.transcript), .text(now)])
            for p in draft.participants {
                try db.run(
                    "INSERT INTO event_participant (event_id, person_id, attendance, role) VALUES (?,?,?,?)",
                    [.text(id), .text(p.person), .text(p.attendance.rawValue), .from(p.role)])
            }
        }
        return id
    }

    /// Transcript is fully editable before confirmation — the review that makes
    /// audio deletion safe (§7.5). After confirmation it is frozen by trigger.
    public func editTranscript(event: String, transcript: String) throws {
        try db.run("UPDATE event SET transcript=? WHERE id=? AND lifecycle='captured'",
                   [.text(transcript), .text(event)])
        if db.changes == 0 {
            throw WriteError.invalidState("transcript is editable only before confirmation")
        }
    }

    /// Confirm the event. Audio is deleted here ONLY when the full model transcribed
    /// (the §6/§7.5 gate) — otherwise the ref stays until an upgrade pass clears it.
    public func confirmEvent(_ id: String, fullModelTranscribed: Bool) throws {
        try db.transaction {
            try db.run(
                "UPDATE event SET lifecycle='confirmed', confirmed_at=? WHERE id=? AND lifecycle='captured'",
                [.text(now), .text(id)])
            if db.changes == 0 {
                throw WriteError.invalidState("only captured events can be confirmed")
            }
            if fullModelTranscribed {
                try db.run("UPDATE event SET raw_audio_ref=NULL WHERE id=?", [.text(id)])
            }
            try store.rmEventConfirmed(id)
        }
    }

    /// Post-confirmation audio deletion once the full model has caught up (§6 note).
    public func deleteAudioAfterUpgrade(event: String) throws {
        try db.run("UPDATE event SET raw_audio_ref=NULL WHERE id=?", [.text(event)])
    }

    public func discardEvent(_ id: String) throws {
        try db.run("UPDATE event SET lifecycle='discarded', raw_audio_ref=NULL WHERE id=? AND lifecycle='captured'",
                   [.text(id)])
        if db.changes == 0 {
            throw WriteError.invalidState("only captured events can be discarded")
        }
    }

    // MARK: - Amendments (ledger corrections; INV-1 companions)

    public func amendEvent(_ event: String, field: String, newValue: String?, reason: String?) throws {
        try db.run(
            "INSERT INTO amendment (id, event_id, field, new_value, reason, created_at) VALUES (?,?,?,?,?,?)",
            [.text(OrbitID.make()), .text(event), .text(field), .from(newValue), .from(reason), .text(now)])
    }

    public func amendAssertion(_ assertion: String, field: String, newValue: String?, reason: String?) throws {
        try db.run(
            "INSERT INTO assertion_amendment (id, assertion_id, field, new_value, reason, created_at) VALUES (?,?,?,?,?,?)",
            [.text(OrbitID.make()), .text(assertion), .text(field), .from(newValue), .from(reason), .text(now)])
    }

    // MARK: - Relationship state (human-authored path, §12)

    @discardableResult
    public func setRelationshipState(person: String, narrative: String?, orbit: Orbit?,
                                     maintenanceMode: MaintenanceMode = .unset,
                                     desiredCadence: String? = nil, intent: String? = nil) throws -> String {
        let id = OrbitID.make()
        try db.run(
            """
            INSERT INTO relationship_state
                (id, person_id, narrative, orbit, maintenance_mode, desired_cadence, intent, authored_by, created_at)
            VALUES (?,?,?,?,?,?,?, 'human', ?)
            """,
            [.text(id), .text(person), .from(narrative), .from(orbit?.rawValue),
             .text(maintenanceMode.rawValue), .from(desiredCadence), .from(intent), .text(now)])
        return id
    }

    // MARK: - Groups (created by Abdoul, and only by Abdoul — no proposal op exists)

    @discardableResult
    public func createGroup(name: String, notes: String? = nil) throws -> String {
        let id = OrbitID.make()
        try db.run("INSERT INTO person_group (id, name, notes, created_at) VALUES (?,?,?,?)",
                   [.text(id), .text(name), .from(notes), .text(now)])
        return id
    }

    public func addGroupMember(group: String, person: String, validFrom: String? = nil) throws {
        try db.transaction {
            try db.run(
                "INSERT INTO group_membership (group_id, person_id, valid_from) VALUES (?,?,?)",
                [.text(group), .text(person), .from(validFrom ?? now)])
            try store.rmRebuild()
        }
    }

    /// Past membership is history, not a row to delete (Principle 2).
    public func endGroupMembership(group: String, person: String) throws {
        try db.transaction {
            try db.run(
                "UPDATE group_membership SET valid_to=? WHERE group_id=? AND person_id=? AND valid_to IS NULL",
                [.text(now), .text(group), .text(person)])
            try store.rmRebuild()
        }
    }

    // MARK: - Loops & threads (explicit user resolution)

    public func resolveLoop(_ id: String, byEvent: String?) throws {
        try db.run("UPDATE open_loop SET state='resolved', resolved_by_event_id=? WHERE id=? AND state='open'",
                   [.from(byEvent), .text(id)])
    }

    public func dropLoop(_ id: String) throws {
        try db.run("UPDATE open_loop SET state='dropped' WHERE id=? AND state='open'", [.text(id)])
    }

    /// Explicit user resolution of a thread — always via a real event (§9.4 trigger).
    public func resolveThread(_ id: String, byEvent: String, note: String?) throws {
        try db.run(
            "UPDATE thread SET state='resolved', resolved_by_event_id=?, resolution_note=? WHERE id=? AND state='open'",
            [.text(byEvent), .from(note), .text(id)])
    }

    /// Decay bookkeeping after a conversation with `person` (§9.2): threads not
    /// mentioned advance their clock; archetype defaults decide context_only.
    /// Notes never advance the clock (INV-11 asymmetry) — callers pass real
    /// conversations only; mentioned threads refresh instead.
    public func recordConversationForThreads(person: String, mentionedThreads: Set<String>) throws {
        let threads = try db.query(
            "SELECT id, archetype, conversations_since_mention FROM thread WHERE person_id=? AND state='open'",
            [.text(person)])
        for t in threads {
            let id = t.text("id")!
            if mentionedThreads.contains(id) {
                try db.run(
                    "UPDATE thread SET conversations_since_mention=0, last_mentioned_at=?, prompt_state='active' WHERE id=?",
                    [.text(now), .text(id)])
            } else {
                let count = Int(t.int("conversations_since_mention") ?? 0) + 1
                var decayed = false
                if let arch = ThreadArchetype(rawValue: t.text("archetype") ?? ""),
                   let limit = arch.decayConversations, count >= limit {
                    decayed = true
                }
                try db.run(
                    "UPDATE thread SET conversations_since_mention=?, prompt_state=? WHERE id=?",
                    [.integer(Int64(count)), .text(decayed ? "context_only" : "active"), .text(id)])
            }
        }
    }

    /// A note mentioning a thread refreshes last_mentioned_at but never advances
    /// the conversation clock (§7.11's deliberate asymmetry).
    public func recordNoteMention(thread: String) throws {
        try db.run("UPDATE thread SET last_mentioned_at=? WHERE id=?", [.text(now), .text(thread)])
    }

    // MARK: - Ranking overrides (Principle 1: human override always wins)

    public func setPinned(assertion: String, _ pinned: Bool) throws {
        try db.run("UPDATE assertion SET pinned=? WHERE id=?", [.from(pinned), .text(assertion)])
    }

    public func setMuted(assertion: String, _ muted: Bool) throws {
        try db.run("UPDATE assertion SET muted=? WHERE id=?", [.from(muted), .text(assertion)])
    }

    public func markSurfaced(assertions: [String]) throws {
        for id in assertions {
            try db.run("UPDATE assertion SET last_surfaced_at=? WHERE id=?", [.text(now), .text(id)])
        }
    }

    // MARK: - Contact points & saved lists

    @discardableResult
    public func addContactPoint(person: String, kind: ContactPointKind, value: String,
                                label: String? = nil, source: ContactPointSource,
                                sourceEvent: String? = nil) throws -> String {
        let id = OrbitID.make()
        try db.run(
            """
            INSERT INTO contact_point (id, person_id, kind, value, label, source, source_event_id, valid_from)
            VALUES (?,?,?,?,?,?,?,?)
            """,
            [.text(id), .text(person), .text(kind.rawValue), .text(value), .from(label),
             .text(source.rawValue), .from(sourceEvent), .text(now)])
        return id
    }

    @discardableResult
    public func createSavedList(name: String, queryDefinition: String) throws -> String {
        let id = OrbitID.make()
        try db.run("INSERT INTO saved_list (id, name, query_definition, created_at) VALUES (?,?,?,?)",
                   [.text(id), .text(name), .text(queryDefinition), .text(now)])
        return id
    }
}
