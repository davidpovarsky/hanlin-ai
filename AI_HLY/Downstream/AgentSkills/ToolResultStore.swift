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

/// Run-scoped, bounded in-memory store for large tool execution results.
/// Prevents context bloat by storing full payloads behind opaque reference strings.
public final class ToolResultStore: @unchecked Sendable {
    public struct StoredResult: Sendable {
        public let referenceID: String
        public let payload: String
        public let mimeType: String
        public let createdAt: Date
        public let metadata: [String: String]

        public var byteCount: Int {
            payload.utf8.count
        }
    }

    public static let defaultReadLimit: Int = 4096
    public static let maxReadLimit: Int = 16384

    private let lock = NSLock()
    private var entries: [String: StoredResult] = [:]
    private var totalBytes: Int = 0

    public let maxEntries: Int
    public let maxTotalBytes: Int

    public var currentTotalBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalBytes
    }

    public init(maxEntries: Int = 50, maxTotalBytes: Int = 10 * 1024 * 1024) {
        self.maxEntries = maxEntries
        self.maxTotalBytes = maxTotalBytes
    }

    public convenience init(maxStoredBytes: Int) {
        self.init(maxEntries: 100, maxTotalBytes: maxStoredBytes)
    }

    /// Stores a large tool output and returns an opaque, unguessable reference string.
    /// Rejects entries that individually exceed maxTotalBytes to maintain hard capacity bounds.
    @discardableResult
    public func store(
        _ payload: String,
        mimeType: String = "text/plain",
        metadata: [String: String] = [:]
    ) -> String {
        lock.lock()
        defer { lock.unlock() }

        let entryBytes = payload.utf8.count
        guard entryBytes <= maxTotalBytes else {
            // Truthfully reject entry that exceeds the store's hard byte capacity
            return ""
        }

        let referenceID = "ref_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))"

        // Evict oldest if bounds exceeded
        while (entries.count >= maxEntries || totalBytes + entryBytes > maxTotalBytes) && !entries.isEmpty {
            if let oldest = entries.values.min(by: { $0.createdAt < $1.createdAt }) {
                entries.removeValue(forKey: oldest.referenceID)
                totalBytes -= oldest.byteCount
            } else {
                break
            }
        }

        let stored = StoredResult(
            referenceID: referenceID,
            payload: payload,
            mimeType: mimeType,
            createdAt: Date(),
            metadata: metadata
        )
        entries[referenceID] = stored
        totalBytes += entryBytes
        return referenceID
    }

    /// Stores a large tool output with labeled payload parameter.
    @discardableResult
    public func store(
        payload: String,
        mimeType: String = "text/plain",
        metadata: [String: String] = [:]
    ) -> String {
        store(payload, mimeType: mimeType, metadata: metadata)
    }

    /// Reads a slice of the stored tool result with offset and limit pagination.
    /// Guarantees Unicode UTF-8 boundary safety, preventing truncated multi-byte sequences.
    public func read(
        reference: String,
        offset: Int = 0,
        limit: Int = ToolResultStore.defaultReadLimit
    ) -> ToolResultSlice? {
        guard !reference.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[reference] else { return nil }
        let data = Data(entry.payload.utf8)
        let total = data.count

        guard offset >= 0 && offset < total else {
            return ToolResultSlice(chunk: "", offset: offset, totalBytes: total, hasMore: false)
        }

        let clampedLimit = max(1, min(limit, Self.maxReadLimit))

        // Snap start offset forward to valid UTF-8 leading byte if it landed on a continuation byte (0x80...0xBF)
        var start = offset
        while start < total && (data[start] & 0xC0) == 0x80 {
            start += 1
        }

        guard start < total else {
            return ToolResultSlice(chunk: "", offset: offset, totalBytes: total, hasMore: false)
        }

        var end = min(start + clampedLimit, total)
        if end < total {
            // Snap end backward so we don't cut off mid-character
            while end > start && (data[end] & 0xC0) == 0x80 {
                end -= 1
            }
            // If clampedLimit was smaller than one multi-byte character, advance end to complete the character
            if end == start {
                end = min(start + clampedLimit, total)
                while end < total && (data[end] & 0xC0) == 0x80 {
                    end += 1
                }
            }
        }

        let sliceBytes = data[start..<end]
        let slice = String(decoding: sliceBytes, as: UTF8.self)

        return ToolResultSlice(
            chunk: slice,
            offset: start,
            totalBytes: total,
            hasMore: end < total
        )
    }

    /// Returns the complete payload for UI / embedded renderers.
    public func fullPayload(for reference: String) -> String? {
        guard !reference.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return entries[reference]?.payload
    }

    /// Clears all entries when the assistant run terminates.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        totalBytes = 0
    }
}
