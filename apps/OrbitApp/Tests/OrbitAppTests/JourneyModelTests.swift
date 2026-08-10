import XCTest
@testable import OrbitApp
import OrbitCore
import OrbitPipeline
import OrbitSQLite

/// J-suite end-state assertions (EVALS §4.1) at the model layer: the journeys
/// drive the SAME AppModel/view-model code the screens call, and every
/// assertion is against the database — "asserted end-state in the database,
/// not just screen state". The tap-level halves (friction budgets, absence of
/// badges on screen) live in OrbitAppUITests.
@MainActor
final class JourneyModelTests: XCTestCase {

    // The Nikos fixture payload (docs/evals/fixtures/nikos.json), inline so the
    // test is hermetic: 1 new person, 2 entities, 3 assertions.
    static let nikosPayload = """
    {"people":[{"ref":"p_nikos","name_as_heard":"Nikos","match":"new","existing_person_id":null,"match_rationale":null,"status":"active"}],
     "entities":[{"ref":"e_ycss","name_as_heard":"Y Combinator Startup School","kind":"event_series","existing_entity_id":null,"part_of_ref":null,"aliases":["startup school"]}],
     "assertions":[
      {"subject_ref":"p_nikos","predicate":"location","object_entity_ref":null,"object_person_ref":null,"object_value":"Greece","verbatim":"Nikos is from Greece","valid_from":null,"valid_to":null,"date_precision":"fuzzy","source_kind":"firsthand","attributed_to_ref":null,"hedged":false,"confidence":null,"thread_ref":null},
      {"subject_ref":"p_nikos","predicate":"life_event","object_entity_ref":"e_ycss","object_person_ref":null,"object_value":"attended Y Combinator Startup School","verbatim":"He was there for startup school","valid_from":"2026-07","valid_to":null,"date_precision":"month","source_kind":"firsthand","attributed_to_ref":null,"hedged":false,"confidence":null,"thread_ref":null},
      {"subject_ref":"p_nikos","predicate":"trait","object_entity_ref":null,"object_person_ref":null,"object_value":"down-to-earth, kind","verbatim":"He was a very down-to-earth guy, super nice to talk to, very kind","valid_from":null,"valid_to":null,"date_precision":"fuzzy","source_kind":"firsthand","attributed_to_ref":null,"hedged":false,"confidence":null,"thread_ref":null}],
     "episodes":[],"threads":[],"thread_closures":[],"loops":[],"contact_points":[],
     "state_declarations":[],"corrections":[],"ambiguities":[]}
    """

    static let nikosTranscript =
        "I met Nikos at the picnic. Nikos is from Greece. He was there for startup school. " +
        "He was a very down-to-earth guy, super nice to talk to, very kind"

    func makeApp(transcript: String = "", fullModel: Bool = true) throws -> AppModel {
        let app = try AppModel(store: .inMemory(),
                               transcription: MockTranscriber(canned: transcript, full: fullModel))
        app.autoExtract = false                 // journeys await extraction explicitly
        app.ensureSelf(named: "Abdoul")
        return app
    }

    /// A stalled flow is a FAILURE, not a skip — every journey depends on this
    /// helper reaching review, so silently skipping would grade nothing.
    struct FlowStalled: Error { let state: String }

    func syncedReview(_ app: AppModel) async throws -> ReviewViewModel {
        app.extractorOverride = StaticPayloadExtractor(json: Self.nikosPayload)
        await app.finishRecording(audioRef: "mock://audio", participants: [], kind: .encounter)
        guard case .reviewingTranscript(let tvm) = app.pendingCapture else {
            XCTFail("transcript review state not reached — pendingCapture is \(String(describing: app.pendingCapture))")
            throw FlowStalled(state: "transcript")
        }
        tvm.confirm()
        guard case .extracting(let eventID) = app.pendingCapture else {
            XCTFail("extracting state not reached — pendingCapture is \(String(describing: app.pendingCapture))")
            throw FlowStalled(state: "extracting")
        }
        await app.runExtraction(eventID: eventID)
        guard case .reviewingProposals(let rvm) = app.pendingCapture else {
            XCTFail("proposal review state not reached — pendingCapture is \(String(describing: app.pendingCapture))")
            throw FlowStalled(state: "review")
        }
        return rvm
    }

    // MARK: J-1 — capture → transcript → review → sync, single person

    func testJ1_endToEndAcceptedFactsWithProvenance() async throws {
        let app = try makeApp(transcript: Self.nikosTranscript)
        let rvm = try await syncedReview(app)

        // audio deleted only AFTER full-model transcript confirmed (§7.5/PRIV-3 DB level)
        let audio = try app.store.db.scalar("SELECT raw_audio_ref FROM event")
        XCTAssertNil(audio.stringValue, "audio ref must be cleared on full-model confirm")

        for group in rvm.groups { rvm.acceptAll(in: group, rendered: Set(group.cards.map(\.id))) }
        XCTAssertTrue(rvm.allSettled, "every card settles under accept-all")

        // N accepted assertions, provenance total (INV-18)
        let accepted = try app.store.db.scalar(
            "SELECT COUNT(*) FROM assertion WHERE source_event_id IS NOT NULL").intValue ?? 0
        XCTAssertGreaterThanOrEqual(accepted, 3)
        let orphans = try app.store.db.scalar(
            "SELECT COUNT(*) FROM assertion WHERE source_event_id IS NULL").intValue ?? 0
        XCTAssertEqual(orphans, 0)
        // the person exists and is a real contact
        let nikos = try app.store.db.scalar(
            "SELECT COUNT(*) FROM person WHERE display_name='Nikos'").intValue ?? 0
        XCTAssertEqual(nikos, 1)
    }

    func testJ1_tinyModelKeepsAudio() async throws {
        let app = try makeApp(transcript: Self.nikosTranscript, fullModel: false)
        app.extractorOverride = StaticPayloadExtractor(json: Self.nikosPayload)
        await app.finishRecording(audioRef: "mock://audio", participants: [], kind: .encounter)
        guard case .reviewingTranscript(let tvm) = app.pendingCapture else {
            return XCTFail("no transcript review")
        }
        XCTAssertEqual(tvm.audioNotice, Copy.audioRetainedNotice)
        tvm.confirm()
        let audio = try app.store.db.scalar("SELECT raw_audio_ref FROM event")
        XCTAssertEqual(audio.stringValue, "mock://audio",
                       "tiny-model transcript must NOT trigger audio deletion")
    }

    // MARK: J-2 (persistence slice) — partial resolution survives reload

    func testJ2_partialResolutionPersists() async throws {
        let app = try makeApp(transcript: Self.nikosTranscript)
        let rvm = try await syncedReview(app)
        let cards = rvm.groups.flatMap(\.cards)
        XCTAssertGreaterThanOrEqual(cards.count, 3)

        // dependency-first: accept the CREATE_PERSON, defer everything else
        let personCard = cards.first { $0.op == .createPerson } ?? cards[0]
        rvm.accept(personCard)
        let rest = cards.filter { $0.id != personCard.id }
        for card in rest { rvm.setAside(card) }

        // reload from the store: deferred cards come back, accepted ones don't
        let reloaded = ReviewViewModel(syncRunID: rvm.syncRunID, app: app)
        let reloadedIDs = Set(reloaded.groups.flatMap(\.cards).map(\.id))
        XCTAssertFalse(reloadedIDs.contains(personCard.id), "accepted proposal must not reappear")
        for card in rest {
            XCTAssertTrue(reloadedIDs.contains(card.id), "deferred proposal must persist")
        }
    }

    // MARK: J-3 — defer everything, zero nags

    func testJ3_deferEverything() async throws {
        let app = try makeApp(transcript: Self.nikosTranscript)
        let rvm = try await syncedReview(app)
        for card in rvm.groups.flatMap(\.cards) { rvm.setAside(card) }
        rvm.finish()

        let pending = try app.store.db.scalar(
            "SELECT COUNT(*) FROM proposal WHERE state='deferred'").intValue ?? 0
        XCTAssertGreaterThanOrEqual(pending, 3)
        // nothing was written to the ledger
        XCTAssertEqual(try app.store.db.scalar("SELECT COUNT(*) FROM assertion").intValue ?? 0, 0)
        // the only ambient surface is the true-count footer line (D-2/D-9)
        XCTAssertEqual(app.setAsideCount, Int(pending))
        // "Today" carries no nag about the half-reviewed event
        XCTAssertTrue(app.todayItems.isEmpty)
    }

    // MARK: J-4 — transcript edit + name fix propagates

    func testJ4_nameFixBecomesTheRecord() async throws {
        let app = try makeApp(transcript: "I met Nico's at the picnic, he is from Greece")
        _ = try? app.edits.createPerson(displayName: "Nikos", isSelf: false)
        app.extractorOverride = StaticPayloadExtractor(json: Self.nikosPayload)

        await app.finishRecording(audioRef: "mock://audio", participants: [], kind: .encounter)
        guard case .reviewingTranscript(let tvm) = app.pendingCapture else {
            return XCTFail("no transcript review")
        }
        guard let s = tvm.nameSuggestions.first(where: { $0.candidate == "Nikos" }) else {
            return XCTFail("expected Nico's → Nikos suggestion")
        }
        tvm.applyFix(s)
        tvm.confirm()

        guard case .extracting(let eventID) = app.pendingCapture else {
            return XCTFail("no extracting state")
        }
        let record = try app.store.reader.effectiveEvent(eventID)?["transcript"]?.stringValue ?? ""
        XCTAssertTrue(record.contains("Nikos"), "the fixed name is the permanent record")
        XCTAssertFalse(record.contains("Nico's"))
    }

    // MARK: J-5 — typed micro-note: text IS the transcript

    func testJ5_typedNote() throws {
        let app = try makeApp()
        try app.captureTypedNote(text: "Sana got the Berlin offer")

        let row = try app.store.db.query("SELECT kind, lifecycle, raw_audio_ref FROM event").first
        XCTAssertEqual(row?.text("kind"), "note")
        XCTAssertEqual(row?.text("lifecycle"), "confirmed")
        XCTAssertNil(row?.text("raw_audio_ref"))
        let eventID = try app.store.db.scalar("SELECT id FROM event").stringValue ?? ""
        let transcript = try app.store.reader.effectiveEvent(eventID)?["transcript"]?.stringValue
        XCTAssertEqual(transcript, "Sana got the Berlin offer")
    }

    // MARK: J-11 — sync-later produces identical proposals

    func testJ11_syncLater() async throws {
        let app = try makeApp()
        app.extractorOverride = UnavailableExtractor()   // offline / no key
        try app.captureTypedNote(text: Self.nikosTranscript)
        guard case .extracting(let eventID) = app.pendingCapture else {
            return XCTFail("no extracting state")
        }
        await app.runExtraction(eventID: eventID)
        XCTAssertNil(app.pendingCapture, "failed extraction returns home quietly")
        XCTAssertEqual(try app.store.reader.syncStatus(of: eventID), "unsynced")
        XCTAssertEqual(try app.store.db.scalar("SELECT COUNT(*) FROM proposal").intValue ?? 0, 0)

        // later: the same event, resumed — proposals identical to immediate sync
        app.extractorOverride = StaticPayloadExtractor(json: Self.nikosPayload)
        app.syncLater(eventID: eventID)
        await app.runExtraction(eventID: eventID)
        guard case .reviewingProposals(let rvm) = app.pendingCapture else {
            return XCTFail("no proposal review after sync-later")
        }
        let laterOps = rvm.groups.flatMap(\.cards).map(\.op.rawValue).sorted()

        let immediate = try makeApp(transcript: Self.nikosTranscript)
        let ivm = try await syncedReview(immediate)
        let immediateOps = ivm.groups.flatMap(\.cards).map(\.op.rawValue).sorted()
        XCTAssertEqual(laterOps, immediateOps, "sync-later proposals ≡ immediate-sync proposals")
    }

    // MARK: J-12 — every decision lands in the eval-harvest log

    func testJ12_reviewOutcomesHarvested() async throws {
        let app = try makeApp(transcript: Self.nikosTranscript)
        let rvm = try await syncedReview(app)
        let cards = rvm.groups.flatMap(\.cards)
        XCTAssertGreaterThanOrEqual(cards.count, 3)

        let personCard = cards.first { $0.op == .createPerson } ?? cards[0]
        let asserts = cards.filter { $0.op == .assert }
        XCTAssertGreaterThanOrEqual(asserts.count, 2)
        rvm.accept(personCard)
        rvm.reject(asserts[0], reason: .notTrue)
        rvm.setAside(asserts[1])

        let outcomes = try app.store.db.query(
            "SELECT action, rejection_reason FROM review_outcome ORDER BY created_at, id")
        XCTAssertEqual(outcomes.count, 3, "every decision writes exactly one harvest row")
        let actions = Set(outcomes.compactMap { $0.text("action") })
        XCTAssertEqual(actions, ["accepted", "rejected", "deferred"])
        XCTAssertTrue(outcomes.contains { $0.text("rejection_reason") == "not_true" })
    }
}
