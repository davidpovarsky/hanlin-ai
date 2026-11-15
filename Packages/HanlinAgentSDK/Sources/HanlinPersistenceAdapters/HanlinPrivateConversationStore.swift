import Foundation
import HanlinHostContracts

/// One actor instance owns this private directory. Cross-process/AppGroup writers are unsupported;
/// hosts needing them must inject their coordinated store. No credentials or host DB access here.
public actor HanlinPrivateConversationStore: HanlinConversationStore {
    private let directory: URL
    private let maximumRecordBytes: Int

    public init(directory: URL, maximumRecordBytes: Int = 4 * 1_048_576) throws {
        guard directory.isFileURL, maximumRecordBytes > 0, maximumRecordBytes <= 16 * 1_048_576 else {
            throw HanlinHostError.invalidArguments
        }
        self.directory = directory.standardizedFileURL
        self.maximumRecordBytes = maximumRecordBytes
    }

    public func load(_ id: UUID, namespace: HanlinConversationNamespace) throws -> HanlinConversationRecord? {
        let url = location(id, namespace: namespace)
        try rejectSymbolicLinks(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= maximumRecordBytes else { throw HanlinHostError.storageLimitExceeded }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumRecordBytes else { throw HanlinHostError.storageLimitExceeded }
        let record = try JSONDecoder().decode(HanlinConversationRecord.self, from: data)
        try record.validate()
        guard record.namespace == namespace, record.conversationID == id else { throw HanlinHostError.invalidRecord }
        return record
    }

    public func save(_ record: HanlinConversationRecord, replacing revision: UInt64?) throws {
        try record.validate()
        let old = try load(record.conversationID, namespace: record.namespace)
        guard old?.revision == revision,
              revision.map({ $0 < UInt64.max && record.revision == $0 + 1 }) ?? (record.revision == 0) else { throw HanlinHostError.storeConflict }
        let data = try JSONEncoder().encode(record)
        guard data.count <= maximumRecordBytes else { throw HanlinHostError.storageLimitExceeded }
        let url = location(record.conversationID, namespace: record.namespace)
        try rejectSymbolicLinks(url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    public func delete(_ id: UUID, namespace: HanlinConversationNamespace, replacing revision: UInt64) throws {
        guard let current = try load(id, namespace: namespace), current.revision == revision else { throw HanlinHostError.storeConflict }
        try FileManager.default.removeItem(at: location(id, namespace: namespace))
    }

    /// Migration is copy/checkpoint only. Unknown versions fail during load and remain untouched.
    /// Restore remains an explicit compare-and-replace by the host, never automatic destructive move.
    public func checkpoint(_ id: UUID, namespace: HanlinConversationNamespace) throws -> Data {
        guard let record = try load(id, namespace: namespace) else { throw HanlinHostError.invalidRecord }
        return try JSONEncoder().encode(record)
    }

    public func restoreCheckpoint(_ data: Data, namespace: HanlinConversationNamespace,
                                  replacing revision: UInt64) throws {
        guard data.count <= maximumRecordBytes else { throw HanlinHostError.storageLimitExceeded }
        let old = try JSONDecoder().decode(HanlinConversationRecord.self, from: data)
        try old.validate()
        guard old.namespace == namespace, revision < UInt64.max else { throw HanlinHostError.invalidRecord }
        try save(.init(namespace: namespace, conversationID: old.conversationID, revision: revision + 1,
                       model: old.model, draft: old.draft, entries: old.entries), replacing: revision)
    }

    private func location(_ id: UUID, namespace: HanlinConversationNamespace) -> URL {
        // Each base64url component is injective and cannot contain path separators. Split long
        // components into chunks: no platform filename-length limit or lossy sanitization.
        var url = directory
        for component in [namespace.app, namespace.account, namespace.workspace, namespace.space] {
            let encoded = Data(component.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let midpoint = encoded.index(encoded.startIndex, offsetBy: min(86, encoded.count))
            url.append(path: "n-" + String(encoded[..<midpoint]), directoryHint: .isDirectory)
            url.append(path: "v-" + String(encoded[midpoint...]), directoryHint: .isDirectory)
        }
        return url.appending(path: id.uuidString.lowercased() + ".json", directoryHint: .notDirectory)
    }

    private func rejectSymbolicLinks(_ url: URL) throws {
        var cursor = url.path
        // Check all existing ancestors, including the host-supplied root. This is a private
        // single-writer store, not an adversarial shared-filesystem race/locking guarantee.
        // Use a strictly shortening lexical path, not repeated mutating Foundation URL
        // navigation. A malformed/non-progressing ancestor must fail closed, never hang save.
        for _ in 0..<1024 {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: cursor),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw HanlinHostError.invalidRecord }
            let parent = (cursor as NSString).deletingLastPathComponent
            if parent == cursor { return }
            guard parent.utf8.count < cursor.utf8.count else { throw HanlinHostError.invalidRecord }
            cursor = parent
        }
        throw HanlinHostError.invalidRecord
    }
}
