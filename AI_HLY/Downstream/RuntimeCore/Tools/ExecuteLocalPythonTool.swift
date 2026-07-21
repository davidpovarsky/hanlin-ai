import Foundation

struct ExecuteLocalPythonTool: NativeTool {
    let name = "execute_local_python_code"

    var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Local Python"),
            summary: RuntimeL10n.string("Run Python locally with the embedded offline interpreter."),
            categories: ["runtime", "code", "python"],
            keywords: ["python", "local", "offline", "קוד", "פייתון"],
            examples: ["Run this Python code locally", "הרץ את קוד הפייתון מקומית"],
            systemImage: "chevron.left.forwardslash.chevron.right",
            presentationProfile: RuntimeToolSupport.profile(name: name, image: "chevron.left.forwardslash.chevron.right", running: "Running local Python", completed: "Local Python completed", arguments: ["source"])
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(name: name, description: RuntimeL10n.string("Run Python code on-device with embedded CPython. This is separate from the remote Piston tool."), parameters: NativeToolSchema.object(properties: [
            "source": NativeToolSchema.string(description: RuntimeL10n.string("Python source code.")),
            "arguments": ["type": "array", "items": ["type": "string"], "description": RuntimeL10n.string("Optional script arguments.")],
            "timeout_seconds": NativeToolSchema.number(description: RuntimeL10n.string("Timeout from 1 to 300 seconds."), minimum: 1, maximum: 300)
        ], required: ["source"]))
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.dictionary(from: argumentsJSON)
            let source = try NativeToolJSON.requiredString(arguments, "source")
            let argv = arguments["arguments"] as? [String] ?? []
            let layout = RuntimeFileLayout.default
            let workspace = try layout.workspace(client: .tools, identifier: name)
            let environment = try await AppRuntimeCore.shared.environment.resolved(scopes: [.shared, .python])
            let result = try await AppRuntimeCore.shared.python.execute(.init(source: source, arguments: argv, workspace: workspace, environment: environment, limits: RuntimeToolSupport.limits(arguments)))
            return RuntimeToolSupport.result(result, title: "Local Python", systemImage: "chevron.left.forwardslash.chevron.right")
        } catch { return RuntimeToolSupport.failure(error, title: "Local Python failed") }
    }
}
