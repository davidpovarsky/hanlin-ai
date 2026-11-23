import HanlinAgentActivityCore
import HanlinLocalization
//
//  ClassicChatAgentProjection.swift
//  AI_HLY
//
//  Canonical data/transport projection mapping Swift AI SDK / AgentRun / StreamData
//  into original ChatMessages fields for rendering by original ChatBubbleView.
//  NOTE: This file is strictly data/transport projection and is NOT a SwiftUI View.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import HanlinPlatformContracts

typealias ClassicToolDisplayItem = ClassicProjectedToolCallEntry

typealias ClassicProjectedToolCallEntry = HanlinAgentActivityCore.ClassicProjectedToolCallEntry


@MainActor
struct ClassicChatAgentProjection {
    let runID: UUID
    private var seenToolCallStartEvents: Set<String> = []
    private var seenToolCallKeys: Set<String> = []
    private var seenToolResultKeys: Set<String> = []
    private var seenToolContentBlocks: Set<String> = []
    private(set) var orderedToolEntries: [ClassicProjectedToolCallEntry] = []
    private var streamChunkSequence: Int = 0
    private var projectedMessageID: UUID?
    private var projectedToolSteps: [AgentActivityStep] = []
    private var projectedToolTranscript: [AgentTranscriptItem] = []
    private var projectedEvidence: [AgentEvidenceItem] = []
    private var projectedApprovals: [AgentToolApproval] = []
    private var checkpointStatus: AgentActivityStatus?
    private var lastCheckpointAt: Date?

    init(runID: UUID) {
        self.runID = runID
    }

    /// Deduplicates `AgentEvent` items by `runID + callID` before feeding `AgentRunCoordinator`.
    mutating func deduplicateEvents(_ events: [AgentEvent]) -> [AgentEvent] {
        var filtered: [AgentEvent] = []
        filtered.reserveCapacity(events.count)

        for event in events {
            switch event {
            case .toolCallStarted(let call):
                let key = "\(runID.uuidString):call:\(call.id)"
                guard seenToolCallStartEvents.insert(key).inserted else { continue }
                filtered.append(event)
            case .toolExecutionCompleted(let id, _):
                let callID = id.hasSuffix(":execution") ? String(id.dropLast(":execution".count)) : id
                let key = "\(runID.uuidString):result:\(callID)"
                guard seenToolResultKeys.insert(key).inserted else { continue }
                filtered.append(event)
            case .toolExecutionFailed(let id, _):
                let callID = id.hasSuffix(":execution") ? String(id.dropLast(":execution".count)) : id
                let key = "\(runID.uuidString):result:\(callID)"
                guard seenToolResultKeys.insert(key).inserted else { continue }
                filtered.append(event)
            default:
                filtered.append(event)
            }
        }
        return filtered
    }

    /// Projects a streaming `StreamData` chunk and current `AgentRun` into original `ChatMessages` fields.
    mutating func applyStreamChunk(
        _ data: StreamData,
        agentRun: AgentRun,
        to assistantMessage: ChatMessages,
        operationalState: inout String,
        operationalDescription: inout String,
        checkpointDate: Date = .now
    ) -> Bool {
        var updated = false

        // 1. Operational status (sanitized so raw CoT and raw SKILL.md instructions never leak into loadingSection)
        if let state = data.operationalState {
            operationalState = state
        }
        if let desc = data.operationalDescription {
            let cleanDesc = ClassicProjectedToolCallEntry.sanitizeUserFacingToolOutput(desc)
            if ProgressSummarySanitizer.looksLikeRawChainOfThought(cleanDesc) {
                operationalDescription = ""
            } else {
                operationalDescription = cleanDesc
            }
        }

        // 2. The original ChatView stream owner appends the reasoning delta to
        // its group message. Appending here as well duplicates the same chunk.

        // 3. Per-call Tool output -> tracked deterministically by (runID, callID, toolName)
        let incomingToolName = (data.toolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let alreadyAttributed = !incomingToolName.isEmpty && agentRun.transcriptItems.contains {
            $0.kind == .toolActivity && $0.toolName == incomingToolName
        }
        var legacyToolOutputChanged = false
        if let toolInfo = data.toolContent, !toolInfo.isEmpty, !alreadyAttributed {
            let isMeta = ClassicProjectedToolCallEntry.isMetaTool(incomingToolName)
            let sanitizedInfo = ClassicProjectedToolCallEntry.sanitizeUserFacingToolOutput(toolInfo, isMetaSkillOrDiscoveryTool: isMeta)
            if !sanitizedInfo.isEmpty {
                streamChunkSequence += 1
                let effectiveName = incomingToolName.isEmpty
                    ? (assistantMessage.toolName ?? "tool")
                    : incomingToolName
                let callID = "stream-\(streamChunkSequence)-\(effectiveName)"
                let callKey = "\(runID.uuidString):call:\(callID)"
                if seenToolCallKeys.insert(callKey).inserted {
                    let entry = ClassicProjectedToolCallEntry(
                        id: callKey,
                        runID: runID,
                        callID: callID,
                        toolName: effectiveName,
                        sequence: streamChunkSequence,
                        startedAt: Date(),
                        status: .completed,
                        summary: nil,
                        output: sanitizedInfo,
                        errorDescription: nil,
                        embeddedResultPayload: nil,
                        isMetaSkillOrDiscoveryTool: isMeta
                    )
                    orderedToolEntries.append(entry)
                    legacyToolOutputChanged = true
                    updated = true
                }
            }
        } else if !incomingToolName.isEmpty, orderedToolEntries.isEmpty, assistantMessage.toolName != incomingToolName {
            assistantMessage.toolName = incomingToolName
            updated = true
        }

        // 4. Resources (filter out fabricated https://search.local/... URLs and deduplicate)
        if let incomingResources = data.resources {
            let validIncoming = Self.filterValidResources(incomingResources)
            if !validIncoming.isEmpty {
                let combined = (assistantMessage.resources ?? []) + validIncoming
                updated = Self.assignResourcesIfChanged(
                    LegacyResourcesEvidenceAdapter.deduplicatedResources(combined), to: assistantMessage) || updated
            }
        }

        // 5. Text-only deltas do not change tool output or evidence. Keep these
        // projections separate from the live transcript so an answer token never
        // reformats every previous tool result or serializes the whole run.
        let messageChanged = projectedMessageID != assistantMessage.id
        let toolSteps = agentRun.steps.filter(Self.isToolProjectionStep)
        let toolTranscript = agentRun.transcriptItems.filter { $0.callID != nil }
        let toolsChanged = messageChanged || projectedToolSteps != toolSteps
            || projectedToolTranscript != toolTranscript
        let evidenceChanged = messageChanged || projectedEvidence != agentRun.evidenceItems
        let approvalsChanged = messageChanged || projectedApprovals != agentRun.approvals
        if toolsChanged {
            Self.syncStructuredToolEntries(from: agentRun, runID: runID,
                orderedToolEntries: &orderedToolEntries, seenToolCallKeys: &seenToolCallKeys)
            projectedToolSteps = toolSteps
            projectedToolTranscript = toolTranscript
        }
        if toolsChanged || legacyToolOutputChanged {
            Self.applyFormattedToolProjection(entries: orderedToolEntries,
                fallbackToolName: incomingToolName, to: assistantMessage)
            updated = true
        }
        if evidenceChanged {
            Self.syncEvidenceResources(from: agentRun, into: assistantMessage)
            projectedEvidence = agentRun.evidenceItems
        }
        let controlEvent = data.agentEvents.contains { event in
            switch event {
            case .reasoningDelta, .answerSegmentDelta, .toolCallArgumentsDelta: false
            default: true
            }
        }
        if messageChanged || toolsChanged || evidenceChanged || approvalsChanged || controlEvent
            || checkpointStatus != agentRun.status
            || lastCheckpointAt.map({ checkpointDate.timeIntervalSince($0) >= 0.5 }) != false {
            // The live UI uses the in-memory run. This bounded checkpoint is
            // persistence only; every control/final event is stored immediately.
            assistantMessage.agentRun = agentRun
            lastCheckpointAt = checkpointDate
            checkpointStatus = agentRun.status
        }
        projectedMessageID = assistantMessage.id
        projectedApprovals = agentRun.approvals

        return updated
    }

    /// Appends a provider-native `.source` event onto `assistantMessage.resources` and the group's `"search"` message if valid HTTP(S).
    static func appendProviderSource(
        id: String,
        url: String,
        title: String?,
        assistantMessage: ChatMessages,
        messages: inout [ChatMessages],
        messageGroupID: UUID,
        searchEngine: String = "Web",
        timestamp: Date = Date()
    ) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host()?.lowercased() != "search.local" else {
            return
        }
        let resource = Resource(icon: trimmed, title: title ?? trimmed, link: trimmed)
        let combined = (assistantMessage.resources ?? []) + [resource]
        assistantMessage.resources = LegacyResourcesEvidenceAdapter.deduplicatedResources(combined)

        if let searchIdx = messages.firstIndex(where: { $0.groupID == messageGroupID && $0.role == "search" }) {
            let searchCombined = (messages[searchIdx].resources ?? []) + [resource]
            messages[searchIdx].resources = LegacyResourcesEvidenceAdapter.deduplicatedResources(searchCombined)
        } else {
            let searchMsg = ChatMessages(
                role: "search",
                text: title ?? trimmed,
                resources: [resource],
                searchEngine: searchEngine,
                groupID: messageGroupID,
                timestamp: timestamp
            )
            messages.insert(searchMsg, at: 0)
        }
    }

    /// Appends a provider-native `.file` event onto `assistantMessage.imageArray` when the mediaType is an image.
    static func appendProviderFile(
        mediaType: String,
        data: Data,
        assistantMessage: ChatMessages
    ) {
        #if canImport(UIKit)
        if mediaType.lowercased().hasPrefix("image/"), let image = UIImage(data: data) {
            var current = assistantMessage.imageArray
            current.append(image)
            assistantMessage.imageArray = current
        }
        #endif
    }

    /// Synchronizes completed or in-progress `AgentRun` state into original `ChatMessages` fields.
    static func syncAgentRunProjection(
        _ agentRun: AgentRun,
        into assistantMessage: ChatMessages,
        seenToolContentBlocks: inout Set<String>
    ) {
        syncAgentRunProjection(
            agentRun,
            into: assistantMessage,
            seenToolCallKeys: &seenToolContentBlocks
        )
    }

    /// Synchronizes completed or in-progress `AgentRun` state into original `ChatMessages` fields.
    static func syncAgentRunProjection(
        _ agentRun: AgentRun,
        into assistantMessage: ChatMessages,
        seenToolCallKeys: inout Set<String>
    ) {
        var entries: [ClassicProjectedToolCallEntry] = []
        // End-of-stream/restore always persists the exact canonical snapshot,
        // including the tail since the last periodic streaming checkpoint.
        assistantMessage.agentRun = agentRun
        AgentDiagnosticsRecorder.trace(runID: agentRun.id, stage: "ClassicChatAgentProjection.snapshot",
            text: agentRun.transcriptItems.compactMap(\.text).joined(separator: "\n"),
            fields: ["messageID": String(describing: assistantMessage.id)])
        // A snapshot rebuild must include previously seen calls so status/output
        // changes replace their old rendering. Event dedup has a separate lifetime.
        var snapshotKeys = Set<String>()
        syncStructuredToolEntries(
            from: agentRun,
            runID: agentRun.id,
            orderedToolEntries: &entries,
            seenToolCallKeys: &snapshotKeys
        )
        seenToolCallKeys.formUnion(snapshotKeys)
        if !entries.isEmpty {
            applyFormattedToolProjection(
                entries: entries,
                fallbackToolName: assistantMessage.toolName ?? "",
                to: assistantMessage
            )
        }
        syncEvidenceResources(from: agentRun, into: assistantMessage)
    }

    /// Sanitizes tool output for user-facing display. Only strips `### Instructions` for meta skill/discovery tools.
    static func sanitizeUserFacingToolOutput(_ raw: String, isMetaSkillOrDiscoveryTool: Bool = false) -> String {
        ClassicProjectedToolCallEntry.sanitizeUserFacingToolOutput(raw, isMetaSkillOrDiscoveryTool: isMetaSkillOrDiscoveryTool)
    }

    /// Convenience projection to derive view-oriented structured tool items from an `AgentRun`.
    static func projectToolEntries(from agentRun: AgentRun?, callID: String? = nil) -> [ClassicProjectedToolCallEntry] {
        AgentActivityToolProjection.projectToolEntries(from: agentRun, callID: callID)
    }

    /// Builds deterministic per-call entries from `AgentRun.steps` and `AgentRun.transcriptItems`.
    /// Preserves independent tool calls with identical toolName and output by keying strictly on runID + callID.
    static func syncStructuredToolEntries(
        from agentRun: AgentRun,
        runID: UUID,
        orderedToolEntries: inout [ClassicProjectedToolCallEntry],
        seenToolCallKeys: inout Set<String>
    ) {
        AgentActivityToolProjection.syncStructuredToolEntries(from: agentRun, runID: runID,
            orderedToolEntries: &orderedToolEntries, seenToolCallKeys: &seenToolCallKeys)
    }

    /// Formats `orderedToolEntries` into `assistantMessage.toolContent` and `assistantMessage.toolName`
    /// so that:
    /// 1. When real domain/MCP tools executed alongside meta skill/discovery tools (`load_skill`, `tool_search`, etc.),
    ///    each entry retains its own explicit `[toolName]` header, and `assistantMessage.toolName` reflects truthful
    ///    activity rather than misattributing `load_skill` output to `manage_mcp_servers`.
    /// 2. Full `### Instructions` markdown never appears in `assistantMessage.toolContent`.
    static func applyFormattedToolProjection(
        entries: [ClassicProjectedToolCallEntry],
        fallbackToolName: String,
        to assistantMessage: ChatMessages
    ) {
        let hadEntries = !entries.isEmpty
        let entries = entries.filter { !$0.isMetaSkillOrDiscoveryTool }
        guard !entries.isEmpty else {
            if hadEntries {
                assistantMessage.toolContent = ""
                assistantMessage.toolName = ""
            } else if (assistantMessage.toolName ?? "").isEmpty && !fallbackToolName.isEmpty
                && !ClassicProjectedToolCallEntry.isMetaTool(fallbackToolName) {
                assistantMessage.toolName = fallbackToolName
            }
            return
        }

        let distinctToolNames = Self.orderedDistinctToolNames(in: entries)
        let includePerCallHeaders = distinctToolNames.count > 1 || entries.count > 1

        let blocks = entries.compactMap { entry -> String? in
            let text = entry.formattedBlock(includeHeader: includePerCallHeaders)
            return text.isEmpty ? nil : text
        }
        let formattedContent = blocks.joined(separator: "\n\n")
        if assistantMessage.toolContent != formattedContent { assistantMessage.toolContent = formattedContent }

        // Compute truthful header badge for `ToggleButton(title: "tooluse_content", timeText: toolName)`
        let name: String
        if entries.count == 1, let onlyTool = distinctToolNames.first {
            name = onlyTool
        } else if entries.count > 1 {
            let format = String(localized: "Tool activity (%lld)", bundle: HanlinLocalization.bundle)
            name = String(format: format, entries.count)
        } else {
            name = fallbackToolName
        }
        if !name.isEmpty, assistantMessage.toolName != name { assistantMessage.toolName = name }
    }

    private static func orderedDistinctToolNames(in entries: [ClassicProjectedToolCallEntry]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in entries {
            let name = entry.toolName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            result.append(name)
        }
        return result
    }

    static func syncEvidenceResources(
        from agentRun: AgentRun,
        into assistantMessage: ChatMessages
    ) {
        let evidenceResources: [Resource] = agentRun.evidenceItems.compactMap { item in
            guard let urlString = item.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !urlString.isEmpty,
                  let url = URL(string: urlString),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host()?.lowercased() != "search.local" else {
                return nil
            }
            return Resource(icon: urlString, title: item.title, link: urlString)
        }
        if !evidenceResources.isEmpty {
            let combined = (assistantMessage.resources ?? []) + evidenceResources
            _ = assignResourcesIfChanged(LegacyResourcesEvidenceAdapter.deduplicatedResources(combined), to: assistantMessage)
        }
    }

    private static func assignResourcesIfChanged(_ resources: [Resource], to message: ChatMessages) -> Bool {
        let existing = message.resources ?? []
        guard !existing.elementsEqual(resources, by: {
            $0.icon == $1.icon && $0.title == $1.title && $0.link == $1.link
        }) else { return false }
        message.resources = resources
        return true
    }

    static func filterValidResources(_ resources: [Resource]) -> [Resource] {
        resources.filter { res in
            let trimmed = res.link.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host()?.lowercased() != "search.local" else {
                return false
            }
            return true
        }
    }

    static func stripRawThinkTags(_ value: String) -> String {
        value.replacingOccurrences(
            of: "(?i)<\\/?(think|reasoning|thought)[^>]*>",
            with: "",
            options: .regularExpression
        )
    }
}
