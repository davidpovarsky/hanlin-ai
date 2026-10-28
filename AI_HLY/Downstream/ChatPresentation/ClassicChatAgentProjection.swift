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

typealias ClassicToolDisplayItem = ClassicProjectedToolCallEntry

/// Represents one discrete, chronologically ordered tool invocation and its user-facing output
/// within a single `AgentRun`, preventing output conflation or mislabeling across tools.
struct ClassicProjectedToolCallEntry: Equatable, Sendable, Identifiable {
    let id: String
    let runID: UUID
    let callID: String
    let toolName: String
    var sequence: Int = 0
    var startedAt: Date = Date()
    var status: AgentActivityStatus = .completed
    var summary: String?
    var output: String
    var errorDescription: String?
    var embeddedResultPayload: HanlinEmbeddedResultPayload?
    var isMetaSkillOrDiscoveryTool: Bool

    var statusText: String {
        switch status {
        case .running: return String(localized: "Running")
        case .pending: return String(localized: "Pending")
        case .completed: return String(localized: "Completed")
        case .failed: return String(localized: "Failed")
        case .cancelled: return String(localized: "Cancelled")
        }
    }

    static let metaToolNames: Set<String> = [
        "load_skill",
        "read_skill_resource",
        "tool_search",
        "read_tool_result",
        "report_progress"
    ]

    static func isMetaTool(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return metaToolNames.contains(normalized)
    }

    /// Formats a single entry for `ChatBubbleView.toolContentView()`, always keeping its own tool label
    /// when multiple tools execute in the same run.
    func formattedBlock(includeHeader: Bool) -> String {
        let cleanName = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOutput = Self.sanitizeUserFacingToolOutput(output, isMetaSkillOrDiscoveryTool: isMetaSkillOrDiscoveryTool)
        let cleanSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var lines: [String] = []
        if includeHeader, !cleanName.isEmpty {
            lines.append("[\(cleanName)]")
        }
        if !cleanSummary.isEmpty,
           cleanSummary != cleanName,
           cleanSummary != cleanOutput,
           !ProgressSummarySanitizer.looksLikeRawChainOfThought(cleanSummary) {
            lines.append(cleanSummary)
        }
        if !cleanOutput.isEmpty {
            lines.append(cleanOutput)
        }
        return lines.joined(separator: "\n")
    }

    /// Strips any accidental raw `### Instructions` skill body from user-facing tool output for meta skill/discovery tools.
    /// Preserves legitimate user-facing markdown headings for domain tools.
    static func sanitizeUserFacingToolOutput(_ raw: String, isMetaSkillOrDiscoveryTool: Bool = false) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if isMetaSkillOrDiscoveryTool {
            if let range = trimmed.range(of: "### Instructions") {
                let prefix = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                    return prefix
                }
                return "Skill loaded."
            }
        }
        return trimmed
    }

    static func sanitizeUserFacingToolOutput(_ raw: String, toolName: String) -> String {
        sanitizeUserFacingToolOutput(raw, isMetaSkillOrDiscoveryTool: isMetaTool(toolName))
    }
}

@MainActor
struct ClassicChatAgentProjection {
    let runID: UUID
    private var seenToolCallKeys: Set<String> = []
    private var seenToolResultKeys: Set<String> = []
    private var seenToolContentBlocks: Set<String> = []
    private(set) var orderedToolEntries: [ClassicProjectedToolCallEntry] = []
    private var streamChunkSequence: Int = 0

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
                guard seenToolCallKeys.insert(key).inserted else { continue }
                filtered.append(event)
            case .toolExecutionCompleted(let id, _):
                let callID = id.replacingOccurrences(of: ":execution", with: "")
                let key = "\(runID.uuidString):result:\(callID)"
                guard seenToolResultKeys.insert(key).inserted else { continue }
                filtered.append(event)
            case .toolExecutionFailed(let id, _):
                let callID = id.replacingOccurrences(of: ":execution", with: "")
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
        operationalDescription: inout String
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

        // 2. Reasoning summary / delta (filter raw <think> tags)
        if let reasoningDelta = data.reasoning, !reasoningDelta.isEmpty {
            let cleanedDelta = Self.stripRawThinkTags(reasoningDelta)
            if !cleanedDelta.isEmpty, !ProgressSummarySanitizer.looksLikeRawChainOfThought(cleanedDelta) {
                assistantMessage.reasoning = (assistantMessage.reasoning ?? "") + cleanedDelta
                updated = true
            }
        }

        // 3. Per-call Tool output -> tracked deterministically by (runID, callID, toolName)
        let incomingToolName = (data.toolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let toolInfo = data.toolContent, !toolInfo.isEmpty {
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
                    updated = true
                }
            }
        } else if !incomingToolName.isEmpty, orderedToolEntries.isEmpty {
            assistantMessage.toolName = incomingToolName
            updated = true
        }

        // 4. Resources (filter out fabricated https://search.local/... URLs and deduplicate)
        if let incomingResources = data.resources {
            let validIncoming = Self.filterValidResources(incomingResources)
            if !validIncoming.isEmpty {
                let combined = (assistantMessage.resources ?? []) + validIncoming
                assistantMessage.resources = LegacyResourcesEvidenceAdapter.deduplicatedResources(combined)
                updated = true
            }
        }

        // 5. Synchronize AgentRun snapshot onto assistantMessage using per-call attribution
        assistantMessage.agentRun = agentRun
        Self.syncStructuredToolEntries(
            from: agentRun,
            runID: runID,
            orderedToolEntries: &orderedToolEntries,
            seenToolCallKeys: &seenToolCallKeys
        )
        Self.applyFormattedToolProjection(
            entries: orderedToolEntries,
            fallbackToolName: incomingToolName,
            to: assistantMessage
        )
        Self.syncEvidenceResources(from: agentRun, into: assistantMessage)

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
        seenToolCallKeys: inout Set<String>
    ) {
        var entries: [ClassicProjectedToolCallEntry] = []
        syncStructuredToolEntries(
            from: agentRun,
            runID: agentRun.id,
            orderedToolEntries: &entries,
            seenToolCallKeys: &seenToolCallKeys
        )
        if !entries.isEmpty {
            applyFormattedToolProjection(
                entries: entries,
                fallbackToolName: assistantMessage.toolName ?? "",
                to: assistantMessage
            )
        }
        syncEvidenceResources(from: agentRun, into: assistantMessage)
    }

    /// Convenience projection to derive view-oriented structured tool items from an `AgentRun`.
    static func projectToolEntries(from agentRun: AgentRun?) -> [ClassicProjectedToolCallEntry] {
        guard let agentRun else { return [] }
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
    static func syncStructuredToolEntries(
        from agentRun: AgentRun,
        runID: UUID,
        orderedToolEntries: inout [ClassicProjectedToolCallEntry],
        seenToolCallKeys: inout Set<String>
    ) {
        let toolSteps = agentRun.steps.filter { step in
            switch step.kind {
            case .toolCall, .toolExecution, .codeExecution, .documentRead, .sourceRead, .map, .calendar, .health, .nativeApp:
                return true
            case .reasoning, .progress, .planning, .webSearch, .result, .error, .cancellation:
                return false
            }
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
                statusByCallID[callID] = item.status
                if let payload = item.embeddedResultPayload {
                    payloadByCallID[callID] = payload
                }
            }
        }

        for step in toolSteps {
            guard step.status == .completed || step.status == .failed || step.status == .running else { continue }
            let rawCallID = (step.externalID ?? step.id.uuidString)
                .replacingOccurrences(of: ":execution", with: "")
                .replacingOccurrences(of: ":call", with: "")
            let stepTitle = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalToolName = toolNameByCallID[rawCallID]
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

            guard !sanitizedOutput.isEmpty || (summary?.isEmpty == false) || step.status == .running else { continue }

            let effectiveOutput = sanitizedOutput.isEmpty ? (summary ?? "") : sanitizedOutput
            let stepStatus = statusByCallID[rawCallID] ?? step.status
            let callKey = "\(runID.uuidString):call:\(rawCallID)"

            // Identity and deduplication is strictly by callID, NEVER by toolName::output
            if let existingIdx = orderedToolEntries.firstIndex(where: { $0.callID == rawCallID }) {
                if orderedToolEntries[existingIdx].summary == nil, let summary, !summary.isEmpty {
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
        guard !entries.isEmpty else {
            if (assistantMessage.toolName ?? "").isEmpty && !fallbackToolName.isEmpty {
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
        assistantMessage.toolContent = blocks.joined(separator: "\n\n")

        // Compute truthful header badge for `ToggleButton(title: "tooluse_content", timeText: toolName)`
        if entries.count == 1, let onlyTool = distinctToolNames.first {
            assistantMessage.toolName = onlyTool
        } else if entries.count > 1 {
            let format = String(localized: "Tool activity (%lld)")
            assistantMessage.toolName = String(format: format, entries.count)
        } else if !fallbackToolName.isEmpty {
            assistantMessage.toolName = fallbackToolName
        }
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
            assistantMessage.resources = LegacyResourcesEvidenceAdapter.deduplicatedResources(combined)
        }
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
