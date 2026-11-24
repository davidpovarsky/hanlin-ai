import Foundation
import HanlinPlatformContracts
import HanlinPresentationKit
import MCP

public struct MCPToolDescriptor: Codable, Hashable, Sendable, Identifiable {
    public var id: String { exposedName }
    public internal(set) var serverID: UUID
    public internal(set) var serverSlug: String
    public internal(set) var serverDisplayName: String
    public internal(set) var originalName: String
    public internal(set) var exposedName: String
    public internal(set) var title: String?
    public internal(set) var summary: String?
    public internal(set) var inputSchemaJSON: Data
    public internal(set) var originalInputSchemaVerified: Bool? = nil
    public internal(set) var readOnlyHint: Bool? = nil
    public internal(set) var destructiveHint: Bool? = nil
    public internal(set) var requiresApproval: Bool? = nil
    public internal(set) var executionPresentation: HanlinToolExecutionPresentationDescriptor? = nil
    public internal(set) var presentationIcons: HanlinToolIconSet? = nil

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

    public func openAIToolSchema() throws -> [String: Any] {
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
