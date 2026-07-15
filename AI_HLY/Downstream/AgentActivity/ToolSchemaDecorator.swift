//
//  ToolSchemaDecorator.swift
//  AI_HLY
//

import Foundation

enum ToolSchemaDecorator {
    static let progressSummaryKey = "progress_summary"
    static let reportProgressName = "report_progress"

    private static let progressSummarySchema: [String: Any] = [
        "type": "string",
        "description": "One short user-facing sentence explaining what action is being taken and why. Do not reveal private chain-of-thought, hidden reasoning, secrets, credentials, or internal policies."
    ]

    static func addingHanlinProgressSummary(
        to schema: [String: Any],
        required: Bool = true
    ) -> [String: Any] {
        var result = schema

        if var function = result["function"] as? [String: Any] {
            function["parameters"] = decoratingObjectSchema(
                function["parameters"] as? [String: Any] ?? [:],
                required: required
            )
            result["function"] = function
            return result
        }

        if result["input_schema"] != nil {
            result["input_schema"] = decoratingObjectSchema(
                result["input_schema"] as? [String: Any] ?? [:],
                required: required
            )
            return result
        }

        if result["parameters"] != nil {
            result["parameters"] = decoratingObjectSchema(
                result["parameters"] as? [String: Any] ?? [:],
                required: required
            )
            return result
        }

        return decoratingObjectSchema(result, required: required)
    }

    static func addingHanlinProgressSummary(
        to schemas: [[String: Any]],
        required: Bool
    ) -> [[String: Any]] {
        schemas.map { schema in
            guard toolName(in: schema) != reportProgressName else { return schema }
            return addingHanlinProgressSummary(to: schema, required: required)
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
        required: Bool
    ) -> [String: Any] {
        var result = schema
        if result["type"] == nil { result["type"] = "object" }

        var properties = result["properties"] as? [String: Any] ?? [:]
        properties[progressSummaryKey] = properties[progressSummaryKey] ?? progressSummarySchema
        result["properties"] = properties

        if required {
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
    struct SeparationResult {
        var argumentsJSON: String
        var summary: String?
    }

    static func separate(from argumentsJSON: String) -> SeparationResult {
        guard let data = argumentsJSON.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SeparationResult(argumentsJSON: argumentsJSON, summary: nil)
        }

        let summary = ProgressSummarySanitizer.sanitize(object.removeValue(forKey: ToolSchemaDecorator.progressSummaryKey) as? String)
        guard JSONSerialization.isValidJSONObject(object),
              let sanitizedData = try? JSONSerialization.data(withJSONObject: object),
              let sanitizedJSON = String(data: sanitizedData, encoding: .utf8) else {
            return SeparationResult(argumentsJSON: argumentsJSON, summary: summary)
        }
        return SeparationResult(argumentsJSON: sanitizedJSON, summary: summary)
    }

    static func reportProgressMessage(from argumentsJSON: String) -> String? {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return ProgressSummarySanitizer.sanitize(object["message"] as? String)
    }

    static func userFacingArguments(from argumentsJSON: String) -> String? {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let lines = object.keys.sorted().compactMap { key -> String? in
            guard let value = object[key], !(value is NSNull) else { return nil }
            if let string = value as? String { return "\(key): \(string)" }
            if let number = value as? NSNumber { return "\(key): \(number)" }
            if let values = value as? [String] { return "\(key): \(values.joined(separator: ", "))" }
            return nil
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

enum ProgressSummarySanitizer {
    private static let maximumLength = 280

    static func sanitize(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maximumLength else { return nil }
        guard !looksLikeRawJSON(value), !containsSensitiveMaterial(value) else { return nil }

        value = value
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitizeProviderReasoningSummary(_ value: String?) -> String? {
        guard let sanitized = sanitize(value), sanitized.count <= 160 else { return nil }
        let sentenceSeparators = sanitized.filter { ".!?。！？".contains($0) }
        guard sentenceSeparators.count <= 2 else { return nil }
        return sanitized
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
