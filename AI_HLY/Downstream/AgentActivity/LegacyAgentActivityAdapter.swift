//
//  LegacyAgentActivityAdapter.swift
//  AI_HLY
//

import Foundation

enum LegacyAgentActivityAdapter {
    @MainActor
    static func run(for messages: [ChatMessages]) -> AgentRun? {
        let sortedMessages = messages.sorted { $0.timestamp < $1.timestamp }
        let assistantMessages = sortedMessages
            .filter { $0.role == "assistant" }
        guard let first = assistantMessages.first else { return nil }

        var run = AgentRun(
            schemaVersion: 1,
            groupID: first.groupID,
            providerID: nil,
            modelID: first.modelName,
            startedAt: first.timestamp,
            completedAt: assistantMessages.last?.timestamp,
            status: .completed,
            finalAnswer: assistantMessages.compactMap(\.text).joined()
        )
        var sequence = 0

        func appendStep(_ step: AgentActivityStep) {
            guard !run.steps.contains(where: {
                $0.kind == step.kind && $0.title == step.title && $0.output == step.output
            }) else { return }
            run.steps.append(step)
            sequence += 1
        }

        if let reasoning = assistantMessages.compactMap(\.reasoning).first(where: { !$0.isEmpty }) {
            appendStep(AgentActivityStep(sequence: sequence, kind: .reasoning, title: String(localized: "Thinking"), status: .completed, startedAt: first.timestamp, completedAt: first.timestamp, output: reasoning))
        }

        for searchMessage in sortedMessages where searchMessage.role == "search" {
            let output = searchMessage.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard output?.isEmpty == false else { continue }
            appendStep(AgentActivityStep(
                externalID: "legacy-search:\(searchMessage.id.uuidString)",
                sequence: sequence,
                kind: .webSearch,
                title: String(localized: "Searching the web"),
                subtitle: searchMessage.searchEngine,
                status: .completed,
                startedAt: searchMessage.timestamp,
                completedAt: searchMessage.timestamp,
                output: output
            ))
        }

        for message in assistantMessages {
            if let toolContent = message.toolContent, !toolContent.isEmpty {
                let name = message.toolName ?? ""
                let presentation = ToolPresentationRegistry.presentation(for: name)
                appendStep(AgentActivityStep(
                    externalID: "legacy-tool:\(message.id.uuidString)",
                    sequence: sequence,
                    kind: presentation.activityKind,
                    title: presentation.title,
                    subtitle: name.isEmpty ? nil : name,
                    userFacingSummary: presentation.completedDescription,
                    summarySource: .applicationGenerated,
                    status: .completed,
                    startedAt: message.timestamp,
                    completedAt: message.timestamp,
                    output: toolContent,
                    richResultBlocks: message.nativeUIBlocks
                ))
            } else if !message.nativeUIBlocks.isEmpty {
                appendStep(AgentActivityStep(sequence: sequence, kind: .result, title: String(localized: "Done"), status: .completed, startedAt: message.timestamp, completedAt: message.timestamp, richResultBlocks: message.nativeUIBlocks))
            }

            if let resources = message.resources, !resources.isEmpty {
                appendStep(AgentActivityStep(
                    sequence: sequence,
                    kind: .sourceRead,
                    title: String(localized: "Reading a source"),
                    status: .completed,
                    startedAt: message.timestamp,
                    completedAt: message.timestamp,
                    sourceItems: resources.map { AgentActivitySource(title: $0.title, url: $0.link, sourceName: message.searchEngine) }
                ))
            }

            if let code = message.codeBlockData, !code.isEmpty {
                appendStep(AgentActivityStep(sequence: sequence, kind: .codeExecution, title: String(localized: "Running code"), status: .completed, startedAt: message.timestamp, completedAt: message.timestamp, input: code.map(\.code).joined(separator: "\n\n"), output: code.map(\.output).joined(separator: "\n\n")))
            }

            if let document = message.document_text, !document.isEmpty {
                appendStep(AgentActivityStep(sequence: sequence, kind: .documentRead, title: String(localized: "Reading a document"), status: .completed, startedAt: message.timestamp, completedAt: message.timestamp, output: document))
            }

            if message.locationsInfo?.isEmpty == false || message.routeInfos?.isEmpty == false {
                appendStep(AgentActivityStep(sequence: sequence, kind: .map, title: String(localized: "Searching locations"), status: .completed, startedAt: message.timestamp, completedAt: message.timestamp))
            }

            if message.events?.isEmpty == false {
                appendStep(AgentActivityStep(sequence: sequence, kind: .calendar, title: String(localized: "Checking the calendar"), status: .completed, startedAt: message.timestamp, completedAt: message.timestamp))
            }

            if message.healthData?.isEmpty == false {
                appendStep(AgentActivityStep(sequence: sequence, kind: .health, title: String(localized: "Using a tool"), status: .completed, startedAt: message.timestamp, completedAt: message.timestamp))
            }

            if message.knowledgeCard?.isEmpty == false || message.htmlContent?.isEmpty == false || message.showCanvas == true {
                appendStep(AgentActivityStep(sequence: sequence, kind: .result, title: String(localized: "Done"), status: .completed, startedAt: message.timestamp, completedAt: message.timestamp))
            }
        }

        return run.steps.isEmpty ? nil : run
    }
}
