//
//  ProviderEventAdapter.swift
//  AI_HLY
//

import Foundation

protocol ProviderEventAdapter {
    mutating func events(from data: StreamData) -> [AgentEvent]
}

struct HanlinStreamEventAdapter: ProviderEventAdapter {
    private let runID: UUID
    private let reasoningID: String
    private let answerID: String
    private var reasoningStarted = false
    private var answerStarted = false
    private var searchSequence = 0
    private var activeSearchID: String?

    init(runID: UUID) {
        self.runID = runID
        reasoningID = "reasoning:\(runID.uuidString)"
        answerID = "answer:\(runID.uuidString)"
    }

    mutating func events(from data: StreamData) -> [AgentEvent] {
        var events = data.agentEvents

        if let reasoning = data.reasoning, !reasoning.isEmpty {
            if !reasoningStarted {
                reasoningStarted = true
                events.append(.reasoningStarted(AgentItemMetadata(id: reasoningID, title: String(localized: "Thinking"), startedAt: Date())))
            }
            events.append(.reasoningDelta(id: reasoningID, text: reasoning))
        }

        if let content = data.content, !content.isEmpty {
            if reasoningStarted {
                events.append(.reasoningCompleted(id: reasoningID))
                reasoningStarted = false
            }
            if !answerStarted {
                answerStarted = true
                events.append(.answerStarted(AgentItemMetadata(id: answerID, title: String(localized: "Done"), startedAt: Date())))
            }
            events.append(.answerDelta(id: answerID, text: content))
        }

        if let state = data.operationalState,
           let sanitized = ProgressSummarySanitizer.sanitize(localizedOperationalState(state)),
           !sanitized.isEmpty {
            events.append(.progressMessage(AgentProgressMessage(id: "status:\(runID.uuidString):\(sanitized)", message: sanitized, source: .applicationGenerated, timestamp: Date())))
        }

        if data.searchEngine != nil || data.search_text != nil || data.resources != nil {
            if activeSearchID == nil {
                searchSequence += 1
                activeSearchID = "search:\(runID.uuidString):\(searchSequence)"
                events.append(.searchStarted(id: activeSearchID!, title: String(localized: "Searching the web"), query: nil))
            }
            let sources = (data.resources ?? []).map {
                AgentActivitySource(title: $0.title, url: $0.link, sourceName: data.searchEngine)
            }
            events.append(.searchCompleted(id: activeSearchID!, sources: sources, output: data.search_text))
            if data.resources != nil { activeSearchID = nil }
        }

        return events
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

    mutating func completionEvents() -> [AgentEvent] {
        var events: [AgentEvent] = []
        if reasoningStarted { events.append(.reasoningCompleted(id: reasoningID)) }
        if answerStarted { events.append(.answerCompleted(id: answerID)) }
        reasoningStarted = false
        answerStarted = false
        return events
    }
}
