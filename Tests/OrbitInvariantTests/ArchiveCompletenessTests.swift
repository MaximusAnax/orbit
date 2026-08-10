import XCTest
import Foundation
import OrbitCore
import OrbitSQLite
@testable import OrbitStore
@testable import OrbitWrite

/// PRIV-5 says the archive is the whole memory, readable and restorable. That
/// promise breaks quietly: a table added later is simply absent from
/// `Export.tables`, every existing test still passes, and the loss only shows
/// up as data missing after a restore nobody performs until they need it.
///
/// Caught for real — `person_alias` (migration 002) and `person_retirement`
/// (migration 003) were both added without reaching the export list, so a
/// restored archive would have forgotten who was retired and every alias that
/// makes person matching work.
///
/// This test is the durable form of the fix: it fails the moment a table exists
/// that is neither exported nor deliberately excluded.
final class ArchiveCompletenessTests: XCTestCase {

    /// Read models are rebuilt from the log, never restored (INV-4).
    private func isDerived(_ table: String) -> Bool { table.hasPrefix("rm_") }

    func testEveryLogTableIsExported() throws {
        let store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        let live = try store.db.query(
            """
            SELECT name FROM sqlite_master
            WHERE type='table' AND name NOT LIKE 'sqlite_%'
            """).compactMap { $0.text("name") }

        let exported = Set(Export.tables)
        let missing = live.filter { !isDerived($0) && !exported.contains($0)
                                    && !$0.hasSuffix("_fts")
                                    && !$0.contains("_fts_") }
        XCTAssertTrue(missing.isEmpty,
            "these tables are in the schema but not in Export.tables, so a PRIV-5 "
            + "restore would silently drop them: \(missing.sorted())")
    }

    func testExportListHasNoTableThatNoLongerExists() throws {
        let store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        let live = Set(try store.db.query(
            "SELECT name FROM sqlite_master WHERE type='table'").compactMap { $0.text("name") })
        let stale = Export.tables.filter { !live.contains($0) }
        XCTAssertTrue(stale.isEmpty, "Export.tables names tables that do not exist: \(stale)")
    }

    /// The specific loss that prompted this: retirement must survive a round trip,
    /// or restoring an archive un-hides everyone who was hidden.
    func testRetirementSurvivesARoundTrip() throws {
        let store = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        let edits = UserEditService(store)
        let person = try edits.createPerson(displayName: "Dara")
        try edits.retirePerson(person)

        let archive = try Export.dump(from: store.db)
        let restored = try WriteStore.inMemory(clock: FixedClock("2026-07-29T12:00:00Z"))
        try Export.restore(archive, into: restored.db)

        XCTAssertEqual(try restored.db.scalar(
            "SELECT COUNT(*) FROM person_retirement WHERE person_id=?",
            [.text(person)]).intValue, 1,
            "a restored archive forgot that this person was retired")
    }
}
