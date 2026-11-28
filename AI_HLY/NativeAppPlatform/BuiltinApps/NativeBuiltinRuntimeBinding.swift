// NativeBuiltinRuntimeBinding.swift
// AI_HLY
//
// App-side runtime binding table mapping canonical Mini App tool IDs
// and presentation handler identifiers to concrete native runtime types.

import Foundation
import HanlinPlatformContracts

/// App-side runtime binding table resolving canonical Mini App declarations
/// (logical tool IDs, presentation handler identifiers) to actual native runtime
/// implementations (`NativeTool` and `NativeChatCardProvider`).
enum NativeBuiltinRuntimeBinding {
    /// Resolves a canonical local tool ID string to its corresponding `NativeTool` instance.
    @MainActor
    static func resolveTool(
        named toolName: String,
        context: NativeAppContext? = nil
    ) -> (any NativeTool)? {
        switch toolName {
        case "sefaria_search":
            return SefariaAssistantSearchTool(
                service: NativeAppSefariaExports.searchService()
            )
        case "sefaria_get_source":
            return SefariaAssistantSourceTool(
                service: NativeAppSefariaExports.sourceService()
            )
        case "wikipedia_search":
            return WikipediaAssistantSearchTool(
                service: NativeAppWikipediaExports.searchService()
            )
        case "wikipedia_get_summary":
            return WikipediaAssistantSummaryTool(
                service: NativeAppWikipediaExports.summaryService()
            )
        case "text_analyze":
            return NativeAppTextStudioAnalyzeTool(
                service: NativeAppTextStudioExports.service()
            )
        case "text_transform":
            return NativeAppTextStudioTransformTool(
                service: NativeAppTextStudioExports.service()
            )
        default:
            return nil
        }
    }

    /// Resolves a canonical `HanlinLogicalToolID` to its corresponding `NativeTool` instance.
    @MainActor
    static func resolveTool(
        logicalID: HanlinLogicalToolID,
        context: NativeAppContext? = nil
    ) -> (any NativeTool)? {
        resolveTool(named: logicalID.localToolID.rawValue, context: context)
    }

    /// Resolves a presentation handler identifier string to its corresponding `NativeChatCardProvider`.
    static func resolveChatCard(
        handler: String
    ) -> (any NativeChatCardProvider)? {
        switch handler {
        case "nativeapp.sefaria.source.card":
            return NativeAppSefariaChatCardProvider()
        case "nativeapp.wikipedia.summary.card":
            return NativeAppWikipediaChatCardProvider()
        case "nativeapp.textstudio.analysis.card":
            return NativeAppTextStudioChatCardProvider()
        default:
            return nil
        }
    }
}
