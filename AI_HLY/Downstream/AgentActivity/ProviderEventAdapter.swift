//
//  ProviderEventAdapter.swift
//  AI_HLY
//

import Foundation

protocol ProviderEventAdapter {
    mutating func events(from data: StreamData) -> [AgentEvent]
}

struct HanlinStreamEventAdapter: ProviderEventAdapter {
    private enum SemanticEventKind {
        case reasoning
        case progress
        case toolActivity
        case search
        case assistantText
    }

    private let runID: UUID
    private var reasoningSegmentSequence = 0
    private var activeReasoningSegmentID: String?
    private var answerSegmentSequence = 0
    private var activeAnswerSegmentID: String?
    private var lastSemanticEventKind: SemanticEventKind?
    private var searchSequence = 0
    private var activeSearchID: String?

    init(runID: UUID) {
        self.runID = runID
    }

    mutating func events(from data: StreamData) -> [AgentEvent] {
        var events: [AgentEvent] = []

        if data.agentEvents.contains(where: isActivityBoundary) {
            endActiveAnswerSegment(as: .interim, into: &events)
            endActiveReasoning(into: &events)
            lastSemanticEventKind = .toolActivity
        }
        events.append(contentsOf: data.agentEvents)

        if let reasoning = data.reasoning, !reasoning.isEmpty {
            endActiveAnswerSegment(as: .interim, into: &events)
            if activeReasoningSegmentID == nil {
                reasoningSegmentSequence += 1
                let id = "reasoning:\(runID.uuidString):\(reasoningSegmentSequence)"
                activeReasoningSegmentID = id
                events.append(.reasoningStarted(AgentItemMetadata(
                    id: id,
                    title: String(localized: "Thinking"),
                    startedAt: Date()
                )))
            }
            if let id = activeReasoningSegmentID {
                events.append(.reasoningDelta(id: id, text: reasoning))
            }
            lastSemanticEventKind = .reasoning
        }

        if let content = data.content, !content.isEmpty {
            endActiveReasoning(into: &events)
            if activeAnswerSegmentID == nil {
                answerSegmentSequence += 1
                let id = "answer:\(runID.uuidString):\(answerSegmentSequence)"
                activeAnswerSegmentID = id
                events.append(.answerSegmentStarted(AgentItemMetadata(
                    id: id,
                    title: String(localized: "Done"),
                    startedAt: Date()
                )))
            }
            if let id = activeAnswerSegmentID {
                events.append(.answerSegmentDelta(id: id, text: content))
            }
            lastSemanticEventKind = .assistantText
        }

        if let state = data.operationalState, !state.isEmpty {
            let classification = OperationalEventClassifier.classify(state)
            if classification.visibility == .userFacingActivity,
               let title = classification.normalizedTitle,
               let sanitized = ProgressSummarySanitizer.sanitize(title) {
                if classification.shouldEndAnswerSegment {
                    endActiveAnswerSegment(as: .interim, into: &events)
                }
                events.append(.progressMessage(AgentProgressMessage(
                    id: "status:\(runID.uuidString):\(sanitized)",
                    message: sanitized,
                    source: .applicationGenerated,
                    timestamp: Date()
                )))
                lastSemanticEventKind = .progress
            }
        }

        if data.searchEngine != nil || data.searchQueries != nil || data.search_text != nil || data.resources != nil {
            endActiveAnswerSegment(as: .interim, into: &events)
            if activeSearchID == nil {
                searchSequence += 1
                let id = "search:\(runID.uuidString):\(searchSequence)"
                activeSearchID = id
                events.append(.searchStarted(
                    id: id,
                    title: String(localized: "Searching the web"),
                    queries: AgentActivityDeduplicator.uniqueStrings(data.searchQueries ?? []),
                    providerName: data.searchEngine
                ))
            } else if let id = activeSearchID, data.searchQueries?.isEmpty == false {
                events.append(.searchStarted(
                    id: id,
                    title: String(localized: "Searching the web"),
                    queries: AgentActivityDeduplicator.uniqueStrings(data.searchQueries ?? []),
                    providerName: data.searchEngine
                ))
            }
            if let id = activeSearchID {
                let sources = (data.resources ?? []).map {
                    AgentActivitySource(
                        title: $0.title,
                        url: $0.link,
                        providerName: data.searchEngine
                    )
                }
                events.append(.searchCompleted(id: id, sources: sources, output: data.search_text))
            }
            if data.resources != nil { activeSearchID = nil }
            lastSemanticEventKind = .search
        }

        return events
    }

    mutating func completionEvents() -> [AgentEvent] {
        var events: [AgentEvent] = []
        endActiveReasoning(into: &events)
        endActiveAnswerSegment(as: .final, into: &events)
        lastSemanticEventKind = nil
        return events
    }

    private func isActivityBoundary(_ event: AgentEvent) -> Bool {
        switch event {
        case .reasoningStarted, .reasoningDelta, .reasoningCompleted,
             .progressMessage, .toolCallStarted, .toolCallArgumentsDelta,
             .toolCallCompleted, .toolExecutionStarted, .toolExecutionProgress,
             .toolExecutionCompleted, .toolExecutionFailed,
             .searchStarted, .searchCompleted:
            return true
        case .runStarted, .answerSegmentStarted, .answerSegmentDelta,
             .answerSegmentEnded, .runCompleted, .runFailed, .runCancelled:
            return false
        }
    }

    private mutating func endActiveReasoning(into events: inout [AgentEvent]) {
        guard let id = activeReasoningSegmentID else { return }
        events.append(.reasoningCompleted(id: id))
        activeReasoningSegmentID = nil
    }

    private mutating func endActiveAnswerSegment(
        as disposition: AgentAnswerDisposition,
        into events: inout [AgentEvent]
    ) {
        guard let id = activeAnswerSegmentID else { return }
        events.append(.answerSegmentEnded(id: id, disposition: disposition))
        activeAnswerSegmentID = nil
    }

}
