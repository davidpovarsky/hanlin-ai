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
            insert(candidate)
        }
    }

    mutating func markUsedInCompletedRun() {
        for index in items.indices where items[index].wasReturnedToModel {
            items[index].wasUsedInCompletedRun = true
        }
    }

    private mutating func insert(_ candidate: AgentEvidenceItem) {
        let canonicalKey = AgentEvidenceDeduplicator.canonicalKey(for: candidate)
        guard !canonicalKey.isEmpty else {
            AgentEvidenceDiagnostics.suppressed(reason: "missingCanonicalKey", kind: candidate.kind)
            return
        }
        let key = "\(candidate.kind.rawValue):\(canonicalKey)"
        if let index = indexByCanonicalKey[key] {
            items[index].wasReturnedToModel = items[index].wasReturnedToModel || candidate.wasReturnedToModel
            items[index].wasUsedInCompletedRun = items[index].wasUsedInCompletedRun || candidate.wasUsedInCompletedRun
            if items[index].toolCallID == nil { items[index].toolCallID = candidate.toolCallID }
            AgentEvidenceDiagnostics.deduplicated(kind: candidate.kind)
            return
        }

        var item = candidate
        item.id = AgentEvidenceDeduplicator.stableID(for: item)
        indexByCanonicalKey[key] = items.count
        items.append(item)
        AgentEvidenceDiagnostics.extracted(kind: item.kind)
    }
}

enum AgentEvidenceDiagnostics {
    static func extracted(kind: AgentEvidenceKind) {
        log("evidenceItemExtracted", ["kind": kind.rawValue])
    }

    static func deduplicated(kind: AgentEvidenceKind) {
        log("evidenceItemDeduplicated", ["kind": kind.rawValue])
    }

    static func suppressed(reason: String, kind: AgentEvidenceKind? = nil) {
        log("evidenceItemSuppressed", ["reason": reason, "kind": kind?.rawValue ?? ""])
    }

    private static func log(_ event: String, _ fields: [String: Any]) {
        guard AgentDiagnosticsConfiguration.level != .off else { return }
        NativeToolTraceLogger.shared.log(event, fields)
    }
}
