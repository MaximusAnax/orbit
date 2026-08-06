import XCTest
import OrbitCore
import OrbitSQLite
import OrbitStore
@testable import OrbitWrite

/// FIELD-NOTES FN-13 / FN-15 — correcting what is already saved.
/// Before these paths existed, review was the only moment anything could be
/// fixed: a name was frozen at first write and a wrong fact could only be
/// answered by recording another memo.
final class CorrectionTests: XCTestCase {
    var store: WriteStore!
    var edits: UserEditService!

    override func setUpWithError() throws {
        store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        edits = UserEditService(store)
    }

    @discardableResult
    func entity(_ name: String, kind: String = "event_series") throws -> String {
        let id = OrbitID.make()
        try store.db.run(
            "INSERT INTO entity (id, kind, canonical_name) VALUES (?,?,?)",
            [.text(id), .text(kind), .text(name)])
        return id
    }

    /// The FN-11 case: nobody says the full name of anything aloud, so the
    /// entity is created under the shorthand. Correcting it must not cost the
    /// shorthand — the next voice note will say it that way again.
    func testRenamingAnEntityKeepsTheOldNameAsAnAlias() throws {
        let id = try entity("Colorstack conference")
        try edits.renameEntity(id, canonicalName: "ColorStack StackedUp Summit '26")

        XCTAssertEqual(
            try store.db.scalar("SELECT canonical_name FROM entity WHERE id=?",
                                [.text(id)]).stringValue,
            "ColorStack StackedUp Summit '26")
        let aliases = try store.db.query(
            "SELECT alias FROM entity_alias WHERE entity_id=?", [.text(id)])
            .compactMap { $0.text("alias") }
        XCTAssertTrue(aliases.contains("Colorstack conference"),
                      "the spoken form still has to resolve here (§7.10 guarantee 3)")
    }

    func testRenamingToTheSameNameIsANoOp() throws {
        let id = try entity("Harvard", kind: "school")
        try edits.renameEntity(id, canonicalName: "Harvard")
        let aliases = try store.db.query(
            "SELECT alias FROM entity_alias WHERE entity_id=?", [.text(id)]).count
        XCTAssertEqual(aliases, 0, "nothing changed, so nothing is recorded")
    }

    func testRenamingRejectsAnEmptyName() throws {
        let id = try entity("CMU", kind: "school")
        XCTAssertThrowsError(try edits.renameEntity(id, canonicalName: "   "))
    }

    func testRenamingAnUnknownEntityIsNotFound() {
        XCTAssertThrowsError(try edits.renameEntity("nope", canonicalName: "X"))
    }

    /// FN-15: a saved fact can be corrected without touching what he said.
    func testAmendingAFactLeavesTheVerbatimAlone() throws {
        let sarah = try edits.createPerson(displayName: "Sarah")
        let event = try edits.captureEvent(.init(
            kind: .dinner, occurredAt: "2026-07-01T20:00:00Z",
            transcript: "Sarah is a staff engineer now",
            participants: [(sarah, .confirmed, nil)]))
        try edits.confirmEvent(event, fullModelTranscribed: true)
        let proposals = ProposalResolutionService(store)
        let x = try proposals.recordExtraction(event: event, version: 1, modelID: "test",
                                               promptVersion: "v1", payload: "{}")
        let run = try proposals.openSyncRun(event: event, extraction: x)
        let pid = try proposals.propose(syncRun: run, .init(
            op: .assert,
            payloadJSON: try PayloadCoding.encode(AssertPayload(
                subject: .id(sarah), predicate: "employment",
                objectValue: "staff engineer now at",     // the FN-10 shape: prose in the tag
                verbatim: "Sarah is a staff engineer now")),
            rationale: "test"))!
        try proposals.resolve(proposal: pid, .accept)
        let assertionID = try XCTUnwrap(try store.db.scalar(
            "SELECT id FROM assertion WHERE subject_id=?", [.text(sarah)]).stringValue)

        try edits.amendAssertion(assertionID, field: "object_value",
                                 newValue: "staff engineer", reason: "corrected on the desk")

        // the read model shows the correction...
        XCTAssertEqual(
            try store.db.scalar("SELECT object_value FROM rm_current_state WHERE assertion_id=?",
                                [.text(assertionID)]).stringValue,
            "staff engineer")
        // ...the quote is untouched (P5)...
        XCTAssertEqual(
            try store.db.scalar("SELECT verbatim FROM assertion WHERE id=?",
                                [.text(assertionID)]).stringValue,
            "Sarah is a staff engineer now")
        // ...and the original value is still readable in the ledger (INV-1)
        XCTAssertEqual(
            try store.db.scalar("SELECT object_value FROM assertion WHERE id=?",
                                [.text(assertionID)]).stringValue,
            "staff engineer now at")
    }
}
