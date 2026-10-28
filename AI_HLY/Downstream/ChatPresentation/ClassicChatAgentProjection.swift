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

/// Represents one discrete, chronologically ordered tool invocation and its user-facing output
/// within a single `AgentRun`, preventing output conflation or mislabeling across tools.
struct ClassicProjectedToolCallEntry: Equatable, Sendable, Identifiable {
    let id: String
    let runID: UUID
    let callID: String
    let toolName: String
    var summary: String?
    var output: String
    var isMetaSkillOrDiscoveryTool: Bool

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
        let cleanOutput = Self.sanitizeUserFacingToolOutput(output)
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

    /// Strips any accidental raw `### Instructions` skill body from user-facing tool output.
    static func sanitizeUserFacingToolOutput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let range = trimmed.range(of: "### Instructions") {
            let prefix = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                return prefix
            }
            return "Skill loaded."
        }
        return trimmed
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
            let sanitizedInfo = ClassicProjectedToolCallEntry.sanitizeUserFacingToolOutput(toolInfo)
            if !sanitizedInfo.isEmpty {
                streamChunkSequence += 1
                let effectiveName = incomingToolName.isEmpty
                    ? (assistantMessage.toolName ?? "tool")
                    : incomingToolName
                let dedupSignature = "\(effectiveName)::\(sanitizedInfo)"
                if seenToolContentBlocks.insert(dedupSignature).inserted {
                    let callID = "stream-\(streamChunkSequence)-\(effectiveName)"
                    let entry = ClassicProjectedToolCallEntry(
                        id: "\(runID.uuidString):\(callID)",
                        runID: runID,
                        callID: callID,
                        toolName: effectiveName,
                        summary: nil,
                        output: sanitizedInfo,
                        isMetaSkillOrDiscoveryTool: ClassicProjectedToolCallEntry.isMetaTool(effectiveName)
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
            seenToolContentBlocks: &seenToolContentBlocks
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
        seenToolContentBlocks: inout Set<String>
    ) {
        var entries: [ClassicProjectedToolCallEntry] = []
        syncStructuredToolEntries(
            from: agentRun,
            runID: agentRun.id,
            orderedToolEntries: &entries,
            seenToolContentBlocks: &seenToolContentBlocks
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

    /// Builds deterministic per-call entries from `AgentRun.steps` and `AgentRun.transcriptItems` without conflating tool names.
    static func syncStructuredToolEntries(
        from agentRun: AgentRun,
        runID: UUID,
        orderedToolEntries: inout [ClassicProjectedToolCallEntry],
        seenToolContentBlocks: inout Set<String>
    ) {
        let toolSteps = agentRun.steps.filter { step in
            switch step.kind {
            case .toolCall, .toolExecution, .codeExecution, .documentRead, .sourceRead, .map, .calendar, .health, .nativeApp:
                return true
            case .reasoning, .progress, .planning, .webSearch, .result, .error, .cancellation:
                return false
            }
        }

        // Map callID -> canonical toolName from transcriptItems when available
        var toolNameByCallID: [String: String] = [:]
        for item in agentRun.transcriptItems {
            if let callID = item.callID, let tName = item.toolName, !tName.isEmpty {
                toolNameByCallID[callID] = tName
            }
        }

        for step in toolSteps {
            guard step.status == .completed || step.status == .failed else { continue }
            let rawCallID = (step.externalID ?? step.id.uuidString)
                .replacingOccurrences(of: ":execution", with: "")
                .replacingOccurrences(of: ":call", with: "")
            let stepTitle = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalToolName = toolNameByCallID[rawCallID]
                ?? (stepTitle.isEmpty ? "tool" : stepTitle)

            let rawOutput: String = {
                if let out = step.output?.trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty {
                    return out
                }
                if let err = step.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !err.isEmpty {
                    return "⚠️ \(err)"
                }
                return ""
            }()
            let sanitizedOutput = ClassicProjectedToolCallEntry.sanitizeUserFacingToolOutput(rawOutput)
            let summary = step.userFacingSummary?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !sanitizedOutput.isEmpty || (summary?.isEmpty == false) else { continue }

            let effectiveOutput = sanitizedOutput.isEmpty ? (summary ?? "") : sanitizedOutput
            let dedupSignature = "\(canonicalToolName)::\(effectiveOutput)"
            let callKey = "\(runID.uuidString):step:\(rawCallID)"

            if let existingIdx = orderedToolEntries.firstIndex(where: {
                $0.callID == rawCallID || ($0.toolName == canonicalToolName && $0.output == effectiveOutput)
            }) {
                if orderedToolEntries[existingIdx].summary == nil, let summary, !summary.isEmpty {
                    orderedToolEntries[existingIdx].summary = summary
                }
                seenToolContentBlocks.insert(callKey)
                continue
            }

            guard seenToolContentBlocks.insert(callKey).inserted,
                  seenToolContentBlocks.insert(dedupSignature).inserted else {
                continue
            }

            orderedToolEntries.append(
                ClassicProjectedToolCallEntry(
                    id: callKey,
                    runID: runID,
                    callID: rawCallID,
                    toolName: canonicalToolName,
                    summary: summary,
                    output: effectiveOutput,
                    isMetaSkillOrDiscoveryTool: ClassicProjectedToolCallEntry.isMetaTool(canonicalToolName)
                )
            )
        }
    }

    /// Formats `orderedToolEntries` into `assistantMessage.toolContent` and `assistantMessage.toolName`
    /// so that:
    /// 1. When real domain/MCP tools executed alongside meta skill/discovery tools (`load_skill`, `tool_search`, etc.),
    ///    each entry retains its own explicit `[toolName]` header, and `assistantMessage.toolName` names the primary
    ///    domain tool(s) rather than misattributing `load_skill` output to `manage_mcp_servers`.
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

        let domainEntries = entries.filter { !$0.isMetaSkillOrDiscoveryTool }
        let distinctToolNames = Self.orderedDistinctToolNames(in: entries)
        let includePerCallHeaders = distinctToolNames.count > 1

        // Render each call with its own explicit `[toolName]` header whenever more than one tool ran,
        // so `load_skill` summary and `manage_mcp_servers` output are never conflated under one label.
        let blocks = entries.compactMap { entry -> String? in
            let text = entry.formattedBlock(includeHeader: includePerCallHeaders)
            return text.isEmpty ? nil : text
        }
        assistantMessage.toolContent = blocks.joined(separator: "\n\n")

        // Compute truthful header badge for `ToggleButton(title: "tooluse_content", timeText: toolName)`
        let domainToolNames = Self.orderedDistinctToolNames(in: domainEntries)
        if domainToolNames.count == 1, let singleDomain = domainToolNames.first {
            if distinctToolNames.count > 1 {
                assistantMessage.toolName = "\(singleDomain) (+\(distinctToolNames.count - 1))"
            } else {
                assistantMessage.toolName = singleDomain
            }
        } else if domainToolNames.count > 1, let lastDomain = domainToolNames.last {
            assistantMessage.toolName = "\(lastDomain) (+\(domainToolNames.count - 1))"
        } else if distinctToolNames.count == 1, let onlyTool = distinctToolNames.first {
            assistantMessage.toolName = onlyTool
        } else if let lastTool = distinctToolNames.last {
            assistantMessage.toolName = "\(lastTool) (+\(distinctToolNames.count - 1))"
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
