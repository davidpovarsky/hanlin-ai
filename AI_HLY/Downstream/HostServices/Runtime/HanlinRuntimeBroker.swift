import Foundation
import HanlinPlatformContracts

/// Unified runtime access facade. Validates availability, capabilities, and
/// workspace before routing to `AppRuntimeCore.shared` runtime actors.
///
/// Does NOT serialize across runtimes — each runtime actor handles its own
/// concurrency. The broker actor provides context validation and workspace derivation.
actor HanlinRuntimeBroker {
    static let shared = HanlinRuntimeBroker()

    private let core = AppRuntimeCore.shared
    private let availability = RuntimeAvailabilityStore.shared

    private init() {}

    // MARK: - Unified Execution

    func execute(
        kind: RuntimeKind,
        source: String,
        context: HanlinHostCallContext,
        arguments: [String] = [],
        environment: [String: String] = [:],
        limits: RuntimeExecutionLimits? = nil
    ) async throws -> RuntimeExecutionResult {
        try checkAvailability(for: kind)
        try await checkCapability(for: kind, in: context)

        let workspace = try deriveWorkspace(for: context)
        let effectiveLimits = limits ?? RuntimeExecutionLimits()

        switch kind {
        case .node:
            let request = RuntimeExecutionRequest(
                source: source, arguments: arguments,
                workspace: workspace, environment: environment,
                limits: effectiveLimits
            )
            return try await core.node.executeJavaScript(request)

        case .localPython:
            let request = RuntimeExecutionRequest(
                source: source, arguments: arguments,
                workspace: workspace, environment: environment,
                limits: effectiveLimits
            )
            return try await core.python.execute(request)

        case .javaScriptCore:
            let request = RuntimeExecutionRequest(
                source: source, arguments: arguments,
                workspace: workspace, environment: environment,
                limits: effectiveLimits
            )
            return try await core.javaScriptCore.execute(request)

        case .typeScript:
            let request = RuntimeExecutionRequest(
                source: "", // TypeScript compile-and-execute uses separate source param
                workspace: workspace, environment: environment,
                limits: effectiveLimits
            )
            let tsResult = try await core.typeScript.compileAndExecute(
                source: source, request: request
            )
            guard tsResult.compilation.succeeded else {
                let diagnosticText = tsResult.compilation.diagnostics.map(\.message).joined(separator: "\n")
                throw HanlinHostServiceError.invalidRequest("TypeScript compilation failed: \(diagnosticText)")
            }
            guard let executionResult = tsResult.execution else {
                throw HanlinHostServiceError.invalidRequest("TypeScript compiled but execution returned no result")
            }
            return executionResult

        case .shell:
            return try await core.shell.execute(
                command: source,
                workspace: workspace,
                environment: environment,
                allowNetwork: false,
                limits: effectiveLimits
            )
        }
    }

    // MARK: - Shell-Specific

    func executeShell(
        command: String,
        context: HanlinHostCallContext,
        environment: [String: String] = [:],
        allowNetwork: Bool = false,
        limits: RuntimeExecutionLimits? = nil
    ) async throws -> RuntimeExecutionResult {
        try checkAvailability(for: .shell)
        try await checkCapability(for: .shell, in: context)

        let workspace = try deriveWorkspace(for: context)

        return try await core.shell.execute(
            command: command,
            workspace: workspace,
            environment: environment,
            allowNetwork: allowNetwork,
            limits: limits ?? RuntimeExecutionLimits()
        )
    }

    // MARK: - TypeScript Compilation Only

    func compileTypeScript(
        source: String,
        context: HanlinHostCallContext
    ) async throws -> TypeScriptCompilationResult {
        try checkAvailability(for: .typeScript)
        try await checkCapability(for: .typeScript, in: context)

        return try await core.typeScript.compile(source: source)
    }

    // MARK: - Validation Helpers

    private func checkAvailability(for kind: RuntimeKind) throws {
        guard availability.isAvailable(kind) else {
            throw HanlinHostServiceError.runtimeDisabledByUser(kind)
        }
    }

    private func checkCapability(for kind: RuntimeKind, in context: HanlinHostCallContext) async throws {
        let capID: String
        switch kind {
        case .node:
            capID = "runtime.node"
        case .localPython:
            capID = "runtime.python"
        case .typeScript:
            capID = "runtime.typescript"
        case .javaScriptCore:
            capID = "runtime.javascript"
        case .shell:
            capID = "runtime.shell"
        }

        let result = await HanlinHostCapabilityAuthority.shared.authorize(capability: capID, context: context)
        guard result == .allowed else {
            throw HanlinHostServiceError.capabilityNotGranted(capID)
        }
    }

    private func deriveWorkspace(for context: HanlinHostCallContext) throws -> URL {
        try RuntimeFileLayout.default.workspace(
            client: .executions,
            identifier: context.runtimeWorkspaceIdentifier
        )
    }
}
