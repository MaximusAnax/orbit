import XCTest
import OrbitCore
import OrbitSQLite
import OrbitStore
@testable import OrbitWrite

/// FIELD-NOTES FN-29 — removing a person is retiring them, and nothing more.
///
/// A hard erase was designed and dropped: it would have needed a named
/// exception in all twelve append-only triggers, which is INV-1 weakened
/// permanently to tidy a list. What these tests pin is the promise that makes
/// retiring safe to do on a hunch — that it destroys nothing.
final class PersonRemovalTests: XCTestCase {
    var store: WriteStore!
    var edits: UserEditService!

    override func setUpWithError() throws {
        store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        edits = UserEditService(store)
    }

    /// A person, a fact about them, and an event they attended alone.
    private func seedSoloPerson() throws -> (person: String, event: String, assertion: String) {
        let person = try edits.createPerson(displayName: "Dara")
        let event = try edits.captureEvent(.init(
            kind: .encounter, occurredAt: "2026-07-20T10:00:00Z",
            transcript: "coffee with Dara", audioRef: "/tmp/orbit-test-dara.m4a",
            participants: [(person, .confirmed, nil)]))
        try edits.confirmEvent(event, fullModelTranscribed: false)
        let assertion = try store.db.query(
            """
            INSERT INTO assertion (id, subject_id, predicate, object_value, verbatim,
                                   date_precision, observed_at, source_event_id, source_kind)
            VALUES ('a-dara', ?, 'interest', 'climbing', 'she climbs', 'fuzzy',
                    '2026-07-20T10:00:00Z', ?, 'firsthand') RETURNING id
            """, [.text(person), .text(event)]).first?.text("id") ?? ""
        return (person, event, assertion)
    }

    // MARK: retire — withdraws presence, keeps everything

    func testRetiringKeepsEveryFactAndEvent() throws {
        let seed = try seedSoloPerson()
        try edits.retirePerson(seed.person)

        XCTAssertNotNil(try store.reader.person(seed.person),
                        "the person row survives — retiring is not a delete")
        XCTAssertEqual(try store.db.scalar(
            "SELECT COUNT(*) FROM assertion WHERE id=?", [.text(seed.assertion)]).intValue, 1,
            "their facts stay in the ledger")
        XCTAssertEqual(try store.db.scalar(
            "SELECT COUNT(*) FROM event WHERE id=?", [.text(seed.event)]).intValue, 1,
            "the event stays too")
        XCTAssertEqual(try store.db.scalar(
            "SELECT COUNT(*) FROM person_retirement WHERE person_id=?",
            [.text(seed.person)]).intValue, 1)
    }

    func testRetiringIsReversibleAndRepeatable() throws {
        let seed = try seedSoloPerson()
        try edits.retirePerson(seed.person)
        try edits.retirePerson(seed.person)   // must not throw on a second call
        try edits.unretirePerson(seed.person)
        XCTAssertEqual(try store.db.scalar(
            "SELECT COUNT(*) FROM person_retirement WHERE person_id=?",
            [.text(seed.person)]).intValue, 0, "unretiring restores presence")
    }
}
