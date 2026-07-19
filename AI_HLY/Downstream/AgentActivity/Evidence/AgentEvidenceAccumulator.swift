import Foundation

struct AgentEvidenceAccumulator {
    private(set) var items: [AgentEvidenceItem]
    private var indexByCanonicalKey: [String: Int]

    init(items: [AgentEvidenceItem] = []) {
        self.items = []
        indexByCanonicalKey = [:]
        insert(contentsOf: items)
    }

    mutating func insert(contentsOf candidates: [AgentEvidenceItem]) {
        for candidate in candidates where candidate.wasReturnedToModel {
            let canonicalKey = AgentEvidenceDeduplicator.canonicalKey(for: candidate)
            guard !canonicalKey.isEmpty else { continue }
            let key = "\(candidate.kind.rawValue):\(canonicalKey)"
            guard indexByCanonicalKey[key] == nil else { continue }

            var item = candidate
            item.id = AgentEvidenceDeduplicator.stableID(for: item)
            indexByCanonicalKey[key] = items.count
            items.append(item)
        }
    }
}
