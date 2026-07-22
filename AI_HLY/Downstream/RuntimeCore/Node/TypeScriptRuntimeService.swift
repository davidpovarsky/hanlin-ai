import Foundation

struct TypeScriptExecutionResult: Sendable {
    let compilation: TypeScriptCompilationResult
    let execution: RuntimeExecutionResult?
}

actor TypeScriptRuntimeService {
    private let node: NodeRuntimeService

    init(node: NodeRuntimeService) { self.node = node }

    func compile(source: String, fileName: String = "main.ts", tsconfig: [String: RuntimeJSONValue]? = nil) async throws -> TypeScriptCompilationResult {
        try await node.compileTypeScript(source: source, fileName: fileName, tsconfig: tsconfig)
    }

    func compileAndExecute(source: String, request: RuntimeExecutionRequest, fileName: String = "main.ts", tsconfig: [String: RuntimeJSONValue]? = nil, compileOnly: Bool = false) async throws -> TypeScriptExecutionResult {
        let compilation = try await compile(source: source, fileName: fileName, tsconfig: tsconfig)
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
        return TypeScriptExecutionResult(compilation: compilation, execution: try await node.executeJavaScript(executionRequest))
    }

    func compileProject(workspace: URL, arguments: [String]) async throws -> TypeScriptProjectCompilationResult {
        try await node.compileTypeScriptProject(workspace: workspace, arguments: arguments)
    }
}
