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

        NativeToolTraceLogger.shared.log(
            "schemas_for_request_started",
            [
                "loadedToolNames": loadedToolNames,
                "loadedToolCount": loadedToolNames.count
            ]
        )

        var schemas: [[String: Any]] = []
        if let toolSearch = catalog.tool(named: ToolSearchTool.toolName) {
            schemas.append(toolSearch.openAIToolSchema())
        } else {
            NativeToolTraceLogger.shared.log("tool_search_schema_missing")
        }

        let deferredSchemas = catalog.schemas(for: loadedToolNames)
        schemas.append(contentsOf: deferredSchemas)

        NativeToolTraceLogger.shared.log(
            "schemas_for_request_completed",
            [
                "schemaCount": schemas.count,
                "deferredSchemaCount": deferredSchemas.count,
                "loadedToolNames": loadedToolNames
            ]
        )

        return schemas
    }

    static func executeIfNativeTool(
        name: String,
        argumentsJSON: String,
        context: NativeToolExecutionContext
    ) async -> NativeToolResult? {
        let catalog = NativeToolCatalog.shared
        catalog.ensureBuiltinsRegistered()

        NativeToolTraceLogger.shared.log(
            "tool_execution_lookup_started",
            [
                "toolName": name,
                "arguments": NativeToolTraceLogger.shared.redactedJSONString(argumentsJSON),
                "localeIdentifier": context.localeIdentifier
            ]
        )

        guard let tool = catalog.tool(named: name) else {
            NativeToolTraceLogger.shared.log(
                "tool_execution_lookup_failed",
                ["toolName": name]
            )
            return nil
        }

        let start = Date()
        NativeToolTraceLogger.shared.log(
            "tool_execution_started",
            [
                "toolName": name,
                "arguments": NativeToolTraceLogger.shared.redactedJSONString(argumentsJSON)
            ]
        )

        let result = await tool.execute(argumentsJSON: argumentsJSON, context: context)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        NativeToolTraceLogger.shared.log(
            "tool_execution_completed",
            [
                "toolName": name,
                "durationMs": durationMs,
                "modelTextLength": result.modelText.count,
                "userTextLength": result.userText?.count ?? 0,
                "uiBlockCount": result.uiBlocks.count,
                "deferredToolNames": result.deferredToolNames
            ]
        )

        return result
    }
}
