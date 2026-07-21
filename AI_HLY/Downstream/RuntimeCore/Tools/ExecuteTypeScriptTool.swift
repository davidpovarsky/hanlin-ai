import Foundation

struct ExecuteTypeScriptTool: NativeTool {
    let name = "execute_typescript_code"

    var catalogEntry: NativeToolCatalogEntry {
        .init(name: name, title: RuntimeL10n.string("TypeScript"), summary: RuntimeL10n.string("Compile TypeScript 6 and run the emitted JavaScript with Node."), categories: ["runtime", "code", "typescript"], keywords: ["typescript", "tsc", "node"], examples: ["Compile and run this TypeScript"], systemImage: "t.square", presentationProfile: RuntimeToolSupport.profile(name: name, image: "t.square", running: "Compiling TypeScript", completed: "TypeScript completed", arguments: ["source", "compile_only"]))
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(name: name, description: RuntimeL10n.string("Compile TypeScript with the pinned compiler and optionally execute it through the embedded Node runtime."), parameters: NativeToolSchema.object(properties: [
            "source": NativeToolSchema.string(description: RuntimeL10n.string("TypeScript source code.")),
            "file_name": NativeToolSchema.string(description: RuntimeL10n.string("Virtual TypeScript file name.")),
            "compile_only": ["type": "boolean", "description": RuntimeL10n.string("Return diagnostics and emitted JavaScript without execution.")],
            "timeout_seconds": NativeToolSchema.number(description: RuntimeL10n.string("Execution timeout from 1 to 300 seconds."), minimum: 1, maximum: 300)
        ], required: ["source"]))
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.dictionary(from: argumentsJSON)
            let source = try NativeToolJSON.requiredString(arguments, "source")
            let compileOnly = NativeToolJSON.bool(arguments, "compile_only")
            let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: name)
            let environment = try await AppRuntimeCore.shared.environment.resolved(scopes: [.shared, .node])
            let request = RuntimeExecutionRequest(source: source, workspace: workspace, environment: environment, limits: RuntimeToolSupport.limits(arguments))
            let result = try await AppRuntimeCore.shared.typeScript.compileAndExecute(source: source, request: request, fileName: NativeToolJSON.optionalString(arguments, "file_name") ?? "main.ts", compileOnly: compileOnly)
            if let execution = result.execution { return RuntimeToolSupport.result(execution, title: "TypeScript", systemImage: "t.square") }
            let diagnostics = result.compilation.diagnostics.map { "TS\($0.code): \($0.message)" }.joined(separator: "\n")
            let emitted = result.compilation.javaScript ?? ""
            let body = [diagnostics, emitted].filter { !$0.isEmpty }.joined(separator: "\n\n")
            return NativeToolResult(modelText: body, userText: body, uiBlocks: [.init(type: result.compilation.succeeded ? .card : .error, title: RuntimeL10n.string("TypeScript compilation"), body: body, systemImage: "t.square")])
        } catch { return RuntimeToolSupport.failure(error, title: "TypeScript failed") }
    }
}
