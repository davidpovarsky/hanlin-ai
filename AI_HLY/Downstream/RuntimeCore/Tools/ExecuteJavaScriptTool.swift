import Foundation

struct ExecuteJavaScriptTool: NativeTool {
    let name = "execute_javascript_code"

    var catalogEntry: NativeToolCatalogEntry {
        .init(name: name, title: RuntimeL10n.string("JavaScript"), summary: RuntimeL10n.string("Run JavaScript with JavaScriptCore or the embedded Node worker runtime."), categories: ["runtime", "code", "javascript"], keywords: ["javascript", "node", "jscore"], examples: ["Evaluate this JavaScript"], systemImage: "curlybraces", presentationProfile: RuntimeToolSupport.profile(name: name, image: "curlybraces", running: "Running JavaScript", completed: "JavaScript completed", arguments: ["source", "runtime"]))
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(name: name, description: RuntimeL10n.string("Run JavaScript on-device. Auto selects JavaScriptCore for simple code and Node for modules or Node APIs."), parameters: NativeToolSchema.object(properties: [
            "source": NativeToolSchema.string(description: RuntimeL10n.string("JavaScript source code.")),
            "runtime": NativeToolSchema.string(description: RuntimeL10n.string("Runtime selection."), enumValues: ["auto", "jscore", "node"]),
            "arguments": ["type": "array", "items": ["type": "string"]],
            "timeout_seconds": NativeToolSchema.number(description: RuntimeL10n.string("Timeout from 1 to 300 seconds."), minimum: 1, maximum: 300)
        ], required: ["source"]))
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.dictionary(from: argumentsJSON)
            let source = try NativeToolJSON.requiredString(arguments, "source")
            let requested = NativeToolJSON.optionalString(arguments, "runtime") ?? "auto"
            let argv = arguments["arguments"] as? [String] ?? []
            let useNode = requested == "node" || (requested == "auto" && Self.requiresNode(source))
            let layout = RuntimeFileLayout.default
            let workspace = try layout.workspace(client: .tools, identifier: name)
            let scope: RuntimeEnvironmentScope = useNode ? .node : .javaScriptCore
            let environment = try await AppRuntimeCore.shared.environment.resolved(scopes: [.shared, scope])
            let request = RuntimeExecutionRequest(source: source, arguments: argv, workspace: workspace, environment: environment, limits: RuntimeToolSupport.limits(arguments))
            let result = useNode ? try await AppRuntimeCore.shared.node.executeJavaScript(request) : try await AppRuntimeCore.shared.javaScriptCore.execute(request)
            return RuntimeToolSupport.result(result, title: useNode ? "Node.js" : "JavaScriptCore", systemImage: "curlybraces")
        } catch { return RuntimeToolSupport.failure(error, title: "JavaScript failed") }
    }

    private static func requiresNode(_ source: String) -> Bool {
        source.range(of: #"\b(process|Buffer|require|module\.exports|import\s|export\s|node:)"#, options: .regularExpression) != nil
    }
}
