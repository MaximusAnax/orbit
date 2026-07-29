import XCTest
import OrbitCore
import OrbitSQLite
import OrbitStore
@testable import OrbitWrite

/// L0 — the EVALS.md invariant suite, run through the production write path.
/// The SQL-level twins live in scripts/dev/sql_properties.py (T1); these tests
/// prove the Swift services uphold the same contract (T2).
final class InvariantTests: XCTestCase {
    var store: WriteStore!
    var edits: UserEditService!
    var proposals: ProposalResolutionService!
    var reader: StoreReader { store.reader }

    override func setUpWithError() throws {
        store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        edits = UserEditService(store)
        proposals = ProposalResolutionService(store)
    }

    // MARK: helpers

    @discardableResult
    func person(_ name: String, status: PersonStatus = .active, isSelf: Bool = false) throws -> String {
        try edits.createPerson(displayName: name, status: status, isSelf: isSelf)
    }

    @discardableResult
    func confirmedEvent(with people: [String], kind: EventKind = .dinner,
                        occurred: String = "2026-07-01T20:00:00Z",
                        transcript: String = "we talked") throws -> String {
        let id = try edits.captureEvent(.init(
            kind: kind, occurredAt: occurred, transcript: transcript,
            participants: people.map { ($0, .confirmed, nil) }))
        try edits.confirmEvent(id, fullModelTranscribed: true)
        return id
    }

    /// Route a single proposal through the funnel and accept it.
    @discardableResult
    func accepted(op: ProposalOp, payload: some Encodable, event: String,
                  targetAssertion: String? = nil) throws -> String {
        let x = try proposals.recordExtraction(event: event, version: 1, modelID: "test",
                                               promptVersion: "v1", payload: "{}")
        let run = try proposals.openSyncRun(event: event, extraction: x)
        let pid = try proposals.propose(syncRun: run, .init(
            op: op, payloadJSON: try PayloadCoding.encode(payload),
            rationale: "test", targetAssertion: targetAssertion))!
        try proposals.resolve(proposal: pid, .accept)
        return pid
    }

    func assertAborts(_ sql: String, _ bindings: [SQLValue] = [],
                      _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try store.db.run(sql, bindings), message, file: file, line: line)
    }

    // MARK: INV-1..3 — history is never rewritten

    func testINV1_confirmedEventFrozen() throws {
        let p = try person("Sarah")
        let e = try confirmedEvent(with: [p], transcript: "original")
        assertAborts("UPDATE event SET transcript='rewritten' WHERE id=?", [.text(e)],
                     "INV-1: transcript frozen after confirmation")
        assertAborts("DELETE FROM event WHERE id=?", [.text(e)], "INV-1: events never deleted")
        // the one allowed mutation: audio deletion
        try store.db.run("UPDATE event SET raw_audio_ref=NULL WHERE id=?", [.text(e)])
    }

    func testINV1_INV3_assertionTransitions() throws {
        let p = try person("Sarah")
        let e = try confirmedEvent(with: [p])
        _ = try accepted(op: .assert, payload: AssertPayload(
            subject: .id(p), predicate: "employment", objectValue: "Google",
            verbatim: "works at Google", validFrom: "2024-01-01"), event: e)
        let aid = try reader.currentState(of: p).first!.text("assertion_id")!
        assertAborts("UPDATE assertion SET verbatim='x' WHERE id=?", [.text(aid)], "INV-1 verbatim frozen")
        assertAborts("DELETE FROM assertion WHERE id=?", [.text(aid)], "INV-1 no delete")
        // CLOSE through the funnel: valid_to only (INV-3)
        _ = try accepted(op: .close, payload: ClosePayload(validTo: "2026-06-01"),
                         event: e, targetAssertion: aid)
        XCTAssertEqual(try reader.currentState(of: p).count, 0, "closed facts leave current state")
        let stillThere = try store.db.scalar("SELECT COUNT(*) FROM assertion WHERE id=?", [.text(aid)])
        XCTAssertEqual(stillThere.intValue, 1, "closed facts remain in the ledger")
    }

    func testINV2_retractedStaysInAudit() throws {
        let p = try person("Maria")
        let e = try confirmedEvent(with: [p])
        _ = try accepted(op: .assert, payload: AssertPayload(
            subject: .id(p), predicate: "employment", objectValue: "Google",
            verbatim: "works at Google"), event: e)
        let aid = try reader.currentState(of: p).first!.text("assertion_id")!
        _ = try accepted(op: .correct, payload: CorrectPayload(reason: "I was wrong — she never worked there"),
                         event: e, targetAssertion: aid)
        XCTAssertEqual(try reader.currentState(of: p).count, 0)
        let audit = try reader.audit(of: p)
        XCTAssertEqual(audit.count, 1)
        XCTAssertEqual(audit[0].text("status"), "retracted")
        XCTAssertNotNil(audit[0].text("retraction_reason"))
    }

    // MARK: INV-4 — incremental read models ≡ full rebuild

    func testINV4_incrementalEqualsRebuild() throws {
        let sarah = try person("Sarah")
        let alex = try person("Alex")
        let e = try confirmedEvent(with: [sarah, alex])
        _ = try accepted(op: .assert, payload: AssertPayload(
            subject: .id(sarah), predicate: "interest", objectValue: "videography",
            verbatim: "really wants to learn videography"), event: e)
        _ = try accepted(op: .assert, payload: AssertPayload(
            subject: .id(alex), predicate: "employment", objectValue: "Stripe",
            verbatim: "at Stripe"), event: e)
        let incremental = try ReadModels.fingerprint(on: store.db)
        try ReadModels.rebuild(on: store.db)
        let rebuilt = try ReadModels.fingerprint(on: store.db)
        XCTAssertEqual(incremental.map { $0.map(\.values) }, rebuilt.map { $0.map(\.values) },
                       "INV-4: incremental maintenance must equal drop-and-rebuild")
    }

    // MARK: INV-5/6 — nothing final without confirmation; upgrades only propose

    func testINV5_pendingProposalTouchesNothing() throws {
        let p = try person("Sarah")
        let e = try confirmedEvent(with: [p])
        let x = try proposals.recordExtraction(event: e, version: 1, modelID: "m", promptVersion: "v1", payload: "{}")
        let run = try proposals.openSyncRun(event: e, extraction: x)
        _ = try proposals.propose(syncRun: run, .init(
            op: .assert,
            payloadJSON: try PayloadCoding.encode(AssertPayload(
                subject: .id(p), predicate: "interest", objectValue: "x", verbatim: "likes x")),
            rationale: "test"))
        XCTAssertEqual(try reader.currentState(of: p).count, 0,
                       "INV-5: a pending proposal changes nothing")
        XCTAssertEqual(try store.db.scalar("SELECT COUNT(*) FROM assertion").intValue, 0)
    }

    func testINV6_reExtractionOnlyAddsPending() throws {
        let p = try person("Sarah")
        let e = try confirmedEvent(with: [p])
        _ = try accepted(op: .assert, payload: AssertPayload(
            subject: .id(p), predicate: "interest", objectValue: "videography",
            verbatim: "wants to learn videography"), event: e)
        let before = try reader.audit(of: p).map(\.values)
        // model upgrade re-extracts the same event
        let x2 = try proposals.recordExtraction(event: e, version: 2, modelID: "better-model",
                                                promptVersion: "v2", payload: "{}")
        let run2 = try proposals.openSyncRun(event: e, extraction: x2)
        _ = try proposals.propose(syncRun: run2, .init(
            op: .assert,
            payloadJSON: try PayloadCoding.encode(AssertPayload(
                subject: .id(p), predicate: "goal", objectValue: "Japan", verbatim: "wants to visit Japan")),
            rationale: "missed by v1"))
        XCTAssertEqual(try reader.audit(of: p).map(\.values), before,
                       "INV-6: an improved model does not get write access to confirmed history")
    }

    // MARK: INV-7 — same-source rejections stay rejected

    func testINV7_sameSourceSuppression() throws {
        let p = try person("Sarah")
        let e = try confirmedEvent(with: [p])
        let payload = AssertPayload(subject: .id(p), predicate: "interest",
                                    objectValue: "golf", verbatim: "maybe likes golf")
        let x = try proposals.recordExtraction(event: e, version: 1, modelID: "m", promptVersion: "v1", payload: "{}")
        let run = try proposals.openSyncRun(event: e, extraction: x)
        let pid = try proposals.propose(syncRun: run, .init(
            op: .assert, payloadJSON: try PayloadCoding.encode(payload), rationale: "r"))!
        try proposals.resolve(proposal: pid, .reject(reason: .notWorthKeeping))
        // re-extraction over the SAME transcript
        let x2 = try proposals.recordExtraction(event: e, version: 2, modelID: "m2", promptVersion: "v1", payload: "{}")
        let run2 = try proposals.openSyncRun(event: e, extraction: x2)
        let resurrected = try proposals.propose(syncRun: run2, .init(
            op: .assert, payloadJSON: try PayloadCoding.encode(payload), rationale: "r"))
        XCTAssertNil(resurrected, "INV-7: same-source re-proposal of rejected content is suppressed")
        // a DIFFERENT event may legitimately re-propose, with disclosure
        let e2 = try confirmedEvent(with: [p], occurred: "2026-07-15T20:00:00Z")
        let x3 = try proposals.recordExtraction(event: e2, version: 1, modelID: "m", promptVersion: "v1", payload: "{}")
        let run3 = try proposals.openSyncRun(event: e2, extraction: x3)
        let again = try proposals.propose(syncRun: run3, .init(
            op: .assert, payloadJSON: try PayloadCoding.encode(payload), rationale: "r",
            priorRejectionNote: "you passed on something like this before — mentioned again at Tuesday's dinner"))
        XCTAssertNotNil(again, "INV-7: new evidence may re-propose (with disclosed history)")
    }

    // MARK: INV-8/9/10 — uncertainty stored, not resolved

    func testINV8_unresolvedSubjectNeverSurfaces() throws {
        let james = try person("James")
        let alex = try person("Alex")
        let e = try confirmedEvent(with: [james, alex])
        let x = try proposals.recordExtraction(event: e, version: 1, modelID: "m", promptVersion: "v1", payload: "{}")
        let run = try proposals.openSyncRun(event: e, extraction: x)
        let pid = try proposals.propose(syncRun: run, .init(
            op: .disambiguate,
            payloadJSON: try PayloadCoding.encode(DisambiguatePayload(
                question: "You mentioned someone works in AI infrastructure. Was this James?",
                candidates: [.id(james), .id(alex)],
                assertion: AssertPayload(subject: .ref("unknown"), predicate: "skill",
                                         objectValue: "AI infrastructure",
                                         verbatim: "works on AI infrastructure"))),
            rationale: "ambiguous attribution"))!
        try proposals.resolve(proposal: pid, .acceptUnresolved)
        XCTAssertEqual(try reader.currentState(of: james).count, 0)
        XCTAssertEqual(try reader.currentState(of: alex).count, 0)
        let held = try store.db.scalar(
            "SELECT COUNT(*) FROM assertion WHERE subject_id IS NULL").intValue
        XCTAssertEqual(held, 1, "the fact is held, attributed to nobody (Decision 5)")
    }

    func testINV9_knownOfScopeRestrictions() throws {
        let ghost = try person("Friend-of-friend", status: .knownOf)
        XCTAssertThrowsError(
            try edits.setRelationshipState(person: ghost, narrative: "x", orbit: .close),
            "known_of people never receive relationship machinery"
        ) { _ in }
        // NOTE: DB-level INV-23 covers self; known_of exclusion is service+query-level:
        // recall/suggestion queries filter status='active'. Covered further in Recall tests.
    }

    func testINV10_hearsayAttribution() throws {
        let sarah = try person("Sarah")
        let alex = try person("Alex")
        let e = try confirmedEvent(with: [alex])
        _ = try accepted(op: .assert, payload: AssertPayload(
            subject: .id(sarah), predicate: "life_event", objectValue: "engaged",
            verbatim: "Alex told me Sarah got engaged",
            sourceKind: "secondhand", attributedTo: .id(alex)), event: e)
        let fact = try reader.currentState(of: sarah).first!
        XCTAssertEqual(fact.text("source_kind"), "secondhand")
        XCTAssertEqual(fact.text("attributed_to_person_id"), alex)
    }

    // MARK: INV-11..14 — contact is sacred

    func testINV11_12_contactRhythmGuards() throws {
        let sarah = try person("Sarah")
        _ = try confirmedEvent(with: [sarah], occurred: "2026-07-03T20:00:00Z")
        // a note ABOUT sarah
        let note = try edits.captureEvent(.init(
            kind: .note, occurredAt: "2026-07-10T09:00:00Z", transcript: "remembered her birthday",
            participants: [(sarah, .about, nil)]))
        try edits.confirmEvent(note, fullModelTranscribed: true)
        let rhythm = try store.db.query(
            "SELECT month, event_count FROM rm_contact_rhythm WHERE person_id=?", [.text(sarah)])
        XCTAssertEqual(rhythm.count, 1)
        XCTAssertEqual(rhythm[0].int("event_count"), 1,
                       "INV-11: writing notes about Sarah must never look like seeing Sarah")
    }

    func testINV13_coAttendancePresentOnly() throws {
        let a = try person("A"), b = try person("B")
        let e = try edits.captureEvent(.init(
            kind: .coffee, occurredAt: "2026-07-05T10:00:00Z",
            participants: [(a, .confirmed, nil), (b, .about, nil)]))
        try edits.confirmEvent(e, fullModelTranscribed: true)
        let edges = try store.db.scalar(
            "SELECT COUNT(*) FROM rm_network_edge WHERE edge_kind='co_attendance'").intValue
        XCTAssertEqual(edges, 0, "INV-13: co-subjects of one note have not met")
    }

    func testINV14_firstMetNeverANote() throws {
        let sarah = try person("Sarah")
        let note = try edits.captureEvent(.init(
            kind: .note, occurredAt: "2026-07-10T09:00:00Z",
            participants: [(sarah, .about, nil)]))
        try edits.confirmEvent(note, fullModelTranscribed: true)
        XCTAssertThrowsError(try edits.setFirstMet(person: sarah, event: note))
        let dinner = try confirmedEvent(with: [sarah])
        try edits.setFirstMet(person: sarah, event: dinner)
    }

    // MARK: INV-17 — merge by pointer

    func testINV17_mergeUnmergeExact() throws {
        let winner = try person("Sarah Chen")
        let loser = try person("Sarah C.")
        let e = try confirmedEvent(with: [loser])
        _ = try accepted(op: .assert, payload: AssertPayload(
            subject: .id(loser), predicate: "interest", objectValue: "videography",
            verbatim: "wants to learn videography"), event: e)
        let before = try ReadModels.fingerprint(on: store.db).map { $0.map(\.values) }
        try edits.mergePerson(loser: loser, winner: winner)
        XCTAssertEqual(try reader.currentState(of: winner).count, 1, "merged facts surface under winner")
        XCTAssertEqual(try store.db.scalar(
            "SELECT COUNT(*) FROM assertion WHERE subject_id=?", [.text(loser)]).intValue, 1,
            "INV-17: zero assertion rows rewritten")
        try edits.unmergePerson(loser)
        let after = try ReadModels.fingerprint(on: store.db).map { $0.map(\.values) }
        XCTAssertEqual(before, after, "INV-17: unmerge restores pre-merge results exactly")
    }

    // MARK: INV-18/19 — provenance total; no person-less events

    func testINV18_provenanceTotal() throws {
        let orphans = try store.db.query(
            """
            SELECT 'assertion' AS t, COUNT(*) AS n FROM assertion WHERE source_event_id IS NULL
            UNION ALL SELECT 'thread', COUNT(*) FROM thread WHERE opened_event_id IS NULL
            UNION ALL SELECT 'loop', COUNT(*) FROM open_loop WHERE source_event_id IS NULL
            """)
        XCTAssertTrue(orphans.allSatisfy { ($0.int("n") ?? 0) == 0 })
    }

    func testINV19_eventRequiresParticipant() throws {
        XCTAssertThrowsError(try edits.captureEvent(.init(
            kind: .note, occurredAt: "2026-07-01T00:00:00Z", participants: [])),
            "an event about nobody is a diary entry, and Orbit is not a diary")
    }

    // MARK: INV-20 — hardship never prompts (type-level)

    func testINV20_hardshipNeverPrompts() throws {
        XCTAssertFalse(ThreadArchetype.conditionHardship.mayPrompt)
        XCTAssertNil(ThreadArchetype.conditionHardship.decayConversations,
                     "hardship threads never decay to silence either — they are remembered, not raised")
        XCTAssertFalse(ThreadArchetype.aspiration.mayPrompt, "aspirations surface forever, urgency never")
    }

    // MARK: INV-22/23/24 — the self and the state

    func testINV22_selfRules() throws {
        let me = try person("Abdoul", isSelf: true)
        XCTAssertThrowsError(try person("Impostor", isSelf: true), "exactly one self row")
        let e = try confirmedEvent(with: [me])
        _ = try accepted(op: .assert, payload: AssertPayload(
            subject: .id(me), predicate: "education", objectValue: "Carnegie Mellon",
            verbatim: "we both study CS at Carnegie Mellon"), event: e)
        XCTAssertEqual(try reader.currentState(of: me).count, 1, "self accumulates plain facts")
        XCTAssertThrowsError(try edits.mergePerson(loser: me, winner: try person("Other")))
    }

    func testINV23_selfExcludedFromRelationshipMachinery() throws {
        let me = try person("Abdoul", isSelf: true)
        XCTAssertThrowsError(try edits.setRelationshipState(person: me, narrative: "x", orbit: .inner))
        let e = try confirmedEvent(with: [me])
        let x = try proposals.recordExtraction(event: e, version: 1, modelID: "m", promptVersion: "v1", payload: "{}")
        let run = try proposals.openSyncRun(event: e, extraction: x)
        let pid = try proposals.propose(syncRun: run, .init(
            op: .openLoop,
            payloadJSON: try PayloadCoding.encode(OpenLoopPayload(
                person: .id(me), direction: "abdoul_owes", description: "x")),
            rationale: "r"))!
        XCTAssertThrowsError(try proposals.resolve(proposal: pid, .accept),
                             "INV-23 holds even through the proposal path")
    }

    func testINV24_proposeStateRequiresVerbatimQuote() throws {
        let eliah = try person("Eliah")
        let e = try edits.captureEvent(.init(
            kind: .portrait, occurredAt: "2026-07-28T21:00:00Z",
            transcript: "he would be in the inner, inner, inner circle, right there along with my family",
            participants: [(eliah, .about, nil)]))
        try edits.confirmEvent(e, fullModelTranscribed: true)
        let x = try proposals.recordExtraction(event: e, version: 1, modelID: "m", promptVersion: "v1", payload: "{}")
        let run = try proposals.openSyncRun(event: e, extraction: x)
        // no quote → Critical, refused at the funnel
        XCTAssertThrowsError(try proposals.propose(syncRun: run, .init(
            op: .proposeState,
            payloadJSON: try PayloadCoding.encode(ProposeStatePayload(
                person: .id(eliah), narrativeQuote: "ten minutes of warmth about him",
                suggestedOrbit: "inner", mappingRationale: "sounded close")),
            rationale: "r")), "INV-24: a state proposal without a verbatim quote is Critical")
        // with the quote → flows, and lands authored_by human on acceptance
        let pid = try proposals.propose(syncRun: run, .init(
            op: .proposeState,
            payloadJSON: try PayloadCoding.encode(ProposeStatePayload(
                person: .id(eliah),
                narrativeQuote: "he would be in the inner, inner, inner circle, right there along with my family",
                suggestedOrbit: "inner",
                mappingRationale: "explicit inner-circle declaration")),
            rationale: "he said it in his own words"))!
        try proposals.resolve(proposal: pid, .accept)
        let state = try store.db.query(
            "SELECT * FROM relationship_state WHERE person_id=?", [.text(eliah)]).first!
        XCTAssertEqual(state.text("authored_by"), "human", "the words were his; the AI only moved them")
        XCTAssertEqual(state.text("source_event_id"), e, "provenance stays total")
    }

    // MARK: Decision 4 — derived sync status, partial resolution is normal

    func testDerivedSyncStatus() throws {
        let p = try person("Sarah")
        let e = try confirmedEvent(with: [p])
        XCTAssertEqual(try reader.syncStatus(of: e), "unsynced")
        let x = try proposals.recordExtraction(event: e, version: 1, modelID: "m", promptVersion: "v1", payload: "{}")
        let run = try proposals.openSyncRun(event: e, extraction: x)
        var ids: [String] = []
        for i in 0..<3 {
            ids.append(try proposals.propose(syncRun: run, .init(
                op: .assert,
                payloadJSON: try PayloadCoding.encode(AssertPayload(
                    subject: .id(p), predicate: "interest", objectValue: "topic\(i)",
                    verbatim: "likes topic\(i)")),
                rationale: "r"))!)
        }
        XCTAssertEqual(try reader.syncStatus(of: e), "in_review")
        try proposals.resolve(proposal: ids[0], .accept)
        try proposals.resolve(proposal: ids[1], .reject(reason: nil))
        try proposals.resolve(proposal: ids[2], .defer_)
        XCTAssertEqual(try reader.syncStatus(of: e), "partially_resolved",
                       "an event may sit half-reviewed indefinitely at no cost")
        try proposals.resolve(proposal: ids[2], .accept)
        XCTAssertEqual(try reader.syncStatus(of: e), "fully_resolved")
    }

    // MARK: §7.3 — first meeting: promote + flag, never quarantine

    func testKnownOfPromotionAndReconfirmation() throws {
        let alex = try person("Alex")
        let sarah = try person("Sarah (of Alex)", status: .knownOf)
        let heard = try confirmedEvent(with: [alex])
        _ = try accepted(op: .assert, payload: AssertPayload(
            subject: .id(sarah), predicate: "employment", objectValue: "Stripe",
            verbatim: "Alex says she's at Stripe", sourceKind: "secondhand",
            attributedTo: .id(alex)), event: heard)
        // first real meeting
        _ = try confirmedEvent(with: [sarah], occurred: "2026-07-20T19:00:00Z")
        try proposals.promoteOnFirstMeeting(person: sarah)
        let row = try reader.person(sarah)!
        XCTAssertEqual(row.text("status"), "active", "a real relationship the moment they are met")
        let fact = try reader.currentState(of: sarah).first!
        XCTAssertEqual(fact.int("needs_reconfirmation"), 1, "flagged, still visible — never quarantined")
    }

    // MARK: worked example (§3) through the full funnel

    func testWorkedExampleThroughServices() throws {
        let sarah = try person("Sarah")
        let e0 = try confirmedEvent(with: [sarah], occurred: "2025-05-10T19:00:00Z")
        _ = try accepted(op: .assert, payload: AssertPayload(
            subject: .id(sarah), predicate: "employment", objectValue: "Google",
            verbatim: "works at Google", validFrom: "2024-01-01"), event: e0)
        let googleID = try reader.currentState(of: sarah).first!.text("assertion_id")!

        let dinner = try confirmedEvent(with: [sarah], occurred: "2026-07-28T20:00:00Z",
                                        transcript: "I had dinner with Sarah tonight…")
        let x = try proposals.recordExtraction(event: dinner, version: 1, modelID: "m", promptVersion: "v1", payload: "{}")
        let run = try proposals.openSyncRun(event: dinner, extraction: x)

        let assertStripe = try proposals.propose(syncRun: run, .init(
            op: .assert,
            payloadJSON: try PayloadCoding.encode(AssertPayload(
                subject: .id(sarah), predicate: "employment", objectValue: "Stripe",
                verbatim: "works at Stripe now", validFrom: "2026-06-01")),
            rationale: "she told you at dinner"))!
        let closeGoogle = try proposals.propose(syncRun: run, .init(
            op: .close, payloadJSON: try PayloadCoding.encode(ClosePayload(validTo: "2026-06-01")),
            rationale: "she left Google when she joined Stripe", targetAssertion: googleID))!
        let boston = try proposals.propose(syncRun: run, .init(
            op: .assert,
            payloadJSON: try PayloadCoding.encode(AssertPayload(
                subject: .id(sarah), predicate: "goal", objectValue: "Boston",
                verbatim: "thinking about moving to Boston next year", datePrecision: "year")),
            rationale: "thinking about, so a goal — not a location"))!
        let loop = try proposals.propose(syncRun: run, .init(
            op: .openLoop,
            payloadJSON: try PayloadCoding.encode(OpenLoopPayload(
                person: .id(sarah), direction: "abdoul_owes",
                description: "send her the AI agents paper")),
            rationale: "you said you'd send it"))!
        let thread = try proposals.propose(syncRun: run, .init(
            op: .openThread,
            payloadJSON: try PayloadCoding.encode(OpenThreadPayload(
                ref: "t1", person: .id(sarah), title: "Boston move", archetype: "decision")),
            rationale: "an open decision in her life"))!

        try proposals.resolve(proposal: assertStripe, .accept)
        try proposals.resolve(proposal: closeGoogle, .accept)
        try proposals.resolve(proposal: boston, .acceptEdited(payloadJSON: PayloadCoding.encode(
            AssertPayload(subject: .id(sarah), predicate: "goal", objectValue: "Boston",
                          verbatim: "thinking about moving to Boston next year",
                          datePrecision: "year", confidence: 0.5))))
        try proposals.resolve(proposal: loop, .accept)
        try proposals.resolve(proposal: thread, .defer_)

        // Six months later: where did Sarah work in 2024? → Google
        let then = try reader.facts(of: sarah, validAt: "2024-06-15")
        XCTAssertEqual(then.map { $0.text("object_value") }, ["Google"])
        // …and now? → Stripe
        let current = try reader.currentState(of: sarah)
            .filter { $0.text("predicate") == "employment" }
        XCTAssertEqual(current.map { $0.text("object_value") }, ["Stripe"])
        XCTAssertEqual(try reader.syncStatus(of: dinner), "partially_resolved")
        // J-12: five decisions, five harvest rows
        XCTAssertEqual(try store.db.scalar("SELECT COUNT(*) FROM review_outcome").intValue, 5)
    }
}
