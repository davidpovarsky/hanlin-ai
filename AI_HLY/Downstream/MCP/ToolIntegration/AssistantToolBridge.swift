import Foundation

@MainActor
enum AssistantToolBridge {
    static func schemasForRequest(scope: AssistantToolRequestScope) async -> [[String: Any]] {
        var schemas = NativeToolBridge.schemasForRequest()
        schemas.append(contentsOf: await MCPToolBridge.schemas(scope: scope))
        return schemas
    }

    static func presentationProfile(for name: String) async -> ToolPresentationProfile? {
        if let native = NativeToolBridge.presentationProfile(for: name) {
            return native
        }
        return await MCPToolBridge.presentationProfile(name: name)
    }

    static func execute(
        name: String,
        argumentsJSON: String,
        context: NativeToolExecutionContext
    ) async -> NativeToolResult? {
        if let native = await NativeToolBridge.executeIfNativeTool(
            name: name,
            argumentsJSON: argumentsJSON,
            context: context
        ) {
            return native
        }
        return await MCPToolBridge.execute(name: name, argumentsJSON: argumentsJSON)
    }
}
