import CryptoKit
import Foundation

public enum HanlinScriptExtensionStoreError: Error, Equatable, Sendable {
    case appGroupUnavailable
    case snapshotTooLarge
    case invalidEnvelope
    case integrityMismatch
    case unsupportedSchema(UInt32)
}

public struct HanlinScriptExtensionStore: Sendable {
    public static let appGroupIdentifier = "group.cherryai.com.AI-Hanlin"
    public static let maximumSnapshotBytes = 4 * 1_024 * 1_024

    private struct Envelope: Codable {
        let schemaVersion: UInt32
        let sha256: String
        let snapshot: HanlinScriptExtensionSnapshot
    }

    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public init(appGroupIdentifier: String = Self.appGroupIdentifier) throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw HanlinScriptExtensionStoreError.appGroupUnavailable
        }
        root = container.appending(path: "ScriptingExtensions", directoryHint: .isDirectory)
    }

    public func load() throws -> HanlinScriptExtensionSnapshot? {
        let url = snapshotURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumSnapshotBytes else {
            throw HanlinScriptExtensionStoreError.snapshotTooLarge
        }
        let envelope = try Self.decoded(Envelope.self, from: data)
        guard envelope.schemaVersion == 1 else {
            throw HanlinScriptExtensionStoreError.unsupportedSchema(envelope.schemaVersion)
        }
        let snapshotData = try Self.encoded(envelope.snapshot)
        guard Self.digest(snapshotData) == envelope.sha256 else {
            throw HanlinScriptExtensionStoreError.integrityMismatch
        }
        return envelope.snapshot
    }

    public func save(_ snapshot: HanlinScriptExtensionSnapshot) throws {
        guard snapshot.schemaVersion == 1 else {
            throw HanlinScriptExtensionStoreError.unsupportedSchema(snapshot.schemaVersion)
        }
        let snapshotData = try Self.encoded(snapshot)
        let envelope = Envelope(
            schemaVersion: 1,
            sha256: Self.digest(snapshotData),
            snapshot: snapshot
        )
        let data = try Self.encoded(envelope)
        guard data.count <= Self.maximumSnapshotBytes else {
            throw HanlinScriptExtensionStoreError.snapshotTooLarge
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: snapshotURL, options: [.atomic, .completeFileProtection])
    }

    public func enqueue(_ command: HanlinScriptResumeCommand) throws {
        try FileManager.default.createDirectory(at: commandRoot, withIntermediateDirectories: true)
        let existing = try FileManager.default.contentsOfDirectory(
            at: commandRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        guard existing.count < 128 else {
            throw HanlinScriptExtensionStoreError.snapshotTooLarge
        }
        let data = try Self.encoded(command)
        guard data.count <= 256 * 1_024 else {
            throw HanlinScriptExtensionStoreError.snapshotTooLarge
        }
        try data.write(
            to: commandRoot.appending(path: "\(command.id.uuidString.lowercased()).json"),
            options: [.atomic, .completeFileProtection]
        )
    }

    public func pendingCommands(limit: Int = 64) throws -> [HanlinScriptResumeCommand] {
        guard FileManager.default.fileExists(atPath: commandRoot.path(percentEncoded: false)) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: commandRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.prefix(max(0, limit)).map {
            try Self.decoded(HanlinScriptResumeCommand.self, from: Data(contentsOf: $0))
        }.sorted { $0.createdAt < $1.createdAt }
    }

    public func acknowledge(_ commandID: UUID) throws {
        let url = commandRoot.appending(path: "\(commandID.uuidString.lowercased()).json")
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private var snapshotURL: URL {
        root.appending(path: "snapshot-v1.json", directoryHint: .notDirectory)
    }

    private var commandRoot: URL {
        root.appending(path: "ResumeQueue", directoryHint: .isDirectory)
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func decoded<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
