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
            if isInternalTransportState(state) {
                AgentOperationalStateDiagnostics.transportStateObserved(state)
            } else if let sanitized = ProgressSummarySanitizer.sanitize(localizedOperationalState(state)),
                      !sanitized.isEmpty {
                endActiveAnswerSegment(as: .interim, into: &events)
                events.append(.progressMessage(AgentProgressMessage(
                    id: "status:\(runID.uuidString):\(sanitized)",
                    message: sanitized,
                    source: .applicationGenerated,
                    timestamp: Date()
                )))
                lastSemanticEventKind = .progress
            }
        }

        if data.searchEngine != nil || data.search_text != nil || data.resources != nil {
            endActiveAnswerSegment(as: .interim, into: &events)
            if activeSearchID == nil {
                searchSequence += 1
                let id = "search:\(runID.uuidString):\(searchSequence)"
                activeSearchID = id
                events.append(.searchStarted(
                    id: id,
                    title: String(localized: "Searching the web"),
                    query: nil
                ))
            }
            if let id = activeSearchID {
                let sources = (data.resources ?? []).map {
                    AgentActivitySource(title: $0.title, url: $0.link, sourceName: data.searchEngine)
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

    private func localizedOperationalState(_ state: String) -> String {
        let normalized = state.lowercased()
        if normalized.contains("tool") || state.contains("工具") {
            return String(localized: "Using a tool")
        }
        if normalized.contains("webpage") || normalized.contains("reading web") || state.contains("读取网页") || state.contains("阅读网页") {
            return String(localized: "Reading a source")
        }
        if normalized.contains("document") || state.contains("文件") {
            return String(localized: "Reading a document")
        }
        if normalized.contains("code") || state.contains("代码") {
            return String(localized: "Running code")
        }
        if normalized.contains("calendar") || normalized.contains("event") || state.contains("日程") || state.contains("事件") {
            return String(localized: "Checking the calendar")
        }
        if normalized.contains("location") || normalized.contains("route") || normalized.contains("weather") || state.contains("位置") || state.contains("路线") || state.contains("天气") {
            return String(localized: "Searching locations")
        }
        if normalized.contains("search") || state.contains("搜索") || state.contains("翻找") || state.contains("检索") {
            return String(localized: "Searching the web")
        }
        return state
    }

    private func isInternalTransportState(_ state: String) -> Bool {
        let normalized = state
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let transportStates = [
            "processing", "processing dialogue content", "sending request",
            "waiting for model response", "request prepared", "request sent",
            "request started", "request completed", "parsing response",
            "stream opened", "stream closed", "retrying transport",
            "internal dispatch", "处理对话内容", "正在发送请求", "等待模型响应"
        ]
        return transportStates.contains {
            normalized == $0 || normalized.hasPrefix("\($0)…") || normalized.hasPrefix("\($0)...")
        }
    }
}

private enum AgentOperationalStateDiagnostics {
    static func transportStateObserved(_ state: String) {
        guard AgentDiagnosticsConfiguration.level != .off else { return }
        NativeToolTraceLogger.shared.log(
            "agent_transport_state_observed",
            ["state": state]
        )
    }
}
