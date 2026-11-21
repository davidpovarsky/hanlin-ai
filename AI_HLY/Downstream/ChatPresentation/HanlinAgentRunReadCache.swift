import Foundation

/// A per-ChatView read-through cache for the original persisted AgentRun getter.
/// It is deliberately not Observable: a cache hit during body evaluation must
/// not publish another view update. Entries retain values, never model objects,
/// model contexts, sessions, or live execution authority.
@MainActor
final class HanlinAgentRunReadCache {
    private struct Entry {
        let sourceJSON: String
        let run: AgentRun?
        let sourceBytes: Int
        var lastAccess: UInt64
    }

    private let capacity: Int
    private let maximumSourceBytes: Int
    private let decode: @MainActor (ChatMessages) -> AgentRun?
    private var entries: [UUID: Entry] = [:]
    private var retainedSourceBytes = 0
    private var accessSequence: UInt64 = 0

    init(capacity: Int = 64, maximumSourceBytes: Int = 16 * 1_024 * 1_024,
         decode: @escaping @MainActor (ChatMessages) -> AgentRun? = { $0.agentRun }) {
        self.capacity = max(0, capacity)
        self.maximumSourceBytes = max(0, maximumSourceBytes)
        self.decode = decode
    }

    func run(for message: ChatMessages) -> AgentRun? {
        let messageID = message.id
        guard let sourceJSON = message.agentRunJSON else {
            // Most non-owner rows have no persisted run. They must neither
            // decode nor evict useful snapshots from the bounded cache.
            remove(messageID)
            return nil
        }
        let sourceBytes = sourceJSON.utf8.count
        accessSequence &+= 1
        if var cached = entries[messageID], cached.sourceBytes == sourceBytes,
           cached.sourceJSON.utf8.elementsEqual(sourceJSON.utf8) {
            cached.lastAccess = accessSequence
            entries[messageID] = cached
            return cached.run
        }

        // Malformed replacements invalidate a previously valid value.
        // The existing getter remains the schema/decoding authority.
        remove(messageID)
        let run = decode(message)
        guard capacity > 0, sourceBytes <= maximumSourceBytes else { return run }
        while entries.count >= capacity || retainedSourceBytes + sourceBytes > maximumSourceBytes {
            guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { break }
            remove(oldest)
        }
        entries[messageID] = Entry(sourceJSON: sourceJSON, run: run,
            sourceBytes: sourceBytes, lastAccess: accessSequence)
        retainedSourceBytes += sourceBytes
        return run
    }

    private func remove(_ messageID: UUID) {
        if let removed = entries.removeValue(forKey: messageID) {
            retainedSourceBytes -= removed.sourceBytes
        }
    }
}
