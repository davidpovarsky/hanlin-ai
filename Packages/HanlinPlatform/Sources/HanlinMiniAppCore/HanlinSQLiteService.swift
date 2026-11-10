import Foundation

/// Optional, explicit host budgets. The default preserves the caller's entire
/// query; SQLite's actual ABI/resource limits and errors still apply.
public struct HanlinSQLiteResourceLimits: Sendable {
    public let maximumOpenDatabases: Int?
    public let maximumFetchRows: Int?
    public let maximumBindParameters: Int?
    public let maximumStatementBytes: Int?

    public init(maximumOpenDatabases: Int? = nil, maximumFetchRows: Int? = nil,
                maximumBindParameters: Int? = nil, maximumStatementBytes: Int? = nil) {
        self.maximumOpenDatabases = maximumOpenDatabases
        self.maximumFetchRows = maximumFetchRows
        self.maximumBindParameters = maximumBindParameters
        self.maximumStatementBytes = maximumStatementBytes
    }

    public static let legacy = Self(maximumOpenDatabases: 16, maximumFetchRows: 10_000,
                                    maximumBindParameters: 1_024, maximumStatementBytes: 1_048_576)

    fileprivate func validate() throws {
        guard [maximumOpenDatabases, maximumFetchRows, maximumBindParameters, maximumStatementBytes]
            .allSatisfy({ ($0 ?? 0) >= 0 }) else {
            throw HanlinSQLiteServiceError.invalidArgument("Explicit SQLite resource budgets must be nonnegative.")
        }
    }
}

#if canImport(SQLite3)
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
    private let registryLock = NSLock()
    private var databases: [String: OpaquePointer] = [:]
    private var stopRequested = false
    private let rootURL: URL
    private let resourceLimits: HanlinSQLiteResourceLimits

    /// Legacy opt-in budget values; the default resource policy has no such caps.
    public static let maximumOpenDatabases = 16
    /// Legacy opt-in row budget.
    public static let maximumFetchRows = 10_000
    /// Legacy opt-in bind-parameter budget.
    public static let maximumBindParameters = 1_024
    /// Legacy opt-in SQL byte budget.
    public static let maximumStatementBytes = 1_048_576

    /// Create a SQLite service scoped to the given root directory.
    /// Database files are created/opened relative to this root.
    public init(rootURL: URL, resourceLimits: HanlinSQLiteResourceLimits = .init()) {
        self.rootURL = rootURL.standardizedFileURL
        self.resourceLimits = resourceLimits
    }

    deinit {
        for database in databases.values { sqlite3_close_v2(database) }
    }

    public var openDatabaseCount: Int {
        registryLock.lock()
        defer { registryLock.unlock() }
        return databases.count
    }

    /// SQLite explicitly permits interruption from another thread. Keep its
    /// pointers leased under the registry lock so close cannot race this call;
    /// never wait for a running query's serialization lock to request a stop.
    public func interruptAll() {
        registryLock.lock()
        defer { registryLock.unlock() }
        for database in databases.values { sqlite3_interrupt(database) }
    }

    /// End this owner's lifetime, including queries admitted just as disposal
    /// starts. The progress handler closes SQLite's interrupt-before-step gap.
    public func requestStop() {
        registryLock.lock()
        defer { registryLock.unlock() }
        stopRequested = true
        for database in databases.values { sqlite3_interrupt(database) }
    }

    private var isStopped: Bool {
        registryLock.lock()
        defer { registryLock.unlock() }
        return stopRequested
    }

    private func ensureActive() throws {
        if isStopped { throw HanlinSQLiteServiceError.sqliteError("interrupted") }
    }

    private func database(for handle: String) -> OpaquePointer? {
        registryLock.lock()
        defer { registryLock.unlock() }
        return databases[handle]
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
        try resourceLimits.validate()
        try ensureActive()
        guard busyTimeoutMs >= 0 else { throw HanlinSQLiteServiceError.invalidArgument("SQLite busy milliseconds must be nonnegative.") }

        guard handle.utf8.count <= 128, !handle.isEmpty else {
            throw HanlinSQLiteServiceError.invalidHandle
        }

        if database(for: handle) != nil { return handle }

        if let maximum = resourceLimits.maximumOpenDatabases, openDatabaseCount >= maximum {
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

        registryLock.lock()
        databases[handle] = database
        registryLock.unlock()
        sqlite3_progress_handler(database, 1_000, { pointer in
            guard let pointer else { return 0 }
            return Unmanaged<HanlinSQLiteService>.fromOpaque(pointer).takeUnretainedValue().isStopped ? 1 : 0
        }, Unmanaged.passUnretained(self).toOpaque())
        do {
            try ensureActive()
            sqlite3_busy_timeout(database, busyTimeoutMs)

            if foreignKeys {
                try executeRaw(sql: "PRAGMA foreign_keys = ON", database: database)
            }
            if walMode, !readonly, name != ":memory:" {
                try executeRaw(sql: "PRAGMA journal_mode = WAL", database: database)
            }

            return handle
        } catch {
            registryLock.lock()
            databases.removeValue(forKey: handle)
            sqlite3_close_v2(database)
            registryLock.unlock()
            throw error
        }
    }

    /// Close a database connection.
    public func close(handle: String) {
        lock.lock()
        defer { lock.unlock() }
        registryLock.lock()
        defer { registryLock.unlock() }
        if let database = databases.removeValue(forKey: handle) {
            sqlite3_close_v2(database)
        }
    }

    /// Close all open database connections.
    public func closeAll() {
        lock.lock()
        defer { lock.unlock() }
        registryLock.lock()
        defer { registryLock.unlock() }
        for database in databases.values { sqlite3_close_v2(database) }
        databases.removeAll()
    }

    // MARK: - Execute

    /// Execute one or more SQL statements (no results returned).
    public func execute(handle: String, sql: String, arguments: Any? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureActive()
        guard let database = database(for: handle) else {
            throw HanlinSQLiteServiceError.noSuchHandle(handle)
        }
        try validateSQL(sql)
        try executeImpl(sql: sql, arguments: arguments, database: database)
    }

    // MARK: - Fetch

    /// Execute a SELECT statement and return all result rows.
    public func fetchAll(handle: String, sql: String, arguments: Any? = nil) throws -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        try ensureActive()
        guard let database = database(for: handle) else {
            throw HanlinSQLiteServiceError.noSuchHandle(handle)
        }
        try validateSQL(sql)
        return try fetchAllImpl(sql: sql, arguments: arguments, database: database)
    }

    // MARK: - Private Implementation

    private func validateSQL(_ sql: String) throws {
        try resourceLimits.validate()
        guard !sql.isEmpty, !sql.utf8.contains(0) else {
            throw HanlinSQLiteServiceError.invalidArgument("SQL must be nonempty and cannot contain a NUL byte.")
        }
        if let maximum = resourceLimits.maximumStatementBytes, sql.utf8.count > maximum {
            throw HanlinSQLiteServiceError.statementTooLarge
        }
    }

    private func executeRaw(sql: String, database: OpaquePointer) throws {
        try executeImpl(sql: sql, arguments: nil, database: database)
    }

    private func executeImpl(sql: String, arguments: Any?, database: OpaquePointer) throws {
        var remaining = sql
        var didBindArguments = false
        while !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var statement: OpaquePointer?
            // SQLite's tail points inside the temporary withCString buffer.
            // Copy it before leaving that closure, not after stepping the statement.
            let (result, remainingSQL) = remaining.withCString { pointer in
                var tail: UnsafePointer<CChar>?
                let result = sqlite3_prepare_v2(database, pointer, -1, &statement, &tail)
                return (result, tail.map { String(cString: $0) })
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
            guard let remainingSQL else { break }
            remaining = remainingSQL
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
            if let maximum = resourceLimits.maximumFetchRows, rows.count >= maximum {
                throw HanlinSQLiteServiceError.tooManyRows
            }
            var row: [String: Any] = [:]
            for index in 0 ..< sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = try columnValue(statement, index: index)
            }
            rows.append(row)
        }
        return rows
    }

    private func bind(_ arguments: Any?, to statement: OpaquePointer) throws {
        guard let arguments, !(arguments is NSNull) else { return }
        let count = Int(sqlite3_bind_parameter_count(statement))
        if let maximum = resourceLimits.maximumBindParameters, count > maximum {
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
        case let value as NSNumber:
            let double = value.doubleValue
            guard double.isFinite else {
                throw HanlinSQLiteServiceError.invalidArgument("SQLite numbers must be finite")
            }
            let type = String(cString: value.objCType)
            if ["f", "d"].contains(type) {
                result = sqlite3_bind_double(statement, index, double)
            } else {
                if ["Q", "L", "I", "S", "C"].contains(type), value.uint64Value > UInt64(Int64.max) {
                    throw HanlinSQLiteServiceError.invalidArgument("The SQLite INTEGER type cannot represent this unsigned value.")
                }
                result = sqlite3_bind_int64(statement, index, value.int64Value)
            }
        case let value as String:
            result = sqlite3_bind_text64(statement, index, value, UInt64(value.utf8.count), sqliteTransient, UInt8(SQLITE_UTF8))
        case let value as Data:
            result = value.isEmpty ? sqlite3_bind_zeroblob(statement, index, 0) : value.withUnsafeBytes { bytes in
                sqlite3_bind_blob64(statement, index, bytes.baseAddress, UInt64(value.count), sqliteTransient)
            }
        default:
            throw HanlinSQLiteServiceError.invalidArgument("Unsupported SQLite argument type")
        }
        guard result == SQLITE_OK else { throw sqliteError(sqlite3_db_handle(statement)) }
    }

    private func columnValue(_ statement: OpaquePointer, index: Int32) throws -> Any {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return NSNumber(value: sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return NSNumber(value: sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            let count = Int(sqlite3_column_bytes(statement, index))
            guard let text = sqlite3_column_text(statement, index) else {
                if sqlite3_errcode(sqlite3_db_handle(statement)) == SQLITE_NOMEM { throw sqliteError(sqlite3_db_handle(statement)) }
                return ""
            }
            return String(decoding: UnsafeBufferPointer(start: text, count: count), as: UTF8.self)
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            if count == 0 { return ["__hanlinSQLiteData": ""] }
            guard let bytes = sqlite3_column_blob(statement, index) else { throw sqliteError(sqlite3_db_handle(statement)) }
            let data = Data(bytes: bytes, count: count)
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

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
#else
public final class HanlinSQLiteService: @unchecked Sendable {
    public static let maximumOpenDatabases = 16
    public static let maximumFetchRows = 10_000
    public static let maximumBindParameters = 1_024
    public static let maximumStatementBytes = 1_048_576

    public init(rootURL: URL, resourceLimits: HanlinSQLiteResourceLimits = .init()) {}

    public var openDatabaseCount: Int { 0 }
    public func interruptAll() {}
    public func requestStop() {}

    public func open(
        handle: String,
        name: String,
        readonly: Bool = false,
        foreignKeys: Bool = false,
        walMode: Bool = true,
        busyTimeoutMs: Int32 = 5_000
    ) throws -> String {
        throw HanlinSQLiteServiceError.openFailed("SQLite3 is not available on this platform")
    }

    public func close(handle: String) {}

    public func closeAll() {}

    public func execute(handle: String, sql: String, arguments: Any? = nil) throws {
        throw HanlinSQLiteServiceError.sqliteError("SQLite3 is not available on this platform")
    }

    public func fetchAll(handle: String, sql: String, arguments: Any? = nil) throws -> [[String: Any]] {
        throw HanlinSQLiteServiceError.sqliteError("SQLite3 is not available on this platform")
    }
}
#endif

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
        case .tooManyDatabases: "SQLite database handles exceed the explicit resource budget"
        case .tooManyRows: "SQLite rows exceed the explicit resource budget"
        case .tooManyParameters: "SQLite parameters exceed the explicit resource budget"
        case .statementTooLarge: "SQL bytes exceed the explicit resource budget"
        case .argumentCountMismatch(let expected, let got): "SQLite argument count mismatch: expected \(expected), got \(got)"
        case .invalidArgument(let msg): "Invalid SQLite argument: \(msg)"
        }
    }
}
