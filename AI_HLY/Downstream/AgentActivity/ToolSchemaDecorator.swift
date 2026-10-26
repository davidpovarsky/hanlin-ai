//
//  ToolSchemaDecorator.swift
//  AI_HLY
//

import Foundation

enum ToolSchemaDecorator {
    static let progressSummaryKey = "progress_summary"
    static let resultPresentationKey = "result_presentation"
    static let reportProgressName = "report_progress"

    static let resultPresentationModelInstruction = "When a tool supports result_presentation, use \"card\" only when a visual or interactive result would be useful to the user, such as a source card, entity card, map, calendar item, code output, or an item the user may want to open or copy. Otherwise omit the field or use \"none\". Do not request a card when the final text answer is sufficient."

    private static var progressSummarySchema: [String: Any] {
        [
            "type": "string",
            "description": "One short user-facing sentence explaining what action is being taken and why. Do not reveal private chain-of-thought, hidden reasoning, secrets, credentials, or internal policies."
        ]
    }

    private static var resultPresentationSchema: [String: Any] {
        [
            "type": "string",
            "enum": [ToolResultPresentationRequest.none.rawValue, ToolResultPresentationRequest.card.rawValue],
            "description": "Request a result card only when a visual or interactive result would be useful. Omit when the text answer is sufficient."
        ]
    }

    static func decorate(
        schema: [String: Any],
        profile: ToolPresentationProfile,
        progressSummaryRequired: Bool
    ) -> [String: Any] {
        guard toolName(in: schema) != reportProgressName else { return schema }
        var result = schema
        let supportsResult = profile.result?.supportsCard == true

        if var function = result["function"] as? [String: Any] {
            function["parameters"] = decoratingObjectSchema(
                function["parameters"] as? [String: Any] ?? [:],
                progressSummaryRequired: progressSummaryRequired,
                supportsResult: supportsResult
            )
            result["function"] = function
            return result
        }

        if result["input_schema"] != nil {
            result["input_schema"] = decoratingObjectSchema(
                result["input_schema"] as? [String: Any] ?? [:],
                progressSummaryRequired: progressSummaryRequired,
                supportsResult: supportsResult
            )
            return result
        }

        if result["parameters"] != nil {
            result["parameters"] = decoratingObjectSchema(
                result["parameters"] as? [String: Any] ?? [:],
                progressSummaryRequired: progressSummaryRequired,
                supportsResult: supportsResult
            )
            return result
        }

        return decoratingObjectSchema(
            result,
            progressSummaryRequired: progressSummaryRequired,
            supportsResult: supportsResult
        )
    }

    static func decorate(
        schemas: [[String: Any]],
        progressSummaryRequired: Bool,
        explicitProfile: (String) -> ToolPresentationProfile? = { _ in nil }
    ) -> [[String: Any]] {
        schemas.map { schema in
            guard let name = toolName(in: schema), name != reportProgressName else { return schema }
            return decorate(
                schema: schema,
                profile: ToolPresentationProfileRegistry.resolve(
                    toolName: name,
                    explicitProfile: explicitProfile(name)
                ),
                progressSummaryRequired: progressSummaryRequired
            )
        }
    }

    static func reportProgressSchema() -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": reportProgressName,
                "description": "Send a brief user-facing progress update during a multi-step task. This does not perform an external action.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "message": [
                            "type": "string",
                            "description": "One short user-facing progress update. Do not reveal private chain-of-thought."
                        ]
                    ],
                    "required": ["message"],
                    "additionalProperties": false
                ]
            ]
        ]
    }

    static func toolName(in schema: [String: Any]) -> String? {
        if let function = schema["function"] as? [String: Any] {
            return function["name"] as? String
        }
        return schema["name"] as? String
    }

    private static func decoratingObjectSchema(
        _ schema: [String: Any],
        progressSummaryRequired: Bool,
        supportsResult: Bool
    ) -> [String: Any] {
        var result = schema
        if result["type"] == nil { result["type"] = "object" }

        var properties = result["properties"] as? [String: Any] ?? [:]
        properties[progressSummaryKey] = properties[progressSummaryKey] ?? progressSummarySchema
        if supportsResult {
            properties[resultPresentationKey] = properties[resultPresentationKey] ?? resultPresentationSchema
        }
        result["properties"] = properties

        if progressSummaryRequired {
            var requiredFields = result["required"] as? [String] ?? []
            if !requiredFields.contains(progressSummaryKey) {
                requiredFields.append(progressSummaryKey)
            }
            result["required"] = requiredFields
        }
        return result
    }
}

enum ToolProgressSummary {
    static func reportProgressMessage(from argumentsJSON: String) -> String? {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return ProgressSummarySanitizer.sanitize(object["message"] as? String)
    }

    static func userFacingArguments(
        from argumentsJSON: String,
        visibleKeys: [String]? = nil
    ) -> String? {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let allowed = visibleKeys.map(Set.init)
        let lines = object.keys.sorted().compactMap { key -> String? in
            if let allowed, !allowed.contains(key) { return nil }
            guard let value = object[key], !(value is NSNull) else { return nil }
            if let string = value as? String { return "\(key): \(string)" }
            if let number = value as? NSNumber { return "\(key): \(number)" }
            if let values = value as? [String] { return "\(key): \(values.joined(separator: ", "))" }
            return nil
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func stringValues(from argumentsJSON: String, keys: [String]) -> [String] {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return keys.flatMap { key -> [String] in
            if let string = object[key] as? String,
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return [string]
            }
            return object[key] as? [String] ?? []
        }
    }
}

enum ProgressSummarySanitizer {
    private static let maximumLength = 280

    static func sanitize(_ value: String?) -> String? {
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

    static func sanitizeProviderReasoningSummary(_ value: String?) -> String? {
        guard let raw = value, !looksLikeRawChainOfThought(raw) else { return nil }
        let newlineCount = raw.filter { $0 == "\n" }.count
        guard newlineCount <= 1 else { return nil }
        guard let sanitized = sanitize(raw), sanitized.count <= 140 else { return nil }
        guard !looksLikeRawChainOfThought(sanitized) else { return nil }
        let sentenceSeparators = sanitized.filter { ".!?。！？".contains($0) }
        guard sentenceSeparators.count <= 2 else { return nil }
        return sanitized
    }

    static func looksLikeRawChainOfThought(_ value: String) -> Bool {
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
