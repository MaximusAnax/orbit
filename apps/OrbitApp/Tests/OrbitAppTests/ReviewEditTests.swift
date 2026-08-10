import XCTest
@testable import OrbitApp
import OrbitCore
import OrbitPipeline
import OrbitSQLite

/// Accept-with-edits (P5) under the one condition that used to discard it: a
/// card whose accept bounces off a dependency that hasn't been accepted yet.
///
/// The failure was silent and looked like a dead Edit button. `acceptEdited`
/// passed the corrected payload straight to the write and nowhere else, so when
/// the write threw `pendingDependency` the correction existed only in that
/// stack frame. `retryDependencyWaiters` then re-accepted from the *unedited*
/// card it had captured, and the ledger got the date the extractor guessed —
/// after the user had plainly said otherwise.
@MainActor
final class ReviewEditTests: XCTestCase {

    /// One new person and one episode about her. The episode's participant ref
    /// is the person the CREATE_PERSON card introduces, so accepting the
    /// episode first is guaranteed to hit `pendingDependency` — which is the
    /// state the card was in when the date was corrected on it.
    static let payload = """
    {"people":[{"ref":"p_gladys","name_as_heard":"Gladys","match":"new","existing_person_id":null,"match_rationale":null,"status":"active"}],
     "entities":[],
     "assertions":[],
     "episodes":[{"occurred_at":"2026-07-15","date_precision":"fuzzy","era_relative":null,"kind":"encounter","title":"Startup School","narrative":"I met Gladys at Y Combinator Startup School 2026 a few weeks ago","participant_refs":["p_gladys"],"is_met_event":true,"hedged":true}],
     "threads":[],"thread_closures":[],"loops":[],"contact_points":[],
     "state_declarations":[],"corrections":[],"ambiguities":[]}
    """

    static let transcript =
        "I met Gladys at Y Combinator Startup School 2026 a few weeks ago, she's pretty cool"

    func makeReview() async throws -> (AppModel, ReviewViewModel) {
        let app = try AppModel(store: .inMemory(),
                               transcription: MockTranscriber(canned: Self.transcript, full: true))
        app.autoExtract = false
        app.ensureSelf(named: "Abdoul")
        app.extractorOverride = StaticPayloadExtractor(json: Self.payload)
        await app.finishRecording(audioRef: "mock://audio", participants: [], kind: .encounter)
        guard case .reviewingTranscript(let tvm) = app.pendingCapture else {
            throw XCTSkip("transcript review not reached")
        }
        tvm.confirm()
        guard case .extracting(let eventID) = app.pendingCapture else {
            throw XCTSkip("extracting not reached")
        }
        await app.runExtraction(eventID: eventID)
        guard case .reviewingProposals(let rvm) = app.pendingCapture else {
            throw XCTSkip("proposal review not reached")
        }
        return (app, rvm)
    }

    /// The Edit sheet's save, reproduced exactly: decode the card's payload,
    /// set the date and the precision his typing vouches for, re-encode.
    func editedDate(_ card: ReviewViewModel.Card, to date: String) throws -> String {
        var dict = (try JSONSerialization.jsonObject(with: Data(card.payload.utf8))
                    as? [String: Any]) ?? [:]
        dict["occurred_at"] = date
        let parts = date.split(separator: "-").count
        dict["date_precision"] = parts >= 3 ? "exact" : (parts == 2 ? "month" : "year")
        return String(data: try JSONSerialization.data(withJSONObject: dict), encoding: .utf8)!
    }

    func card(_ rvm: ReviewViewModel, _ op: ProposalOp) throws -> ReviewViewModel.Card {
        guard let c = rvm.groups.flatMap(\.cards).first(where: { $0.op == op }) else {
            throw XCTSkip("no \(op) card in this run")
        }
        return c
    }

    /// The reported bug, end to end: Yes → blocked on a dependency → correct
    /// the date on the blocked card → accept the dependency. The ledger must
    /// carry the corrected date, not the extracted one.
    func testDateEditedWhileBlockedSurvivesTheDependencyRetry() async throws {
        let (app, rvm) = try await makeReview()
        let episode = try card(rvm, .createEvent)

        // Yes, out of order: the person this episode names isn't saved yet.
        rvm.accept(episode)
        let blocked = rvm.groups.flatMap(\.cards).first { $0.id == episode.id }
        XCTAssertEqual(blocked?.blocked, Copy.cardWaitingOnDependency,
                       "an episode accepted before its person must park, visibly")
        XCTAssertNil(blocked?.settled)

        // Correct the date on the card while it sits there waiting.
        rvm.acceptEdited(episode, payloadJSON: try editedDate(episode, to: "2026-07"))

        // Now the dependency lands, which fires the retry.
        rvm.accept(try card(rvm, .createPerson))

        let event = try XCTUnwrap(try app.store.db.query(
            "SELECT occurred_at, date_precision FROM event WHERE derived_from_event_id IS NOT NULL").first)
        XCTAssertEqual(event.text("occurred_at"), "2026-07",
                       "the retry must submit the corrected date, not the extracted one")
        XCTAssertEqual(event.text("date_precision"), "month",
                       "precision follows what he actually typed — a month is a month")
    }

    /// The same correction made before any Yes: `acceptEdited` is the first
    /// thing that touches the card, blocks, and must still be what gets retried.
    func testDateEditedBeforeAnyAcceptSurvivesTheDependencyRetry() async throws {
        let (app, rvm) = try await makeReview()
        let episode = try card(rvm, .createEvent)

        rvm.acceptEdited(episode, payloadJSON: try editedDate(episode, to: "2026"))
        XCTAssertEqual(rvm.groups.flatMap(\.cards).first { $0.id == episode.id }?.blocked,
                       Copy.cardWaitingOnDependency)

        rvm.accept(try card(rvm, .createPerson))

        let event = try XCTUnwrap(try app.store.db.query(
            "SELECT occurred_at, date_precision FROM event WHERE derived_from_event_id IS NOT NULL").first)
        XCTAssertEqual(event.text("occurred_at"), "2026")
        XCTAssertEqual(event.text("date_precision"), "year")
    }

    /// The other half of "it didn't change": the card is display derived from
    /// its payload, so a corrected date has to re-render on the card itself.
    /// Showing the old day next to a save that took is the same bug wearing a
    /// different coat.
    func testCorrectedDateRendersOnTheCard() async throws {
        // `app` stays bound for the whole test on purpose: the view model holds
        // it weakly, and a display rebuild with no app quietly does nothing.
        let (app, rvm) = try await makeReview()
        let episode = try card(rvm, .createEvent)
        XCTAssertEqual(episode.whenLine, Copy.whenLine("July 2026", precision: "fuzzy", era: nil),
                       "precondition: the extracted date renders hedged")

        rvm.acceptEdited(episode, payloadJSON: try editedDate(episode, to: "2026-08-01"))

        let shown = try XCTUnwrap(rvm.groups.flatMap(\.cards).first { $0.id == episode.id })
        XCTAssertEqual(shown.whenLine, Copy.whenLine("1 August 2026", precision: "exact", era: nil),
                       "the card must show the date he typed, at the precision he gave it")
        // and it says so while still blocked — the correction is visible before
        // it is written, which is the whole point of review deciding (P5)
        XCTAssertEqual(shown.blocked, Copy.cardWaitingOnDependency)
        XCTAssertEqual(try app.store.db.scalar(
            "SELECT COUNT(*) FROM event WHERE derived_from_event_id IS NOT NULL").intValue, 0,
            "nothing lands until the person card does")
    }

    /// Editing must not cost a rename made on the same card, or vice versa —
    /// both corrections are his, and both belong in the payload that is written.
    func testRenameAndPayloadEditCompose() async throws {
        let (app, rvm) = try await makeReview()
        let person = try card(rvm, .createPerson)
        let ref = try XCTUnwrap(rvm.renameableRef(person))

        rvm.rename(ref: ref, to: "Gladys Okonkwo")
        let episode = try card(rvm, .createEvent)
        rvm.acceptEdited(episode, payloadJSON: try editedDate(episode, to: "2026-07"))
        rvm.accept(try XCTUnwrap(rvm.groups.flatMap(\.cards).first { $0.id == person.id }))

        XCTAssertEqual(try app.store.db.scalar(
            "SELECT display_name FROM person WHERE is_self=0").stringValue, "Gladys Okonkwo",
            "the corrected name is what lands")
        XCTAssertEqual(try app.store.db.scalar(
            "SELECT occurred_at FROM event WHERE derived_from_event_id IS NOT NULL").stringValue,
            "2026-07", "the corrected date is what lands")
    }
}
