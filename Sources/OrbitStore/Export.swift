import Foundation
import OrbitSQLite

/// PRIV-5: export produces a complete, human-readable archive; a fresh install
/// restored from an export passes INV-4 equivalence (read models are derived,
/// so the archive carries the LOG — never the rm_* projections).
public enum Export {
    /// Log tables in FK-safe restore order. rm_* tables are excluded by
    /// design: they are rebuilt, not restored (INV-4).
    static let tables = [
        "orbit_meta", "person", "entity", "entity_alias", "contact_point",
        "event", "event_participant", "amendment", "extraction", "sync_run",
        "sync_person_ref", "sync_entity_ref", "thread", "assertion",
        "assertion_subject_candidate", "assertion_amendment", "proposal",
        "review_outcome", "relationship_state", "open_loop",
        "person_group", "group_membership", "saved_list",
    ]

    public static func dump(from db: Database) throws -> Data {
        var archive: [String: Any] = [
            "format": "orbit-archive",
            "format_version": 1,
        ]
        var payload: [String: [[String: Any]]] = [:]
        for table in tables {
            let rows = try db.query("SELECT * FROM \(table)")
            payload[table] = rows.map { row in
                var object: [String: Any] = [:]
                for (name, value) in zip(row.columns, row.values) {
                    switch value {
                    case .text(let s): object[name] = s
                    case .integer(let i): object[name] = i
                    case .real(let d): object[name] = d
                    case .blob(let data): object[name] = ["$blob": data.base64EncodedString()]
                    case .null: break   // absent key = NULL; keeps the archive readable
                    }
                }
                return object
            }
        }
        archive["tables"] = payload
        return try JSONSerialization.data(withJSONObject: archive,
                                          options: [.prettyPrinted, .sortedKeys])
    }

    /// Restore into a database that has the schema but no data. Read models
    /// are rebuilt from the restored log, completing the INV-4 round trip.
    public static func restore(_ data: Data, into db: Database) throws {
        guard let archive = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              archive["format"] as? String == "orbit-archive",
              let payload = archive["tables"] as? [String: [[String: Any]]] else {
            throw SQLiteError(code: -1, message: "not an orbit archive")
        }
        try db.run("PRAGMA defer_foreign_keys = ON")
        // meta row was created by Schema.create; the archive's copy replaces it
        try db.run("DELETE FROM orbit_meta")
        for table in tables {
            for object in payload[table] ?? [] {
                let columns = object.keys.sorted()
                guard !columns.isEmpty else { continue }
                let values: [SQLValue] = columns.map { key in
                    switch object[key] {
                    case let s as String: return .text(s)
                    case let blob as [String: String]:
                        guard let b64 = blob["$blob"], let d = Data(base64Encoded: b64) else {
                            return .null
                        }
                        return .blob(d)
                    case let n as NSNumber:
                        return CFNumberIsFloatType(n) ? .real(n.doubleValue) : .integer(n.int64Value)
                    default: return .null
                    }
                }
                let sql = "INSERT INTO \(table) (\(columns.joined(separator: ","))) " +
                          "VALUES (\(columns.map { _ in "?" }.joined(separator: ",")))"
                try db.run(sql, values)
            }
        }
        try ReadModels.rebuild(on: db)
    }
}
