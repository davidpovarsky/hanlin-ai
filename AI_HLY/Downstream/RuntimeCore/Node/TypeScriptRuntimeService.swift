import Foundation

struct TypeScriptExecutionResult: Sendable {
    let compilation: TypeScriptCompilationResult
    let execution: RuntimeExecutionResult?
}

actor TypeScriptRuntimeService {
    private let node: NodeRuntimeService
    private var snapshotValue = RuntimeSnapshot.stopped(.typeScript)
    private var activeOperations = 0
    private var stopGeneration: UInt64 = 0
    private var stopRequested = false
    private var compilerObserved = false
    private var activeExecutions: Set<UUID> = []

    init(node: NodeRuntimeService) { self.node = node }

    func snapshot() async -> RuntimeSnapshot {
        let dependency = await node.snapshot()
        var value = snapshotValue
        if value.state == .ready || value.state == .executing,
           [.failed, .stopped, .unavailable, .appRestartRequired].contains(dependency.state) {
            value.state = dependency.state
            value.lastErrorCode = dependency.lastErrorCode
            value.lastDiagnostic = dependency.lastDiagnostic
        }
        return value
    }

    func healthCheck() async throws -> RuntimeSnapshot {
        let result = try await compile(source: "export const hanlinCompilerHealth: number = 1;", fileName: "hanlin-compiler-health.ts")
        guard result.succeeded else {
            let error = RuntimeCoreError.runtimeFailure("The actual TypeScript compiler health source failed.")
            failed(error)
            throw error
        }
        snapshotValue.lastHealthCheck = .now
        return await snapshot()
    }

    func stop() async -> RuntimeSnapshot {
        stopGeneration &+= 1
        stopRequested = true
        snapshotValue.state = activeOperations == 0 ? .stopped : .executing
        snapshotValue.lastDiagnostic = activeOperations == 0 ? nil : "Stop requested. Active compilation must return; managed Node executions receive cancellation and no compiled result starts new work."
        for id in Array(activeExecutions) { await node.cancelExecution(id: id) }
        return snapshotValue
    }

    private func begin() throws -> UInt64 {
        try Task.checkCancellation()
        try RuntimeUserOperation.current?.checkInterruption()
        activeOperations += 1
        stopRequested = false
        snapshotValue.state = .executing
        snapshotValue.activeExecutionCount = activeOperations
        snapshotValue.lastErrorCode = nil
        snapshotValue.lastDiagnostic = nil
        return stopGeneration
    }

    private func end() {
        activeOperations -= 1
        snapshotValue.activeExecutionCount = activeOperations
        if activeOperations == 0, snapshotValue.state != .failed {
            snapshotValue.state = stopRequested || !compilerObserved ? .stopped : .ready
        }
    }

    private func check(_ generation: UInt64) throws {
        guard generation == stopGeneration else { throw CancellationError() }
        try Task.checkCancellation()
        try RuntimeUserOperation.current?.checkInterruption()
    }

    private func observed(version: String?) {
        compilerObserved = true
        snapshotValue.version = version
        snapshotValue.source = "Actual Host TypeScript compiler"
    }

    private func failed(_ error: any Error) {
        guard !Task.isCancelled, RuntimeUserOperation.current?.snapshot.reason == nil,
              !(error is CancellationError), !(error is RuntimeJobInterruptionError),
              !(error is RuntimeOperationInterruptionError) else { return }
        snapshotValue.state = .failed
        snapshotValue.lastErrorCode = "typescript_operation_failed"
        snapshotValue.lastDiagnostic = error.localizedDescription
    }

    func compile(source: String, fileName: String = "main.ts", tsconfig: [String: RuntimeJSONValue]? = nil) async throws -> TypeScriptCompilationResult {
        let generation = try begin()
        defer { end() }
        do {
            let result = try await node.compileTypeScript(source: source, fileName: fileName, tsconfig: tsconfig)
            observed(version: result.compilerVersion)
            try check(generation)
            return result
        } catch { failed(error); throw error }
    }

    func compileAndExecute(source: String, request: RuntimeExecutionRequest, fileName: String = "main.ts", tsconfig: [String: RuntimeJSONValue]? = nil, compileOnly: Bool = false) async throws -> TypeScriptExecutionResult {
        let generation = try begin()
        defer { end() }
        do {
            let compilation = try await node.compileTypeScript(source: source, fileName: fileName, tsconfig: tsconfig)
            observed(version: compilation.compilerVersion)
            try check(generation)
            guard compilation.succeeded, let javaScript = compilation.javaScript else { return TypeScriptExecutionResult(compilation: compilation, execution: nil) }
            if compileOnly { return TypeScriptExecutionResult(compilation: compilation, execution: nil) }
            let executionRequest = RuntimeExecutionRequest(
                id: request.id,
                source: javaScript + (compilation.sourceMap.map { "\n//# sourceMappingURL=data:application/json;base64,\(Data($0.utf8).base64EncodedString())" } ?? ""),
                arguments: request.arguments,
                workspace: request.workspace,
                environment: request.environment,
                limits: request.limits
            )
            activeExecutions.insert(request.id)
            defer { activeExecutions.remove(request.id) }
            let execution = try await node.executeJavaScript(executionRequest)
            // Once started, the Node job owns cancellation and its complete
            // receipt. A later stop must not discard retained output metadata.
            return TypeScriptExecutionResult(compilation: compilation, execution: execution)
        } catch { failed(error); throw error }
    }

    func compileProject(workspace: URL, arguments: [String]) async throws -> TypeScriptProjectCompilationResult {
        let generation = try begin()
        defer { end() }
        do {
            let result = try await node.compileTypeScriptProject(workspace: workspace, arguments: arguments)
            observed(version: result.compilerVersion)
            try check(generation)
            return result
        } catch { failed(error); throw error }
    }
}
