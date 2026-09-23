import Foundation

struct ExecuteJavaScriptTool: NativeTool {
    let name = "execute_javascript_code"

    var catalogEntry: NativeToolCatalogEntry {
        .init(name: name, title: RuntimeL10n.string("JavaScript"), summary: RuntimeL10n.string("Run JavaScript with JavaScriptCore or the embedded Node worker runtime."), categories: ["runtime", "code", "javascript"], keywords: ["javascript", "node", "jscore"], examples: ["Evaluate this JavaScript"], systemImage: "curlybraces", presentationProfile: RuntimeToolSupport.profile(name: name, image: "curlybraces", running: "Running JavaScript", completed: "JavaScript completed", arguments: ["source", "runtime"]))
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(name: name, description: RuntimeL10n.string("Run JavaScript on-device. 'jscore' is in-process Apple JavaScriptCore for simple synchronous code: it has no Node built-ins, require(), process, Buffer, npm packages, browser DOM, setTimeout, or setInterval. 'node' uses Hanlin's embedded Node runtime and supports permitted Node APIs, async/Promises/timers, and packages installed through NodePackageManager. 'auto' selects Node for Node/module syntax or whenever timeout_seconds is supplied; otherwise it selects JavaScriptCore."), parameters: NativeToolSchema.object(properties: [
            "source": NativeToolSchema.string(description: RuntimeL10n.string("JavaScript source code.")),
            "runtime": NativeToolSchema.string(description: RuntimeL10n.string("Runtime selection; defaults to auto."), enumValues: ["auto", "jscore", "node"]),
            "arguments": NativeToolSchema.stringArray(description: RuntimeL10n.string("Arguments exposed to the selected runtime.")),
            "timeout_seconds": NativeToolSchema.integer(description: RuntimeL10n.string("Node execution timeout in whole seconds. Supplying it with auto selects Node; explicit jscore rejects it because JavaScriptCore cannot be interrupted truthfully."), minimum: 1, maximum: 300)
        ], required: ["source"]))
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["source", "runtime", "arguments", "timeout_seconds"]
            )
            let source = try NativeToolJSON.strictRequiredString(arguments, "source")
            let requested = try NativeToolJSON.strictOptionalString(arguments, "runtime") ?? "auto"
            guard ["auto", "jscore", "node"].contains(requested) else {
                throw NativeToolJSON.JSONError.invalidValue(
                    key: "runtime",
                    description: "expected auto, jscore, or node"
                )
            }
            if requested == "jscore", arguments["timeout_seconds"] != nil {
                throw NativeToolJSON.JSONError.invalidValue(
                    key: "timeout_seconds",
                    description: "explicit JavaScriptCore execution does not support interruption; use node or auto"
                )
            }
            let argv = try NativeToolJSON.strictStringArray(arguments, "arguments")
            let useNode = requested == "node"
                || (requested == "auto" && (Self.requiresNode(source) || arguments["timeout_seconds"] != nil))
            let scope: RuntimeEnvironmentScope = useNode ? .node : .javaScriptCore
            let environment = try await AppRuntimeCore.shared.environment.resolved(scopes: [.shared, scope])
            let kind: RuntimeKind = useNode ? .node : .javaScriptCore
            let result = try await AgentHostServicesAdapter.executeRuntime(
                kind,
                source: source,
                arguments: argv,
                environment: environment,
                limits: try RuntimeToolSupport.limits(arguments)
            )
            return RuntimeToolSupport.result(
                result,
                title: useNode ? "Node.js" : "JavaScriptCore",
                systemImage: "curlybraces",
                runtimeKind: kind,
                argumentKeys: Array(arguments.keys)
            )
        } catch { return RuntimeToolSupport.failure(error, title: "JavaScript failed") }
    }

    private static func requiresNode(_ source: String) -> Bool {
        source.range(of: #"\b(process|Buffer|require|module\.exports|import\s|export\s|node:)"#, options: .regularExpression) != nil
    }
}
