import XCTest
import OrbitCore
import OrbitSQLite
import OrbitStore
@testable import OrbitSearch
@testable import OrbitWrite

/// Two ways a search answer can be confidently wrong, both found by review of PR #1.
final class FactAnswerTests: XCTestCase {
    var store: WriteStore!
    var edits: UserEditService!

    override func setUpWithError() throws {
        store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        edits = UserEditService(store)
    }

    private func entity(_ id: String, _ name: String, kind: String = "organization") throws {
        try store.db.run(
            "INSERT INTO entity (id, kind, canonical_name) VALUES (?,?,?)",
            [.text(id), .text(kind), .text(name)])
    }

    private func fact(subject: String, predicate: String, value: String?,
                      entity entityID: String?, verbatim: String) throws {
        let event = try edits.captureEvent(.init(
            kind: .encounter, occurredAt: "2026-07-01T10:00:00Z",
            transcript: verbatim, participants: [(subject, .confirmed, nil)]))
        try edits.confirmEvent(event, fullModelTranscribed: true)
        try store.db.run(
            """
            INSERT INTO assertion (id, subject_id, predicate, object_entity_id, object_value,
                                   verbatim, date_precision, observed_at, source_event_id, source_kind)
            VALUES (?,?,?,?,?,?,'fuzzy','2026-07-01T10:00:00Z',?,'firsthand')
            """,
            [.text(OrbitID.make()), .text(subject), .text(predicate), .from(entityID),
             .from(value), .text(verbatim), .text(event)])
        try store.rmRebuild()
        try store.rmSearchRebuild()
    }

    /// `object_value` is the literal *beside* the object (DATA-MODEL §2 — "a role
    /// title, a date, a name"), so answering from it alone says "intern" when the
    /// question was "where does she work". Prompt v3 made it sharper still by
    /// putting `origin`/`residence` there for `location`.
    func testWhereSomeoneWorksAnswersTheEmployerNotTheRole() throws {
        let eliah = try edits.createPerson(displayName: "Eliah")
        try entity("e_google", "Google")
        try fact(subject: eliah, predicate: "employment", value: "intern",
                 entity: "e_google", verbatim: "she interned at Google")

        let answer = try Searcher(reader: store.reader).search("where does Eliah work?")
        guard case .answer(let a) = answer else {
            return XCTFail("expected an answer band, got \(answer)")
        }
        XCTAssertEqual(a.factAnswer, "Google", "the role is not the workplace")
    }

    func testWhereSomeoneLivesAnswersThePlaceNotTheQualifier() throws {
        let james = try edits.createPerson(displayName: "James")
        try entity("e_sf", "San Francisco", kind: "place")
        // prompt v3 shape: the qualifier in object_value, the place as the entity
        try fact(subject: james, predicate: "location", value: "residence",
                 entity: "e_sf", verbatim: "he's been in San Francisco ever since")

        let answer = try Searcher(reader: store.reader).search("where does James live?")
        guard case .answer(let a) = answer else {
            return XCTFail("expected an answer band, got \(answer)")
        }
        XCTAssertEqual(a.factAnswer, "San Francisco",
                       "'residence' is the qualifier, not an answer to where")
    }

    /// Facts that never linked an entity still answer from the literal.
    func testALiteralOnlyFactStillAnswers() throws {
        let nikos = try edits.createPerson(displayName: "Nikos")
        try fact(subject: nikos, predicate: "location", value: "Greece",
                 entity: nil, verbatim: "he's from Greece")

        let answer = try Searcher(reader: store.reader).search("where is Nikos from?")
        guard case .answer(let a) = answer else {
            return XCTFail("expected an answer band, got \(answer)")
        }
        XCTAssertEqual(a.factAnswer, "Greece")
    }

    /// Decision 6 is a pointer merge: the loser's rows are never rewritten, so
    /// every read has to follow the pointer. Recall does this in eight queries;
    /// search's provenance line did not, so the Desk and the search result
    /// disagreed about the same person after a merge.
    func testLastSeenFollowsAMergePointer() throws {
        let winner = try edits.createPerson(displayName: "Sarah")
        let loser = try edits.createPerson(displayName: "Sara")
        let event = try edits.captureEvent(.init(
            kind: .coffee, occurredAt: "2026-06-15T10:00:00Z",
            transcript: "coffee with Sara", participants: [(loser, .confirmed, nil)]))
        try edits.confirmEvent(event, fullModelTranscribed: true)
        try edits.mergePerson(loser: loser, winner: winner)
        try store.rmRebuild()
        try store.rmSearchRebuild()

        let anchor = try Searcher(reader: store.reader).provenanceAnchor(winner)
        XCTAssertTrue(anchor.contains("last seen 2026-06"),
                      "the merged-away id held the only event; anchor was \(anchor.debugDescription)")
    }
}
