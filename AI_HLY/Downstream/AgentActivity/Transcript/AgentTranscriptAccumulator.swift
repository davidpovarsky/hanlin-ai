import Foundation

struct AgentTranscriptAccumulator {
    private(set) var items: [AgentTranscriptItem]
    private var itemIndexByExternalID: [String: Int]
    private var resultDeduplicationKeys: Set<String>
    private(set) var nextSequence: Int

    init(items: [AgentTranscriptItem] = []) {
        self.items = items.sorted { $0.sequence < $1.sequence }
        itemIndexByExternalID = [:]
        resultDeduplicationKeys = []
        nextSequence = (items.map(\.sequence).max() ?? -1) + 1

        for (index, item) in self.items.enumerated() {
            if let externalID = item.externalID {
                itemIndexByExternalID[externalID] = index
            }
            if item.kind == .userVisibleToolResult {
                resultDeduplicationKeys.insert(Self.resultKey(callID: item.callID, blocks: item.nativeUIBlocks))
            }
        }
    }

    mutating func begin(
        externalID: String,
        kind: AgentTranscriptItemKind,
        roundID: String? = nil,
        callID: String? = nil,
        activityStepID: UUID? = nil,
        startedAt: Date = Date(),
        status: AgentActivityStatus = .running,
        text: String? = nil,
        textRole: AgentTranscriptTextRole? = nil,
        visibility: AgentTranscriptCompletionVisibility = .collapseIntoThinking,
        sequence: Int? = nil
    ) -> UUID {
        if let index = itemIndexByExternalID[externalID], items.indices.contains(index) {
            return items[index].id
        }

        let item = AgentTranscriptItem(
            externalID: externalID,
            sequence: sequence ?? allocateSequence(),
            kind: kind,
            roundID: roundID,
            callID: callID,
            activityStepID: activityStepID,
            startedAt: startedAt,
            completedAt: status == .completed ? startedAt : nil,
            status: status,
            text: text,
            textRole: textRole,
            visibilityAfterCompletion: visibility
        )
        items.append(item)
        itemIndexByExternalID[externalID] = items.count - 1
        AgentTranscriptDiagnostics.itemCreated(item)
        return item.id
    }

    mutating func appendText(_ text: String, to externalID: String) {
        guard !text.isEmpty else { return }
        update(externalID: externalID) { item in
            item.text = (item.text ?? "") + text
        }
    }

    mutating func update(
        externalID: String,
        _ mutation: (inout AgentTranscriptItem) -> Void
    ) {
        guard let index = itemIndexByExternalID[externalID], items.indices.contains(index) else { return }
        mutation(&items[index])
    }

    func item(externalID: String) -> AgentTranscriptItem? {
        guard let index = itemIndexByExternalID[externalID], items.indices.contains(index) else { return nil }
        return items[index]
    }

    mutating func complete(
        externalID: String,
        status: AgentActivityStatus = .completed,
        completedAt: Date = Date()
    ) {
        guard let index = itemIndexByExternalID[externalID], items.indices.contains(index) else { return }
        items[index].status = status
        items[index].completedAt = completedAt
        AgentTranscriptDiagnostics.itemCompleted(items[index])
    }

    mutating func endAnswerSegment(
        externalID: String,
        disposition: AgentAnswerDisposition,
        completedAt: Date = Date()
    ) {
        update(externalID: externalID) { item in
            item.status = .completed
            item.completedAt = completedAt
            switch disposition {
            case .provisional:
                item.textRole = .provisional
                item.visibilityAfterCompletion = .collapseIntoThinking
            case .interim:
                item.textRole = .interim
                item.visibilityAfterCompletion = .collapseIntoThinking
            case .final:
                item.textRole = .final
                item.visibilityAfterCompletion = .remainInChat
            }
        }
        guard let index = itemIndexByExternalID[externalID], items.indices.contains(index) else { return }
        AgentTranscriptDiagnostics.answerSegmentCompleted(items[index])
    }

    @discardableResult
    mutating func insertUserVisibleResult(
        callID: String,
        blocks: [NativeUIBlock],
        completedAt: Date = Date()
    ) -> Bool {
        guard !blocks.isEmpty else { return false }
        let key = Self.resultKey(callID: callID, blocks: blocks)
        guard resultDeduplicationKeys.insert(key).inserted else {
            AgentTranscriptDiagnostics.duplicateResultSuppressed(callID: callID)
            return false
        }

        let externalID = "result:\(key)"
        let item = AgentTranscriptItem(
            externalID: externalID,
            sequence: allocateSequence(),
            kind: .userVisibleToolResult,
            callID: callID,
            startedAt: completedAt,
            completedAt: completedAt,
            status: .completed,
            nativeUIBlocks: blocks,
            visibilityAfterCompletion: .remainInChat
        )
        items.append(item)
        itemIndexByExternalID[externalID] = items.count - 1
        AgentTranscriptDiagnostics.userVisibleResultInserted(item)
        return true
    }

    mutating func closeActiveItems(as status: AgentActivityStatus, completedAt: Date = Date()) {
        for index in items.indices where items[index].status == .running || items[index].status == .pending {
            items[index].status = status
            items[index].completedAt = completedAt
            if items[index].kind == .assistantText {
                items[index].textRole = .interim
                items[index].visibilityAfterCompletion = .collapseIntoThinking
            }
            AgentTranscriptDiagnostics.itemCompleted(items[index])
        }
    }

    mutating func allocateSequence() -> Int {
        defer { nextSequence += 1 }
        return nextSequence
    }

    private static func resultKey(callID: String?, blocks: [NativeUIBlock]) -> String {
        let blockIDs = blocks.map(\.id).joined(separator: ",")
        return "\(callID ?? "unknown"):\(blockIDs)"
    }
}

enum AgentTranscriptDiagnostics {
    static func itemCreated(_ item: AgentTranscriptItem) {
        trace("agent_transcript_item_created", item: item)
    }

    static func itemCompleted(_ item: AgentTranscriptItem) {
        trace("agent_transcript_item_completed", item: item)
    }

    static func answerSegmentCompleted(_ item: AgentTranscriptItem) {
        let event = item.textRole == .final
            ? "agent_answer_segment_marked_final"
            : "agent_answer_segment_marked_interim"
        trace(event, item: item)
    }

    static func userVisibleResultInserted(_ item: AgentTranscriptItem) {
        trace("agent_user_visible_result_inserted", item: item)
    }

    static func duplicateResultSuppressed(callID: String) {
        guard AgentDiagnosticsConfiguration.level == .fullLocalDebug else { return }
        NativeToolTraceLogger.shared.log(
            "agent_duplicate_result_suppressed",
            ["callID": callID]
        )
    }

    private static func trace(_ event: String, item: AgentTranscriptItem) {
        guard AgentDiagnosticsConfiguration.level == .fullLocalDebug else { return }
        NativeToolTraceLogger.shared.log(
            event,
            [
                "itemID": item.id.uuidString,
                "kind": item.kind.rawValue,
                "sequence": item.sequence,
                "status": item.status.rawValue,
                "callID": item.callID ?? ""
            ]
        )
    }
}
