import Foundation
import HanlinPlatformContracts

struct LegacyToolExecutionResult: @unchecked Sendable {
    let modelText: String
    let userText: String?
    let outcome: NativeToolExecutionOutcome
    let uiBlocks: [NativeUIBlock]
    let diagnostics: NativeToolExecutionDiagnostics

    init(
        modelText: String,
        userText: String? = nil,
        outcome: NativeToolExecutionOutcome = .succeeded,
        uiBlocks: [NativeUIBlock] = [],
        diagnostics: NativeToolExecutionDiagnostics = NativeToolExecutionDiagnostics()
    ) {
        self.modelText = modelText
        self.userText = userText
        self.outcome = outcome
        self.uiBlocks = uiBlocks
        self.diagnostics = diagnostics
    }
}

@MainActor
protocol LegacyToolExecutionHandler: AnyObject {
    func executeLegacyTool(
        name: String,
        argumentsJSON: String,
        context: NativeToolExecutionContext
    ) async -> LegacyToolExecutionResult
}

enum LegacyToolExecutor {
    @MainActor
    static func execute(
        name: String,
        argumentsJSON: String,
        context: NativeToolExecutionContext,
        handler: LegacyToolExecutionHandler?
    ) async -> NativeToolResult {
        if let handler {
            let res = await handler.executeLegacyTool(name: name, argumentsJSON: argumentsJSON, context: context)
            return NativeToolResult(
                modelText: res.modelText,
                userText: res.userText,
                uiBlocks: res.uiBlocks,
                outcome: res.outcome,
                diagnostics: res.diagnostics
            )
        }
        return NativeToolResult(
            modelText: "Legacy tool '\(name)' execution handler not configured.",
            userText: "Legacy tool not configured.",
            uiBlocks: [],
            outcome: NativeToolExecutionOutcome.failed
        )
    }
}
