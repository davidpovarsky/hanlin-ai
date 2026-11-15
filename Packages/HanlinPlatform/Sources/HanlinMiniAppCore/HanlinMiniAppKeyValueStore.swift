import Foundation
import HanlinPlatformContracts

/// Durable synchronous KV for native bridges, using the existing shared SQLite
/// service and canonical Mini App State directory. A nil app identity selects
/// the explicitly shared namespace, which cannot collide with a valid app ID.
public final class HanlinMiniAppKeyValueStore: @unchecked Sendable {
    public struct Value: Equatable, Sendable {
        public enum Kind: String, Sendable { case json, data }
        public let kind: Kind
        public let content: String
        public init(kind: Kind, content: String) { self.kind = kind; self.content = content }
    }

    private let lock = NSLock()
    private let database: HanlinSQLiteService
    private let handle = "canonical-kv"

    public init(root: URL, appID: HanlinAppID?) throws {
        var directory = root.standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for component in [appID?.rawValue ?? "__shared_storage__", "State"] {
            directory.append(path: component, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: directory.path),
               try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw CocoaError(.fileReadInvalidFileName)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let file = directory.appending(path: "KeyValue.sqlite3")
        if FileManager.default.fileExists(atPath: file.path),
           try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw CocoaError(.fileReadInvalidFileName)
        }
        database = HanlinSQLiteService(rootURL: directory)
        _ = try database.open(handle: handle, name: "KeyValue.sqlite3")
        try database.execute(handle: handle, sql: """
        CREATE TABLE IF NOT EXISTS hanlin_kv (key TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('json','data')), value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS hanlin_kv_migrations (identity TEXT PRIMARY KEY);
        """)
    }

    public func value(for key: String) throws -> Value? {
        lock.lock(); defer { lock.unlock() }
        guard let row = try database.fetchAll(handle: handle, sql: "SELECT kind,value FROM hanlin_kv WHERE key=?", arguments: [key]).first else { return nil }
        guard let raw = row["kind"] as? String, let kind = Value.Kind(rawValue: raw), let content = row["value"] as? String else {
            throw HanlinMiniAppKeyValueError.invalidRecord(key)
        }
        return Value(kind: kind, content: content)
    }

    public func set(_ value: Value, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        try write(value, for: key, preserveExisting: false)
    }

    public func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        try database.execute(handle: handle, sql: "DELETE FROM hanlin_kv WHERE key=?", arguments: [key])
    }

    public func contains(key: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return try !database.fetchAll(handle: handle, sql: "SELECT 1 FROM hanlin_kv WHERE key=?", arguments: [key]).isEmpty
    }

    public func keys() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        try database.execute(handle: handle, sql: "BEGIN")
        var committed = false
        defer { if !committed { try? database.execute(handle: handle, sql: "ROLLBACK") } }
        var result: [String] = []
        var previous: String?
        while true {
            // Keyset paging avoids the service's per-fetch row budget and does
            // not truncate the public keys() result. No payloads are selected.
            let rows = try database.fetchAll(handle: handle,
                sql: previous == nil ? "SELECT key FROM hanlin_kv ORDER BY key LIMIT 500" : "SELECT key FROM hanlin_kv WHERE key>? ORDER BY key LIMIT 500",
                arguments: previous.map { [$0] })
            let page = rows.compactMap { $0["key"] as? String }
            result.append(contentsOf: page)
            guard let last = page.last, page.count == 500 else {
                try database.execute(handle: handle, sql: "COMMIT")
                committed = true
                return result
            }
            previous = last
        }
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        // Keep migration markers so an explicit clear never resurrects the
        // preserved UserDefaults values on the next launch.
        try database.execute(handle: handle, sql: "DELETE FROM hanlin_kv")
    }

    public func migrateLegacy(_ values: [String: Any], identity: String) throws {
        lock.lock(); defer { lock.unlock() }
        try database.execute(handle: handle, sql: "BEGIN IMMEDIATE")
        do {
            let imported = try database.fetchAll(handle: handle, sql: "SELECT identity FROM hanlin_kv_migrations WHERE identity=?", arguments: [identity])
            if imported.isEmpty {
                var keys = Set<String>()
                for raw in values.keys.sorted() {
                    let key: String
                    let value: Value
                    if let data = values[raw] as? Data, raw.hasPrefix("__hanlin_data__:") {
                        key = String(raw.dropFirst("__hanlin_data__:".count))
                        value = Value(kind: .data, content: data.base64EncodedString())
                    } else if let string = values[raw] as? String {
                        key = raw
                        value = Value(kind: .json, content: string)
                    } else { throw HanlinMiniAppKeyValueError.invalidLegacyValue(raw) }
                    guard keys.insert(key).inserted else { throw HanlinMiniAppKeyValueError.invalidLegacyValue(raw) }
                    try write(value, for: key, preserveExisting: true)
                }
                try database.execute(handle: handle, sql: "INSERT INTO hanlin_kv_migrations(identity) VALUES(?)", arguments: [identity])
            }
            try database.execute(handle: handle, sql: "COMMIT")
        } catch {
            try? database.execute(handle: handle, sql: "ROLLBACK")
            throw error
        }
    }

    private func write(_ value: Value, for key: String, preserveExisting: Bool) throws {
        let sql = preserveExisting
            ? "INSERT OR IGNORE INTO hanlin_kv(key,kind,value) VALUES(?,?,?)"
            : "INSERT INTO hanlin_kv(key,kind,value) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET kind=excluded.kind,value=excluded.value"
        try database.execute(handle: handle, sql: sql, arguments: [key,value.kind.rawValue,value.content])
    }
}

public enum HanlinMiniAppKeyValueError: Error, LocalizedError, Sendable {
    case invalidRecord(String)
    case invalidLegacyValue(String)
    public var errorDescription: String? {
        switch self {
        case .invalidRecord(let key): "The stored KV record is invalid: \(key)"
        case .invalidLegacyValue(let key): "Legacy KV migration could not preserve this value: \(key). The original defaults remain intact."
        }
    }
}
