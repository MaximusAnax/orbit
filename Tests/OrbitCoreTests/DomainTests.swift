import XCTest
import OrbitCore

/// OrbitCore unit tests: the domain vocabulary must agree with the schema's
/// CHECK constraints byte-for-byte, and every proposal payload must survive a
/// coding round trip (the payloads ARE the write protocol).
final class DomainTests: XCTestCase {

    // Raw values are the strings the DDL CHECKs against — a rename here without
    // a migration is a ledger break, so the pairs are pinned.
    func testRawValuesMatchSchemaVocabulary() {
        XCTAssertEqual(PersonStatus.knownOf.rawValue, "known_of")
        XCTAssertEqual(Predicate.lifeEvent.rawValue, "life_event")
        XCTAssertEqual(RejectionReason.notTrue.rawValue, "not_true")
        XCTAssertEqual(ProposalOp.createPerson.rawValue, "CREATE_PERSON")
        XCTAssertEqual(ProposalOp.proposeState.rawValue, "PROPOSE_STATE")
        XCTAssertEqual(ReviewAction.deferred.rawValue, "deferred")
        XCTAssertEqual(Set(Orbit.allCases.map(\.rawValue)),
                       ["inner", "close", "active", "extended", "outer"])
        XCTAssertEqual(Attendance.about.rawValue, "about")
    }

    func testPersonRefCoding() throws {
        let id = PersonRef.id("p-123")
        let ref = PersonRef.ref("p_nikos")
        XCTAssertEqual(try roundTrip(id), id)
        XCTAssertEqual(try roundTrip(ref), ref)
        // wire keys are snake_case per the extraction contract
        XCTAssertTrue(try PayloadCoding.encode(id).contains("person_id"))
    }

    func testAssertPayloadRoundTrip() throws {
        let payload = AssertPayload(
            subject: .ref("p_nikos"), predicate: "location",
            objectValue: "Greece", verbatim: "Nikos is from Greece",
            validFrom: "2024-06", sourceKind: "firsthand")
        let back = try PayloadCoding.decode(AssertPayload.self,
                                            from: try PayloadCoding.encode(payload))
        XCTAssertEqual(back.subject, .ref("p_nikos"))
        XCTAssertEqual(back.verbatim, "Nikos is from Greece")
        XCTAssertEqual(back.validFrom, "2024-06")
    }

    func testProposeStatePayloadRoundTrip() throws {
        let payload = ProposeStatePayload(
            person: .id("p-1"), narrativeQuote: "inner, inner, inner circle",
            suggestedOrbit: "inner", mappingRationale: "explicit declaration")
        let back = try PayloadCoding.decode(ProposeStatePayload.self,
                                            from: try PayloadCoding.encode(payload))
        XCTAssertEqual(back.narrativeQuote, "inner, inner, inner circle")
        XCTAssertEqual(back.suggestedOrbit, "inner")
    }

    func testFixedClockIsFixed() {
        let clock = FixedClock("2026-07-29T12:00:00Z")
        XCTAssertEqual(clock.now(), clock.now())
    }

    func testOrbitIDsAreUniqueAndLowercased() {
        let ids = (0..<100).map { _ in OrbitID.make() }
        XCTAssertEqual(Set(ids).count, 100)
        XCTAssertTrue(ids.allSatisfy { $0 == $0.lowercased() })
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try PayloadCoding.decode(T.self, from: try PayloadCoding.encode(value))
    }
}
