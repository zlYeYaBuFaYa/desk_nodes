import Foundation
import CSQLite

internal enum SQLValue {
    case text(String), number(Double), integer(Int64), null
    static func date(_ date: Date?) -> SQLValue { date.map { .number($0.timeIntervalSince1970) } ?? .null }
}

/// One connection, serialized by Store's recursive lock; statements never escape a call.
internal final class SQLite {
    private var handle: OpaquePointer?
    init(url: URL?) throws {
        let result = sqlite3_open_v2(url?.path ?? ":memory:", &handle,
                                    SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let error = failure(result)
            sqlite3_close(handle)
            handle = nil
            throw error
        }
        sqlite3_busy_timeout(handle, 5_000)
    }
    deinit { try? close() }
    func close() throws {
        guard let handle else { return }
        let result = sqlite3_close(handle)
        guard result == SQLITE_OK else { throw failure(result) }
        self.handle = nil
    }
    private func failure(_ code: Int32) -> StoreError {
        .sqlite(code: code, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite open failed")
    }
    /// Public SQLite backup API: destination transaction commits only at DONE.
    /// An interrupted/incomplete copy is rolled back by backup_finish.
    func replace(from source: SQLite, interruptAfterPage: Bool = false) throws {
        guard let handle, let sourceHandle = source.handle else { throw StoreError.closed }
        guard let copy = sqlite3_backup_init(handle, "main", sourceHandle, "main") else { throw failure(sqlite3_errcode(handle)) }
        let step = sqlite3_backup_step(copy, interruptAfterPage ? 1 : -1)
        let finish = sqlite3_backup_finish(copy)
        guard step == SQLITE_DONE, finish == SQLITE_OK else {
            throw StoreError.sqlite(code: step == SQLITE_DONE ? finish : step, message: "atomic backup replacement failed")
        }
    }
    func run(_ sql: String, _ values: [SQLValue] = []) throws {
        _ = try query(sql, values)
    }
    func query(_ sql: String, _ values: [SQLValue] = []) throws -> [[String?]] {
        guard let handle else { throw StoreError.closed }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw failure(prepared) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_parameter_count(statement) == Int32(values.count) else {
            throw StoreError.invalid("SQL binding count")
        }
        for (index, value) in values.enumerated() {
            let slot = Int32(index + 1)
            let result: Int32
            switch value {
            case .null: result = sqlite3_bind_null(statement, slot)
            case .number(let number): result = sqlite3_bind_double(statement, slot, number)
            case .integer(let number): result = sqlite3_bind_int64(statement, slot, number)
            case .text(let text):
                // Explicit UTF-8 byte count preserves embedded NUL as well as Chinese/emoji.
                result = text.withCString { pointer in
                    sqlite3_bind_text(statement, slot, pointer, Int32(text.utf8.count),
                                      unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            }
            guard result == SQLITE_OK else { throw failure(result) }
        }
        var rows: [[String?]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw failure(result) }
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                let type = sqlite3_column_type(statement, column)
                // REAL columns hold timestamps: SQLite's own text rendering keeps only 15 digits.
                if type == SQLITE_FLOAT { return String(sqlite3_column_double(statement, column)) }
                guard type != SQLITE_NULL,
                      let bytes = sqlite3_column_text(statement, column) else { return nil }
                return String(decoding: UnsafeBufferPointer(start: bytes,
                              count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
            })
        }
    }
}
