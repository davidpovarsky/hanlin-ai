//
//  NativeToolBridge.swift
//  AI_HLY
//
//  Single integration surface between the existing APIManager and our separate native tools layer.
//

import Foundation

@MainActor
enum NativeToolBridge {
    static func schemasForRequest() -> [[String: Any]] {
        let catalog = NativeToolCatalog.shared
        catalog.ensureBuiltinsRegistered()

        return catalog.schemasForEnabledTools()
    }

    static func presentationProfile(for name: String) -> ToolPresentationProfile? {
        let catalog = NativeToolCatalog.shared
        catalog.ensureBuiltinsRegistered()
        return catalog.presentationProfile(named: name)
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

        guard let entry = catalog.entry(named: name) else {
            NativeToolTraceLogger.shared.log(
                "tool_execution_lookup_failed",
                ["toolName": name]
            )
            return nil
        }

        guard catalog.isEnabled(entry), let tool = catalog.tool(named: name) else {
            NativeToolTraceLogger.shared.log(
                "disabled_tool_execution_rejected",
                ["toolName": name, "sourceAppID": entry.sourceAppID as Any]
            )
            return NativeToolResult(
                modelText: "The assistant tool '\(name)' is unavailable because it is disabled in Settings.",
                userText: "Tool unavailable: \(entry.title) is disabled.",
                uiBlocks: [
                    NativeUIBlock(
                        type: .error,
                        title: "Tool unavailable",
                        body: "\(entry.title) is disabled in Settings.",
                        systemImage: "wrench.and.screwdriver.fill"
                    )
                ]
            )
        }

        let start = Date()
        NativeToolTraceLogger.shared.log(
            "tool_execution_started",
            [
                "toolName": name,
                "sourceAppID": entry.sourceAppID as Any,
                "arguments": NativeToolTraceLogger.shared.redactedJSONString(argumentsJSON)
            ]
        )

        let extraction = ToolInvocationMetadataExtractor.extract(from: argumentsJSON)
        let result = await tool.execute(argumentsJSON: extraction.sanitizedArgumentsJSON, context: context)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        NativeToolTraceLogger.shared.log(
            "tool_execution_completed",
            [
                "toolName": name,
                "durationMs": durationMs,
                "modelTextLength": result.modelText.count,
                "userTextLength": result.userText?.count ?? 0,
                "uiBlockCount": result.uiBlocks.count,
                "sourceAppID": entry.sourceAppID as Any
            ]
        )

        return result
    }
}
