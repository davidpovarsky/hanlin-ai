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
}
