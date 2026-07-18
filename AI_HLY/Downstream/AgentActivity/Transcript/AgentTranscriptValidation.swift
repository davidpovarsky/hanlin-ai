import Foundation

enum AgentTranscriptValidation {
    static func normalized(_ items: [AgentTranscriptItem]) -> [AgentTranscriptItem] {
        var seenIDs = Set<UUID>()
        var seenSequences = Set<Int>()
        return items
            .sorted { lhs, rhs in
                lhs.sequence == rhs.sequence
                    ? lhs.startedAt < rhs.startedAt
                    : lhs.sequence < rhs.sequence
            }
            .filter { item in
                guard item.sequence >= 0,
                      seenIDs.insert(item.id).inserted,
                      seenSequences.insert(item.sequence).inserted else {
                    return false
                }
                if item.kind == .userVisibleToolResult {
                    return !item.nativeUIBlocks.isEmpty
                }
                return true
            }
    }

    static func hasStrictlyIncreasingSequence(_ items: [AgentTranscriptItem]) -> Bool {
        let sequences = items.sorted { $0.sequence < $1.sequence }.map(\.sequence)
        return zip(sequences, sequences.dropFirst()).allSatisfy { lhs, rhs in
            lhs < rhs
        }
    }

    static func containsDuplicateNativeUIResults(_ items: [AgentTranscriptItem]) -> Bool {
        var keys = Set<String>()
        for item in items where item.kind == .userVisibleToolResult {
            let key = "\(item.callID ?? ""):\(item.nativeUIBlocks.map(\.id).joined(separator: ","))"
            if !keys.insert(key).inserted { return true }
        }
        return false
    }
}
