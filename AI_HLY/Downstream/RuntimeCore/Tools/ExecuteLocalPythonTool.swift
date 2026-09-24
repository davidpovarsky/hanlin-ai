import Foundation

struct ExecuteLocalPythonTool: NativeTool {
    let name = "execute_local_python_code"

    var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Local Python"),
            summary: RuntimeL10n.string("Run CPython 3.14.6 locally on this device, including offline."),
            categories: ["runtime", "code", "python"],
            keywords: ["python", "local", "offline", "קוד", "פייתון"],
            examples: ["Run this Python code locally", "הרץ את קוד הפייתון מקומית"],
            systemImage: "chevron.left.forwardslash.chevron.right",
            presentationProfile: RuntimeToolSupport.profile(name: name, image: "chevron.left.forwardslash.chevron.right", running: "Running local Python", completed: "Local Python completed", arguments: ["source"])
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(name: name, description: RuntimeL10n.string("Run normal Python source with embedded CPython 3.14.6 on this device. It works offline and does not use the remote Piston service. Script arguments become sys.argv entries. Packages installed by Hanlin's local Python package manager are available; iOS permits pure-Python wheels, not dynamically installed native-extension wheels or source builds."), parameters: NativeToolSchema.object(properties: [
            "source": NativeToolSchema.string(description: RuntimeL10n.string("Python source code to run locally.")),
            "arguments": NativeToolSchema.stringArray(description: RuntimeL10n.string("Optional script arguments exposed through sys.argv.")),
            "timeout_seconds": NativeToolSchema.integer(description: RuntimeL10n.string("Bounded execution timeout in whole seconds; defaults to 30."), minimum: 1, maximum: 300)
        ], required: ["source"]))
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        guard await isAllowedByCatalog() else {
            return RuntimeToolSupport.failure(
                HanlinHostServiceError.capabilityNotGranted("tool.\(name)"),
                title: "Local Python disabled",
                runtimeKind: .localPython
            )
        }
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["source", "arguments", "timeout_seconds"]
            )
            let source = try NativeToolJSON.strictRequiredString(arguments, "source")
            let argv = try NativeToolJSON.strictStringArray(arguments, "arguments")
            let environment = try await AppRuntimeCore.shared.environment.resolved(scopes: [.shared, .python])
            let result = try await AgentHostServicesAdapter.executeRuntime(
                .localPython,
                source: source,
                arguments: argv,
                environment: environment,
                limits: try RuntimeToolSupport.limits(arguments)
            )
            return RuntimeToolSupport.result(
                result,
                title: "Local Python",
                systemImage: "chevron.left.forwardslash.chevron.right",
                runtimeKind: .localPython,
                argumentKeys: Array(arguments.keys)
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Local Python failed", runtimeKind: .localPython)
        }
    }
}
