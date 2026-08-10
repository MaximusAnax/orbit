import XCTest
import OrbitCore
import OrbitSQLite
import OrbitStore
import OrbitWrite
@testable import OrbitPipeline

/// L1 — the pipeline through the real funnel, using the recorded corpus fixtures.
final class PipelineTests: XCTestCase {
    static var root: URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir = dir.deletingLastPathComponent() }   // Tests/OrbitPipelineTests/file
        return dir
    }

    func fixture(_ memo: String) throws -> (ReplayExtractor.Fixture, String) {
        let url = Self.root.appendingPathComponent("docs/evals/fixtures/\(memo).json")
        let data = try Data(contentsOf: url)
        let fix = try JSONDecoder().decode(ReplayExtractor.Fixture.self, from: data)
        let meta = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let transcript = try String(
            contentsOf: Self.root.appendingPathComponent(meta["source"] as! String),
            encoding: .utf8)
        return (fix, transcript)
    }

    func makeStore() throws -> (WriteStore, UserEditService, ProposalResolutionService) {
        let store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        let edits = UserEditService(store)
        _ = try edits.createPerson(displayName: "Abdoul", isSelf: true)
        return (store, edits, ProposalResolutionService(store))
    }

    /// The Eliah golden, end to end: sync → review-accept in dependency order →
    /// the ledger holds the portrait per DATA-MODEL §7.11/7.12/7.13.
    func testEliahPortraitFullReview() throws {
        let (store, edits, proposals) = try makeStore()
        let (fix, transcript) = try fixture("eliah")

        let eliahAnchor = try edits.createPerson(displayName: "(portrait subject pending)")
        let portrait = try edits.captureEvent(.init(
            kind: .portrait, occurredAt: "2026-07-28T21:00:00Z",
            transcript: transcript, participants: [(eliahAnchor, .about, nil)]))
        try edits.confirmEvent(portrait, fullModelTranscribed: true)

        let outcome = try SyncEngine(store).sync(
            event: portrait, extractionVersion: 1,
            result: .init(payload: fix.payload, modelID: fix.modelID, promptVersion: fix.promptVersion))
        XCTAssertGreaterThan(outcome.proposalIDs.count, 30, "a decade of friendship yields a rich review")

        // Accept in dependency order: people/entities first, then everything else.
        let rows = try store.db.query(
            "SELECT id, op FROM proposal WHERE state='pending' ORDER BY CASE op WHEN 'CREATE_PERSON' THEN 0 WHEN 'LINK' THEN 1 WHEN 'OPEN_THREAD' THEN 2 ELSE 3 END, id")
        for row in rows {
            let id = row.text("id")!
            if row.text("op") == "DISAMBIGUATE" {
                try proposals.resolve(proposal: id, .defer_)   // partial resolution is normal
            } else {
                try proposals.resolve(proposal: id, .accept)
            }
        }

        let reader = store.reader
        // one Eliah, with facts under him
        let eliah = try store.db.query(
            "SELECT id FROM person WHERE display_name LIKE '%Tapia%'")
        XCTAssertEqual(eliah.count, 1, "identity: exactly one subject person")
        let eliahID = eliah[0].text("id")!
        XCTAssertGreaterThan(try reader.currentState(of: eliahID).count, 10)

        // self facts landed on the self row (INV-22)
        let selfID = try reader.selfPerson()!.text("id")!
        let selfFacts = try reader.currentState(of: selfID)
        XCTAssertTrue(selfFacts.contains { ($0.text("verbatim") ?? "").contains("Bronx") })
        XCTAssertEqual(try store.db.scalar(
            "SELECT COUNT(*) FROM person WHERE display_name='Abdoul'").intValue, 1)

        // the Google internship is a CLOSED interval (the tense trap)
        let google = try reader.currentState(of: eliahID)
            .filter { ($0.text("verbatim") ?? "").contains("interning at Google") }
        XCTAssertTrue(google.isEmpty, "closed intervals never appear as current facts")
        let googleAudit = try reader.audit(of: eliahID)
            .filter { ($0.text("verbatim") ?? "").contains("interning at Google") }
        XCTAssertEqual(googleAudit.count, 1)
        XCTAssertNotNil(googleAudit[0].text("valid_to"))

        // three reconstructed episodes exist, confirmed, derived-from the portrait —
        // and none of them count as contact (INV-12)
        let episodes = try store.db.query(
            "SELECT id FROM event WHERE derived_from_event_id=?", [.text(portrait)])
        XCTAssertEqual(episodes.count, 3)
        let rhythm = try store.db.scalar(
            "SELECT COALESCE(SUM(event_count),0) FROM rm_contact_rhythm WHERE person_id=?",
            [.text(eliahID)])
        XCTAssertEqual(rhythm.intValue, 0, "reconstructed history never enters rate math")

        // the relationship state carries his exact words, authored_by human (§7.13)
        let state = try store.db.query(
            "SELECT * FROM relationship_state WHERE person_id=?", [.text(eliahID)])
        XCTAssertEqual(state.count, 1)
        XCTAssertTrue((state[0].text("narrative") ?? "").contains("inner, inner, inner circle"))
        XCTAssertEqual(state[0].text("authored_by"), "human")
        XCTAssertEqual(state[0].text("orbit"), "inner")

        // first-met falls out naturally: link it to the reconstructed met-event
        let met = episodes[0].text("id")!
        try edits.setFirstMet(person: eliahID, event: met)

        // INV-4 still holds after the whole flow
        let inc = try ReadModels.fingerprint(on: store.db).map { $0.map(\.values) }
        try ReadModels.rebuild(on: store.db)
        let reb = try ReadModels.fingerprint(on: store.db).map { $0.map(\.values) }
        XCTAssertEqual(inc, reb)
    }

    /// INV-7 through the pipeline: reject once, re-sync same transcript, gone.
    func testSameSourceSuppressionThroughSync() throws {
        let (store, edits, proposals) = try makeStore()
        let (fix, transcript) = try fixture("nikos")
        let anchor = try edits.createPerson(displayName: "anchor")
        let event = try edits.captureEvent(.init(
            kind: .encounter, occurredAt: "2026-07-24T18:00:00Z",
            transcript: transcript, participants: [(anchor, .confirmed, nil)]))
        try edits.confirmEvent(event, fullModelTranscribed: true)

        let engine = SyncEngine(store)
        let first = try engine.sync(event: event, extractionVersion: 1,
                                    result: .init(payload: fix.payload, modelID: "m", promptVersion: "v1"))
        for id in first.proposalIDs {
            try proposals.resolve(proposal: id, .reject(reason: .notWorthKeeping))
        }
        let second = try engine.sync(event: event, extractionVersion: 2,
                                     result: .init(payload: fix.payload, modelID: "m2", promptVersion: "v1"))
        XCTAssertEqual(second.proposalIDs.count, 0, "INV-7/PIPE-8: nothing resurrects from the same source")
        XCTAssertEqual(second.suppressedCount, first.proposalIDs.count)
    }
}
