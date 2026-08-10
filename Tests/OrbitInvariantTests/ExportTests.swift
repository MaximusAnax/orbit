import XCTest
import Foundation
import OrbitCore
import OrbitSQLite
import OrbitStore
@testable import OrbitWrite

/// PRIV-5: a complete, human-readable archive; restore into a fresh install
/// passes INV-4 equivalence (the archive carries the log; read models rebuild).
final class ExportTests: XCTestCase {

    func testExportRestoreRoundTrip() throws {
        let store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        let edits = UserEditService(store)
        let proposals = ProposalResolutionService(store)

        let sarah = try edits.createPerson(displayName: "Sarah")
        let event = try edits.captureEvent(.init(
            kind: .dinner, occurredAt: "2026-07-01T20:00:00Z",
            transcript: "Sarah moved to Berlin", participants: [(sarah, .confirmed, nil)]))
        try edits.confirmEvent(event, fullModelTranscribed: true)
        let x = try proposals.recordExtraction(event: event, version: 1, modelID: "test",
                                               promptVersion: "v1", payload: "{}")
        let run = try proposals.openSyncRun(event: event, extraction: x)
        let pid = try proposals.propose(syncRun: run, .init(
            op: .assert,
            payloadJSON: try PayloadCoding.encode(AssertPayload(
                subject: .id(sarah), predicate: "location", objectValue: "Berlin",
                verbatim: "Sarah moved to Berlin", validFrom: "2026-06")),
            rationale: "test"))!
        try proposals.resolve(proposal: pid, .accept)

        // export: complete and human-readable
        let archive = try Export.dump(from: store.db)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, "orbit-archive")
        let text = String(decoding: archive, as: UTF8.self)
        XCTAssertTrue(text.contains("Sarah moved to Berlin"),
                      "the archive is readable by a human, verbatims in the clear")

        // restore into a fresh install
        let fresh = try Database.openWriterInMemory()
        try Schema.create(on: fresh)
        try Export.restore(archive, into: fresh)

        // INV-4 equivalence: rebuilt read models match the original's
        let a = try ReadModels.fingerprint(on: store.db)
        let b = try ReadModels.fingerprint(on: fresh)
        XCTAssertEqual(a.count, b.count)
        for (ta, tb) in zip(a, b) {
            XCTAssertEqual(ta.count, tb.count, "read-model row counts equal after restore")
            for (ra, rb) in zip(ta, tb) {
                XCTAssertEqual(ra.values, rb.values)
            }
        }
        // and the log itself round-tripped
        for table in ["person", "event", "assertion", "proposal", "review_outcome"] {
            let na = try store.db.scalar("SELECT COUNT(*) FROM \(table)").intValue
            let nb = try fresh.scalar("SELECT COUNT(*) FROM \(table)").intValue
            XCTAssertEqual(na, nb, "\(table) rows survive the round trip")
        }
    }

    /// The richer half of PRIV-5: first-met pointers, contact points, and merge
    /// pointers survive restore — these cross-reference person↔event rows, so
    /// they pin the restore's insertion order (person after event_participant,
    /// defer_foreign_keys inside one transaction).
    func testRichArchiveRoundTrip() throws {
        let store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        let edits = UserEditService(store)

        let sara = try edits.createPerson(displayName: "Sara")
        let sarah = try edits.createPerson(displayName: "Sarah Chen")
        let met = try edits.captureEvent(.init(
            kind: .coffee, occurredAt: "2026-05-10T09:00:00Z",
            transcript: "first coffee with Sarah",
            participants: [(sarah, .confirmed, nil)]))
        try edits.confirmEvent(met, fullModelTranscribed: true)
        try edits.setFirstMet(person: sarah, event: met)
        _ = try edits.addContactPoint(person: sarah, kind: .email,
                                      value: "sarah@example.com", source: .manual)
        try edits.mergePerson(loser: sara, winner: sarah)

        let archive = try Export.dump(from: store.db)
        let fresh = try Database.openWriterInMemory()
        try Schema.create(on: fresh)
        try Export.restore(archive, into: fresh)

        XCTAssertEqual(
            try fresh.scalar("SELECT first_met_event_id FROM person WHERE id=?",
                             [.text(sarah)]).stringValue,
            met, "first-met pointer survives restore")
        XCTAssertEqual(
            try fresh.scalar("SELECT merged_into FROM person WHERE id=?",
                             [.text(sara)]).stringValue,
            sarah, "merge pointer survives restore")
        XCTAssertEqual(
            try fresh.scalar("SELECT COUNT(*) FROM contact_point WHERE person_id=?",
                             [.text(sarah)]).intValue,
            1, "contact points survive restore")

        // INV-4 equivalence holds on the richer graph too
        let a = try ReadModels.fingerprint(on: store.db)
        let b = try ReadModels.fingerprint(on: fresh)
        for (ta, tb) in zip(a, b) {
            XCTAssertEqual(ta.count, tb.count)
            for (ra, rb) in zip(ta, tb) {
                XCTAssertEqual(ra.values, rb.values)
            }
        }
    }
}
