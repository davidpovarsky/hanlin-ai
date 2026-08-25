import Foundation
import SQLite3

final class HanlinScriptingSQLiteStore: @unchecked Sendable {
    private let lock = NSLock()
    private let fileSystem: HanlinScriptingPackageFileSystem
    private var databases: [String: OpaquePointer] = [:]

    init(fileSystem: HanlinScriptingPackageFileSystem) {
        self.fileSystem = fileSystem
    }

    deinit {
        for database in databases.values { sqlite3_close_v2(database) }
    }

    func perform(operation: String, payloadJSON: String) throws -> Any {
        lock.lock()
        defer { lock.unlock() }
        let payload = try HanlinScriptingNativeJSON.decodeObject(payloadJSON)
        guard let handle = payload["handle"] as? String, handle.utf8.count <= 128,
              let path = payload["path"] as? String else {
            throw invalid("A SQLite handle and path are required.")
        }
        let database = try database(handle: handle, path: path, configuration: payload["configuration"])
        guard let sql = payload["sql"] as? String, !sql.isEmpty, sql.utf8.count <= 1_048_576 else {
            throw invalid("A bounded non-empty SQL statement is required.")
        }
        switch operation {
        case "sqlite.execute":
            try execute(sql: sql, arguments: payload["arguments"], database: database)
            return NSNull()
        case "sqlite.fetchAll":
            return try fetchAll(sql: sql, arguments: payload["arguments"], database: database)
        default:
            throw HanlinScriptingNativeError(
                name: "Error", code: "unsupported_operation",
                message: "The SQLite operation is unavailable."
            )
        }
    }

    private func database(handle: String, path: String, configuration: Any?) throws -> OpaquePointer {
        if let database = databases[handle] { return database }
        guard databases.count < 16 else { throw invalid("Too many SQLite databases are open.") }
        let options = configuration as? [String: Any] ?? [:]
        let readonly = options["readonly"] as? Bool ?? false
        let url: URL
        if path.hasPrefix(":memory:") {
            url = URL(filePath: ":memory:")
        } else {
            url = try fileSystem.databaseURL(for: path)
        }
        var database: OpaquePointer?
        let flags = readonly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path.hasPrefix(":memory:") ? ":memory:" : url.path(), &database, flags, nil) == SQLITE_OK,
              let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let database { sqlite3_close_v2(database) }
            throw failure(message)
        }
        do {
            if let busy = options["busyMode"] as? NSNumber {
                sqlite3_busy_timeout(database, Int32(max(0, min(300_000, busy.doubleValue * 1_000))))
            }
            if options["foreignKeysEnabled"] as? Bool == true {
                try execute(sql: "PRAGMA foreign_keys = ON", arguments: nil, database: database)
            }
            if options["journalMode"] as? String == "wal", !readonly, !path.hasPrefix(":memory:") {
                try execute(sql: "PRAGMA journal_mode = WAL", arguments: nil, database: database)
            }
            databases[handle] = database
            return database
        } catch {
            sqlite3_close_v2(database)
            throw error
        }
    }

    private func execute(sql: String, arguments: Any?, database: OpaquePointer) throws {
        var remaining = sql
        var isFirstStatement = true
        while !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var statement: OpaquePointer?
            var tail: UnsafePointer<CChar>?
            let result = remaining.withCString { pointer in
                sqlite3_prepare_v2(database, pointer, -1, &statement, &tail)
            }
            guard result == SQLITE_OK else { throw failure(database) }
            guard let statement else { break }
            defer { sqlite3_finalize(statement) }
            if isFirstStatement { try bind(arguments, to: statement) }
            let step = sqlite3_step(statement)
            guard step == SQLITE_DONE || step == SQLITE_ROW else { throw failure(database) }
            isFirstStatement = false
            guard let tail else { break }
            remaining = String(cString: tail)
        }
    }

    private func fetchAll(sql: String, arguments: Any?, database: OpaquePointer) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw failure(database) }
        defer { sqlite3_finalize(statement) }
        try bind(arguments, to: statement)
        var rows: [[String: Any]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw failure(database) }
            guard rows.count < 10_000 else { throw invalid("The SQLite result has too many rows.") }
            var row: [String: Any] = [:]
            for index in 0 ..< sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = columnValue(statement, index: index)
            }
            rows.append(row)
        }
        return rows
    }

    private func bind(_ arguments: Any?, to statement: OpaquePointer) throws {
        guard let arguments, !(arguments is NSNull) else { return }
        let count = Int(sqlite3_bind_parameter_count(statement))
        guard count <= 1_024 else { throw invalid("The SQLite statement has too many arguments.") }
        if let values = arguments as? [Any] {
            guard values.count == count else { throw invalid("The SQLite argument count does not match.") }
            for (offset, value) in values.enumerated() { try bind(value, index: Int32(offset + 1), to: statement) }
            return
        }
        if let values = arguments as? [String: Any] {
            for (name, value) in values {
                let candidates = [":\(name)", "@\(name)", "$\(name)"]
                guard let index = candidates.lazy.map({ sqlite3_bind_parameter_index(statement, $0) })
                    .first(where: { $0 > 0 }) else { continue }
                try bind(value, index: index, to: statement)
            }
            return
        }
        throw invalid("SQLite arguments must be an array or object.")
    }

    private func bind(_ value: Any, index: Int32, to statement: OpaquePointer) throws {
        let result: Int32
        switch value {
        case is NSNull:
            result = sqlite3_bind_null(statement, index)
        case let value as Bool:
            result = sqlite3_bind_int(statement, index, value ? 1 : 0)
        case let value as NSNumber:
            let double = value.doubleValue
            guard double.isFinite else { throw invalid("SQLite numbers must be finite.") }
            result = double.rounded(.towardZero) == double
                ? sqlite3_bind_int64(statement, index, value.int64Value)
                : sqlite3_bind_double(statement, index, double)
        case let value as String:
            result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        default:
            throw invalid("The SQLite argument type is unsupported.")
        }
        guard result == SQLITE_OK else { throw failure(sqlite3_db_handle(statement)) }
    }

    private func columnValue(_ statement: OpaquePointer, index: Int32) -> Any {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER: NSNumber(value: sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT: NSNumber(value: sqlite3_column_double(statement, index))
        case SQLITE_TEXT: sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, index) else { return NSNull() }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
            return ["__hanlinSQLiteData": data.base64EncodedString()]
        default: NSNull()
        }
    }

    private func invalid(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "TypeError", code: "invalid_sqlite_request", message: message)
    }

    private func failure(_ database: OpaquePointer?) -> HanlinScriptingNativeError {
        failure(database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite failed.")
    }

    private func failure(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "Error", code: "sqlite_failure", message: String(message.prefix(512)))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
