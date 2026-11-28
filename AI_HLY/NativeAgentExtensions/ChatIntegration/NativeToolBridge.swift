//
//  NativeToolBridge.swift
//  AI_HLY
//
//  Single integration surface between the existing APIManager and our separate native tools layer.
//

import Foundation
import HanlinPlatformContracts

@MainActor
enum NativeToolBridge {
    static func canonicalSourcesForRequest(explicitToolNames: Set<String> = [],
                                           catalog: NativeToolCatalog = .shared) throws -> [
        HanlinCanonicalToolAuthority.NativeSource
    ] {
        catalog.ensureBuiltinsRegistered()
        var schemas = catalog.schemasForEnabledTools()
        let alreadyIncluded = Set(schemas.compactMap { ToolSchemaDecorator.toolName(in: $0) })
        for name in explicitToolNames.sorted() where !alreadyIncluded.contains(name) {
            guard let tool = catalog.tool(named: name, enabledOnly: false),
                  let entry = catalog.entry(named: name) else { continue }
            schemas.append(ToolSchemaDecorator.decorate(schema: tool.openAIToolSchema(),
                profile: entry.presentationProfile, progressSummaryRequired: false))
        }
        return try schemas.map { schema in
            guard let name = ToolSchemaDecorator.toolName(in: schema),
                  let entry = catalog.entry(named: name),
                  let tool = catalog.tool(named: name, enabledOnly: false),
                  catalog.isEffectivelyEnabled(entry) || explicitToolNames.contains(name) else {
                throw HanlinCanonicalToolAuthorityError.invalidModelSchema(
                    ToolSchemaDecorator.toolName(in: schema) ?? "<missing-name>"
                )
            }
            return HanlinCanonicalToolAuthority.NativeSource(
                entry: entry,
                canonicalSchema: tool.openAIToolSchema(),
                modelSchema: schema
            )
        }
    }

    static func executeCanonical(
        providerInstanceID: HanlinProviderInstanceID,
        toolName: String,
        argumentsJSON: String,
        context: NativeToolExecutionContext,
        explicitlySelected: Bool = false,
        catalog: NativeToolCatalog = .shared
    ) async -> NativeToolResult {
        catalog.ensureBuiltinsRegistered()

        NativeToolTraceLogger.shared.log(
            "tool_execution_lookup_started",
            [
                "toolName": toolName,
                "providerInstanceID": providerInstanceID.rawValue,
                "arguments": NativeToolTraceLogger.shared.redactedJSONString(argumentsJSON),
                "localeIdentifier": context.localeIdentifier
            ]
        )

        guard let entry = catalog.entry(named: toolName),
              let actualProvider = try? NativeToolCanonicalShadowAdapter
                .providerInstanceID(for: entry),
              actualProvider == providerInstanceID else {
            NativeToolTraceLogger.shared.log(
                "tool_execution_lookup_failed",
                [
                    "toolName": toolName,
                    "providerInstanceID": providerInstanceID.rawValue
                ]
            )
            return NativeToolResult(
                modelText: "The canonical assistant tool route is no longer available.",
                userText: "Tool unavailable.",
                uiBlocks: [NativeUIBlock(
                    type: .error,
                    title: "Tool unavailable",
                    body: "The selected tool route is no longer available.",
                    systemImage: "wrench.and.screwdriver.fill"
                )],
                outcome: .rejectedByAvailability
            )
        }

        guard explicitlySelected || catalog.isEnabled(entry),
              let tool = catalog.tool(named: toolName, enabledOnly: !explicitlySelected) else {
            NativeToolTraceLogger.shared.log(
                "disabled_tool_execution_rejected",
                ["toolName": toolName, "sourceAppID": entry.sourceAppID as Any]
            )
            return NativeToolResult(
                modelText: "The assistant tool '\(toolName)' is unavailable because it is disabled in Settings.",
                userText: "Tool unavailable: \(entry.title) is disabled.",
                uiBlocks: [
                    NativeUIBlock(
                        type: .error,
                        title: "Tool unavailable",
                        body: "\(entry.title) is disabled in Settings.",
                        systemImage: "wrench.and.screwdriver.fill"
                    )
                ],
                outcome: .rejectedByAvailability
            )
        }

        let start = Date()
        NativeToolTraceLogger.shared.log(
            "tool_execution_started",
            [
                "toolName": toolName,
                "sourceAppID": entry.sourceAppID as Any,
                "arguments": NativeToolTraceLogger.shared.redactedJSONString(argumentsJSON)
            ]
        )

        let extraction = ToolInvocationMetadataExtractor.extract(from: argumentsJSON)
        var result = await tool.execute(argumentsJSON: extraction.sanitizedArgumentsJSON, context: context)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        result.diagnostics.argumentKeys = Self.argumentKeys(in: extraction.sanitizedArgumentsJSON)

        NativeToolTraceLogger.shared.log(
            result.outcome.isSuccess ? "tool_execution_succeeded" : "tool_execution_failed",
            [
                "toolName": toolName,
                "durationMs": durationMs,
                "outcome": result.outcome.rawValue,
                "failureCategory": result.diagnostics.failureCategory as Any,
                "backendRoute": result.diagnostics.backendRoute as Any,
                "runtimeKind": result.diagnostics.runtimeKind as Any,
                "exitCode": result.diagnostics.exitCode as Any,
                "didTimeOut": result.diagnostics.didTimeOut,
                "wasCancelled": result.diagnostics.wasCancelled,
                "outputWasTruncated": result.diagnostics.outputWasTruncated,
                "stdoutByteCount": result.diagnostics.stdoutByteCount,
                "stderrByteCount": result.diagnostics.stderrByteCount,
                "valueType": result.diagnostics.valueType as Any,
                "modelTextLength": result.modelText.count,
                "userTextLength": result.userText?.count ?? 0,
                "uiBlockCount": result.uiBlocks.count,
                "sourceAppID": entry.sourceAppID as Any
            ]
        )

        return result
    }

    private static func argumentKeys(in argumentsJSON: String) -> [String] {
        guard let data = argumentsJSON.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return dictionary.keys.sorted()
    }
}
