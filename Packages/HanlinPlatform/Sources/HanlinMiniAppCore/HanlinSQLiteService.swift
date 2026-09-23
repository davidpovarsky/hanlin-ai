import Foundation
import SQLite3

/// Shared SQLite service for all Mini App engines and agent tools.
///
/// Uses the canonical `HanlinMiniAppDataStore` directory structure for
/// database file resolution. Each database is scoped to an app's `State`
/// directory by default, preventing cross-app data access.
///
/// Thread safety: This class uses `NSLock` to serialize access to the
/// underlying SQLite connections. Each database handle is opened with
/// `SQLITE_OPEN_FULLMUTEX` for additional safety.
public final class HanlinSQLiteService: @unchecked Sendable {
    private let lock = NSLock()
    private var databases: [String: OpaquePointer] = [:]
    private let rootURL: URL

    /// Maximum number of open databases per service instance.
    public static let maximumOpenDatabases = 16
    /// Maximum number of rows returned from a single fetchAll.
    public static let maximumFetchRows = 10_000
    /// Maximum bind parameter count per statement.
    public static let maximumBindParameters = 1_024
    /// Maximum SQL statement size in bytes.
    public static let maximumStatementBytes = 1_048_576

    /// Create a SQLite service scoped to the given root directory.
    /// Database files are created/opened relative to this root.
    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    deinit {
        for database in databases.values { sqlite3_close_v2(database) }
    }

    // MARK: - Database Lifecycle

    /// Open or get an existing database connection.
    public func open(
        handle: String,
        name: String,
        readonly: Bool = false,
        foreignKeys: Bool = false,
        walMode: Bool = true,
        busyTimeoutMs: Int32 = 5_000
    ) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        guard handle.utf8.count <= 128, !handle.isEmpty else {
            throw HanlinSQLiteServiceError.invalidHandle
        }

        if databases[handle] != nil { return handle }

        guard databases.count < Self.maximumOpenDatabases else {
            throw HanlinSQLiteServiceError.tooManyDatabases
        }

        let url: URL
        if name == ":memory:" {
            url = URL(filePath: ":memory:")
        } else {
            // Validate path doesn't escape root
            guard !name.contains(".."), !name.hasPrefix("/"), !name.hasPrefix("\\") else {
                throw HanlinSQLiteServiceError.invalidPath(name)
            }
            url = rootURL.appending(path: name, directoryHint: .notDirectory)
            // Verify resolved path is under root
            let resolvedPath = url.standardizedFileURL.path(percentEncoded: false)
            let rootPath = rootURL.path(percentEncoded: false)
            guard resolvedPath.hasPrefix(rootPath) else {
                throw HanlinSQLiteServiceError.invalidPath(name)
            }
            // Ensure parent directory exists
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        var database: OpaquePointer?
        let flags = readonly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX

        let openPath = name == ":memory:" ? ":memory:" : url.path(percentEncoded: false)
        guard sqlite3_open_v2(openPath, &database, flags, nil) == SQLITE_OK,
              let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let database { sqlite3_close_v2(database) }
            throw HanlinSQLiteServiceError.openFailed(message)
        }

        do {
            sqlite3_busy_timeout(database, max(0, min(300_000, busyTimeoutMs)))

            if foreignKeys {
                try executeRaw(sql: "PRAGMA foreign_keys = ON", database: database)
            }
            if walMode, !readonly, name != ":memory:" {
                try executeRaw(sql: "PRAGMA journal_mode = WAL", database: database)
            }

            databases[handle] = database
            return handle
        } catch {
            sqlite3_close_v2(database)
            throw error
        }
    }

    /// Close a database connection.
    public func close(handle: String) {
        lock.lock()
        defer { lock.unlock() }
        if let database = databases.removeValue(forKey: handle) {
            sqlite3_close_v2(database)
        }
    }

    /// Close all open database connections.
    public func closeAll() {
        lock.lock()
        defer { lock.unlock() }
        for database in databases.values { sqlite3_close_v2(database) }
        databases.removeAll()
    }

    // MARK: - Execute

    // MARK: - Execute

    /// Execute one or more SQL statements (no results returned).
    public func execute(handle: String, sql: String, arguments: Any? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let database = databases[handle] else {
            throw HanlinSQLiteServiceError.noSuchHandle(handle)
        }
        guard !sql.isEmpty, sql.utf8.count <= Self.maximumStatementBytes else {
            throw HanlinSQLiteServiceError.statementTooLarge
        }
        try executeImpl(sql: sql, arguments: arguments, database: database)
    }

    // MARK: - Fetch

    /// Execute a SELECT statement and return all result rows.
    public func fetchAll(handle: String, sql: String, arguments: Any? = nil) throws -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        guard let database = databases[handle] else {
            throw HanlinSQLiteServiceError.noSuchHandle(handle)
        }
        guard !sql.isEmpty, sql.utf8.count <= Self.maximumStatementBytes else {
            throw HanlinSQLiteServiceError.statementTooLarge
        }
        return try fetchAllImpl(sql: sql, arguments: arguments, database: database)
    }

    // MARK: - Private Implementation

    private func executeRaw(sql: String, database: OpaquePointer) throws {
        try executeImpl(sql: sql, arguments: nil, database: database)
    }

    private func executeImpl(sql: String, arguments: Any?, database: OpaquePointer) throws {
        var remaining = sql
        var didBindArguments = false
        while !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var statement: OpaquePointer?
            var tail: UnsafePointer<CChar>?
            let result = remaining.withCString { pointer in
                sqlite3_prepare_v2(database, pointer, -1, &statement, &tail)
            }
            guard result == SQLITE_OK else { throw sqliteError(database) }
            guard let statement else { break }
            defer { sqlite3_finalize(statement) }
            let parameterCount = Int(sqlite3_bind_parameter_count(statement))
            if parameterCount > 0, let arguments {
                guard !didBindArguments else {
                    throw HanlinSQLiteServiceError.invalidArgument(
                        "Arguments may target only one statement in a multi-statement execution"
                    )
                }
                try bind(arguments, to: statement)
                didBindArguments = true
            }
            let step = sqlite3_step(statement)
            guard step == SQLITE_DONE || step == SQLITE_ROW else { throw sqliteError(database) }
            guard let tail else { break }
            remaining = String(cString: tail)
        }
        if let arguments, !didBindArguments {
            try requireEmptyArguments(arguments)
        }
    }

    private func requireEmptyArguments(_ arguments: Any) throws {
        if arguments is NSNull { return }
        if let values = arguments as? [Any] {
            guard values.isEmpty else {
                throw HanlinSQLiteServiceError.argumentCountMismatch(expected: 0, got: values.count)
            }
            return
        }
        if let values = arguments as? [String: Any] {
            guard values.isEmpty else {
                throw HanlinSQLiteServiceError.argumentCountMismatch(expected: 0, got: values.count)
            }
            return
        }
        throw HanlinSQLiteServiceError.invalidArgument("SQLite arguments must be an array or object")
    }

    private func fetchAllImpl(sql: String, arguments: Any?, database: OpaquePointer) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw sqliteError(database) }
        defer { sqlite3_finalize(statement) }
        if let arguments { try bind(arguments, to: statement) }
        var rows: [[String: Any]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw sqliteError(database) }
            guard rows.count < Self.maximumFetchRows else {
                throw HanlinSQLiteServiceError.tooManyRows
            }
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
        guard count <= Self.maximumBindParameters else {
            throw HanlinSQLiteServiceError.tooManyParameters
        }
        if let values = arguments as? [Any] {
            guard values.count == count else {
                throw HanlinSQLiteServiceError.argumentCountMismatch(expected: count, got: values.count)
            }
            for (offset, value) in values.enumerated() {
                try bindValue(value, index: Int32(offset + 1), to: statement)
            }
            return
        }
        if let values = arguments as? [String: Any] {
            for (name, value) in values {
                let candidates = [":\(name)", "@\(name)", "$\(name)"]
                guard let index = candidates.lazy.map({ sqlite3_bind_parameter_index(statement, $0) })
                    .first(where: { $0 > 0 }) else { continue }
                try bindValue(value, index: index, to: statement)
            }
            return
        }
        throw HanlinSQLiteServiceError.invalidArgument("SQLite arguments must be an array or object")
    }

    private func bindValue(_ value: Any, index: Int32, to statement: OpaquePointer) throws {
        let result: Int32
        switch value {
        case is NSNull:
            result = sqlite3_bind_null(statement, index)
        case let value as Bool:
            result = sqlite3_bind_int(statement, index, value ? 1 : 0)
        case let value as NSNumber:
            let double = value.doubleValue
            guard double.isFinite else {
                throw HanlinSQLiteServiceError.invalidArgument("SQLite numbers must be finite")
            }
            result = double.rounded(.towardZero) == double
                ? sqlite3_bind_int64(statement, index, value.int64Value)
                : sqlite3_bind_double(statement, index, double)
        case let value as String:
            result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        case let value as Data:
            result = value.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), sqliteTransient)
            }
        default:
            throw HanlinSQLiteServiceError.invalidArgument("Unsupported SQLite argument type")
        }
        guard result == SQLITE_OK else { throw sqliteError(sqlite3_db_handle(statement)) }
    }

    private func columnValue(_ statement: OpaquePointer, index: Int32) -> Any {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return NSNumber(value: sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return NSNumber(value: sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            return sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, index) else { return NSNull() }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
            return ["__hanlinSQLiteData": data.base64EncodedString()]
        default:
            return NSNull()
        }
    }

    private func sqliteError(_ database: OpaquePointer?) -> HanlinSQLiteServiceError {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite operation failed"
        return .sqliteError(String(message.prefix(512)))
    }
}

// MARK: - Errors

public enum HanlinSQLiteServiceError: Error, Equatable, Sendable, LocalizedError {
    case invalidHandle
    case invalidPath(String)
    case noSuchHandle(String)
    case openFailed(String)
    case sqliteError(String)
    case tooManyDatabases
    case tooManyRows
    case tooManyParameters
    case statementTooLarge
    case argumentCountMismatch(expected: Int, got: Int)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHandle: "Invalid SQLite handle"
        case .invalidPath(let path): "Invalid database path: \(path)"
        case .noSuchHandle(let handle): "No open database with handle: \(handle)"
        case .openFailed(let msg): "SQLite open failed: \(msg)"
        case .sqliteError(let msg): "SQLite error: \(msg)"
        case .tooManyDatabases: "Too many open SQLite databases (limit: \(HanlinSQLiteService.maximumOpenDatabases))"
        case .tooManyRows: "SQLite result has too many rows (limit: \(HanlinSQLiteService.maximumFetchRows))"
        case .tooManyParameters: "SQLite statement has too many parameters (limit: \(HanlinSQLiteService.maximumBindParameters))"
        case .statementTooLarge: "SQLite statement exceeds maximum size"
        case .argumentCountMismatch(let expected, let got): "SQLite argument count mismatch: expected \(expected), got \(got)"
        case .invalidArgument(let msg): "Invalid SQLite argument: \(msg)"
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
