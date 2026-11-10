import Foundation

public typealias BoundedToolResultStore = ToolResultStore

public struct ToolResultSlice: Sendable {
    public let text: String
    public let chunk: String
    public let offset: Int
    public let sliceLength: Int
    public let totalLength: Int
    public let totalBytes: Int
    public let hasMore: Bool

    public init(
        chunk: String,
        offset: Int,
        totalBytes: Int,
        hasMore: Bool
    ) {
        self.text = chunk
        self.chunk = chunk
        self.offset = offset
        self.sliceLength = chunk.utf8.count
        self.totalLength = totalBytes
        self.totalBytes = totalBytes
        self.hasMore = hasMore
    }
}

/// Disk-backed full results. Pagination bounds transport, never retention.
/// Explicit legacy capacity budgets remain opt-in; ordinary sessions have no eviction cap.
public final class ToolResultStore: @unchecked Sendable {
    private struct Record: Codable {
        let referenceID: String
        let byteCount: Int
        let mimeType: String
        let createdAt: Date
        let metadata: [String: String]
    }

    public static let defaultReadLimit = 4096
    public static let maxReadLimit = 16384
    public let directory: URL
    public let maxEntries: Int?
    public let maxTotalBytes: Int?
    private let lock = NSLock()
    private var entries: [String: Record] = [:]
    private var totalBytes = 0
    public private(set) var lastStorageError: String?

    public var currentTotalBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return totalBytes
    }

    public init(maxEntries: Int? = nil, maxTotalBytes: Int? = nil, directory: URL? = nil) {
        self.maxEntries = maxEntries
        self.maxTotalBytes = maxTotalBytes
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? base.appending(path: "Hanlin/ToolResults/\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            for file in try FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
                let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: file))
                guard Self.validReference(record.referenceID),
                      FileManager.default.fileExists(atPath: payloadURL(record.referenceID).path) else { continue }
                entries[record.referenceID] = record
                totalBytes += record.byteCount
            }
        } catch { lastStorageError = error.localizedDescription }
    }

    public convenience init(maxStoredBytes: Int) {
        self.init(maxEntries: 100, maxTotalBytes: maxStoredBytes)
    }

    private static func validReference(_ reference: String) -> Bool {
        reference.hasPrefix("ref_") && reference.count == 36
            && reference.dropFirst(4).allSatisfy { "0123456789abcdef".contains($0) }
    }

    private func payloadURL(_ reference: String) -> URL { directory.appending(path: reference + ".payload") }
    private func metadataURL(_ reference: String) -> URL { directory.appending(path: reference + ".json") }

    @discardableResult
    public func store(_ payload: String, mimeType: String = "text/plain", metadata: [String: String] = [:]) -> String? {
        lock.lock(); defer { lock.unlock() }
        let data = Data(payload.utf8)
        if let maxTotalBytes, data.count > maxTotalBytes { return nil }
        if let maxEntries, maxEntries < 1 { return nil }
        let reference = "ref_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let record = Record(referenceID: reference, byteCount: data.count, mimeType: mimeType, createdAt: Date(), metadata: metadata)
        do {
            try data.write(to: payloadURL(reference), options: .atomic)
            do { try JSONEncoder().encode(record).write(to: metadataURL(reference), options: .atomic) }
            catch { try? FileManager.default.removeItem(at: payloadURL(reference)); throw error }
            // Only callers explicitly choosing the legacy bounded policy opt into eviction.
            while (maxEntries.map { entries.count >= $0 } ?? false)
                || (maxTotalBytes.map { totalBytes + data.count > $0 } ?? false) {
                guard let oldest = entries.values.min(by: { $0.createdAt < $1.createdAt }) else { break }
                try FileManager.default.removeItem(at: metadataURL(oldest.referenceID))
                try FileManager.default.removeItem(at: payloadURL(oldest.referenceID))
                entries.removeValue(forKey: oldest.referenceID)
                totalBytes -= oldest.byteCount
            }
            entries[reference] = record
            totalBytes += data.count
            lastStorageError = nil
            return reference
        } catch {
            lastStorageError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    public func store(payload: String, mimeType: String = "text/plain", metadata: [String: String] = [:]) -> String? {
        store(payload, mimeType: mimeType, metadata: metadata)
    }

    public func read(reference: String, offset: Int = 0, limit: Int = defaultReadLimit) -> ToolResultSlice? {
        lock.lock(); defer { lock.unlock() }
        guard Self.validReference(reference), let record = entries[reference], offset >= 0 else { return nil }
        if offset >= record.byteCount { return ToolResultSlice(chunk: "", offset: offset, totalBytes: record.byteCount, hasMore: false) }
        do {
            let handle = try FileHandle(forReadingFrom: payloadURL(reference))
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            let count = min(max(1, min(limit, Self.maxReadLimit)) + 4, record.byteCount - offset)
            let data = try handle.read(upToCount: count) ?? Data()
            var start = 0
            while start < data.count && (data[start] & 0xC0) == 0x80 { start += 1 }
            var end = min(start + max(1, min(limit, Self.maxReadLimit)), data.count)
            while end > start && end < data.count && (data[end] & 0xC0) == 0x80 { end -= 1 }
            if end == start {
                end = min(start + 1, data.count)
                while end < data.count && (data[end] & 0xC0) == 0x80 { end += 1 }
            }
            guard let text = String(data: data[start..<end], encoding: .utf8) else { return nil }
            return ToolResultSlice(chunk: text, offset: offset + start, totalBytes: record.byteCount, hasMore: offset + end < record.byteCount)
        } catch { lastStorageError = error.localizedDescription; return nil }
    }

    public func fullPayload(for reference: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard Self.validReference(reference), entries[reference] != nil else { return nil }
        do { return try String(contentsOf: payloadURL(reference), encoding: .utf8) }
        catch { lastStorageError = error.localizedDescription; return nil }
    }

    /// Explicit deletion only. Finishing a run does not delete referenced history.
    public func clear() {
        lock.lock(); defer { lock.unlock() }
        do {
            for reference in entries.keys {
                try FileManager.default.removeItem(at: metadataURL(reference))
                try FileManager.default.removeItem(at: payloadURL(reference))
            }
            entries.removeAll(); totalBytes = 0; lastStorageError = nil
        } catch { lastStorageError = error.localizedDescription }
    }
}
