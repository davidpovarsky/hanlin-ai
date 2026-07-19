import Foundation

enum OperationalEventVisibility: String, Sendable {
    case diagnosticsOnly
    case userFacingActivity
}

struct OperationalEventClassification: Sendable {
    var visibility: OperationalEventVisibility
    var normalizedTitle: String?
    var shouldEndAnswerSegment: Bool
}

enum OperationalEventClassifier {
    private static let transportPhrases = [
        "processing", "sending request", "waiting for model response",
        "request started", "request completed", "request prepared", "request sent",
        "waiting for first token", "parsing response", "stream opened", "stream closed",
        "retrying transport", "internal dispatch", "internal tool lookup",
        "处理对话内容", "正在发送请求", "等待模型响应"
    ]

    static func classify(_ rawState: String) -> OperationalEventClassification {
        let normalized = rawState
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let isKnownTransport = transportPhrases.contains { phrase in
            normalized == phrase || normalized.hasPrefix("\(phrase)…")
        }

        // Operational state strings are transport telemetry. Semantic progress is
        // admitted separately through AgentEvent.progressMessage (report_progress,
        // provider-visible reasoning summaries, and explicit tool progress).
        let classification = OperationalEventClassification(
            visibility: .diagnosticsOnly,
            normalizedTitle: nil,
            shouldEndAnswerSegment: false
        )
        AgentOperationalEventDiagnostics.suppressed(
            knownTransport: isKnownTransport,
            stateLength: rawState.count
        )
        return classification
    }
}

private enum AgentOperationalEventDiagnostics {
    static func suppressed(knownTransport: Bool, stateLength: Int) {
        guard AgentDiagnosticsConfiguration.level != .off else { return }
        NativeToolTraceLogger.shared.log(
            "transportEventSuppressed",
            [
                "knownTransport": knownTransport,
                "stateLength": stateLength
            ]
        )
    }
}
