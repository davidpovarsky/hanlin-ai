import Foundation
import MCP

@MainActor
enum MCPToolBridge {
    static func schemas(scope: AssistantToolRequestScope) async -> [[String: Any]] {
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
        var schemas: [[String: Any]] = []
        for descriptor in result.descriptors {
            do {
                schemas.append(try descriptor.openAIToolSchema())
            } catch {
                await MCPTraceLogger.shared.log(
                    "mcp_tool_schema_conversion_failed",
                    fields: [
                        "serverID": descriptor.serverID.uuidString.lowercased(),
                        "toolName": descriptor.originalName,
                        "errorCode": "mcp_tool_schema_invalid",
                        "message": error.localizedDescription
                    ]
                )
            }
        }
        await MCPTraceLogger.shared.log(
            "mcp_tool_schema_resolution_completed",
            fields: [
                "selectedServerCount": "\(scope.mcpServerIDs.count)",
                "successfulServerCount": "\(result.successfulServerCount)",
                "failedServerCount": "\(result.failures.count)",
                "toolCount": "\(schemas.count)"
            ]
        )
        return schemas
    }

    static func execute(name: String, argumentsJSON: String) async -> NativeToolResult? {
        guard name.hasPrefix("mcp__") else { return nil }
        do {
            let descriptor = await MCPRuntimeProvider.shared.controller.descriptor(exposedName: name)
            let output = try await MCPRuntimeProvider.shared.controller.call(
                exposedName: name,
                argumentsJSON: argumentsJSON
            )
            await MCPRuntimeProvider.shared.synchronizeRuntimeState()
            return render(output, descriptor: descriptor)
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

    static func presentationProfile(name: String) async -> ToolPresentationProfile? {
        guard let descriptor = await MCPRuntimeProvider.shared.controller.descriptor(exposedName: name) else {
            return nil
        }
        return ToolPresentationProfile(
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

    private static func render(_ output: MCPToolCallOutput, descriptor: MCPToolDescriptor?) -> NativeToolResult {
        var modelParts: [String] = []
        var blocks: [NativeUIBlock] = []
        let title = descriptor?.title ?? descriptor?.originalName ?? MCPL10n.string("MCP tool")
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
