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
        command: String,
        environment: [String: String] = [:],
        allowNetwork: Bool = false,
        limits: RuntimeExecutionLimits? = nil
    ) async throws -> RuntimeExecutionResult {
        let context = makeContext()
        return try await HanlinRuntimeBroker.shared.executeShell(
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
        let context = makeContext()
        let availability = RuntimeAvailabilityStore.shared
        guard availability.isAvailable(.typeScript) else {
            throw HanlinHostServiceError.runtimeDisabledByUser(.typeScript)
        }
        if !compileOnly {
            guard availability.isAvailable(.node) else {
                throw HanlinHostServiceError.runtimeDisabledByUser(.node)
            }
        }
        let authResult = await HanlinHostCapabilityAuthority.shared.authorize(capability: "runtime.typescript", context: context)
        guard authResult == .allowed else {
            throw HanlinHostServiceError.capabilityNotGranted("runtime.typescript")
        }

        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "execute_typescript_code")
        let request = RuntimeExecutionRequest(
            source: source,
            workspace: workspace,
            environment: environment,
            limits: limits ?? RuntimeExecutionLimits()
        )
        let core = AppRuntimeCore.shared
        let result = try await core.typeScript.compileAndExecute(
            source: source,
            request: request,
            fileName: fileName,
            compileOnly: compileOnly
        )
        return (result.compilation, result.execution)
    }
}
