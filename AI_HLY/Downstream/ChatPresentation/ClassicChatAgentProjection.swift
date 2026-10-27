//
//  ClassicChatAgentProjection.swift
//  AI_HLY
//
//  Canonical data/transport projection mapping Swift AI SDK / AgentRun / StreamData
//  into original ChatMessages fields for rendering by original ChatBubbleView.
//  NOTE: This file is strictly data/transport projection and is NOT a SwiftUI View.
//

import Foundation

@MainActor
struct ClassicChatAgentProjection {
    let runID: UUID
    private var seenToolCallKeys: Set<String> = []
    private var seenToolResultKeys: Set<String> = []
    private var seenToolContentBlocks: Set<String> = []

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

        // 1. Operational status (sanitized so raw CoT never leaks into loadingSection)
        if let state = data.operationalState {
            operationalState = state
        }
        if let desc = data.operationalDescription {
            if ProgressSummarySanitizer.looksLikeRawChainOfThought(desc) {
                operationalDescription = ""
            } else {
                operationalDescription = desc
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

        // 3. Tool call / output -> original ChatMessages.toolContent & toolName
        if let toolInfo = data.toolContent, !toolInfo.isEmpty {
            let normalizedBlock = toolInfo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedBlock.isEmpty, seenToolContentBlocks.insert(normalizedBlock).inserted {
                let current = assistantMessage.toolContent ?? ""
                if current.isEmpty {
                    assistantMessage.toolContent = toolInfo
                } else if !current.contains(normalizedBlock) {
                    assistantMessage.toolContent = current + "\n" + toolInfo
                }
                updated = true
            }
        }
        if let toolName = data.toolName, !toolName.isEmpty {
            assistantMessage.toolName = toolName
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

        // 5. Synchronize AgentRun snapshot onto assistantMessage
        assistantMessage.agentRun = agentRun
        Self.syncAgentRunProjection(agentRun, into: assistantMessage, seenToolContentBlocks: &seenToolContentBlocks)

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
        // Project tool steps into toolContent / toolName when not already populated
        let toolSteps = agentRun.steps.filter { step in
            switch step.kind {
            case .toolCall, .toolExecution, .codeExecution, .documentRead, .sourceRead, .map, .calendar, .health, .nativeApp:
                return true
            case .reasoning, .progress, .planning, .webSearch, .result, .error, .cancellation:
                return false
            }
        }

        if assistantMessage.toolName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let lastToolStep = toolSteps.last {
            assistantMessage.toolName = lastToolStep.title
        }

        var synthesizedLines: [String] = []
        for step in toolSteps {
            let stepKey = step.externalID ?? step.id.uuidString
            guard !seenToolContentBlocks.contains(stepKey) else { continue }
            var parts: [String] = []
            let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                parts.append("[\(title)]")
            }
            if let summary = step.userFacingSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty,
               summary != title,
               !ProgressSummarySanitizer.looksLikeRawChainOfThought(summary) {
                parts.append(summary)
            }
            if let output = step.output?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                parts.append(output)
            } else if let error = step.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !error.isEmpty {
                parts.append("⚠️ \(error)")
            }
            if !parts.isEmpty, (step.status == .completed || step.status == .failed) {
                seenToolContentBlocks.insert(stepKey)
                synthesizedLines.append(parts.joined(separator: "\n"))
            }
        }

        if !synthesizedLines.isEmpty {
            let current = assistantMessage.toolContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let addition = synthesizedLines.joined(separator: "\n\n")
            if current.isEmpty {
                assistantMessage.toolContent = addition
            } else if !current.contains(addition) {
                assistantMessage.toolContent = current + "\n\n" + addition
            }
        }

        // Project valid HTTP(S) evidence items into ChatMessages.resources
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
