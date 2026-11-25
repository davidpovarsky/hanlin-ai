import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Durable transport only. The standalone MiniApps app remains the execution owner.
/// Every read/modify/write transaction uses the same interprocess file lock; writes
/// are atomic. Payloads and attachments have no invented size or age restrictions.
public struct MiniAppBridgeStore: Sendable {
    public static let appGroupIdentifier = "group.com.itorah.shared"
    public static let urlScheme = "hanlinminiapps"
    public let rootURL: URL

    private struct Catalog: Codable { var schemaVersion = 1; var items: [MiniAppCatalogItem] }
    private struct Preferences: Codable { var schemaVersion = 1; var value: MiniAppPreferences }
    private struct Record: Codable {
        var schemaVersion = 1
        let request: MiniAppInvocation
        var result: MiniAppResult?
        var acknowledged = false
    }

    public init(appGroupIdentifier: String = Self.appGroupIdentifier) throws {
        #if canImport(Darwin)
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { throw MiniAppBridgeError.appGroupUnavailable }
        try self.init(containerURL: container)
        #else
        throw MiniAppBridgeError.appGroupUnavailable
        #endif
    }

    public init(containerURL: URL) throws {
        rootURL = containerURL.appendingPathComponent("MiniAppsBridge/v1", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public func publishCatalog(_ items: [MiniAppCatalogItem]) throws {
        guard Set(items.map(\.id)).count == items.count else { throw MiniAppBridgeError.duplicateCatalogIdentity }
        try transaction { try write(Catalog(items: items), to: rootURL.appendingPathComponent("catalog.json")) }
    }

    public func loadCatalog() throws -> [MiniAppCatalogItem] {
        try transaction {
            guard let catalog: Catalog = try read(rootURL.appendingPathComponent("catalog.json")) else { return [] }
            guard catalog.schemaVersion == 1 else { throw MiniAppBridgeError.unsupportedSchema }
            return catalog.items
        }
    }

    public func preferences() throws -> MiniAppPreferences {
        try transaction { try readPreferences() }
    }

    public func updatePreferences(_ body: (inout MiniAppPreferences) -> Void) throws {
        try transaction {
            var current = try readPreferences()
            body(&current)
            current.normalize()
            try write(Preferences(value: current), to: rootURL.appendingPathComponent("preferences.json"))
        }
    }

    private func readPreferences() throws -> MiniAppPreferences {
        guard let stored: Preferences = try read(rootURL.appendingPathComponent("preferences.json")) else {
            return .init()
        }
        guard stored.schemaVersion == 1 else { throw MiniAppBridgeError.unsupportedSchema }
        var result = stored.value
        result.normalize()
        return result
    }

    /// Save before opening the URL so cold launch can resolve the complete input.
    @discardableResult
    public func enqueue(_ request: MiniAppInvocation) throws -> URL {
        let url = try Self.launchURL(for: request)
        try transaction {
            if let existing = try readRecord(request.id) {
                guard existing.request == request else { throw MiniAppBridgeError.duplicateIdentity }
                return
            }
            try writeRecord(.init(request: request))
        }
        return url
    }

    public func request(id: UUID) throws -> MiniAppInvocation? {
        try transaction { try readRecord(id)?.request }
    }

    public func pendingRequests() throws -> [MiniAppInvocation] {
        try transaction {
            try records().filter { $0.result == nil }.map(\.request).sorted {
                $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
            }
        }
    }

    /// Called by MiniApps after the actual execution has completed. Repeated
    /// delivery of the identical result is harmless; a conflicting result is not
    /// allowed to overwrite a result the source app may already have applied.
    public func complete(_ result: MiniAppResult) throws {
        try transaction {
            guard var record = try readRecord(result.requestID) else { throw MiniAppBridgeError.missingRequest }
            if let existing = record.result {
                guard existing == result else { throw MiniAppBridgeError.conflictingResult }
                return
            }
            record.result = result
            try writeRecord(record)
        }
    }

    public func result(id: UUID) throws -> MiniAppResult? {
        try transaction { try readRecord(id)?.result }
    }

    public func pendingResults(sourceAppID: String) throws -> [MiniAppResult] {
        try transaction {
            try records().filter { !$0.acknowledged && $0.request.source.appID == sourceAppID }
                .sorted { $0.request.createdAt < $1.request.createdAt }.compactMap(\.result)
        }
    }

    /// Call only AFTER the host commits the returned edit and its request-ID
    /// receipt in one native transaction. Acknowledging first can lose an edit;
    /// applying without a host receipt can replay an edit after process death.
    @discardableResult
    public func acknowledgeResult(id: UUID, sourceAppID: String) throws -> Bool {
        try transaction {
            guard var record = try readRecord(id), record.result != nil else {
                throw MiniAppBridgeError.missingRequest
            }
            guard record.request.source.appID == sourceAppID else { throw MiniAppBridgeError.wrongSource }
            guard !record.acknowledged else { return false }
            record.acknowledged = true
            try writeRecord(record)
            return true
        }
    }

    /// Copies an input/output file into the App Group; names are display metadata,
    /// while UUIDs identify files independently of source sandbox locations.
    public func importAttachment(at sourceURL: URL, name: String? = nil,
                                 typeIdentifier: String? = nil) throws -> MiniAppContent {
        let id = UUID()
        try transaction {
            try FileManager.default.createDirectory(at: attachmentRoot, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: attachmentPath(id))
        }
        return .init(kind: .file, attachmentID: id, typeIdentifier: typeIdentifier,
                     name: name ?? sourceURL.lastPathComponent)
    }

    public func writeAttachment(_ data: Data, name: String? = nil,
                                typeIdentifier: String? = nil) throws -> MiniAppContent {
        let id = UUID()
        try transaction {
            try FileManager.default.createDirectory(at: attachmentRoot, withIntermediateDirectories: true)
            try data.write(to: attachmentPath(id), options: .atomic)
        }
        return .init(kind: .file, attachmentID: id, typeIdentifier: typeIdentifier, name: name)
    }

    public func attachmentURL(id: UUID) throws -> URL {
        try transaction {
            let url = attachmentPath(id)
            guard FileManager.default.fileExists(atPath: url.path) else { throw MiniAppBridgeError.invalidAttachment }
            return url
        }
    }

    public static func requestID(from url: URL) -> UUID? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = parts.queryItems?.first(where: { $0.name == "request" })?.value else { return nil }
        return UUID(uuidString: value)
    }

    public static func launchURL(for request: MiniAppInvocation) throws -> URL {
        var parts = URLComponents()
        parts.scheme = urlScheme; parts.host = "x-callback-url"; parts.path = "/run"
        var query = [URLQueryItem(name: "request", value: request.id.uuidString.lowercased()),
                     URLQueryItem(name: "x-source", value: request.source.displayName)]
        if let url = request.callbacks.success { query.append(.init(name: "x-success", value: url.absoluteString)) }
        if let url = request.callbacks.error { query.append(.init(name: "x-error", value: url.absoluteString)) }
        if let url = request.callbacks.cancel { query.append(.init(name: "x-cancel", value: url.absoluteString)) }
        parts.queryItems = query
        guard let url = parts.url else { throw MiniAppBridgeError.invalidURL }
        return url
    }

    private var requestRoot: URL { rootURL.appendingPathComponent("requests", isDirectory: true) }
    private var attachmentRoot: URL { rootURL.appendingPathComponent("attachments", isDirectory: true) }
    private func requestPath(_ id: UUID) -> URL {
        requestRoot.appendingPathComponent(id.uuidString.lowercased()).appendingPathExtension("json")
    }
    private func attachmentPath(_ id: UUID) -> URL {
        attachmentRoot.appendingPathComponent(id.uuidString.lowercased())
    }

    private func readRecord(_ id: UUID) throws -> Record? {
        guard let record: Record = try read(requestPath(id)) else { return nil }
        guard record.schemaVersion == 1 else { throw MiniAppBridgeError.unsupportedSchema }
        guard record.request.id == id, record.result == nil || record.result?.requestID == id else {
            throw MiniAppBridgeError.duplicateIdentity
        }
        return record
    }

    private func writeRecord(_ record: Record) throws {
        try FileManager.default.createDirectory(at: requestRoot, withIntermediateDirectories: true)
        try write(record, to: requestPath(record.request.id))
    }

    private func records() throws -> [Record] {
        guard FileManager.default.fileExists(atPath: requestRoot.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: requestRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
                return try readRecord(id)
            }
    }

    private func read<Value: Decodable>(_ url: URL) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func transaction<Value>(_ operation: () throws -> Value) throws -> Value {
        let descriptor = open(rootURL.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { _ = close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
