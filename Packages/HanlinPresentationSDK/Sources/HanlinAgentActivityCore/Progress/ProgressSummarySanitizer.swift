import Foundation


public enum ProgressSummarySanitizer {
    private static let maximumLength = 280

    public static func sanitize(_ value: String?) -> String? {
        guard var value else { return nil }
        guard !looksLikeRawChainOfThought(value) else { return nil }
        let newlineCount = value.filter { $0 == "\n" }.count
        guard newlineCount <= 2 else { return nil }
        value = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maximumLength else { return nil }
        guard !looksLikeRawJSON(value), !containsSensitiveMaterial(value), !looksLikeRawChainOfThought(value) else {
            return nil
        }

        value = value
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public static func sanitizeProviderReasoningSummary(_ value: String?) -> String? {
        guard let raw = value, !looksLikeRawChainOfThought(raw) else { return nil }
        let newlineCount = raw.filter { $0 == "\n" }.count
        guard newlineCount <= 1 else { return nil }
        guard let sanitized = sanitize(raw), sanitized.count <= 140 else { return nil }
        guard !looksLikeRawChainOfThought(sanitized) else { return nil }
        let sentenceSeparators = sanitized.filter { ".!?。！？".contains($0) }
        guard sentenceSeparators.count <= 2 else { return nil }
        return sanitized
    }

    public static func looksLikeRawChainOfThought(_ value: String) -> Bool {
        let patterns = [
            "(?i)<\\/?(think|reasoning|thought)[^>]*>",
            "(?i)(^|\\n)\\s*(#+)\\s*(thinking|thought|reasoning|analysis|plan)\\b",
            "(?i)\\*\\*\\s*(thinking|thought\\s*process|internal\\s*reasoning|chain\\s*of\\s*thought|reasoning)\\s*\\*\\*",
            "(?i)^\\s*(thinking\\s*process|thought\\s*process|internal\\s*reasoning|chain\\s*of\\s*thought|reasoning\\s*process|internal\\s*monologue)\\s*:?",
            "(?i)(understand\\s+the\\s+user'?s\\s+request|analyze\\s+the\\s+user'?s\\s+request|let'?s\\s+think\\s+step\\s+by\\s+step)",
            "(?i)\\b(let\\s+me\\s+think|first,\\s+let'?s|i\\s+need\\s+to\\s+(check|think|analyze|figure|look|understand|verify)|i\\s+should\\s+(check|think|analyze|first)|the\\s+user\\s+(wants|is\\s+asking)\\s+me\\s+to|my\\s+plan\\s+is\\s+to)\\b",
            "(?i)(^|\\n)\\s*(step\\s*\\d+\\s*:|\\d+[\\.)]\\s*(understand|analyze|identify|determine|formulate|draft|check|verify|inspect)\\b)",
            "(思考过程|内部推理|思维链|分析用户请求|首先我需要|让我先思考|תהליך חשיבה|נימוק פנימי|שרשרת חשיבה)"
        ]
        return patterns.contains { value.range(of: $0, options: .regularExpression) != nil }
    }

    private static func looksLikeRawJSON(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }

    private static func containsSensitiveMaterial(_ value: String) -> Bool {
        let patterns = [
            "(?i)api[_-]?key",
            "(?i)(authorization|bearer|password|credential|secret|system prompt|internal policy)",
            "(?i)sk-[a-z0-9_-]{12,}",
            "https?://"
        ]
        return patterns.contains { value.range(of: $0, options: .regularExpression) != nil }
    }
}
