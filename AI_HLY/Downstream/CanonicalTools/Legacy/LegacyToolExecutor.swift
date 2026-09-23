import Foundation
import HanlinPlatformContracts

public struct LegacyToolExecutionResult: Sendable {
    public let modelText: String
    public let userText: String?
    public let outcome: NativeToolExecutionOutcome
    public let uiBlocks: [NativeUIBlock]
    public let diagnostics: NativeToolExecutionDiagnostics

    public init(
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
public protocol LegacyToolExecutionHandler: AnyObject {
    func executeLegacyTool(
        name: String,
        argumentsJSON: String,
        context: NativeToolExecutionContext
    ) async -> LegacyToolExecutionResult
}

public enum LegacyToolExecutor {
    @MainActor
    public static func execute(
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
            outcome: .failed
        )
    }
}
