import XCTest
import OrbitCore
import OrbitSQLite
@testable import OrbitStore

/// FIELD-NOTES FN-17 — a database that already holds data must be able to move
/// forward. Before this, `ensure` created the schema only when the database was
/// empty and `schema_version` was written once and never read, so every schema
/// change reached fresh installs only.
final class MigrationTests: XCTestCase {

    func testFreshDatabaseIsBornAtTheLatestVersion() throws {
        let db = try Database.openWriterInMemory()
        try Schema.create(on: db)
        XCTAssertEqual(try Schema.version(on: db), Schema.latestVersion,
                       "a fresh database already contains what the migrations add")
    }

    func testMigrateIsANoOpOnAFreshDatabase() throws {
        let db = try Database.openWriterInMemory()
        try Schema.create(on: db)
        try Schema.migrate(on: db)          // must not re-apply anything
        try Schema.migrate(on: db)
        XCTAssertEqual(try Schema.version(on: db), Schema.latestVersion)
    }

    /// The case that matters: an older database, with rows in it, is brought
    /// forward without losing them.
    func testAPopulatedOlderDatabaseMigratesWithoutLosingData() throws {
        let db = try Database.openWriterInMemory()
        try Schema.create(on: db)

        // stand in for the pre-migration shape
        try db.exec("DROP INDEX IF EXISTS person_alias_alias; DROP TABLE IF EXISTS person_alias;")
        try db.run("UPDATE orbit_meta SET value='1' WHERE key='schema_version'")
        try db.run(
            "INSERT INTO person (id, display_name, status, is_self, created_at) VALUES (?,?,?,?,?)",
            [.text("p1"), .text("Sarah"), .text("active"), .integer(0),
             .text("2026-07-01T00:00:00Z")])

        try Schema.migrate(on: db)

        XCTAssertEqual(try Schema.version(on: db), Schema.latestVersion)
        XCTAssertEqual(
            try db.scalar("SELECT display_name FROM person WHERE id='p1'").stringValue,
            "Sarah", "the row survives the migration")
        // and the thing the migration adds is usable
        try db.run("INSERT INTO person_alias (person_id, alias) VALUES (?,?)",
                   [.text("p1"), .text("Sarah C")])
        XCTAssertEqual(
            try db.scalar("SELECT COUNT(*) FROM person_alias WHERE person_id='p1'").intValue, 1)
    }

    func testEnsureMigratesAnExistingDatabaseRatherThanSkippingIt() throws {
        let db = try Database.openWriterInMemory()
        try Schema.create(on: db)
        try db.exec("DROP INDEX IF EXISTS person_alias_alias; DROP TABLE IF EXISTS person_alias;")
        try db.run("UPDATE orbit_meta SET value='1' WHERE key='schema_version'")

        try Schema.ensure(on: db)           // non-empty: the migrate path

        XCTAssertEqual(try Schema.version(on: db), Schema.latestVersion)
        XCTAssertEqual(
            try db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE name='person_alias'").intValue,
            1)
    }

    /// Read models are derived, so INV-4 has to keep holding after a migration.
    func testRebuildStillWorksAfterMigrating() throws {
        let db = try Database.openWriterInMemory()
        try Schema.create(on: db)
        try db.run("UPDATE orbit_meta SET value='1' WHERE key='schema_version'")
        try Schema.migrate(on: db)
        XCTAssertNoThrow(try ReadModels.rebuild(on: db))
    }
}
