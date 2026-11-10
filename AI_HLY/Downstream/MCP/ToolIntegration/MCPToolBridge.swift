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
                )],
                outcome: .failed
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

    static func render(
        _ output: MCPToolCallOutput,
        title: String
    ) -> NativeToolResult {
        var modelParts: [String] = []
        var userParts: [String] = []
        var publicContent: [[String: Any]] = []
        var needsFullPayload = output.structuredContent != nil
        var blocks: [NativeUIBlock] = []
        for content in output.content {
            // Protocol _meta is private to the client. Preserve model-visible
            // media/structured data without copying UI metadata into the model.
            guard var encoded = (try? JSONEncoder().encode(content))
                .flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) else {
                return NativeToolResult(modelText: "MCP result encoding failed; content was not silently truncated.", outcome: .failed)
            }
            let audience = (encoded["annotations"] as? [String: Any])?["audience"] as? [String]
            let visible = audience.map { $0.contains("assistant") } ?? true
            encoded.removeValue(forKey: "_meta")
            if var resource = encoded["resource"] as? [String: Any] {
                resource.removeValue(forKey: "_meta"); encoded["resource"] = resource
            }
            if visible { publicContent.append(encoded) }
            switch content {
            case .text(let text, _, _):
                if visible { modelParts.append(text) }
                userParts.append(text)
                blocks.append(.init(type: output.isError ? .error : .markdown, title: title, body: text, systemImage: "server.rack"))
            case .image(let data, let mimeType, _, _):
                if visible { modelParts.append("[Image returned by \(title), \(mimeType)]"); needsFullPayload = true }
                blocks.append(.init(type: .card, title: title, body: mimeType, systemImage: "photo", imageURL: "data:\(mimeType);base64,\(data)"))
            case .audio(_, let mimeType, _, _):
                if visible { modelParts.append("[Audio returned by \(title), \(mimeType)]"); needsFullPayload = true }
                blocks.append(.init(type: .card, title: title, body: mimeType, systemImage: "waveform"))
            case .resource(_, _, _):
                let text = (try? JSONSerialization.data(withJSONObject: encoded["resource"] ?? [:], options: [.sortedKeys]))
                    .map { String(decoding: $0, as: UTF8.self) } ?? "MCP resource encoding failed."
                if visible { modelParts.append(text); needsFullPayload = true }
                userParts.append(text)
                blocks.append(.init(type: .source, title: title, body: text, systemImage: "doc.text"))
            case .resourceLink(let uri, let name, let resourceTitle, let description, _, _):
                if visible { modelParts.append("\(resourceTitle ?? name): \(uri)"); needsFullPayload = true }
                blocks.append(.init(type: .source, title: resourceTitle ?? name, body: description, systemImage: "link", url: uri))
            }
        }
        var payload: [String: Any] = ["content": publicContent, "isError": output.isError]
        if let structured = output.structuredContent {
            guard let bytes = try? JSONEncoder().encode(structured),
                  let object = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]) else {
                return NativeToolResult(modelText: "MCP structured result encoding failed.", outcome: .failed)
            }
            // Arbitrary user data may legitimately contain a key named _meta.
            // Only the protocol metadata above is private; do not rewrite data.
            payload["structuredContent"] = object
            let text = String(decoding: bytes, as: UTF8.self)
            modelParts.append(text); userParts.append(text)
            blocks.append(.init(type: output.isError ? .error : .markdown, title: title, body: "```json\n\(text)\n```", systemImage: "curlybraces"))
        }
        let fullPayload: String?
        if needsFullPayload {
            guard let bytes = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
                return NativeToolResult(modelText: "MCP complete result encoding failed.", outcome: .failed)
            }
            fullPayload = String(decoding: bytes, as: UTF8.self)
        } else { fullPayload = nil }
        let modelText = modelParts.joined(separator: "\n")
        let userText = userParts.joined(separator: "\n")
        return NativeToolResult(
            modelText: modelText.isEmpty ? "MCP tool returned no model-visible text." : modelText,
            userText: userText.isEmpty ? MCPL10n.string("No content returned") : userText,
            uiBlocks: blocks,
            outcome: output.isError ? .failed : .succeeded,
            isStoreEligible: true,
            fullResultPayload: fullPayload,
            fullResultMIMEType: fullPayload == nil ? nil : "application/json"
        )
    }
}
