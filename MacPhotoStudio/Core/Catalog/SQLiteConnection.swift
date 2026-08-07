import Foundation
import SQLite3

enum SQLiteValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

struct SQLiteRow: Sendable {
    fileprivate let values: [SQLiteValue]

    func text(at index: Int) -> String? {
        guard case .text(let value) = values[safe: index] else { return nil }
        return value
    }

    func integer(at index: Int) -> Int64? {
        guard case .integer(let value) = values[safe: index] else { return nil }
        return value
    }

    func real(at index: Int) -> Double? {
        switch values[safe: index] {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    func blob(at index: Int) -> Data? {
        guard case .blob(let value) = values[safe: index] else { return nil }
        return value
    }
}

final class SQLiteConnection: @unchecked Sendable {
    private var handle: OpaquePointer?

    init(databaseURL: URL) throws {
        var openedHandle: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path(percentEncoded: false),
            &openedHandle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard result == SQLITE_OK, let openedHandle else {
            if let openedHandle {
                sqlite3_close(openedHandle)
            }
            throw StudioError.databaseOpenFailed(
                path: databaseURL.path(percentEncoded: false),
                code: result
            )
        }

        handle = openedHandle
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func execute(_ statement: String, bindings: [SQLiteValue] = []) throws {
        guard !bindings.isEmpty else {
            var errorMessage: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(handle, statement, nil, nil, &errorMessage)
            defer {
                if let errorMessage {
                    sqlite3_free(errorMessage)
                }
            }
            guard result == SQLITE_OK else {
                let message = errorMessage.map { String(cString: $0) } ?? self.errorMessage()
                throw StudioError.databaseExecutionFailed(message: message)
            }
            return
        }

        let query = try prepare(statement)
        defer { sqlite3_finalize(query) }
        try bind(bindings, to: query)

        var stepResult = sqlite3_step(query)
        while stepResult == SQLITE_ROW {
            stepResult = sqlite3_step(query)
        }
        guard stepResult == SQLITE_DONE else {
            throw StudioError.databaseExecutionFailed(message: errorMessage())
        }
    }

    func query(_ statement: String, bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        let query = try prepare(statement)
        defer { sqlite3_finalize(query) }
        try bind(bindings, to: query)

        var rows: [SQLiteRow] = []
        var stepResult = sqlite3_step(query)
        while stepResult == SQLITE_ROW {
            let columnCount = Int(sqlite3_column_count(query))
            let values = (0..<columnCount).map { columnIndex in
                value(at: Int32(columnIndex), in: query)
            }
            rows.append(SQLiteRow(values: values))
            stepResult = sqlite3_step(query)
        }

        if stepResult != SQLITE_DONE {
            throw StudioError.databaseExecutionFailed(message: errorMessage())
        }

        return rows
    }

    func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try operation()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func hasColumn(named column: String, inTable table: String) throws -> Bool {
        try query("PRAGMA table_info(\(table));").contains { $0.text(at: 1) == column }
    }

    private func prepare(_ statement: String) throws -> OpaquePointer {
        var query: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, statement, -1, &query, nil)
        guard result == SQLITE_OK, let query else {
            throw StudioError.databaseExecutionFailed(message: errorMessage())
        }
        return query
    }

    private func bind(_ values: [SQLiteValue], to query: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(query, index)
            case .integer(let value):
                result = sqlite3_bind_int64(query, index, value)
            case .real(let value):
                result = sqlite3_bind_double(query, index, value)
            case .text(let value):
                result = sqlite3_bind_text(query, index, value, -1, sqliteTransient)
            case .blob(let value):
                result = value.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(query, index, bytes.baseAddress, Int32(value.count), sqliteTransient)
                }
            }
            guard result == SQLITE_OK else {
                throw StudioError.databaseExecutionFailed(message: errorMessage())
            }
        }
    }

    private func value(at index: Int32, in query: OpaquePointer) -> SQLiteValue {
        switch sqlite3_column_type(query, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(query, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(query, index))
        case SQLITE_TEXT:
            return .text(String(cString: sqlite3_column_text(query, index)))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(query, index))
            guard let bytes = sqlite3_column_blob(query, index), count > 0 else { return .blob(Data()) }
            return .blob(Data(bytes: bytes, count: count))
        default:
            return .null
        }
    }

    private var sqliteTransient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private func errorMessage() -> String {
        guard let handle, let message = sqlite3_errmsg(handle) else {
            return "SQLite operation failed without an error message."
        }
        return String(cString: message)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
