import Foundation

struct ExecuteTypeScriptTool: NativeTool {
    let name = "execute_typescript_code"

    var catalogEntry: NativeToolCatalogEntry {
        .init(name: name, title: RuntimeL10n.string("TypeScript"), summary: RuntimeL10n.string("Compile with Hanlin's pinned TypeScript compiler and optionally execute with embedded Node."), categories: ["runtime", "code", "typescript"], keywords: ["typescript", "tsc", "node"], examples: ["Compile and run this TypeScript"], systemImage: "t.square", presentationProfile: RuntimeToolSupport.profile(name: name, image: "t.square", running: "Compiling TypeScript", completed: "TypeScript completed", arguments: ["source", "file_name", "compile_only"]))
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(name: name, description: RuntimeL10n.string("Compile TypeScript with Hanlin's pinned compiler. compile_only=true returns compiler diagnostics and emitted JavaScript without executing the output. compile_only=false executes emitted JavaScript through embedded Node, so Node availability and runtime permission are required. Installed npm packages resolve through the embedded Node package location."), parameters: NativeToolSchema.object(properties: [
            "source": NativeToolSchema.string(description: RuntimeL10n.string("TypeScript source code.")),
            "file_name": NativeToolSchema.string(description: RuntimeL10n.string("Virtual TypeScript file name.")),
            "compile_only": ["type": "boolean", "description": RuntimeL10n.string("Return diagnostics and emitted JavaScript without execution.")],
            "timeout_seconds": NativeToolSchema.integer(description: RuntimeL10n.string("Node execution timeout in whole seconds; defaults to 30 and applies when compile_only is false."), minimum: 1, maximum: 300)
        ], required: ["source"]))
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        guard await isAllowedByCatalog() else {
            return RuntimeToolSupport.failure(
                HanlinHostServiceError.capabilityNotGranted("tool.\(name)"),
                title: "TypeScript disabled",
                runtimeKind: .typeScript
            )
        }
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["source", "file_name", "compile_only", "timeout_seconds"]
            )
            let source = try NativeToolJSON.strictRequiredString(arguments, "source")
            let compileOnly = try NativeToolJSON.strictBool(arguments, "compile_only")
            guard compileOnly || RuntimeAvailabilityStore.shared.isAvailable(.node) else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.runtimeUnavailable(.node),
                    title: "Node unavailable",
                    runtimeKind: .node
                )
            }
            let environment = try await AppRuntimeCore.shared.environment.resolved(scopes: [.shared, .node])
            let result = try await AgentHostServicesAdapter.compileAndExecuteTypeScript(
                source: source,
                fileName: try NativeToolJSON.strictOptionalString(arguments, "file_name") ?? "main.ts",
                compileOnly: compileOnly,
                environment: environment,
                limits: try RuntimeToolSupport.limits(arguments)
            )
            if let execution = result.execution {
                return RuntimeToolSupport.result(
                    execution,
                    title: "TypeScript",
                    systemImage: "t.square",
                    runtimeKind: .typeScript,
                    argumentKeys: Array(arguments.keys)
                )
            }
            let diagnostics = result.compilation.diagnostics.map { "TS\($0.code): \($0.message)" }.joined(separator: "\n")
            let emitted = result.compilation.javaScript ?? ""
            let body = [diagnostics, emitted].filter { !$0.isEmpty }.joined(separator: "\n\n")
            return NativeToolResult(
                modelText: body,
                userText: body,
                uiBlocks: [.init(type: result.compilation.succeeded ? .card : .error, title: RuntimeL10n.string("TypeScript compilation"), body: body, systemImage: "t.square")],
                outcome: result.compilation.succeeded ? .succeeded : .failed,
                diagnostics: NativeToolExecutionDiagnostics(
                    backendRoute: "host-services/runtime-broker/typescript",
                    source: "native",
                    runtimeKind: RuntimeKind.typeScript.rawValue,
                    failureCategory: result.compilation.succeeded ? nil : NativeToolExecutionOutcome.failed.rawValue,
                    argumentKeys: Array(arguments.keys).sorted(),
                    capabilityDecision: "allowed",
                    availabilityDecision: "allowed",
                    callerIdentity: "agent"
                )
            )
        } catch { return RuntimeToolSupport.failure(error, title: "TypeScript failed", runtimeKind: .typeScript) }
    }

    private func isAllowedByCatalog() async -> Bool {
        await MainActor.run {
            NativeToolCatalog.shared.ensureBuiltinsRegistered()
            guard let entry = NativeToolCatalog.shared.entry(named: name) else { return true }
            return NativeToolCatalog.shared.isEffectivelyEnabled(entry)
        }
    }
}
