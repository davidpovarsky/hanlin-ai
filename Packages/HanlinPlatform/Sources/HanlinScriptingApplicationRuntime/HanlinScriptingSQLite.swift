import Foundation
import HanlinMiniAppCore

final class HanlinScriptingSQLiteStore: @unchecked Sendable {
    private let lock = NSLock()
    private let stateLock = NSLock()
    private let fileSystem: HanlinScriptingPackageFileSystem
    private var services: [String: HanlinSQLiteService] = [:]
    private var stopped = false

    init(fileSystem: HanlinScriptingPackageFileSystem) {
        self.fileSystem = fileSystem
    }

    var openDatabaseCount: Int { activeServices().reduce(0) { $0 + $1.openDatabaseCount } }

    func requestStop() {
        stateLock.lock()
        stopped = true
        let active = Array(services.values)
        stateLock.unlock()
        active.forEach { $0.requestStop() }
    }

    func closeAll() {
        lock.lock()
        defer { lock.unlock() }
        activeServices().forEach { $0.closeAll() }
        stateLock.lock()
        services.removeAll()
        stateLock.unlock()
    }

    func release(handles: [String]) {
        lock.lock()
        defer { lock.unlock() }
        for service in activeServices() { for handle in handles { service.close(handle: handle) } }
        stateLock.lock()
        services = services.filter { $0.value.openDatabaseCount > 0 }
        stateLock.unlock()
    }

    private func activeServices() -> [HanlinSQLiteService] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return Array(services.values)
    }

    private func ensureActive() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        if stopped { throw HanlinScriptingNativeError(name: "AbortError", code: "cancelled", message: "The SQLite session has ended.") }
    }

    private func service(key: String, root: URL) throws -> HanlinSQLiteService {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !stopped else { throw HanlinScriptingNativeError(name: "AbortError", code: "cancelled", message: "The SQLite session has ended.") }
        if let existing = services[key] { return existing }
        let created = HanlinSQLiteService(rootURL: root)
        services[key] = created
        return created
    }

    func perform(operation: String, payloadJSON: String) throws -> Any {
        lock.lock()
        defer { lock.unlock() }
        try ensureActive()
        let payload = try HanlinScriptingNativeJSON.decodeObject(payloadJSON, maximumBytes: nil)
        guard ["sqlite.execute", "sqlite.fetchAll"].contains(operation) else {
            throw HanlinScriptingNativeError(name: "Error", code: "unsupported_operation", message: "The SQLite operation is unavailable.")
        }
        guard let handle = payload["handle"] as? String, handle.utf8.count <= 128,
              let path = payload["path"] as? String else {
            throw invalid("A SQLite handle and path are required.")
        }
        let configuration = payload["configuration"] as? [String: Any] ?? [:]
        let readonly = configuration["readonly"] as? Bool ?? false
        let foreignKeys = configuration["foreignKeysEnabled"] as? Bool ?? false
        let wal = (configuration["journalMode"] as? String) == "wal"
        let busy = (configuration["busyMode"] as? NSNumber)?.doubleValue ?? 5.0
        guard busy.isFinite, busy >= 0, busy * 1_000 <= Double(Int32.max) else {
            throw invalid("The SQLite busy duration must fit its nonnegative millisecond ABI.")
        }
        guard let sql = payload["sql"] as? String, !sql.isEmpty, !sql.utf8.contains(0) else {
            throw invalid("A non-empty SQL statement without NUL bytes is required.")
        }

        let service: HanlinSQLiteService
        let dbName: String
        if path.hasPrefix(":memory:") {
            service = try self.service(key: ":memory:", root: FileManager.default.temporaryDirectory)
            dbName = ":memory:"
        } else {
            let dbURL = try fileSystem.databaseURL(for: path)
            let parentDir = dbURL.deletingLastPathComponent()
            let dirKey = parentDir.path(percentEncoded: false)
            service = try self.service(key: dirKey, root: parentDir)
            dbName = dbURL.lastPathComponent
        }

        do {
            _ = try service.open(
                handle: handle,
                name: dbName,
                readonly: readonly,
                foreignKeys: foreignKeys,
                walMode: wal,
                busyTimeoutMs: Int32(busy * 1_000)
            )
        } catch let err as HanlinSQLiteServiceError {
            throw failure(err.localizedDescription)
        }

        try ensureActive()
        let arguments = try decodeArguments(payload["arguments"] ?? NSNull())
        do {
            switch operation {
            case "sqlite.execute":
                try service.execute(handle: handle, sql: sql, arguments: arguments)
                return NSNull()
            case "sqlite.fetchAll":
                let rows = try service.fetchAll(handle: handle, sql: sql, arguments: arguments)
                return rows
            default:
                throw HanlinScriptingNativeError(
                    name: "Error", code: "unsupported_operation",
                    message: "The SQLite operation is unavailable."
                )
            }
        } catch let err as HanlinSQLiteServiceError {
            throw failure(err.localizedDescription)
        }
    }

    private func decodeArguments(_ value: Any) throws -> Any {
        // The outer dictionary contains SQL parameter names, including names
        // identical to the private binary tag. Decode only its individual values.
        if let values = value as? [Any] { return try values.map(decodeValue) }
        if let values = value as? [String: Any] { return try values.mapValues(decodeValue) }
        return value
    }

    private func decodeValue(_ value: Any) throws -> Any {
        if let values = value as? [String: Any] {
            if values.count == 1, let encoded = values["__hanlinSQLiteData"] as? String {
                guard let bytes = Data(base64Encoded: encoded) else { throw invalid("SQLite Data encoding is invalid.") }
                return bytes
            }
        }
        return value
    }

    private func invalid(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "TypeError", code: "invalid_sqlite_request", message: message)
    }

    private func failure(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "Error", code: "sqlite_failure", message: String(message.prefix(512)))
    }
}
