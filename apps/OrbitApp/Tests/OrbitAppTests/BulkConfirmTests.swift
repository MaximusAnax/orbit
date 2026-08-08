import XCTest
@testable import OrbitApp
import OrbitCore
import OrbitSQLite

/// INV-5b — the guard that came with P5's amendment (2026-08-08).
///
/// P5 was amended because a portrait produces 56 proposals against a 12-decision
/// budget: one tap per claim made "nothing final without confirmation" and
/// "capture should be effortless" contradict each other outright. The amendment
/// permits batching the *tap*. It does not permit batching the *reading*, and
/// this suite is where that distinction is enforced rather than asserted —
/// a granularity change is exactly where a silent-write regression hides.
@MainActor
final class BulkConfirmTests: XCTestCase {

    static let transcript =
        "Dinner with Maya. She just started at Figma on the design systems team, " +
        "and her dad was diagnosed with early-stage Parkinson's so she's been " +
        "flying home every other weekend. She's basically family at this point. " +
        "There was another Maya there too, I think, or maybe I'm mixing them up."

    /// One ordinary fact, one hardship thread, one state declaration, one
    /// ambiguity — the four kinds the bulk path must treat differently.
    static let payload = """
    {"people":[{"ref":"p_maya","name_as_heard":"Maya","match":"new","existing_person_id":null,"match_rationale":null,"status":"active"}],
     "entities":[{"ref":"e_figma","name_as_heard":"Figma","kind":"organization","existing_entity_id":null,"part_of_ref":null,"aliases":[]}],
     "assertions":[
       {"subject_ref":"p_maya","predicate":"employment","object_entity_ref":"e_figma","object_person_ref":null,
        "object_value":"design systems","verbatim":"She just started at Figma on the design systems team",
        "valid_from":"2026-07","valid_to":null,"date_precision":"month","source_kind":"firsthand",
        "attributed_to_ref":null,"hedged":false,"confidence":null,"thread_ref":null}],
     "episodes":[],
     "threads":[{"ref":"t_dad","subject_ref":"p_maya","title":"her father's Parkinson's diagnosis",
        "archetype":"condition_hardship","expected_resolution_at":null,
        "expected_resolution_precision":null,
        "evidence_verbatim":"her dad was diagnosed with early-stage Parkinson's"}],
     "thread_closures":[],"loops":[],"contact_points":[],
     "state_declarations":[{"subject_ref":"p_maya","quote":"She's basically family at this point",
        "suggested_orbit":"inner","suggested_intent":null,
        "mapping_rationale":"explicit self-characterisation of the relationship"}],
     "corrections":[],
     "ambiguities":[{"kind":"subject","question":"Which Maya was that?",
        "candidate_refs":["p_maya"],"assertion":null}]}
    """

    func makeApp() throws -> AppModel {
        let app = try AppModel(store: .inMemory(),
                               transcription: MockTranscriber(canned: Self.transcript))
        app.autoExtract = false
        app.ensureSelf(named: "Abdoul")
        return app
    }

    /// A stalled flow is a FAILURE, not a skip. The first version of this file
    /// used XCTSkip and reported "TEST SUCCEEDED" with four ungraded tests —
    /// silence looking exactly like success, which is the thing this whole
    /// suite exists to prevent.
    struct FlowStalled: Error { let state: String }

    func review(_ app: AppModel) async throws -> ReviewViewModel {
        app.extractorOverride = StaticPayloadExtractor(json: Self.payload)
        await app.finishRecording(audioRef: "mock://audio", participants: [], kind: .dinner)
        guard case .reviewingTranscript(let tvm) = app.pendingCapture else {
            XCTFail("transcript review not reached — \(String(describing: app.pendingCapture))")
            throw FlowStalled(state: "transcript")
        }
        tvm.confirm()
        guard case .extracting(let id) = app.pendingCapture else {
            XCTFail("extracting not reached — \(String(describing: app.pendingCapture))")
            throw FlowStalled(state: "extracting")
        }
        await app.runExtraction(eventID: id)
        guard case .reviewingProposals(let rvm) = app.pendingCapture else {
            XCTFail("proposal review not reached — \(String(describing: app.pendingCapture))")
            throw FlowStalled(state: "review")
        }
        return rvm
    }

    /// The core of INV-5b: hardship, state declarations and questions never ride
    /// along with an "all yes".
    func testUncertainAndHighStakesCardsAreHeldBackFromBulk() async throws {
        let app = try makeApp()
        let rvm = try await review(app)
        let cards = rvm.groups.flatMap(\.cards)
        XCTAssertFalse(cards.isEmpty, "nothing to review — the fixture is not exercising the path")

        for card in cards where card.op == .openThread && card.payload.contains("condition_hardship") {
            XCTAssertFalse(card.bulkEligible,
                           "INV-20: a hardship thread must never be swept up in an accept-all")
        }
        for card in cards where card.op == .proposeState {
            XCTAssertFalse(card.bulkEligible,
                           "a relationship-state declaration gets its own look (INV-24)")
        }
        for card in cards where card.question != nil || !card.candidates.isEmpty {
            XCTAssertFalse(card.bulkEligible,
                           "answering a DISAMBIGUATE in bulk is guessing, which the ask exists to prevent")
        }
    }

    /// A bulk accept settles the ordinary facts and leaves the rest genuinely
    /// unsettled — not silently accepted, not silently dropped.
    func testBulkAcceptSettlesOrdinaryFactsOnly() async throws {
        let app = try makeApp()
        let rvm = try await review(app)

        var accepted = 0, held = 0
        for group in rvm.groups {
            let out = rvm.acceptAll(in: group, rendered: Set(group.cards.map(\.id)))
            accepted += out.accepted; held += out.held
        }
        XCTAssertGreaterThan(accepted, 0, "the ordinary facts should settle")
        XCTAssertGreaterThan(held, 0, "the hardship/state/question cards should not")

        // Held-back cards are still awaiting a decision, not resolved behind his back.
        let unsettled = rvm.groups.flatMap(\.cards).filter { $0.settled == nil }
        XCTAssertEqual(unsettled.count, held)

        // INV-20 specifically: the hardship thread has not been written.
        let hardship = try app.store.db.scalar(
            "SELECT COUNT(*) FROM thread WHERE archetype='condition_hardship'").intValue ?? 0
        XCTAssertEqual(hardship, 0, "hardship must not reach the ledger via an accept-all")
    }

    /// The part that makes INV-5b structural rather than aspirational: a card the
    /// view did not render cannot be resolved, however eligible it is.
    func testACardThatWasNotOnScreenIsNeverResolved() async throws {
        let app = try makeApp()
        let rvm = try await review(app)
        guard let group = rvm.groups.first(where: { $0.cards.contains(where: \.bulkEligible) }) else {
            return XCTFail("no group with an eligible card")
        }
        let eligible = group.cards.filter(\.bulkEligible)
        let offScreen = try XCTUnwrap(eligible.first)

        // Simulate a truncated list: everything rendered EXCEPT that one.
        let rendered = Set(group.cards.map(\.id)).subtracting([offScreen.id])
        let out = rvm.acceptAll(in: group, rendered: rendered)

        let after = rvm.groups.flatMap(\.cards).first { $0.id == offScreen.id }
        XCTAssertNil(after?.settled,
                     "a proposal the reviewer could not see must not be settled by a bulk accept")
        XCTAssertGreaterThanOrEqual(out.held, 1, "and it is reported as held, not silently skipped")
    }

    /// No default may be accept: constructing the review must write nothing.
    func testReviewAloneWritesNothing() async throws {
        let app = try makeApp()
        _ = try await review(app)
        let assertions = try app.store.db.scalar("SELECT COUNT(*) FROM assertion").intValue ?? 0
        let threads = try app.store.db.scalar("SELECT COUNT(*) FROM thread").intValue ?? 0
        let states = try app.store.db.scalar("SELECT COUNT(*) FROM relationship_state").intValue ?? 0
        XCTAssertEqual(assertions + threads + states, 0,
                       "INV-5: rendering proposals writes nothing until a human decides")
    }
}
