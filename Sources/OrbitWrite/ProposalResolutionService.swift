import Foundation
import OrbitCore
import OrbitSQLite
import OrbitStore

/// The proposal side of the write funnel: registering extraction output as pending
/// proposals, and applying the user's decisions. Nothing reaches the ledger except
/// through `resolve` (or UserEditService) — INV-5.
public struct ProposalResolutionService {
    let store: WriteStore
    var db: Database { store.db }
    var now: String { store.clock.now() }

    public init(_ store: WriteStore) { self.store = store }

    // MARK: - Registering pipeline output (everything lands pending; INV-6)

    @discardableResult
    public func recordExtraction(event: String, version: Int, modelID: String,
                                 promptVersion: String, payload: String,
                                 ambiguities: String? = nil) throws -> String {
        let id = OrbitID.make()
        try db.run(
            "INSERT INTO extraction VALUES (?,?,?,?,?,?,?,?)",
            [.text(id), .text(event), .integer(Int64(version)), .text(modelID),
             .text(promptVersion), .text(now), .text(payload), .from(ambiguities)])
        return id
    }

    @discardableResult
    public func openSyncRun(event: String, extraction: String) throws -> String {
        let id = OrbitID.make()
        try db.run("INSERT INTO sync_run VALUES (?,?,?,?,NULL)",
                   [.text(id), .text(event), .text(extraction), .text(now)])
        return id
    }

    public func completeSyncRun(_ id: String) throws {
        try db.run("UPDATE sync_run SET completed_at=? WHERE id=?", [.text(now), .text(id)])
    }

    public struct Draft: Sendable {
        public var op: ProposalOp
        public var payloadJSON: String
        public var rationale: String
        public var targetPerson: String?
        public var targetAssertion: String?
        public var priorRejectionNote: String?
        public init(op: ProposalOp, payloadJSON: String, rationale: String,
                    targetPerson: String? = nil, targetAssertion: String? = nil,
                    priorRejectionNote: String? = nil) {
            self.op = op
            self.payloadJSON = payloadJSON
            self.rationale = rationale
            self.targetPerson = targetPerson
            self.targetAssertion = targetAssertion
            self.priorRejectionNote = priorRejectionNote
        }
    }

    /// Register one proposal. Guards:
    ///  - INV-24: PROPOSE_STATE must quote the source transcript verbatim.
    ///  - INV-7 : content rejected from THIS transcript is never re-proposed from it.
    @discardableResult
    public func propose(syncRun: String, _ draft: Draft) throws -> String? {
        if draft.op == .proposeState {
            let payload = try PayloadCoding.decode(ProposeStatePayload.self, from: draft.payloadJSON)
            let transcript = try sourceTranscript(ofSyncRun: syncRun)
            guard !payload.narrativeQuote.isEmpty, transcript.contains(payload.narrativeQuote) else {
                throw WriteError.constitutionViolation(
                    "INV-24: PROPOSE_STATE requires a verbatim quote from the source transcript")
            }
        }
        if try isSuppressedBySameSourceRejection(syncRun: syncRun, draft: draft) {
            return nil   // INV-7 / PIPE-8: silently dropped, never resurfaced from the same source
        }
        let id = OrbitID.make()
        try db.run(
            """
            INSERT INTO proposal (id, sync_run_id, op, target_person_id, target_assertion_id,
                                  payload, rationale, prior_rejection_note)
            VALUES (?,?,?,?,?,?,?,?)
            """,
            [.text(id), .text(syncRun), .text(draft.op.rawValue), .from(draft.targetPerson),
             .from(draft.targetAssertion), .text(draft.payloadJSON), .text(draft.rationale),
             .from(draft.priorRejectionNote)])
        return id
    }

    func sourceTranscript(ofSyncRun id: String) throws -> String {
        let row = try db.query(
            """
            SELECT e.transcript AS t FROM sync_run s JOIN event e ON e.id = s.event_id WHERE s.id=?
            """, [.text(id)]).first
        return row?.text("t") ?? ""
    }

    /// INV-7 scope: a rejection is a verdict on (source-event, claim) — same event,
    /// same op, same payload ⇒ suppressed. New evidence (another event) may re-propose.
    func isSuppressedBySameSourceRejection(syncRun: String, draft: Draft) throws -> Bool {
        let count = try db.scalar(
            """
            SELECT COUNT(*) FROM proposal p
            JOIN sync_run s1 ON s1.id = p.sync_run_id
            JOIN sync_run s2 ON s2.id = ?
            WHERE s1.event_id = s2.event_id
              AND p.state = 'rejected'
              AND p.op = ?
              AND p.payload = ?
            """,
            [.text(syncRun), .text(draft.op.rawValue), .text(draft.payloadJSON)])
        return (count.intValue ?? 0) > 0
    }

    // MARK: - Resolution (the human decides — Principle 5)

    public enum Decision: Sendable {
        case accept
        case acceptEdited(payloadJSON: String)
        case reject(reason: RejectionReason?)
        case defer_
        /// DISAMBIGUATE only: answer the question with a person…
        case chooseCandidate(personID: String)
        /// …or keep the fact with its subject genuinely open (Decision 5).
        case acceptUnresolved
    }

    public func resolve(proposal id: String, _ decision: Decision) throws {
        guard let row = try db.query("SELECT * FROM proposal WHERE id=?", [.text(id)]).first else {
            throw WriteError.notFound("proposal \(id)")
        }
        let state = row.text("state")!
        guard state == "pending" || state == "deferred" else {
            throw WriteError.invalidState("proposal already \(state)")
        }
        let op = ProposalOp(rawValue: row.text("op")!)!
        let syncRun = row.text("sync_run_id")!

        try db.transaction {
            switch decision {
            case .accept:
                try apply(op: op, payloadJSON: row.text("payload")!, row: row, syncRun: syncRun)
                try close(id, state: "accepted", action: .accepted, edited: nil, reason: nil)
            case .acceptEdited(let payloadJSON):
                try apply(op: op, payloadJSON: payloadJSON, row: row, syncRun: syncRun)
                try db.run("UPDATE proposal SET edited_payload=? WHERE id=?", [.text(payloadJSON), .text(id)])
                try close(id, state: "accepted", action: .edited, edited: payloadJSON, reason: nil)
            case .reject(let reason):
                try close(id, state: "rejected", action: .rejected, edited: nil, reason: reason)
            case .defer_:
                try db.run("UPDATE proposal SET state='deferred' WHERE id=?", [.text(id)])
                try recordOutcome(proposal: id, action: .deferred, edited: nil, reason: nil)
            case .chooseCandidate(let personID):
                guard op == .disambiguate else {
                    throw WriteError.invalidState("chooseCandidate applies to DISAMBIGUATE only")
                }
                let payload = try PayloadCoding.decode(DisambiguatePayload.self, from: row.text("payload")!)
                var assertion = payload.assertion
                assertion.subject = .id(personID)
                _ = try insertAssertion(assertion, syncRun: syncRun)
                try close(id, state: "accepted", action: .accepted, edited: nil, reason: nil)
            case .acceptUnresolved:
                guard op == .disambiguate else {
                    throw WriteError.invalidState("acceptUnresolved applies to DISAMBIGUATE only")
                }
                let payload = try PayloadCoding.decode(DisambiguatePayload.self, from: row.text("payload")!)
                let aid = try insertAssertion(payload.assertion, syncRun: syncRun, forceUnresolved: true)
                for c in payload.candidates {
                    if case .id(let pid) = c {
                        try db.run("INSERT INTO assertion_subject_candidate VALUES (?,?)",
                                   [.text(aid), .text(pid)])
                    }
                }
                try close(id, state: "accepted", action: .accepted, edited: nil, reason: nil)
            }
        }
    }

    func close(_ id: String, state: String, action: ReviewAction,
               edited: String?, reason: RejectionReason?) throws {
        try db.run("UPDATE proposal SET state=?, resolved_at=? WHERE id=?",
                   [.text(state), .text(now), .text(id)])
        try recordOutcome(proposal: id, action: action, edited: edited, reason: reason)
    }

    /// J-12: the labeling machine — every decision becomes eval ground truth (EVALS §3.2).
    func recordOutcome(proposal: String, action: ReviewAction,
                       edited: String?, reason: RejectionReason?) throws {
        try db.run(
            """
            INSERT INTO review_outcome (id, proposal_id, action, rejection_reason, edited_payload, created_at)
            VALUES (?,?,?,?,?,?)
            """,
            [.text(OrbitID.make()), .text(proposal), .text(action.rawValue),
             .from(reason?.rawValue), .from(edited), .text(now)])
    }

    // MARK: - Applying accepted ops

    func apply(op: ProposalOp, payloadJSON: String, row: Row, syncRun: String) throws {
        switch op {
        case .assert:
            let p = try PayloadCoding.decode(AssertPayload.self, from: payloadJSON)
            _ = try insertAssertion(p, syncRun: syncRun)

        case .close:
            guard let target = row.text("target_assertion_id") else {
                throw WriteError.invalidState("CLOSE requires a target assertion")
            }
            let p = try PayloadCoding.decode(ClosePayload.self, from: payloadJSON)
            try db.run("UPDATE assertion SET valid_to=? WHERE id=?", [.text(p.validTo), .text(target)])
            try store.rmRemoveAssertion(target)

        case .correct:
            guard let target = row.text("target_assertion_id") else {
                throw WriteError.invalidState("CORRECT requires a target assertion")
            }
            let p = try PayloadCoding.decode(CorrectPayload.self, from: payloadJSON)
            try db.run("UPDATE assertion SET status='retracted', retraction_reason=? WHERE id=?",
                       [.text(p.reason), .text(target)])
            try store.rmRemoveAssertion(target)

        case .createPerson:
            let p = try PayloadCoding.decode(CreatePersonPayload.self, from: payloadJSON)
            let id = OrbitID.make()
            try db.run(
                "INSERT INTO person (id, display_name, status, created_at) VALUES (?,?,?,?)",
                [.text(id), .text(p.displayName), .text(p.status), .text(now)])
            try db.run("INSERT INTO sync_person_ref VALUES (?,?,?)",
                       [.text(syncRun), .text(p.ref), .text(id)])

        case .link:
            let p = try PayloadCoding.decode(LinkEntityPayload.self, from: payloadJSON)
            let entityID: String
            if let existing = p.existingEntityID {
                entityID = existing
            } else {
                guard let kind = p.kind, let name = p.canonicalName else {
                    throw WriteError.invalidState("LINK create requires kind + canonical_name")
                }
                entityID = OrbitID.make()
                let parent: String? = try p.partOf.flatMap { try resolveEntity($0, syncRun: syncRun) }
                try db.run(
                    "INSERT INTO entity (id, kind, canonical_name, part_of) VALUES (?,?,?,?)",
                    [.text(entityID), .text(kind), .text(name), .from(parent)])
            }
            for alias in p.aliases {
                try db.run("INSERT OR IGNORE INTO entity_alias VALUES (?,?)",
                           [.text(entityID), .text(alias)])
            }
            try db.run("INSERT INTO sync_entity_ref VALUES (?,?,?)",
                       [.text(syncRun), .text(p.ref), .text(entityID)])

        case .openLoop:
            let p = try PayloadCoding.decode(OpenLoopPayload.self, from: payloadJSON)
            let person = try resolvePerson(p.person, syncRun: syncRun)
            let event = try eventID(ofSyncRun: syncRun)
            try db.run(
                """
                INSERT INTO open_loop (id, person_id, source_event_id, direction, description, due_at, due_precision)
                VALUES (?,?,?,?,?,?,?)
                """,
                [.text(OrbitID.make()), .text(person), .text(event), .text(p.direction),
                 .text(p.description), .from(p.dueAt), .from(p.duePrecision)])

        case .openThread:
            let p = try PayloadCoding.decode(OpenThreadPayload.self, from: payloadJSON)
            let person = try resolvePerson(p.person, syncRun: syncRun)
            let event = try eventID(ofSyncRun: syncRun)
            let id = OrbitID.make()
            try db.run(
                """
                INSERT INTO thread (id, person_id, title, archetype, opened_event_id,
                                    expected_resolution_at, expected_resolution_precision, last_mentioned_at)
                VALUES (?,?,?,?,?,?,?,?)
                """,
                [.text(id), .text(person), .text(p.title), .text(p.archetype), .text(event),
                 .from(p.expectedResolutionAt), .from(p.expectedResolutionPrecision), .text(now)])
            try db.run("INSERT INTO sync_entity_ref VALUES (?,?,?)",   // thread refs share the map namespace
                       [.text(syncRun), .text("thread:" + p.ref), .text(id)])

        case .closeThread:
            // §9.4 implicit resolution — proposed by sync, applied only on acceptance.
            let p = try PayloadCoding.decode(CloseThreadPayload.self, from: payloadJSON)
            let event = try eventID(ofSyncRun: syncRun)
            try db.run(
                "UPDATE thread SET state='resolved', resolved_by_event_id=?, resolution_note=? WHERE id=? AND state='open'",
                [.text(event), .text(p.resolutionNote), .text(p.threadID)])

        case .proposeState:
            let p = try PayloadCoding.decode(ProposeStatePayload.self, from: payloadJSON)
            let person = try resolvePerson(p.person, syncRun: syncRun)
            let event = try eventID(ofSyncRun: syncRun)
            // The words were literally his; the AI only moved them (§7.13) → authored_by human.
            try db.run(
                """
                INSERT INTO relationship_state
                    (id, person_id, narrative, orbit, intent, authored_by, source_event_id, created_at)
                VALUES (?,?,?,?,?, 'human', ?, ?)
                """,
                [.text(OrbitID.make()), .text(person), .text(p.narrativeQuote),
                 .from(p.suggestedOrbit), .from(p.suggestedIntent), .text(event), .text(now)])

        case .merge:
            let p = try PayloadCoding.decode(MergePayload.self, from: payloadJSON)
            try db.run("UPDATE person SET merged_into=?, status='merged' WHERE id=?",
                       [.text(p.winnerID), .text(p.loserID)])
            try store.rmRebuild()

        case .createEvent:
            // §7.11 reconstructed episode: no transcript/audio of its own; confirmed on
            // acceptance (the review WAS the confirmation); excluded from rate math via
            // derived_from_event_id (INV-12).
            let p = try PayloadCoding.decode(CreateEventPayload.self, from: payloadJSON)
            let source = try eventID(ofSyncRun: syncRun)
            let id = OrbitID.make()
            try db.run(
                """
                INSERT INTO event (id, occurred_at, date_precision, kind, title, narrative,
                                   lifecycle, derived_from_event_id, captured_at, confirmed_at)
                VALUES (?,?,?,?,?,?, 'captured', ?, ?, NULL)
                """,
                [.text(id), .text(p.occurredAt), .text(p.datePrecision), .text(p.kind),
                 .from(p.title), .text(p.narrative), .text(source), .text(now)])
            for participant in p.participants {
                let pid = try resolvePerson(participant.person, syncRun: syncRun)
                try db.run(
                    "INSERT INTO event_participant (event_id, person_id, attendance, role) VALUES (?,?,?,?)",
                    [.text(id), .text(pid), .text(participant.attendance), .from(participant.role)])
            }
            try db.run("UPDATE event SET lifecycle='confirmed', confirmed_at=? WHERE id=?",
                       [.text(now), .text(id)])
            try db.run("INSERT INTO sync_entity_ref VALUES (?,?,?)",
                       [.text(syncRun), .text("event:reconstructed:" + p.occurredAt), .text(id)])

        case .contactPoint:
            let p = try PayloadCoding.decode(ContactPointPayload.self, from: payloadJSON)
            let person = try resolvePerson(p.person, syncRun: syncRun)
            let event = try eventID(ofSyncRun: syncRun)
            try db.run(
                """
                INSERT INTO contact_point (id, person_id, kind, value, label, source, source_event_id, valid_from)
                VALUES (?,?,?,?,?,?,?,?)
                """,
                [.text(OrbitID.make()), .text(person), .text(p.kind), .text(p.value),
                 .from(p.label), .text(p.source), .text(event), .text(now)])

        case .disambiguate:
            // Reached only via .accept on a DISAMBIGUATE (i.e. "yes" to the framed
            // question with a single candidate); multi-candidate answers use
            // .chooseCandidate / .acceptUnresolved.
            let payload = try PayloadCoding.decode(DisambiguatePayload.self, from: payloadJSON)
            if payload.candidates.count == 1, case .id(let pid) = payload.candidates[0] {
                var assertion = payload.assertion
                assertion.subject = .id(pid)
                _ = try insertAssertion(assertion, syncRun: syncRun)
            } else {
                throw WriteError.invalidState("ambiguous DISAMBIGUATE needs chooseCandidate/acceptUnresolved")
            }
        }
    }

    @discardableResult
    func insertAssertion(_ p: AssertPayload, syncRun: String, forceUnresolved: Bool = false) throws -> String {
        let subject: String? = forceUnresolved ? nil : try resolvePerson(p.subject, syncRun: syncRun)
        let entity: String? = try p.objectEntity.flatMap { try resolveEntity($0, syncRun: syncRun) }
        let attributed: String? = try p.attributedTo.flatMap { try resolvePerson($0, syncRun: syncRun) }
        let objectValue: String? = try p.objectPerson.map { try resolvePerson($0, syncRun: syncRun) } ?? p.objectValue
        let event = try eventID(ofSyncRun: syncRun)
        let thread: String? = try p.threadRef.flatMap { ref in
            try db.scalar("SELECT entity_id FROM sync_entity_ref WHERE sync_run_id=? AND ref=?",
                          [.text(syncRun), .text("thread:" + ref)]).stringValue
        }
        let id = OrbitID.make()
        try db.run(
            """
            INSERT INTO assertion (id, subject_id, predicate, object_entity_id, object_value, verbatim,
                                   valid_from, valid_to, date_precision, observed_at, source_event_id,
                                   source_kind, attributed_to_person_id, confidence, thread_id)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            [.text(id), .from(subject), .text(p.predicate), .from(entity), .from(objectValue),
             .text(p.verbatim), .from(p.validFrom), .from(p.validTo), .text(p.datePrecision),
             .text(try observedAt(ofSyncRun: syncRun)), .text(event), .text(p.sourceKind),
             .from(attributed), p.confidence.map { SQLValue.real($0) } ?? .null, .from(thread)])
        try store.rmInsertAssertion(id)
        return id
    }

    // MARK: - Ref resolution

    func resolvePerson(_ ref: PersonRef, syncRun: String) throws -> String {
        switch ref {
        case .id(let id): return id
        case .ref(let r):
            guard let id = try db.scalar(
                "SELECT person_id FROM sync_person_ref WHERE sync_run_id=? AND ref=?",
                [.text(syncRun), .text(r)]).stringValue else {
                throw WriteError.pendingDependency("accept the new-person card for '\(r)' first")
            }
            return id
        }
    }

    func resolveEntity(_ ref: EntityRef, syncRun: String) throws -> String {
        switch ref {
        case .id(let id): return id
        case .ref(let r):
            guard let id = try db.scalar(
                "SELECT entity_id FROM sync_entity_ref WHERE sync_run_id=? AND ref=?",
                [.text(syncRun), .text(r)]).stringValue else {
                throw WriteError.pendingDependency("accept the entity card for '\(r)' first")
            }
            return id
        }
    }

    func eventID(ofSyncRun id: String) throws -> String {
        guard let e = try db.scalar("SELECT event_id FROM sync_run WHERE id=?", [.text(id)]).stringValue else {
            throw WriteError.notFound("sync_run \(id)")
        }
        return e
    }

    func observedAt(ofSyncRun id: String) throws -> String {
        let t = try db.scalar(
            "SELECT e.occurred_at FROM sync_run s JOIN event e ON e.id=s.event_id WHERE s.id=?",
            [.text(id)])
        return t.stringValue ?? now
    }

    // MARK: - §7.3 first-meeting reconfirmation

    /// Called by the sync engine when a `known_of` person appears with PRESENT
    /// attendance for the first time: promote immediately (meeting someone must
    /// never become a chore), flag every secondhand fact for reconfirmation —
    /// visible, never quarantined.
    public func promoteOnFirstMeeting(person: String) throws {
        try db.transaction {
            try db.run("UPDATE person SET status='active' WHERE id=? AND status IN ('known_of','provisional')",
                       [.text(person)])
            try db.run(
                "UPDATE assertion SET needs_reconfirmation=1 WHERE subject_id=? AND source_kind='secondhand' AND status='active'",
                [.text(person)])
            try db.run(
                "UPDATE rm_current_state SET needs_reconfirmation=1 WHERE subject_id=? AND source_kind='secondhand'",
                [.text(person)])
        }
    }
}
