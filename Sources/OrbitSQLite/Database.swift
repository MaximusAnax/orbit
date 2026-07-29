import CSQLite
import Foundation

public struct SQLiteError: Error, CustomStringConvertible, Sendable {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

/// A single SQLite connection. Reader/writer separation is the point of this type:
/// `openReadOnly` is public; `openWriter` exists for OrbitWrite (and migrations)
/// alone — enforced by scripts/lint-writepath.sh in CI (INV-5, layer 3) on top of
/// the immutability triggers (layer 1).
public final class Database {
    let handle: OpaquePointer

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    public static func openReadOnly(path: String) throws -> Database {
        try open(path: path, flags: SQLITE_OPEN_READONLY)
    }

    /// The sole writable constructor. Do not call outside OrbitWrite/migrations.
    public static func openWriter(path: String) throws -> Database {
        try open(path: path, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
    }

    /// In-memory writer for tests and the eval harness.
    public static func openWriterInMemory() throws -> Database {
        try open(path: ":memory:", flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
    }

    private static func open(path: String, flags: Int32) throws -> Database {
        var h: OpaquePointer?
        let rc = sqlite3_open_v2(path, &h, flags, nil)
        guard rc == SQLITE_OK, let handle = h else {
            let msg = h.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            if let h { sqlite3_close_v2(h) }
            throw SQLiteError(code: rc, message: msg)
        }
        let db = Database(handle: handle)
        try db.exec("PRAGMA foreign_keys = ON")
        return db
    }

    func check(_ rc: Int32) throws {
        guard rc == SQLITE_OK || rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(handle)))
        }
    }

    /// Execute a script (multiple statements, no bindings).
    public func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(err)
            throw SQLiteError(code: rc, message: message)
        }
    }

    /// Run a single statement with bindings.
    public func run(_ sql: String, _ bindings: [SQLValue] = []) throws {
        let stmt = try Statement(db: self, sql: sql)
        try stmt.bind(bindings)
        _ = try stmt.step()
    }

    /// Query rows.
    public func query(_ sql: String, _ bindings: [SQLValue] = []) throws -> [Row] {
        let stmt = try Statement(db: self, sql: sql)
        try stmt.bind(bindings)
        var rows: [Row] = []
        while try stmt.step() {
            rows.append(stmt.currentRow())
        }
        return rows
    }

    public func scalar(_ sql: String, _ bindings: [SQLValue] = []) throws -> SQLValue {
        try query(sql, bindings).first?.values.first ?? .null
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    public var changes: Int { Int(sqlite3_changes(handle)) }
}

// MARK: - Values & rows

public enum SQLValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public var stringValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }
    public var intValue: Int64? {
        if case .integer(let i) = self { return i }
        return nil
    }
    public var isNull: Bool { self == .null }
}

extension SQLValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .text(value) }
    public init(integerLiteral value: Int64) { self = .integer(value) }
    public init(nilLiteral: ()) { self = .null }
}

public extension SQLValue {
    static func from(_ s: String?) -> SQLValue { s.map { .text($0) } ?? .null }
    static func from(_ b: Bool) -> SQLValue { .integer(b ? 1 : 0) }
}

public struct Row {
    public let columns: [String]
    public let values: [SQLValue]

    public subscript(name: String) -> SQLValue {
        guard let i = columns.firstIndex(of: name) else { return .null }
        return values[i]
    }
    public func text(_ name: String) -> String? { self[name].stringValue }
    public func int(_ name: String) -> Int64? { self[name].intValue }
    public func bool(_ name: String) -> Bool { self[name].intValue == 1 }
}

// MARK: - Statement

public final class Statement {
    private let stmt: OpaquePointer
    private let db: Database

    init(db: Database, sql: String) throws {
        var s: OpaquePointer?
        let rc = sqlite3_prepare_v2(db.handle, sql, -1, &s, nil)
        guard rc == SQLITE_OK, let stmt = s else {
            throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(db.handle)))
        }
        self.stmt = stmt
        self.db = db
    }

    deinit {
        sqlite3_finalize(stmt)
    }

    func bind(_ values: [SQLValue]) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, v) in values.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch v {
            case .null: rc = sqlite3_bind_null(stmt, idx)
            case .integer(let n): rc = sqlite3_bind_int64(stmt, idx, n)
            case .real(let d): rc = sqlite3_bind_double(stmt, idx, d)
            case .text(let s): rc = sqlite3_bind_text(stmt, idx, s, -1, transient)
            case .blob(let d):
                rc = d.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, idx, buf.baseAddress, Int32(buf.count), transient)
                }
            }
            try db.check(rc)
        }
    }

    /// Returns true while a row is available.
    func step() throws -> Bool {
        let rc = sqlite3_step(stmt)
        switch rc {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default:
            throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(db.handle)))
        }
    }

    func currentRow() -> Row {
        let count = Int(sqlite3_column_count(stmt))
        var columns: [String] = []
        var values: [SQLValue] = []
        for i in 0..<count {
            columns.append(String(cString: sqlite3_column_name(stmt, Int32(i))))
            switch sqlite3_column_type(stmt, Int32(i)) {
            case SQLITE_NULL:
                values.append(.null)
            case SQLITE_INTEGER:
                values.append(.integer(sqlite3_column_int64(stmt, Int32(i))))
            case SQLITE_FLOAT:
                values.append(.real(sqlite3_column_double(stmt, Int32(i))))
            case SQLITE_TEXT:
                values.append(.text(String(cString: sqlite3_column_text(stmt, Int32(i)))))
            case SQLITE_BLOB:
                if let base = sqlite3_column_blob(stmt, Int32(i)) {
                    let n = Int(sqlite3_column_bytes(stmt, Int32(i)))
                    values.append(.blob(Data(bytes: base, count: n)))
                } else {
                    values.append(.blob(Data()))
                }
            default:
                values.append(.null)
            }
        }
        return Row(columns: columns, values: values)
    }
}
