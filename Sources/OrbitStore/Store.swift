import Foundation
import OrbitCore
import OrbitSQLite

/// Loads the shipped SQL resources. The .sql files ARE the schema — Swift never
/// restates DDL, so the T1-verified SQL and the production runtime cannot drift.
public enum Schema {
    static func resource(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "sql", subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw SQLiteError(code: -1, message: "missing SQL resource \(name)")
        }
        return text
    }

    /// Create a fresh database (schema + triggers + read-model shells).
    public static func create(on db: Database) throws {
        for name in ["001_schema", "002_triggers", "003_readmodels"] {
            try db.exec(try resource(name))
        }
        try db.run(
            "INSERT INTO orbit_meta (key, value) VALUES ('schema_version','1')")
    }

    /// Idempotent open-or-create for app startup.
    public static func ensure(on db: Database) throws {
        let exists = try db.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='person'")
        if exists.intValue == 0 { try create(on: db) }
    }
}

public enum ReadModels {
    /// Full rebuild from the log (INV-4's reference implementation).
    public static func rebuild(on db: Database) throws {
        try db.exec(try Schema.resource("004_rebuild_readmodels"))
    }

    /// Dump for INV-4 equivalence diffs (stable ordering).
    public static func fingerprint(on db: Database) throws -> [[Row]] {
        try [
            db.query("SELECT * FROM rm_current_state ORDER BY assertion_id"),
            db.query("SELECT * FROM rm_network_edge ORDER BY edge_kind, from_person, COALESCE(to_person,''), COALESCE(to_entity,''), evidence_id"),
            db.query("SELECT * FROM rm_contact_rhythm ORDER BY person_id, month"),
        ]
    }
}

/// Read-side queries shared by recall/search/app. Read-only by construction —
/// hand it a read-only connection in production.
public struct StoreReader {
    public let db: Database
    public init(_ db: Database) { self.db = db }

    /// Canonical person id through the merge pointer (Decision 6: resolution at read time).
    public func canonicalPerson(_ id: String) throws -> String {
        let merged = try db.scalar("SELECT merged_into FROM person WHERE id=?", [.text(id)])
        return merged.stringValue ?? id
    }

    public func person(_ id: String) throws -> Row? {
        try db.query("SELECT * FROM person WHERE id=?", [.text(id)]).first
    }

    public func selfPerson() throws -> Row? {
        try db.query("SELECT * FROM person WHERE is_self=1").first
    }

    /// Effective event = stored row + amendments applied in order (ledger semantics).
    public func effectiveEvent(_ id: String) throws -> [String: SQLValue]? {
        guard let base = try db.query("SELECT * FROM event WHERE id=?", [.text(id)]).first else {
            return nil
        }
        var fields = Dictionary(uniqueKeysWithValues: zip(base.columns, base.values))
        let amendments = try db.query(
            "SELECT field, new_value FROM amendment WHERE event_id=? ORDER BY created_at, id",
            [.text(id)])
        for a in amendments {
            if let f = a.text("field") { fields[f] = a["new_value"] }
        }
        return fields
    }

    public func effectiveAssertion(_ id: String) throws -> [String: SQLValue]? {
        guard let base = try db.query("SELECT * FROM assertion WHERE id=?", [.text(id)]).first else {
            return nil
        }
        var fields = Dictionary(uniqueKeysWithValues: zip(base.columns, base.values))
        let amendments = try db.query(
            "SELECT field, new_value FROM assertion_amendment WHERE assertion_id=? ORDER BY created_at, id",
            [.text(id)])
        for a in amendments {
            if let f = a.text("field") { fields[f] = a["new_value"] }
        }
        return fields
    }

    /// Current facts for one person, from the read model.
    public func currentState(of personID: String) throws -> [Row] {
        try db.query(
            "SELECT * FROM rm_current_state WHERE subject_id=? ORDER BY observed_at",
            [.text(canonicalPerson(personID))])
    }

    /// Validity-time query: what was true in the world at `date` (INV-21 semantics).
    public func facts(of personID: String, validAt date: String) throws -> [Row] {
        try db.query(
            """
            SELECT a.* FROM assertion a
            JOIN person p ON p.id = a.subject_id
            WHERE COALESCE(p.merged_into, p.id) = ?
              AND a.status='active'
              AND a.valid_from IS NOT NULL AND a.valid_from <= ?
              AND (a.valid_to IS NULL OR a.valid_to > ?)
            ORDER BY a.valid_from
            """,
            [.text(canonicalPerson(personID)), .text(date), .text(date)])
    }

    /// Observation-time query: what was known by `date`.
    public func facts(of personID: String, knownBy date: String) throws -> [Row] {
        try db.query(
            """
            SELECT a.* FROM assertion a
            JOIN person p ON p.id = a.subject_id
            WHERE COALESCE(p.merged_into, p.id) = ?
              AND a.status='active' AND a.observed_at <= ?
            ORDER BY a.observed_at
            """,
            [.text(canonicalPerson(personID)), .text(date), .text(date)])
    }

    /// The audit view: everything ever believed, including retractions (INV-2).
    public func audit(of personID: String) throws -> [Row] {
        try db.query(
            """
            SELECT a.* FROM assertion a
            JOIN person p ON p.id = a.subject_id
            WHERE COALESCE(p.merged_into, p.id) = ?
            ORDER BY a.observed_at
            """,
            [.text(canonicalPerson(personID))])
    }

    public func timeline(of personID: String) throws -> [Row] {
        try db.query(
            "SELECT * FROM v_timeline WHERE person_id=? ORDER BY at",
            [.text(canonicalPerson(personID))])
    }

    public func openThreads(of personID: String) throws -> [Row] {
        try db.query(
            "SELECT * FROM thread WHERE person_id=? AND state='open' ORDER BY last_mentioned_at DESC",
            [.text(canonicalPerson(personID))])
    }

    public func openLoops(of personID: String) throws -> [Row] {
        try db.query(
            "SELECT * FROM open_loop WHERE person_id=? AND state='open'",
            [.text(canonicalPerson(personID))])
    }

    public func pendingProposals(syncRun: String) throws -> [Row] {
        try db.query(
            "SELECT * FROM proposal WHERE sync_run_id=? AND state IN ('pending','deferred') ORDER BY id",
            [.text(syncRun)])
    }

    /// Event sync status is DERIVED, never stored (Decision 4).
    public func syncStatus(of eventID: String) throws -> String {
        let runs = try db.scalar(
            "SELECT COUNT(*) FROM sync_run WHERE event_id=?", [.text(eventID)])
        if runs.intValue == 0 { return "unsynced" }
        let counts = try db.query(
            """
            SELECT
              SUM(CASE WHEN p.state = 'pending' THEN 1 ELSE 0 END) AS pending,
              SUM(CASE WHEN p.state IN ('accepted','rejected','superseded') THEN 1 ELSE 0 END) AS resolved,
              SUM(CASE WHEN p.state = 'deferred' THEN 1 ELSE 0 END) AS deferred,
              COUNT(*) AS total
            FROM proposal p JOIN sync_run s ON s.id = p.sync_run_id
            WHERE s.event_id=?
            """,
            [.text(eventID)]).first!
        let pending = counts.int("pending") ?? 0
        let deferred = counts.int("deferred") ?? 0
        let total = counts.int("total") ?? 0
        if pending > 0 { return "in_review" }
        if deferred > 0 || (total > 0 && (counts.int("resolved") ?? 0) < total) { return "partially_resolved" }
        return "fully_resolved"
    }
}
