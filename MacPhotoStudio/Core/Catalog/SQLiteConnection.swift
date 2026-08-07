import Foundation
import SQLite3

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

    func execute(_ statement: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, statement, nil, nil, &errorMessage)
        defer {
            if let errorMessage {
                sqlite3_free(errorMessage)
            }
        }

        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite error \(result)"
            throw StudioError.databaseExecutionFailed(message: message)
        }
    }

    func integerValue(for statement: String) throws -> Int {
        var query: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(handle, statement, -1, &query, nil)
        guard prepareResult == SQLITE_OK, let query else {
            throw StudioError.databaseExecutionFailed(message: errorMessage())
        }
        defer { sqlite3_finalize(query) }

        guard sqlite3_step(query) == SQLITE_ROW else {
            throw StudioError.databaseExecutionFailed(message: errorMessage())
        }
        return Int(sqlite3_column_int64(query, 0))
    }

    private func errorMessage() -> String {
        guard let handle, let message = sqlite3_errmsg(handle) else {
            return "SQLite operation failed without an error message."
        }
        return String(cString: message)
    }
}
