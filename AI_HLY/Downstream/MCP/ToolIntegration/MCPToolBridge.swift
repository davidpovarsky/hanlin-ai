import Foundation
import MCP

@MainActor
enum MCPToolBridge {
    static func schemas(scope: AssistantToolRequestScope) async -> [[String: Any]] {
        guard scope.mcpGloballyEnabled, !scope.mcpServerIDs.isEmpty else { return [] }
        do {
            let descriptors = try await MCPRuntimeProvider.shared.controller.toolDescriptors(
                serverIDs: scope.mcpServerIDs
            )
            return descriptors.compactMap { try? $0.openAIToolSchema() }
        } catch {
            await MCPTraceLogger.shared.log("tool_schema_refresh_failed", fields: ["error": error.localizedDescription])
            return []
        }
    }

    static func execute(name: String, argumentsJSON: String) async -> NativeToolResult? {
        guard name.hasPrefix("mcp__") else { return nil }
        do {
            let descriptor = await MCPRuntimeProvider.shared.controller.descriptor(exposedName: name)
            let output = try await MCPRuntimeProvider.shared.controller.call(
                exposedName: name,
                argumentsJSON: argumentsJSON
            )
            return render(output, descriptor: descriptor)
        } catch {
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
