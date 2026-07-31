import XCTest
@testable import OrbitApp
import OrbitCore
import OrbitPipeline
import OrbitSQLite
import OrbitSearch

/// M5 gate: INV-22/23/24 and the PIPE-12 machinery (episodes → reconstructed
/// events, we-splits, era-anchored portraits, PROPOSE_STATE transport) driven
/// through the SAME AppModel/view-model path the screens call.
@MainActor
final class PortraitFlowTests: XCTestCase {

    static let transcript =
        "Nikos and I go way back. We met at the startup school picnic last summer. " +
        "We both love freediving. He would be right there in my inner circle."

    static let portraitPayload = """
    {"people":[{"ref":"p_nikos","name_as_heard":"Nikos","match":"new","existing_person_id":null,"match_rationale":null,"status":"active"}],
     "entities":[],
     "assertions":[
      {"subject_ref":"p_nikos","predicate":"interest","object_entity_ref":null,"object_person_ref":null,"object_value":"freediving","verbatim":"We both love freediving","valid_from":null,"valid_to":null,"date_precision":"fuzzy","source_kind":"firsthand","attributed_to_ref":null,"hedged":false,"confidence":null,"thread_ref":null},
      {"subject_ref":"self","predicate":"interest","object_entity_ref":null,"object_person_ref":null,"object_value":"freediving","verbatim":"We both love freediving","valid_from":null,"valid_to":null,"date_precision":"fuzzy","source_kind":"firsthand","attributed_to_ref":null,"hedged":false,"confidence":null,"thread_ref":null}],
     "episodes":[
      {"occurred_at":"2025-07","date_precision":"month","era_relative":null,"kind":"party","title":"Startup school picnic","narrative":"We met at the startup school picnic last summer","participant_refs":["p_nikos"],"is_met_event":true,"hedged":false}],
     "threads":[],"thread_closures":[],"loops":[],"contact_points":[],
     "state_declarations":[
      {"subject_ref":"p_nikos","quote":"He would be right there in my inner circle","suggested_orbit":"inner","suggested_intent":null,"mapping_rationale":"explicit self-characterization of the relationship"}],
     "corrections":[],"ambiguities":[]}
    """

    func makeApp() throws -> AppModel {
        let app = try AppModel(store: .inMemory(),
                               transcription: MockTranscriber(canned: Self.transcript))
        app.autoExtract = false
        app.ensureSelf(named: "Abdoul")
        return app
    }

    /// A stalled flow is a FAILURE, not a skip — every portrait test depends on
    /// this helper reaching review, so silently skipping would grade nothing.
    struct FlowStalled: Error { let state: String }

    func portraitReview(_ app: AppModel, payload: String = portraitPayload) async throws -> ReviewViewModel {
        app.extractorOverride = StaticPayloadExtractor(json: payload)
        await app.finishRecording(audioRef: "mock://audio", participants: [], kind: .portrait)
        guard case .reviewingTranscript(let tvm) = app.pendingCapture else {
            XCTFail("transcript review not reached — pendingCapture is \(String(describing: app.pendingCapture))")
            throw FlowStalled(state: "transcript")
        }
        tvm.confirm()
        guard case .extracting(let eventID) = app.pendingCapture else {
            XCTFail("extracting not reached — pendingCapture is \(String(describing: app.pendingCapture))")
            throw FlowStalled(state: "extracting")
        }
        await app.runExtraction(eventID: eventID)
        guard case .reviewingProposals(let rvm) = app.pendingCapture else {
            XCTFail("proposal review not reached — pendingCapture is \(String(describing: app.pendingCapture))")
            throw FlowStalled(state: "review")
        }
        return rvm
    }

    // MARK: PIPE-12 machinery — episode → reconstructed event, first-met, we-split

    func testPortraitEndToEnd() async throws {
        let app = try makeApp()
        let rvm = try await portraitReview(app)
        let cards = rvm.groups.flatMap(\.cards)

        // the review renders every op kind the portrait produced
        let personCard = try XCTUnwrap(cards.first { $0.op == .createPerson })
        let episodeCard = try XCTUnwrap(cards.first { $0.op == .createEvent })
        let stateCard = try XCTUnwrap(cards.first { $0.op == .proposeState })
        XCTAssertTrue(episodeCard.isEpisode)
        XCTAssertEqual(stateCard.stateSuggestion, Copy.suggestedPrefix + "inner",
                       "the mapping renders AS a suggestion (§7.13)")
        XCTAssertEqual(stateCard.quote, "He would be right there in my inner circle")

        rvm.accept(personCard)
        rvm.acceptAsFirstMet(episodeCard)
        // fresh read — Card is a value type, the local snapshot's settled is stale
        for card in rvm.groups.flatMap(\.cards) where card.settled == nil {
            rvm.accept(card)
        }

        // reconstructed event: real row, fuzzy date, confirmed on acceptance,
        // derived_from pointing at the portrait (§7.11)
        let episode = try XCTUnwrap(app.store.db.query(
            "SELECT * FROM event WHERE derived_from_event_id IS NOT NULL").first)
        XCTAssertEqual(episode.text("occurred_at"), "2025-07")
        XCTAssertEqual(episode.text("date_precision"), "month")
        XCTAssertEqual(episode.text("lifecycle"), "confirmed")
        XCTAssertNil(episode.text("transcript"), "an episode has no transcript of its own")

        // its participant genuinely was there — present attendance
        let att = try app.store.db.scalar(
            "SELECT attendance FROM event_participant WHERE event_id=?",
            [.text(episode.text("id") ?? "")]).stringValue
        XCTAssertEqual(att, "confirmed")

        // INV-12: reconstructed history never enters rate math
        let rhythm = try app.store.db.scalar(
            "SELECT COUNT(*) FROM rm_contact_rhythm").intValue ?? 0
        XCTAssertEqual(rhythm, 0)

        // first_met fell out of confirming the episode as the meeting
        let nikosRow = try XCTUnwrap(app.store.db.query(
            "SELECT id, first_met_event_id FROM person WHERE display_name='Nikos'").first)
        XCTAssertEqual(nikosRow.text("first_met_event_id"), episode.text("id"))

        // the we-split: the same verbatim landed on both Nikos AND the self row (§7.12)
        let holders = try app.store.db.query(
            """
            SELECT p.is_self FROM assertion a JOIN person p ON p.id = a.subject_id
            WHERE a.verbatim='We both love freediving'
            """)
        XCTAssertEqual(holders.count, 2)
        XCTAssertEqual(Set(holders.compactMap { $0.int("is_self") }), [0, 1])

        // PROPOSE_STATE accepted → authored_by human, his words, provenance kept (§7.13)
        let state = try XCTUnwrap(app.store.db.query("SELECT * FROM relationship_state").first)
        XCTAssertEqual(state.text("authored_by"), "human")
        XCTAssertEqual(state.text("orbit"), "inner")
        XCTAssertEqual(state.text("narrative"), "He would be right there in my inner circle")
        XCTAssertNotNil(state.text("source_event_id"))
    }

    // MARK: INV-24 — no quote, no proposal (and the memo survives)

    func testINV24_unquotedStateIsRefusedQuietly() async throws {
        let app = try makeApp()
        let doctored = Self.portraitPayload.replacingOccurrences(
            of: "He would be right there in my inner circle",
            with: "He seems really important to you")   // NOT in the transcript
        let rvm = try await portraitReview(app, payload: doctored)
        let cards = rvm.groups.flatMap(\.cards)
        XCTAssertNil(cards.first { $0.op == .proposeState },
                     "inferred state never becomes a proposal (INV-24)")
        XCTAssertNotNil(cards.first { $0.op == .createPerson },
                        "the rest of the memo still syncs — the gate refuses the op, not the review")
    }

    // MARK: INV-22/23 — the self row's structurally limited scope, UI-visible surfaces

    func testINV23_selfNeverSurfaces() async throws {
        let app = try makeApp()
        let rvm = try await portraitReview(app)
        for group in rvm.groups { rvm.acceptAll(in: group) }

        // search: name shape never returns the self row
        let hits = try OrbitSearchProxy.people(app: app, query: "Abdoul")
        XCTAssertTrue(hits.isEmpty, "the self is not a search result (INV-23)")

        // Today: the self's life events never appear
        XCTAssertTrue(app.computeToday().allSatisfy { $0.personName != "Abdoul" })

        // review grouping: the self's we-split half renders under the self group
        // but the self row holds NO relationship machinery
        let machinery = try app.store.db.scalar(
            """
            SELECT COUNT(*) FROM relationship_state rs JOIN person p ON p.id = rs.person_id
            WHERE p.is_self=1
            """).intValue ?? 0
        XCTAssertEqual(machinery, 0)
    }
}

/// Tiny indirection so the test reads clearly.
enum OrbitSearchProxy {
    @MainActor static func people(app: AppModel, query: String) throws -> [Searcher.PersonHit] {
        if case .people(let hits) = try Searcher(reader: app.store.reader).search(query) {
            return hits
        }
        return []
    }
}
