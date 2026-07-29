import XCTest
import OrbitCore
import OrbitSQLite
import OrbitStore
import OrbitSearch
@testable import OrbitWrite

/// The executable form of docs/evals/goldens/search.yaml (S-1..S-10) — authored
/// with the goldens BEFORE the Searcher existed (EVALS §3.4). The corpus enters
/// through the production funnel; every expectation mirrors the YAML by id.
final class SearchTests: XCTestCase {
    var store: WriteStore!
    var edits: UserEditService!
    var proposals: ProposalResolutionService!
    var searcher: Searcher!

    var nikos = "", james = "", maya = "", alex = "", sarah = ""

    override func setUpWithError() throws {
        store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        edits = UserEditService(store)
        proposals = ProposalResolutionService(store)
        searcher = Searcher(reader: store.reader)
        try seedCorpus()
    }

    // MARK: corpus (docs/evals/goldens/search.yaml `corpus:`)

    func event(_ kind: EventKind, _ occurred: String, title: String? = nil,
               participants: [(String, Attendance, String?)]) throws -> String {
        let id = try edits.captureEvent(.init(
            kind: kind, occurredAt: occurred, transcript: "…", title: title,
            participants: participants))
        try edits.confirmEvent(id, fullModelTranscribed: true)
        return id
    }

    func fact(_ subject: String, _ predicate: String, _ verbatim: String,
              value: String? = nil, entity: EntityRef? = nil, validFrom: String? = nil,
              sourceKind: String = "firsthand", attributedTo: String? = nil,
              event: String) throws {
        let x = try proposals.recordExtraction(event: event, version: 1, modelID: "test",
                                               promptVersion: "v1", payload: "{}")
        let run = try proposals.openSyncRun(event: event, extraction: x)
        let pid = try proposals.propose(syncRun: run, .init(
            op: .assert,
            payloadJSON: try PayloadCoding.encode(AssertPayload(
                subject: .id(subject), predicate: predicate, objectEntity: entity,
                objectValue: value ?? verbatim, verbatim: verbatim, validFrom: validFrom,
                sourceKind: sourceKind,
                attributedTo: attributedTo.map { .id($0) })),
            rationale: "seed"))!
        try proposals.resolve(proposal: pid, .accept)
    }

    func seedCorpus() throws {
        nikos = try edits.createPerson(displayName: "Nikos")
        james = try edits.createPerson(displayName: "James")
        maya = try edits.createPerson(displayName: "Maya", status: .knownOf)
        alex = try edits.createPerson(displayName: "Alex")
        sarah = try edits.createPerson(displayName: "Sarah")

        let picnic = try event(.party, "2026-07-12T14:00:00Z",
                               title: "Y Combinator Startup School Picnic",
                               participants: [(nikos, .confirmed, nil)])
        try edits.setFirstMet(person: nikos, event: picnic)
        let dinner = try event(.dinner, "2025-11-02T20:00:00Z",
                               participants: [(james, .confirmed, nil)])
        let intro = try event(.introduction, "2026-02-20T18:00:00Z",
                              participants: [(alex, .confirmed, "introducer"),
                                             (maya, .about, nil)])
        let coffee = try event(.coffee, "2026-03-05T10:00:00Z",
                               participants: [(sarah, .confirmed, nil)])

        try fact(nikos, "location", "Nikos is from Greece", event: picnic)
        try fact(nikos, "interest", "he free-dives off Crete", event: picnic)
        try fact(james, "employment", "James works at Google", value: "Google",
                 validFrom: "2023-01", event: dinner)
        try fact(james, "location", "he's settled in New York", value: "New York",
                 event: dinner)
        try fact(maya, "employment", "Alex's friend Maya is an engineer at Google",
                 value: "Google", sourceKind: "secondhand", attributedTo: alex,
                 event: intro)
        try fact(sarah, "skill", "Sarah runs the visa clinic", value: "visa clinic",
                 event: coffee)
    }

    // MARK: helpers

    func people(_ result: Searcher.Result) -> [Searcher.PersonHit] {
        if case .people(let hits) = result { return hits }
        return []
    }

    func answer(_ result: Searcher.Result) throws -> Searcher.Answer {
        guard case .answer(let a) = result else {
            throw XCTSkip("expected question shape")
        }
        return a
    }

    func probably(_ result: Searcher.Result) -> Searcher.Probably? {
        if case .probably(let p, _) = result { return p }
        return nil
    }

    // MARK: name shape

    func testS1_nameIsProvenanceAnchored() throws {
        let hits = people(try searcher.search("Sarah"))
        XCTAssertEqual(hits.first?.name, "Sarah")
        XCTAssertFalse(hits.first!.anchor.isEmpty,
                       "a name result carries provenance, not a bare name")
    }

    func testS2_misspellingStillLands() throws {
        XCTAssertEqual(people(try searcher.search("Sara")).first?.name, "Sarah")
    }

    func testS3_directName() throws {
        XCTAssertEqual(people(try searcher.search("Nikos")).first?.name, "Nikos")
    }

    // MARK: question shape

    func testS4_whoAtGoogle() throws {
        let a = try answer(try searcher.search("who do I know at Google?"))
        XCTAssertEqual(a.firsthand.map(\.name), ["James"])
        XCTAssertEqual(a.maybe.map(\.name), ["Maya"], "the And-maybe band holds known-of people")
        XCTAssertEqual(a.maybe.first?.source, "Alex told you", "every maybe cites its source")
        XCTAssertTrue(a.firsthand.first!.evidence.contains { $0.text == "James works at Google" })
        XCTAssertEqual(a.firsthand.first?.evidence.first?.timeBound, "since 2023-01",
                       "evidence is time-bounded")
    }

    func testS5_whereDoesJamesWork() throws {
        let a = try answer(try searcher.search("where does James work?"))
        XCTAssertEqual(a.factAnswer, "Google")
        XCTAssertEqual(a.firsthand.first?.name, "James")
        XCTAssertTrue(a.firsthand.first!.evidence.contains { $0.text == "James works at Google" })
    }

    func testS6_throughAlex() throws {
        let a = try answer(try searcher.search("who did I meet through Alex?"))
        XCTAssertTrue(a.firsthand.isEmpty, "Maya was never actually met")
        XCTAssertEqual(a.maybe.map(\.name), ["Maya"])
        XCTAssertEqual(a.maybe.first?.source, "Alex told you")
    }

    func testS7_askAboutVisas() throws {
        let a = try answer(try searcher.search("who should I ask about visas?"))
        XCTAssertEqual(a.firsthand.map(\.name), ["Sarah"])
        XCTAssertTrue(a.firsthand.first!.evidence.contains { $0.text == "Sarah runs the visa clinic" })
    }

    // MARK: fragment shape

    func testS8_greecePicnicGuy() throws {
        let p = try XCTUnwrap(probably(try searcher.search("the guy from Greece at the picnic")))
        XCTAssertEqual(p.name, "Nikos", "Probably Nikos — here's why")
        XCTAssertTrue(p.evidence.contains { $0.text == "Nikos is from Greece" })
        XCTAssertGreaterThanOrEqual(p.evidence.count, 2,
                                    "the location fact AND the picnic event both cited")
    }

    func testS9_freeDivingCrete() throws {
        let p = try XCTUnwrap(probably(try searcher.search("free diving crete")))
        XCTAssertEqual(p.name, "Nikos")
        XCTAssertTrue(p.evidence.contains { $0.text == "he free-dives off Crete" })
    }

    // MARK: absence — search never invents

    func testS10_unknownCompanyIsEmpty() throws {
        let a = try answer(try searcher.search("who do I know at Stripe?"))
        XCTAssertTrue(a.firsthand.isEmpty)
        XCTAssertTrue(a.maybe.isEmpty, "empty answers render empty (D-8), never guessed")
    }

    // MARK: muted stays invisible here too (D-suite consistency)

    func testMutedFactsNeverSurface() throws {
        let id = try store.db.scalar(
            "SELECT id FROM assertion WHERE verbatim='Sarah runs the visa clinic'").stringValue!
        try edits.setMuted(assertion: id, true)
        let a = try answer(try searcher.search("who should I ask about visas?"))
        XCTAssertTrue(a.firsthand.isEmpty)
    }
}
