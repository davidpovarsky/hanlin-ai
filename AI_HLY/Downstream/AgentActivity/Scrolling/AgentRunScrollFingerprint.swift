import Foundation

struct AgentRunScrollFingerprint: Equatable, Sendable {
    var runID: UUID?
    var status: AgentActivityStatus?
    var transcriptItemCount: Int
    var lastSequence: Int?
    var lastItemID: UUID?
    var lastItemTextLength: Int
    var lastItemStatus: AgentActivityStatus?
    var visibleResultCount: Int
    var evidenceCount: Int
    var finalAnswerLength: Int

    func isStructuralChange(comparedTo previous: AgentRunScrollFingerprint?) -> Bool {
        guard let previous else { return true }
        return runID != previous.runID
            || status != previous.status
            || transcriptItemCount != previous.transcriptItemCount
            || lastItemID != previous.lastItemID
            || lastItemStatus != previous.lastItemStatus
            || visibleResultCount != previous.visibleResultCount
            || evidenceCount != previous.evidenceCount
    }
}

extension AgentRun {
    var scrollFingerprint: AgentRunScrollFingerprint {
        let ordered = transcriptItems.max { $0.sequence < $1.sequence }
        return AgentRunScrollFingerprint(
            runID: id,
            status: status,
            transcriptItemCount: transcriptItems.count,
            lastSequence: ordered?.sequence,
            lastItemID: ordered?.id,
            lastItemTextLength: ordered?.text?.count ?? 0,
            lastItemStatus: ordered?.status,
            visibleResultCount: transcriptItems.lazy.filter {
                $0.kind == .userVisibleToolResult
            }.count,
            evidenceCount: evidenceItems.lazy.filter(\.wasReturnedToModel).count,
            finalAnswerLength: finalAnswer?.count ?? 0
        )
    }
}
