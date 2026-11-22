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
            if let index = indexByCanonicalKey[key] {
                items[index].alternateURLs = Self.boundedAlternateURLs(
                    (items[index].alternateURLs ?? []) + [candidate.url].compactMap { $0 }
                        + (candidate.alternateURLs ?? []), primaryURL: items[index].url)
                if let newAnchors = candidate.claimAnchors {
                    var anchors = items[index].claimAnchors ?? []
                    for anchor in newAnchors where !anchors.contains(anchor) && anchors.count < 256 { anchors.append(anchor) }
                    items[index].claimAnchors = anchors
                }
                continue
            }

            var item = candidate
            item.id = AgentEvidenceDeduplicator.stableID(for: item)
            item.alternateURLs = Self.boundedAlternateURLs(item.alternateURLs ?? [], primaryURL: item.url)
            indexByCanonicalKey[key] = items.count
            items.append(item)
        }
    }

    private static func boundedAlternateURLs(_ values: [String], primaryURL: String?) -> [String]? {
        var seen = Set([primaryURL].compactMap { $0 })
        var result: [String] = []
        // Deduplication may fold a returned #section or tracking variant into
        // an earlier source. Keep its exact URL, never an inferred equivalent.
        for value in values {
            guard value.utf8.count <= 8_192, let url = URL(string: value),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  url.host?.isEmpty == false, seen.insert(value).inserted else { continue }
            result.append(value)
            if result.count == 32 { break }
        }
        return result.isEmpty ? nil : result
    }
}
