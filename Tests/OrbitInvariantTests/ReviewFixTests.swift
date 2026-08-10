import XCTest
import OrbitCore
import OrbitSQLite
import OrbitStore
@testable import OrbitWrite

/// Regression pins from the full-build review pass: each test here anchors a
/// fix that shipped without a covering test (bind-count on knownBy, merge-chain
/// flattening, INV-7 semantic identity, INV-19 for reconstructed episodes).
final class ReviewFixTests: XCTestCase {
    var store: WriteStore!
    var edits: UserEditService!
    var proposals: ProposalResolutionService!
    var reader: StoreReader { store.reader }

    override func setUpWithError() throws {
        store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        edits = UserEditService(store)
        proposals = ProposalResolutionService(store)
    }

    @discardableResult
    func person(_ name: String, status: PersonStatus = .active) throws -> String {
        try edits.createPerson(displayName: name, status: status)
    }

    @discardableResult
    func confirmedEvent(with people: [String], transcript: String = "we talked") throws -> String {
        let id = try edits.captureEvent(.init(
            kind: .dinner, occurredAt: "2026-07-01T20:00:00Z", transcript: transcript,
            participants: people.map { ($0, .confirmed, nil) }))
        try edits.confirmEvent(id, fullModelTranscribed: true)
        return id
    }

    func syncRun(on event: String) throws -> String {
        let x = try proposals.recordExtraction(event: event, version: 1, modelID: "test",
                                               promptVersion: "v1", payload: "{}")
        return try proposals.openSyncRun(event: event, extraction: x)
    }

    // MARK: observation-time query (the bind-count fix)

    func testKnownByIsObservationTime() throws {
        let sarah = try person("Sarah")
        let event = try confirmedEvent(with: [sarah], transcript: "Sarah moved to Berlin")
        let run = try syncRun(on: event)
        let pid = try proposals.propose(syncRun: run, .init(
            op: .assert,
            payloadJSON: try PayloadCoding.encode(AssertPayload(
                subject: .id(sarah), predicate: "location", objectValue: "Berlin",
                verbatim: "Sarah moved to Berlin", validFrom: "2020-01")),
            rationale: "test"))!
        try proposals.resolve(proposal: pid, .accept)

        // valid since 2020, but only OBSERVED at the fixed clock (2026-07-29):
        // knownBy before the observation shows nothing, after shows the fact.
        XCTAssertTrue(try reader.facts(of: sarah, knownBy: "2026-01-01").isEmpty,
                      "a fact is not known before it was observed")
        let after = try reader.facts(of: sarah, knownBy: "2026-12-31")
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.text("object_value"), "Berlin")
        // while validity-time sees it at any date inside the validity window
        XCTAssertEqual(try reader.facts(of: sarah, validAt: "2021-06-01").count, 1)
    }

    // MARK: merge chains flatten at write time (Decision 6)

    func testMergeChainFlattensToCanonicalWinner() throws {
        let a = try person("Sara")
        let b = try person("Sarah")
        let c = try person("Sarah Chen")
        try edits.mergePerson(loser: a, winner: b)
        try edits.mergePerson(loser: b, winner: c)

        // the earlier loser is re-pointed at the final winner — one hop, no chain
        let aPointer = try store.db.scalar(
            "SELECT merged_into FROM person WHERE id=?", [.text(a)]).stringValue
        XCTAssertEqual(aPointer, c, "merge pointers flatten: a → c directly, never a → b → c")
        XCTAssertEqual(try reader.canonicalPerson(a), c)
        XCTAssertEqual(try reader.canonicalPerson(b), c)

        // merging into a merged row lands on its canonical target
        let d = try person("S. Chen")
        try edits.mergePerson(loser: d, winner: b)   // b is merged — winner resolves to c
        let dPointer = try store.db.scalar(
            "SELECT merged_into FROM person WHERE id=?", [.text(d)]).stringValue
        XCTAssertEqual(dPointer, c, "a merged winner resolves to its canonical row")
    }

    // MARK: INV-7 — rejection suppresses the CLAIM, not the payload bytes

    func testINV7_rewordedSameClaimStaysSuppressed() throws {
        let sarah = try person("Sarah")
        let event = try confirmedEvent(with: [sarah], transcript: "Sarah works at Google now")
        let run1 = try syncRun(on: event)
        let pid = try proposals.propose(syncRun: run1, .init(
            op: .assert,
            payloadJSON: try PayloadCoding.encode(AssertPayload(
                subject: .id(sarah), predicate: "employer", objectValue: "Google",
                verbatim: "Sarah works at Google now")),
            rationale: "first extraction"))!
        try proposals.resolve(proposal: pid, .reject(reason: .notTrue))

        // a re-extraction of the SAME event: same predicate + verbatim, but the
        // payload bytes differ (valid_from added). Same claim → suppressed.
        let run2 = try syncRun(on: event)
        let reproposed = try proposals.propose(syncRun: run2, .init(
            op: .assert,
            payloadJSON: try PayloadCoding.encode(AssertPayload(
                subject: .id(sarah), predicate: "employer", objectValue: "Google",
                verbatim: "Sarah works at Google now", validFrom: "2026-07")),
            rationale: "re-extraction, reworded rationale"))
        XCTAssertNil(reproposed, "INV-7: the same claim from the same source stays rejected")

        // a DIFFERENT claim from the same source is not suppressed
        let other = try proposals.propose(syncRun: run2, .init(
            op: .assert,
            payloadJSON: try PayloadCoding.encode(AssertPayload(
                subject: .id(sarah), predicate: "location", objectValue: "Berlin",
                verbatim: "she's in Berlin these days")),
            rationale: "different claim"))
        XCTAssertNotNil(other)
    }

    // MARK: INV-19 — reconstructed episodes need participants too

    func testCreateEventRejectsEmptyParticipants() throws {
        let sarah = try person("Sarah")
        let portrait = try confirmedEvent(with: [sarah], transcript: "we met at the picnic")
        let run = try syncRun(on: portrait)
        let pid = try proposals.propose(syncRun: run, .init(
            op: .createEvent,
            payloadJSON: try PayloadCoding.encode(CreateEventPayload(
                occurredAt: "2024-06", datePrecision: "month", kind: "encounter",
                title: nil, narrative: "we met at the picnic", participants: [])),
            rationale: "episode about nobody"))!
        XCTAssertThrowsError(try proposals.resolve(proposal: pid, .accept)) { error in
            guard case WriteError.constitutionViolation(let msg) = error else {
                return XCTFail("expected constitutionViolation, got \(error)")
            }
            XCTAssertTrue(msg.contains("INV-19"))
        }
    }
}
