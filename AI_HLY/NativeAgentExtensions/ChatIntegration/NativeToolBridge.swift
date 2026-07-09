//
//  NativeToolBridge.swift
//  AI_HLY
//
//  Single integration surface between the existing APIManager and our separate native tools layer.
//

import Foundation

@MainActor
enum NativeToolBridge {
    static func schemasForRequest(loadedToolNames: [String]) -> [[String: Any]] {
        let catalog = NativeToolCatalog.shared
        catalog.ensureBuiltinsRegistered()

        var schemas: [[String: Any]] = []
        if let toolSearch = catalog.tool(named: ToolSearchTool.toolName) {
            schemas.append(toolSearch.openAIToolSchema())
        }
        schemas.append(contentsOf: catalog.schemas(for: loadedToolNames))
        return schemas
    }

    static func executeIfNativeTool(
        name: String,
        argumentsJSON: String,
        context: NativeToolExecutionContext
    ) async -> NativeToolResult? {
        let catalog = NativeToolCatalog.shared
        catalog.ensureBuiltinsRegistered()
        guard let tool = catalog.tool(named: name) else { return nil }
        return await tool.execute(argumentsJSON: argumentsJSON, context: context)
    }
}
