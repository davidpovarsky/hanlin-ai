import Foundation

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

    private let lock = NSLock()
    private var entries: [String: StoredResult] = [:]
    private var totalBytes: Int = 0

    public let maxEntries: Int
    public let maxTotalBytes: Int

    public init(maxEntries: Int = 50, maxTotalBytes: Int = 10 * 1024 * 1024) {
        self.maxEntries = maxEntries
        self.maxTotalBytes = maxTotalBytes
    }

    /// Stores a large tool output and returns an opaque, unguessable reference string.
    public func store(
        payload: String,
        mimeType: String = "text/plain",
        metadata: [String: String] = [:]
    ) -> String {
        lock.lock()
        defer { lock.unlock() }

        let referenceID = "ref_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))"
        let entryBytes = payload.utf8.count

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

    /// Reads a slice of the stored tool result with offset and limit pagination.
    public func read(
        reference: String,
        offset: Int = 0,
        limit: Int = 2000
    ) -> (chunk: String, totalBytes: Int, hasMore: Bool)? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[reference] else { return nil }
        let utf8 = entry.payload.utf8
        let total = utf8.count

        guard offset >= 0 && offset < total else {
            return (chunk: "", totalBytes: total, hasMore: false)
        }

        let clampedLimit = max(1, min(limit, 10000))
        let startIdx = utf8.index(utf8.startIndex, offsetBy: offset)
        let endOffset = min(offset + clampedLimit, total)
        let endIdx = utf8.index(utf8.startIndex, offsetBy: endOffset)
        let slice = String(utf8[startIdx..<endIdx]) ?? ""

        return (chunk: slice, totalBytes: total, hasMore: endOffset < total)
    }

    /// Returns the complete payload for UI / embedded renderers.
    public func fullPayload(for reference: String) -> String? {
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
