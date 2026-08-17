import Foundation
import MCP

@MainActor
enum MCPToolBridge {
    static func resolveDescriptors(
        scope: AssistantToolRequestScope
    ) async -> [MCPToolDescriptor] {
        guard scope.mcpGloballyEnabled, !scope.mcpServerIDs.isEmpty else { return [] }
        let provider = MCPRuntimeProvider.shared
        let result = await provider.controller.resolveToolDescriptors(
            serverIDs: scope.mcpServerIDs
        )
        await provider.synchronizeRuntimeState()
        for failure in result.failures {
            await MCPTraceLogger.shared.log(
                "mcp_server_schema_resolution_failed",
                fields: [
                    "serverID": failure.serverID.uuidString.lowercased(),
                    "packageName": failure.packageName,
                    "displayName": failure.displayName,
                    "errorCode": failure.errorCode,
                    "message": failure.message
                ]
            )
        }
        await MCPTraceLogger.shared.log(
            "mcp_tool_schema_resolution_completed",
            fields: [
                "selectedServerCount": "\(scope.mcpServerIDs.count)",
                "successfulServerCount": "\(result.successfulServerCount)",
                "failedServerCount": "\(result.failures.count)",
                "toolCount": "\(result.descriptors.count)"
            ]
        )
        return result.descriptors
    }

    static func execute(
        serverID: UUID,
        toolName: String,
        resultTitle: String,
        argumentsJSON: String
    ) async -> NativeToolResult {
        do {
            let output = try await MCPRuntimeProvider.shared.controller.call(
                serverID: serverID,
                toolName: toolName,
                argumentsJSON: argumentsJSON
            )
            await MCPRuntimeProvider.shared.synchronizeRuntimeState()
            return render(output, title: resultTitle)
        } catch {
            await MCPRuntimeProvider.shared.synchronizeRuntimeState()
            return NativeToolResult(
                modelText: "MCP tool failed: \(error.localizedDescription)",
                userText: error.localizedDescription,
                uiBlocks: [.init(
                    type: .error,
                    title: MCPL10n.string("MCP tool failed"),
                    body: error.localizedDescription,
                    systemImage: "server.rack"
                )]
            )
        }
    }

    static func presentationProfile(
        descriptor: MCPToolDescriptor
    ) -> ToolPresentationProfile {
        ToolPresentationProfile(
            identity: "mcp.\(descriptor.serverID.uuidString).\(descriptor.originalName)",
            activity: .init(
                kind: .execute,
                systemImage: "server.rack",
                runningTitle: "\(MCPL10n.string("Running")) \(descriptor.title ?? descriptor.originalName) — \(descriptor.serverDisplayName)",
                completedTitle: "\(MCPL10n.string("Completed")) — \(descriptor.serverDisplayName)",
                failedTitle: MCPL10n.string("MCP tool failed"),
                visibleArgumentKeys: []
            ),
            result: .init(rendererKind: .modernNative, supportsCard: true),
            resultDisplayPolicy: .modelControlled
        )
    }

    private static func render(
        _ output: MCPToolCallOutput,
        title: String
    ) -> NativeToolResult {
        var modelParts: [String] = []
        var blocks: [NativeUIBlock] = []
        for content in output.content {
            switch content {
            case .text(let text, _, _):
                modelParts.append(text)
                blocks.append(.init(type: output.isError ? .error : .markdown, title: title, body: text, systemImage: "server.rack"))
            case .image(let data, let mimeType, _, _):
                modelParts.append("[Image returned by \(title), \(mimeType)]")
                blocks.append(.init(type: .card, title: title, body: mimeType, systemImage: "photo", imageURL: "data:\(mimeType);base64,\(data)"))
            case .audio(_, let mimeType, _, _):
                modelParts.append("[Audio returned by \(title), \(mimeType)]")
                blocks.append(.init(type: .card, title: title, body: mimeType, systemImage: "waveform"))
            case .resource(let resource, _, _):
                let text = (try? String(decoding: JSONEncoder().encode(resource), as: UTF8.self)) ?? String(describing: resource)
                modelParts.append(text)
                blocks.append(.init(type: .source, title: title, body: text, systemImage: "doc.text"))
            case .resourceLink(let uri, let name, let resourceTitle, let description, _, _):
                modelParts.append("\(resourceTitle ?? name): \(uri)")
                blocks.append(.init(type: .source, title: resourceTitle ?? name, body: description, systemImage: "link", url: uri))
            }
        }
        let modelText = modelParts.joined(separator: "\n")
        return NativeToolResult(
            modelText: modelText.isEmpty ? "MCP tool returned no content." : String(modelText.prefix(8 * 1_024 * 1_024)),
            userText: modelText.isEmpty ? MCPL10n.string("No content returned") : modelText,
            uiBlocks: blocks
        )
    }
}
