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
}
