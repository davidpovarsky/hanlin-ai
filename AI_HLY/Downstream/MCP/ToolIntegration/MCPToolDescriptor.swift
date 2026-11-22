import Foundation
import HanlinPlatformContracts
import HanlinPresentationKit
import MCP

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
    var presentationIcons: HanlinToolIconSet? = nil

    /// The pinned MCP SDK already decodes these declarations. Retain only
    /// bounded HTTPS artwork from this exact tool and its connected server.
    static func presentationIcons(tool: [MCP.Icon]?, server: [MCP.Icon]?) -> HanlinToolIconSet? {
        func admitted(_ icons: [MCP.Icon]?) -> [HanlinToolIcon] {
            (icons ?? []).prefix(8).compactMap { icon in
                HanlinToolIcon(source: icon.src,
                    theme: icon.theme.flatMap { HanlinToolIcon.Theme(rawValue: $0.rawValue) })
            }
        }
        return HanlinToolIconSet(tool: admitted(tool), server: admitted(server))
    }

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
