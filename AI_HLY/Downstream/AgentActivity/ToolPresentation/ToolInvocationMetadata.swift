import Foundation

struct ToolInvocationMetadata: Codable, Hashable, Sendable {
    var progressSummary: String?
    var resultPresentation: ToolResultPresentationRequest
}

struct ToolInvocationExtractionResult: Hashable, Sendable {
    var sanitizedArgumentsJSON: String
    var metadata: ToolInvocationMetadata
    var hadInvalidResultPresentation: Bool
}

enum ToolInvocationMetadataExtractor {
    static func extract(from argumentsJSON: String) -> ToolInvocationExtractionResult {
        guard let data = argumentsJSON.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ToolInvocationExtractionResult(
                sanitizedArgumentsJSON: argumentsJSON,
                metadata: ToolInvocationMetadata(progressSummary: nil, resultPresentation: .none),
                hadInvalidResultPresentation: false
            )
        }

        let summary = ProgressSummarySanitizer.sanitize(
            object.removeValue(forKey: ToolSchemaDecorator.progressSummaryKey) as? String
        )
        let rawPresentation = object.removeValue(forKey: ToolSchemaDecorator.resultPresentationKey)
        let request: ToolResultPresentationRequest
        let invalid: Bool
        if let raw = rawPresentation as? String,
           let decoded = ToolResultPresentationRequest(rawValue: raw) {
            request = decoded
            invalid = false
        } else {
            request = .none
            invalid = rawPresentation != nil
        }

        let sanitizedJSON: String
        if JSONSerialization.isValidJSONObject(object),
           let sanitizedData = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let string = String(data: sanitizedData, encoding: .utf8) {
            sanitizedJSON = string
        } else {
            sanitizedJSON = argumentsJSON
        }

        return ToolInvocationExtractionResult(
            sanitizedArgumentsJSON: sanitizedJSON,
            metadata: ToolInvocationMetadata(
                progressSummary: summary,
                resultPresentation: request
            ),
            hadInvalidResultPresentation: invalid
        )
    }
}
