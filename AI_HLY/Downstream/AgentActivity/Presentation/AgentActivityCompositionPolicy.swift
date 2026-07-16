import Foundation

enum AgentActivityCompositionPolicy {
    private static let transportPhrases = [
        "processing", "sending request", "waiting for model response", "request started",
        "request completed", "parsing response", "stream opened", "stream closed",
        "retrying transport", "internal dispatch", "internal tool lookup",
        "处理对话内容", "正在发送请求", "等待模型响应"
    ]

    static func isInternalTransport(_ step: AgentActivityStep) -> Bool {
        guard step.kind == .progress else { return false }
        if step.summarySource == .applicationGenerated { return true }
        let values = [step.title, step.userFacingSummary, step.output]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return values.contains { value in
            transportPhrases.contains { value == $0 || value.hasPrefix("\($0)…") }
        }
    }

    static func displayKind(for kind: AgentActivityKind) -> AgentDisplayActivityKind? {
        switch kind {
        case .reasoning: return nil
        case .progress, .planning: return .narrative
        case .toolCall, .toolExecution, .nativeApp: return .tool
        case .webSearch: return .search
        case .sourceRead: return .source
        case .documentRead: return .document
        case .codeExecution: return .code
        case .map: return .map
        case .calendar: return .calendar
        case .health: return .health
        case .result: return .result
        case .error, .cancellation: return .error
        }
    }
}
