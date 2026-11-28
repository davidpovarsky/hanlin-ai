import Foundation
import HanlinPlatformContracts

/// Original deterministic projection shared by the activity UI and app persistence adapter.
public enum AgentActivityToolProjection {

    /// Convenience projection to derive view-oriented structured tool items from an `AgentRun`.
    public static func projectToolEntries(from agentRun: AgentRun?, callID: String? = nil) -> [ClassicProjectedToolCallEntry] {
        guard var agentRun else { return [] }
        if let callID {
            // A mounted disclosure projects only its own call. Its payload does
            // not change when a parent begins collapsing, and collapsed calls
            // never pay the sanitization cost for unrelated tool outputs.
            agentRun.steps.removeAll {
                ($0.toolCallID ?? $0.externalID ?? $0.id.uuidString) != callID
            }
            agentRun.transcriptItems.removeAll { $0.callID != callID }
        }
        var entries: [ClassicProjectedToolCallEntry] = []
        var seenKeys: Set<String> = []
        syncStructuredToolEntries(
            from: agentRun,
            runID: agentRun.id,
            orderedToolEntries: &entries,
            seenToolCallKeys: &seenKeys
        )
        return entries
    }

    /// Builds deterministic per-call entries from `AgentRun.steps` and `AgentRun.transcriptItems`.
    /// Preserves independent tool calls with identical toolName and output by keying strictly on runID + callID.
    public static func syncStructuredToolEntries(
        from agentRun: AgentRun,
        runID: UUID,
        orderedToolEntries: inout [ClassicProjectedToolCallEntry],
        seenToolCallKeys: inout Set<String>
    ) {
        let toolSteps = agentRun.steps.filter(isToolProjectionStep)
        var entryIndexByCallID: [String: Int] = [:]
        for index in orderedToolEntries.indices {
            entryIndexByCallID[orderedToolEntries[index].callID] = index
        }

        // Map callID -> canonical toolName and status from transcriptItems when available
        var toolNameByCallID: [String: String] = [:]
        var statusByCallID: [String: AgentActivityStatus] = [:]
        var payloadByCallID: [String: HanlinEmbeddedResultPayload] = [:]
        for item in agentRun.transcriptItems {
            if let callID = item.callID, !callID.isEmpty {
                if let tName = item.toolName, !tName.isEmpty {
                    toolNameByCallID[callID] = tName
                }
                if item.kind == .toolActivity { statusByCallID[callID] = item.status }
                if let payload = item.embeddedResultPayload {
                    payloadByCallID[callID] = payload
                }
            }
        }

        for step in toolSteps {
            guard step.status == .completed || step.status == .failed || step.status == .running || step.status == .cancelled else { continue }
            let rawCallID = step.toolCallID ?? step.externalID ?? step.id.uuidString
            let stepTitle = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalToolName = toolNameByCallID[rawCallID]
                ?? step.subtitle
                ?? (stepTitle.isEmpty ? "tool" : stepTitle)
            let isMeta = ClassicProjectedToolCallEntry.isMetaTool(canonicalToolName)

            let rawOutput: String = {
                if let out = step.output?.trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty {
                    return out
                }
                if let err = step.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !err.isEmpty {
                    return "⚠️ \(err)"
                }
                return ""
            }()
            let sanitizedOutput = ClassicProjectedToolCallEntry.sanitizeUserFacingToolOutput(rawOutput, isMetaSkillOrDiscoveryTool: isMeta)
            let summary = step.userFacingSummary?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !sanitizedOutput.isEmpty || (summary?.isEmpty == false) || step.status == .running || step.status == .cancelled else { continue }

            let effectiveOutput = sanitizedOutput.isEmpty ? (summary ?? "") : sanitizedOutput
            let stepStatus: AgentActivityStatus = step.status == .failed ? .failed : statusByCallID[rawCallID] ?? step.status
            let callKey = "\(runID.uuidString):call:\(rawCallID)"

            // Identity and deduplication is strictly by callID, NEVER by toolName::output
            if let existingIdx = entryIndexByCallID[rawCallID] {
                if let summary, !summary.isEmpty {
                    orderedToolEntries[existingIdx].summary = summary
                }
                if !effectiveOutput.isEmpty {
                    orderedToolEntries[existingIdx].output = effectiveOutput
                }
                orderedToolEntries[existingIdx].status = stepStatus
                if let err = step.errorDescription, !err.isEmpty {
                    orderedToolEntries[existingIdx].errorDescription = err
                }
                if let payload = payloadByCallID[rawCallID] {
                    orderedToolEntries[existingIdx].embeddedResultPayload = payload
                }
                seenToolCallKeys.insert(callKey)
                continue
            }

            guard seenToolCallKeys.insert(callKey).inserted else { continue }

            entryIndexByCallID[rawCallID] = orderedToolEntries.count
            orderedToolEntries.append(
                ClassicProjectedToolCallEntry(
                    id: callKey,
                    runID: runID,
                    callID: rawCallID,
                    toolName: canonicalToolName,
                    sequence: step.sequence,
                    startedAt: step.startedAt,
                    status: stepStatus,
                    summary: summary,
                    output: effectiveOutput,
                    errorDescription: step.errorDescription,
                    embeddedResultPayload: payloadByCallID[rawCallID],
                    isMetaSkillOrDiscoveryTool: isMeta
                )
            )
        }
    }

    public static func isToolProjectionStep(_ step: AgentActivityStep) -> Bool {
        switch step.kind {
        case .toolCall, .toolExecution, .codeExecution, .documentRead, .sourceRead, .map, .calendar, .health, .nativeApp: true
        case .reasoning, .progress, .planning, .webSearch, .result, .error, .cancellation: false
        }
    }
}
