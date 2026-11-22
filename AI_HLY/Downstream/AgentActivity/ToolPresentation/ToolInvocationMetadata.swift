import Foundation
import HanlinAgentCore

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
        guard let extraction = try? HanlinHostSchemaValidation.extractStringMetadata(
            argumentsJSON: Data(argumentsJSON.utf8),
            keys: [ToolSchemaDecorator.progressSummaryKey, ToolSchemaDecorator.resultPresentationKey]
        ) else {
            return ToolInvocationExtractionResult(
                sanitizedArgumentsJSON: argumentsJSON,
                metadata: ToolInvocationMetadata(progressSummary: nil, resultPresentation: .none),
                hadInvalidResultPresentation: false
            )
        }

        let summary = ProgressSummarySanitizer.sanitize(
            extraction.strings[ToolSchemaDecorator.progressSummaryKey]
        )
        let rawPresentation = extraction.strings[ToolSchemaDecorator.resultPresentationKey]
        let request: ToolResultPresentationRequest
        let invalid: Bool
        if let raw = rawPresentation,
           let decoded = ToolResultPresentationRequest(rawValue: raw) {
            request = decoded
            invalid = false
        } else {
            request = .none
            invalid = extraction.presentKeys.contains(ToolSchemaDecorator.resultPresentationKey)
        }

        let sanitizedJSON = String(decoding: extraction.argumentsJSON, as: UTF8.self)

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
