import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

/// Bridge for agent tool execution through the unified host services layer.
enum AgentHostServicesAdapter {

    /// Build context for agent tool execution (all capabilities, no UI).
    static func makeContext() -> HanlinHostCallContext {
        HanlinHostCallContext.forAgent()
    }

    /// Execute a runtime through the broker with agent permissions.
    static func executeRuntime(
        _ kind: RuntimeKind,
        source: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        limits: RuntimeExecutionLimits? = nil
    ) async throws -> RuntimeExecutionResult {
        let context = makeContext()
        return try await HanlinRuntimeBroker.shared.execute(
            kind: kind,
            source: source,
            context: context,
            arguments: arguments,
            environment: environment,
            limits: limits
        )
    }

    /// Execute a shell command through the broker with agent permissions.
    static func executeShell(
        program: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        allowNetwork: Bool = false,
        limits: RuntimeExecutionLimits? = nil,
        context: HanlinHostCallContext? = nil
    ) async throws -> RuntimeExecutionResult {
        let context = context ?? makeContext()
        return try await HanlinRuntimeBroker.shared.executeShell(
            program: program,
            arguments: arguments,
            context: context,
            environment: environment,
            allowNetwork: allowNetwork,
            limits: limits
        )
    }

    /// Compatibility route for historical free-form shell tool calls.
    static func executeLegacyShell(
        command: String,
        environment: [String: String] = [:],
        allowNetwork: Bool = false,
        limits: RuntimeExecutionLimits? = nil,
        context: HanlinHostCallContext? = nil
    ) async throws -> RuntimeExecutionResult {
        let context = context ?? makeContext()
        return try await HanlinRuntimeBroker.shared.executeLegacyShell(
            command: command,
            context: context,
            environment: environment,
            allowNetwork: allowNetwork,
            limits: limits
        )
    }

    /// Compile and optionally execute TypeScript through broker and capability checks.
    static func compileAndExecuteTypeScript(
        source: String,
        fileName: String = "main.ts",
        compileOnly: Bool = false,
        environment: [String: String] = [:],
        limits: RuntimeExecutionLimits? = nil
    ) async throws -> (compilation: TypeScriptCompilationResult, execution: RuntimeExecutionResult?) {
        let result = try await HanlinRuntimeBroker.shared.compileAndExecuteTypeScript(
            source: source,
            context: makeContext(),
            fileName: fileName,
            compileOnly: compileOnly,
            environment: environment,
            limits: limits
        )
        return (result.compilation, result.execution)
    }
}
