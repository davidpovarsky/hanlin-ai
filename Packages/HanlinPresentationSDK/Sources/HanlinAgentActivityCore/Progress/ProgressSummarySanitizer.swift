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

    /// This is the provider's public reasoning-text channel, not a short title.
    /// Preserve already-visible text as it grows. Explicit private blocks stay
    /// private; credentials are redacted in place instead of erasing the passage.
    public static func sanitizeProviderReasoningDisplay(_ value: String?) -> String? {
        guard let value else { return nil }
        var visible = removingPrivateBlocks(value)
        let privateSectionPatterns = [
            #"(?im)^\s*(?:#{1,6}\s+|\*\*\s*)(?:thinking|thought(?:\s*process)?|reasoning|analysis|plan|internal\s+reasoning|chain\s+of\s+thought)\b.*$"#,
            #"(?im)^\s*(?:thinking\s+process|thought\s+process|internal\s+reasoning|chain\s+of\s+thought|reasoning\s+process|internal\s+monologue|system\s+prompt|internal\s+policy|תהליך חשיבה|נימוק פנימי|שרשרת חשיבה)\s*:"#
        ]
        // A private section has no explicit closing delimiter. Keep preceding
        // public paragraphs, and never guess where that private section ends.
        for pattern in privateSectionPatterns {
            if let range = visible.range(of: pattern, options: .regularExpression) {
                visible = String(visible[..<range.lowerBound])
            }
        }
        visible = visible.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visible.isEmpty, !visible.hasPrefix("{"), !visible.hasPrefix("["),
              !visible.hasPrefix("data:") else { return nil }
        let redacted = AgentDiagnosticsRedactor.sanitize(visible)
        return redacted.isEmpty ? nil : redacted
    }

    private static func removingPrivateBlocks(_ value: String) -> String {
        let pattern = #"(?i)<\/?(?:think|reasoning|thought)[^>]*>"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return "" }
        var visible = ""
        var depth = 0
        var cursor = value.startIndex
        for match in expression.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let range = Range(match.range, in: value) else { continue }
            if depth == 0 { visible += value[cursor..<range.lowerBound] }
            if value[range].hasPrefix("</") { depth = max(0, depth - 1) }
            else { depth += 1 }
            cursor = range.upperBound
        }
        if depth == 0 { visible += value[cursor...] }
        // A streaming tag can arrive split across chunks. Do not briefly show
        // its prefix or expose its following text before the closing '>'.
        if let opening = visible.lastIndex(of: "<") {
            let tail = visible[opening...].lowercased()
            let markers = ["<think", "<reasoning", "<thought", "</think", "</reasoning", "</thought"]
            if !tail.contains(">"), markers.contains(where: { $0.hasPrefix(tail) || tail.hasPrefix($0) }) {
                visible = String(visible[..<opening])
            }
        }
        return visible
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
