import XCTest
import OrbitCore
import OrbitSQLite
import OrbitStore
import OrbitRecall
@testable import OrbitWrite

/// PIPE-14 (recall-ranking sanity, rule-based, 100%) + the model halves of
/// J-6 (Desk sections after three captures) and J-7 (Deck order + surfacing).
/// All data enters through the production funnel — no fixture INSERTs.
final class RecallTests: XCTestCase {
    var store: WriteStore!
    var edits: UserEditService!
    var proposals: ProposalResolutionService!
    let now = "2026-07-29T12:00:00Z"

    override func setUpWithError() throws {
        store = try WriteStore.inMemory(clock: FixedClock(now))
        edits = UserEditService(store)
        proposals = ProposalResolutionService(store)
    }

    // MARK: helpers (same shapes as the invariant suite)

    func person(_ name: String) throws -> String {
        try edits.createPerson(displayName: name)
    }

    @discardableResult
    func confirmedEvent(with people: [String], kind: EventKind = .dinner,
                        occurred: String, transcript: String = "we talked") throws -> String {
        let id = try edits.captureEvent(.init(
            kind: kind, occurredAt: occurred, transcript: transcript,
            participants: people.map { ($0, .confirmed, nil) }))
        try edits.confirmEvent(id, fullModelTranscribed: true)
        return id
    }

    @discardableResult
    func accepted(op: ProposalOp, payload: some Encodable, event: String) throws -> String {
        let x = try proposals.recordExtraction(event: event, version: 1, modelID: "test",
                                               promptVersion: "v1", payload: "{}")
        let run = try proposals.openSyncRun(event: event, extraction: x)
        let pid = try proposals.propose(syncRun: run, .init(
            op: op, payloadJSON: try PayloadCoding.encode(payload), rationale: "test"))!
        try proposals.resolve(proposal: pid, .accept)
        return pid
    }

    @discardableResult
    func fact(_ subject: String, _ predicate: String, _ verbatim: String,
              value: String? = nil, validFrom: String? = nil, event: String) throws -> String {
        try accepted(op: .assert, payload: AssertPayload(
            subject: .id(subject), predicate: predicate, objectValue: value ?? verbatim,
            verbatim: verbatim, validFrom: validFrom), event: event)
        let id = try store.db.scalar(
            "SELECT id FROM assertion WHERE subject_id=? AND verbatim=?",
            [.text(subject), .text(verbatim)]).stringValue
        return id ?? ""
    }

    func brief(_ personID: String) throws -> Brief {
        try BriefAssembler(reader: store.reader).assemble(personID: personID, now: now)
    }

    /// Nikos with three captures' worth of history: facts, a thread, a loop,
    /// and a change after the last meeting.
    func seedNikos() throws -> String {
        let nikos = try person("Nikos")
        let e1 = try confirmedEvent(with: [nikos], occurred: "2024-06-01T20:00:00Z")
        try edits.setFirstMet(person: nikos, event: e1)
        _ = try fact(nikos, "location", "Nikos is from Greece", event: e1)
        _ = try fact(nikos, "interest", "he free-dives off Crete every summer", event: e1)

        let e2 = try confirmedEvent(with: [nikos], occurred: "2025-03-10T19:00:00Z")
        _ = try accepted(op: .openThread, payload: OpenThreadPayload(
            ref: "t1", person: .id(nikos), title: "interviewing at a robotics startup",
            archetype: "event_pending", expectedResolutionAt: "2025-05"), event: e2)
        _ = try accepted(op: .openLoop, payload: OpenLoopPayload(
            person: .id(nikos), direction: "abdoul_owes",
            description: "send him the freediving documentary"), event: e2)

        // observed AFTER the last time they actually met → "changed since"
        let note = try edits.captureEvent(.init(
            kind: .note, occurredAt: "2026-07-01T09:00:00Z",
            transcript: "Nikos moved to Berlin",
            participants: [(nikos, .about, nil)]))
        try edits.confirmEvent(note, fullModelTranscribed: true)
        _ = try fact(nikos, "location", "Nikos moved to Berlin", validFrom: "2026-06", event: note)
        return nikos
    }

    // MARK: PIPE-14 — recall-ranking sanity (rule-based, 100%)

    func testPIPE14_openThreadsPresent() throws {
        let nikos = try seedNikos()
        let b = try brief(nikos)
        XCTAssertEqual(b.openThreads.map(\.title), ["interviewing at a robotics startup"])
    }

    func testPIPE14_heroIsTopUnsurfacedItem() throws {
        let nikos = try seedNikos()
        // surface one fact; the hero must be an item never shown, oldest-known first
        let surfaced = try store.db.scalar(
            "SELECT id FROM assertion WHERE verbatim LIKE '%Greece%'").stringValue!
        try edits.markSurfaced(assertions: [surfaced])
        let b = try brief(nikos)
        XCTAssertEqual(b.hero?.claim, "he free-dives off Crete every summer",
                       "hero = top unsurfaced item, not the recently-shown one")
        XCTAssertFalse(b.hero!.reason.isEmpty, "the reason travels with the item (P9)")
    }

    func testPIPE14_mutedAbsentEverywhere() throws {
        let nikos = try seedNikos()
        let muted = try store.db.scalar(
            "SELECT id FROM assertion WHERE verbatim LIKE '%free-dives%'").stringValue!
        try edits.setMuted(assertion: muted, true)
        let b = try brief(nikos)
        let everywhere = [b.hero?.claim ?? ""] + b.changed.map(\.line) + b.forgotten.map(\.claim)
        XCTAssertFalse(everywhere.contains { $0.contains("free-dives") },
                       "muted facts never render, in any section")
    }

    func testPIPE14_pinnedWinsHeroOutright() throws {
        let nikos = try seedNikos()
        let pinned = try store.db.scalar(
            "SELECT id FROM assertion WHERE verbatim LIKE '%Greece%'").stringValue!
        // even a freshly-surfaced pinned fact beats every unsurfaced one
        try edits.markSurfaced(assertions: [pinned])
        try edits.setPinned(assertion: pinned, true)
        let b = try brief(nikos)
        XCTAssertEqual(b.hero?.claim, "Nikos is from Greece")
        XCTAssertTrue(b.hero!.pinned)
        XCTAssertEqual(b.hero?.reason, "You pinned this.")
    }

    func testPIPE14_hardshipIsContextNeverOpener() throws {
        let nikos = try person("Eliah")
        let e = try confirmedEvent(with: [nikos], occurred: "2026-05-01T20:00:00Z")
        _ = try fact(nikos, "location", "he lives in Atlanta now", event: e)
        _ = try fact(nikos, "interest", "he builds modular synths", event: e)
        _ = try accepted(op: .openThread, payload: OpenThreadPayload(
            ref: "t1", person: .id(nikos), title: "his mother's illness",
            archetype: "condition_hardship"), event: e)
        let b = try brief(nikos)
        // present in the brief as context…
        XCTAssertEqual(b.openThreads.count, 1)
        XCTAssertTrue(b.openThreads[0].isHardship)
        // …but the Deck frames it as context, never an opener
        let deck = Deck.build(from: b)
        let card = deck.cards.first { $0.main == "his mother's illness" }
        XCTAssertNotNil(card)
        XCTAssertEqual(card?.tag, "Context")
        XCTAssertTrue(card!.sub.contains("let them bring it up"))
    }

    // MARK: J-6 — profile after three captures

    func testJ6_deskSectionsAfterThreeCaptures() throws {
        let nikos = try seedNikos()
        let b = try brief(nikos)

        XCTAssertEqual(b.header.name, "Nikos")
        XCTAssertTrue(b.header.metLine.contains("met 2024-06"))
        XCTAssertTrue(b.header.metLine.contains("last seen 2025-03-10"),
                      "'about' notes never count as seeing someone (INV-11)")
        XCTAssertNotNil(b.hero)
        XCTAssertEqual(b.openThreads.count, 1)
        XCTAssertEqual(b.loops.map(\.tag), ["You owe"])
        XCTAssertEqual(b.changed.map(\.line), ["Nikos moved to Berlin"])
        XCTAssertFalse(b.forgotten.isEmpty)
        XCTAssertEqual(b.timeline.eventCount, 3)   // true count (D-9)
        XCTAssertEqual(b.timeline.sinceYear, "2024")
        XCTAssertTrue(b.deckAvailable)

        // items live in exactly one section — the change never doubles as "forgotten"
        XCTAssertFalse(b.forgotten.contains { $0.claim == "Nikos moved to Berlin" })
        // era labels: first-met-year facts read as "when you first met"
        XCTAssertTrue(b.forgotten.allSatisfy { $0.eraLabel == "when you first met" })
    }

    func testJ6_sparseProfileCollapsesNotPlaceholds() throws {
        let p = try person("Mara")
        let e = try confirmedEvent(with: [p], occurred: "2026-07-20T18:00:00Z")
        _ = try fact(p, "employment", "she teaches ceramics", event: e)
        let b = try brief(p)
        XCTAssertNotNil(b.hero)
        XCTAssertTrue(b.openThreads.isEmpty, "no filler: absent, not placeholder'd")
        XCTAssertTrue(b.loops.isEmpty)
        XCTAssertTrue(b.changed.isEmpty)
        XCTAssertFalse(b.deckAvailable, "the pill hides on near-empty profiles")
    }

    // MARK: J-7 — Deck order = Desk order; surfacing writes; the end card

    func testJ7_deckOrderAndEndCard() throws {
        let nikos = try seedNikos()
        let b = try brief(nikos)
        let deck = Deck.build(from: b)

        XCTAssertGreaterThanOrEqual(deck.cards.count, 5)
        XCTAssertLessThanOrEqual(deck.cards.count, 7)
        // card order teaches the Desk's map: hero → thread → loop → change → forgotten
        XCTAssertEqual(deck.cards.first?.tag, "If you remember one thing")
        let tags = deck.cards.map(\.tag)
        XCTAssertEqual(tags.firstIndex(of: "Open").map { $0 > 0 }, true)
        XCTAssertLessThan(tags.firstIndex(of: "Open")!, tags.firstIndex(of: "You owe")!)
        XCTAssertLessThan(tags.firstIndex(of: "You owe")!,
                          tags.firstIndex(of: "Since you last saw them")!)
        // always ends on the tool's one memory-voice sentence
        XCTAssertEqual(deck.cards.last?.main, "Go be present.")
        XCTAssertTrue(deck.cards.last!.isEnd)

        // deck sessions count as surfaced — through the funnel
        try edits.markSurfaced(assertions: deck.surfacedAssertionIDs)
        for id in deck.surfacedAssertionIDs {
            let at = try store.db.scalar(
                "SELECT last_surfaced_at FROM assertion WHERE id=?", [.text(id)]).stringValue
            XCTAssertEqual(at, now, "last_surfaced_at written on shown items")
        }
    }

    func testJ7_surfacingRotatesTheHero() throws {
        let nikos = try seedNikos()
        let before = try brief(nikos)
        let heroID = try XCTUnwrap(before.hero?.assertionID)
        try edits.markSurfaced(assertions: [heroID])
        let after = try brief(nikos)
        XCTAssertNotEqual(after.hero?.assertionID, heroID,
                          "surfacing feeds back into the forgotten-ranking (§8 signal 4)")
    }
}
