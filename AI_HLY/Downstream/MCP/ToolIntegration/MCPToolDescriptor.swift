import Foundation
import HanlinPlatformContracts

struct MCPToolDescriptor: Codable, Hashable, Sendable, Identifiable {
    var id: String { exposedName }
    var serverID: UUID
    var serverSlug: String
    var serverDisplayName: String
    var originalName: String
    var exposedName: String
    var title: String?
    var summary: String?
    var inputSchemaJSON: Data
    var originalInputSchemaVerified: Bool? = nil
    var readOnlyHint: Bool? = nil
    var destructiveHint: Bool? = nil
    var requiresApproval: Bool? = nil
    var executionPresentation: HanlinToolExecutionPresentationDescriptor? = nil

    func openAIToolSchema() throws -> [String: Any] {
        let parameters = try JSONSerialization.jsonObject(with: inputSchemaJSON)
        return [
            "type": "function",
            "function": [
                "name": exposedName,
                "description": "[\(serverDisplayName)] \(summary ?? title ?? originalName)",
                "parameters": parameters
            ]
        ]
    }
}
