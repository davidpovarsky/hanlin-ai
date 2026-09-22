import Foundation
import HanlinMiniAppCore

final class HanlinScriptingSQLiteStore: @unchecked Sendable {
    private let lock = NSLock()
    private let fileSystem: HanlinScriptingPackageFileSystem
    private var services: [String: HanlinSQLiteService] = [:]

    init(fileSystem: HanlinScriptingPackageFileSystem) {
        self.fileSystem = fileSystem
    }

    func perform(operation: String, payloadJSON: String) throws -> Any {
        lock.lock()
        defer { lock.unlock() }
        let payload = try HanlinScriptingNativeJSON.decodeObject(payloadJSON)
        guard let handle = payload["handle"] as? String, handle.utf8.count <= 128,
              let path = payload["path"] as? String else {
            throw invalid("A SQLite handle and path are required.")
        }
        let configuration = payload["configuration"] as? [String: Any] ?? [:]
        let readonly = configuration["readonly"] as? Bool ?? false
        let foreignKeys = configuration["foreignKeysEnabled"] as? Bool ?? false
        let wal = (configuration["journalMode"] as? String) == "wal"
        let busy = (configuration["busyMode"] as? NSNumber)?.doubleValue ?? 5.0

        let service: HanlinSQLiteService
        let dbName: String
        if path.hasPrefix(":memory:") {
            if let existing = services[":memory:"] {
                service = existing
            } else {
                let temp = FileManager.default.temporaryDirectory
                let svc = HanlinSQLiteService(rootURL: temp)
                services[":memory:"] = svc
                service = svc
            }
            dbName = ":memory:"
        } else {
            let dbURL = try fileSystem.databaseURL(for: path)
            let parentDir = dbURL.deletingLastPathComponent()
            let dirKey = parentDir.path(percentEncoded: false)
            if let existing = services[dirKey] {
                service = existing
            } else {
                let svc = HanlinSQLiteService(rootURL: parentDir)
                services[dirKey] = svc
                service = svc
            }
            dbName = dbURL.lastPathComponent
        }

        do {
            _ = try service.open(
                handle: handle,
                name: dbName,
                readonly: readonly,
                foreignKeys: foreignKeys,
                walMode: wal,
                busyTimeoutMs: Int32(max(0, min(300_000, busy * 1_000)))
            )
        } catch let err as HanlinSQLiteServiceError {
            throw failure(err.localizedDescription)
        }

        guard let sql = payload["sql"] as? String, !sql.isEmpty, sql.utf8.count <= 1_048_576 else {
            throw invalid("A bounded non-empty SQL statement is required.")
        }

        let arguments = payload["arguments"]
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

    private func invalid(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "TypeError", code: "invalid_sqlite_request", message: message)
    }

    private func failure(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "Error", code: "sqlite_failure", message: String(message.prefix(512)))
    }
}
