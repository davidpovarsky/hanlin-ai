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

        static var live: Self {
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
                }
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
            }
        }
    }

    static func prepare(scope: AssistantToolRequestScope) async throws -> PreparedTools {
        do {
            let nativeSources = try NativeToolBridge.canonicalSourcesForRequest()
            let mcpTools = await MCPToolBridge.resolveDescriptors(scope: scope)
            return PreparedTools(authority: try HanlinCanonicalToolAuthority.build(
                nativeSources: nativeSources,
                mcpTools: mcpTools
            ))
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
