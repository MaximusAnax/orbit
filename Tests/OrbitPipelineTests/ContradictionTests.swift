import XCTest
import OrbitCore
import OrbitStore
import OrbitWrite
@testable import OrbitPipeline

/// FIELD-NOTES FN-9 / FN-2 — contradictions inside one memo, and the
/// origin-vs-residence problem that made the old rule ask wrong questions.
final class ContradictionTests: XCTestCase {

    func draft(_ subject: String, _ predicate: String, value: String,
               from: String? = nil, to: String? = nil,
               verbatim: String = "said so") -> ExtractionPayload.AssertionDraft {
        .init(subjectRef: subject, predicate: predicate, objectValue: value,
              verbatim: verbatim, validFrom: from, validTo: to)
    }

    var engine: SyncEngine {
        SyncEngine(try! WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z")))
    }

    // MARK: FN-9 — two dated claims in one memo

    func testDatedMoveClosesTheEarlierResidence() {
        let drafts = [
            draft("p1", "location", value: "New York", from: "2015",
                  verbatim: "he lived in New York"),
            draft("p1", "location", value: "San Francisco", from: "2022",
                  verbatim: "moved to San Francisco in 2022"),
        ]
        let found = engine.withinRunSupersessions(drafts)
        XCTAssertEqual(found[0]?.closedAt, "2022",
                       "the earlier residence ends when the later one starts")
        XCTAssertTrue(found[0]?.byVerbatim.contains("San Francisco") ?? false,
                      "the rationale quotes what ended it")
        XCTAssertNil(found[1], "the current claim stays open")
    }

    /// The case that must NOT fire: a birthplace and a current city are both
    /// true. Without dates on both sides there is no order to infer, and
    /// guessing one is the inference P4 forbids.
    func testUndatedOriginIsNeverClosedByAMove() {
        let drafts = [
            draft("p1", "location", value: "New York",
                  verbatim: "born and raised in New York"),
            draft("p1", "location", value: "San Francisco", from: "2022",
                  verbatim: "in San Francisco since 2022"),
        ]
        XCTAssertTrue(engine.withinRunSupersessions(drafts).isEmpty,
                      "an undated origin claim is background, not a superseded residence")
    }

    /// FN-9's guard 1 was `if case .id = subject` — a person introduced by this
    /// memo is a ref, so their first memo could never be checked against itself.
    /// The within-run pass keys on the ref, so a brand-new person is covered.
    func testWorksForAPersonWhoIsNewInThisMemo() {
        let drafts = [
            draft("p_new", "employment", value: "Stripe", from: "2020",
                  verbatim: "he was at Stripe"),
            draft("p_new", "employment", value: "Google", from: "2024",
                  verbatim: "he's at Google now"),
        ]
        XCTAssertEqual(engine.withinRunSupersessions(drafts)[0]?.closedAt, "2024")
    }

    func testThreeStepHistoryClosesEachStepAtTheNextOne() {
        let drafts = [
            draft("p1", "employment", value: "A", from: "2015", verbatim: "started at A"),
            draft("p1", "employment", value: "B", from: "2018", verbatim: "then B"),
            draft("p1", "employment", value: "C", from: "2022", verbatim: "now C"),
        ]
        let found = engine.withinRunSupersessions(drafts)
        XCTAssertEqual(found[0]?.closedAt, "2018", "closed by the NEXT job, not the last")
        XCTAssertEqual(found[1]?.closedAt, "2022")
        XCTAssertNil(found[2])
    }

    // MARK: things that are not contradictions

    func testRestatingTheSameFactIsNotAContradiction() {
        let drafts = [
            draft("p1", "location", value: "Berlin", from: "2020", verbatim: "in Berlin"),
            draft("p1", "location", value: "berlin", from: "2023", verbatim: "still Berlin"),
        ]
        XCTAssertTrue(engine.withinRunSupersessions(drafts).isEmpty,
                      "same place, different mention — one fact, not two")
    }

    func testCumulativePredicatesNeverSupersede() {
        for predicate in ["interest", "trait", "relation", "skill"] {
            let drafts = [
                draft("p1", predicate, value: "one", from: "2015", verbatim: "a"),
                draft("p1", predicate, value: "two", from: "2022", verbatim: "b"),
            ]
            XCTAssertTrue(engine.withinRunSupersessions(drafts).isEmpty,
                          "\(predicate) accumulates — two of them are two facts")
        }
    }

    func testDifferentPeopleNeverSupersedeEachOther() {
        let drafts = [
            draft("p1", "location", value: "New York", from: "2015", verbatim: "a"),
            draft("p2", "location", value: "San Francisco", from: "2022", verbatim: "b"),
        ]
        XCTAssertTrue(engine.withinRunSupersessions(drafts).isEmpty)
    }

    func testAnAlreadyClosedClaimIsLeftAlone() {
        let drafts = [
            draft("p1", "employment", value: "A", from: "2015", to: "2017", verbatim: "a"),
            draft("p1", "employment", value: "B", from: "2022", verbatim: "b"),
        ]
        XCTAssertTrue(engine.withinRunSupersessions(drafts).isEmpty,
                      "it already carries its end date; nothing to infer")
    }

    // MARK: FN-2 — the qualifier decides, not the dates

    func testOriginIsNeverSupersededEvenWhenDated() {
        let drafts = [
            draft("p1", "location", value: "origin", from: "1998",
                  verbatim: "born in New York in 1998"),
            draft("p1", "location", value: "residence", from: "2022",
                  verbatim: "moved to San Francisco in 2022"),
        ]
        XCTAssertTrue(engine.withinRunSupersessions(drafts).isEmpty,
                      "a birthplace with a year is still a birthplace")
    }

    func testResidenceSupersedesResidence() {
        let drafts = [
            draft("p1", "location", value: "residence", from: "2015", verbatim: "lived in NY"),
            draft("p1", "location", value: "residence", from: "2022", verbatim: "now in SF"),
        ]
        XCTAssertEqual(engine.withinRunSupersessions(drafts)[0]?.closedAt, "2022")
    }

    func testIsResidenceFallsBackToDatesForPreQualifierFacts() {
        // written before prompt v3: no qualifier, so the old heuristic applies
        XCTAssertTrue(SyncEngine.isResidence(value: nil, hasStart: true))
        XCTAssertFalse(SyncEngine.isResidence(value: nil, hasStart: false))
        XCTAssertFalse(SyncEngine.isResidence(value: "New York", hasStart: false))
        // and the qualifier always wins over the dates
        XCTAssertFalse(SyncEngine.isResidence(value: "origin", hasStart: true))
        XCTAssertTrue(SyncEngine.isResidence(value: "residence", hasStart: false))
    }
}
