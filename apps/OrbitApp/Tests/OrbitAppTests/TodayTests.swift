import XCTest
@testable import OrbitApp
import OrbitCore
import OrbitWrite

/// Today speaks only about people you've actually met: known-of and merged
/// rows never surface (§7.3 — hearsay people are context, not obligations).
@MainActor
final class TodayTests: XCTestCase {

    func testTodayExcludesKnownOfPeople() throws {
        let app = try AppModel(store: .inMemory(),
                               transcription: MockTranscriber(canned: "", full: true))
        app.ensureSelf(named: "Abdoul")
        let edits = UserEditService(app.store)
        let met = try edits.createPerson(displayName: "Sana")
        let heardOf = try edits.createPerson(displayName: "Marcus", status: .knownOf)

        // one life_event each, dated this month — only the met person may surface
        let month = String(app.store.clock.now().prefix(7))
        for (i, pid) in [met, heardOf].enumerated() {
            try app.store.db.run(
                """
                INSERT INTO rm_current_state
                    (assertion_id, subject_id, predicate, object_value, verbatim,
                     valid_from, date_precision, observed_at, source_event_id,
                     source_kind, needs_reconfirmation)
                VALUES (?,?,?,?,?,?,?,?,?,?,0)
                """,
                [.text("a\(i)"), .text(pid), .text("life_event"), .text("moving"),
                 .text("they're moving this month"), .text(month),
                 .text("month"), .text(app.store.clock.now()), .text("ev\(i)"),
                 .text("firsthand")])
        }

        let items = app.computeToday()
        XCTAssertTrue(items.contains { $0.personID == met },
                      "an active person's life event surfaces")
        XCTAssertFalse(items.contains { $0.personID == heardOf },
                       "a known-of person never generates a Today item")
    }
}
