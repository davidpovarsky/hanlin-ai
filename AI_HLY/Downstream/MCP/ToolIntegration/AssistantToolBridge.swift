import Foundation
import HanlinPlatformContracts

@MainActor
enum AssistantToolBridge {
    struct Executors {
        let executeNative: @MainActor (
            HanlinProviderInstanceID,
            String,
            String,
            NativeToolExecutionContext
        ) async -> NativeToolResult
        let executeMCP: @MainActor (
            UUID,
            String,
            String,
            String
        ) async -> NativeToolResult
        let executeScripting: @MainActor (
            HanlinScriptBackendRoute,
            String
        ) async -> NativeToolResult

        static var live: Self {
            live(scriptingRegistry: .shared)
        }

        static func live(
            scriptingRegistry: HanlinScriptingProviderRegistry
        ) -> Self {
            Self(
                executeNative: { providerInstanceID, toolName, argumentsJSON, context in
                    await NativeToolBridge.executeCanonical(
                        providerInstanceID: providerInstanceID,
                        toolName: toolName,
                        argumentsJSON: argumentsJSON,
                        context: context
                    )
                },
                executeMCP: { serverID, toolName, resultTitle, argumentsJSON in
                    await MCPToolBridge.execute(
                        serverID: serverID,
                        toolName: toolName,
                        resultTitle: resultTitle,
                        argumentsJSON: argumentsJSON
                    )
                },
                executeScripting: { route, argumentsJSON in
                    do {
                        let result = try await scriptingRegistry.execute(
                            route: route,
                            argumentsJSON: argumentsJSON
                        )
                        if result.isStructured {
                            return try nativeResult(for: result)
                        }
                        let modelText: String
                        if let data = result.data {
                            let payload = HanlinJSONValue.object([
                                "success": .bool(result.success),
                                "message": .string(result.message),
                                "data": try data.jsonValue()
                            ])
                            modelText = String(
                                decoding: try payload.canonicalJSONData(),
                                as: UTF8.self
                            )
                        } else {
                            modelText = result.message
                        }
                        return NativeToolResult(
                            modelText: modelText,
                            userText: result.success ? nil : result.message,
                            uiBlocks: result.success ? [] : [.init(
                                type: .error,
                                title: "Script tool failed",
                                body: result.message,
                                systemImage: "exclamationmark.triangle"
                            )]
                        )
                    } catch let error as HanlinScriptingError {
                        return NativeToolResult(
                            modelText: "Script tool failed (\(error.diagnosticCode)).",
                            userText: error.localizedDescription,
                            uiBlocks: [.init(
                                type: .error,
                                title: "Script tool failed",
                                body: error.localizedDescription,
                                systemImage: "exclamationmark.triangle"
                            )]
                        )
                    } catch {
                        return NativeToolResult(
                            modelText: "Script tool failed (unexpected_failure).",
                            userText: "The Script tool could not complete.",
                            uiBlocks: [.init(
                                type: .error,
                                title: "Script tool failed",
                                body: "The Script tool could not complete.",
                                systemImage: "exclamationmark.triangle"
                            )]
                        )
                    }
                }
            )
        }

        static func nativeResult(
            for result: HanlinScriptToolExecutionResult
        ) throws -> NativeToolResult {
            let assistantParts = result.assistantParts ?? []
            let assistantPayload = HanlinValue.object([
                "success": .bool(result.success),
                "output": .object([
                    "assistantParts": .array(assistantParts.map(\.value)),
                ]),
            ])
            let modelText = String(
                decoding: try assistantPayload.canonicalJSONData(),
                as: UTF8.self
            )
            let userParts = result.userParts ?? []
            let userText = userParts.compactMap { part -> String? in
                switch part {
                case let .string(text), let .text(text): text
                case .image: nil
                }
            }.joined(separator: "\n")
            let blocks = userParts.map { part -> NativeUIBlock in
                switch part {
                case let .string(text), let .text(text):
                    return NativeUIBlock(type: .markdown, body: text)
                case let .image(base64, mimeType):
                    return NativeUIBlock(
                        type: .card,
                        title: String(localized: "Image"),
                        systemImage: "photo",
                        embeddedImageBase64: base64,
                        embeddedImageMIMEType: mimeType
                    )
                }
            }
            return NativeToolResult(
                modelText: modelText,
                userText: userText.isEmpty ? nil : userText,
                uiBlocks: blocks
            )
        }
    }

    @MainActor
    struct PreparedTools {
        let authority: HanlinCanonicalToolAuthority
        let executors: Executors

        init(
            authority: HanlinCanonicalToolAuthority,
            executors: Executors = .live
        ) {
            self.authority = authority
            self.executors = executors
        }

        var schemas: [[String: Any]] {
            authority.modelSchemas
        }

        func presentationProfile(for alias: String) -> ToolPresentationProfile? {
            authority.resolution(alias: alias)?.presentationProfile
        }

        func execute(
            alias: String,
            argumentsJSON: String,
            context: NativeToolExecutionContext
        ) async -> NativeToolResult? {
            guard let resolution = authority.resolution(alias: alias) else {
                return nil
            }
            switch resolution.backend {
            case .native(let providerInstanceID, let toolName):
                return await executors.executeNative(
                    providerInstanceID,
                    toolName,
                    argumentsJSON,
                    context
                )
            case .mcp(let serverID, let toolName):
                return await executors.executeMCP(
                    serverID,
                    toolName,
                    resolution.resultTitle ?? toolName,
                    argumentsJSON
                )
            case .scripting(let route):
                return await executors.executeScripting(route, argumentsJSON)
            }
        }
    }

    static func prepare(
        scope: AssistantToolRequestScope,
        scriptingRegistry: HanlinScriptingProviderRegistry = .shared
    ) async throws -> PreparedTools {
        do {
            let nativeSources = try NativeToolBridge.canonicalSourcesForRequest()
            let mcpTools = await MCPToolBridge.resolveDescriptors(scope: scope)
            let scriptSources = try HanlinScriptCanonicalAdapter.project(
                await scriptingRegistry.snapshots()
            )
            return PreparedTools(authority: try HanlinCanonicalToolAuthority.build(
                nativeSources: nativeSources,
                mcpTools: mcpTools,
                scriptSources: scriptSources
            ), executors: .live(scriptingRegistry: scriptingRegistry))
        } catch {
            NativeToolTraceLogger.shared.log(
                "canonical_tool_authority_build_failed",
                [
                    "errorType": String(describing: type(of: error)),
                    "message": error.localizedDescription
                ]
            )
            throw error
        }
    }
}
