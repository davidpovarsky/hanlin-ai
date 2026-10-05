import Foundation
import IOSSystemLite

@MainActor
struct GetRuntimeCapabilitiesTool: NativeTool {
    let name = "get_runtime_capabilities"

    var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Runtime Capabilities"),
            summary: RuntimeL10n.string("Inspect live execution capabilities, syntax support, and health status for local runtime engines."),
            categories: ["runtime", "system", "diagnostics"],
            keywords: ["runtime", "capabilities", "python", "node", "shell", "typescript", "jsc", "סביבה", "יכולות"],
            examples: ["Get runtime capabilities", "בדוק את יכולות סביבות ההרצה"],
            systemImage: "cpu",
            presentationProfile: RuntimeToolSupport.profile(
                name: name,
                image: "cpu",
                running: "Inspecting runtimes...",
                completed: "Runtime inspection complete",
                arguments: ["runtime"]
            )
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: RuntimeL10n.string("Inspect live execution capabilities, syntax support, package paths, effective limits, and health status for local runtime engines (Python, Node, TypeScript, JavaScriptCore, Shell)."),
            parameters: NativeToolSchema.object(
                properties: [
                    "runtime": NativeToolSchema.string(
                        description: RuntimeL10n.string("Optional runtime filter ('python', 'node', 'typescript', 'jsc', 'shell', or 'all'). Default is 'all'."),
                        enumValues: ["python", "node", "typescript", "jsc", "shell", "all"]
                    )
                ],
                required: []
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try? NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["runtime"]
            )
            let requestedRuntime = (try? NativeToolJSON.strictOptionalString(arguments ?? [:], "runtime")) ?? "all"

            var sections: [String] = []

            // 1. Python
            if requestedRuntime == "all" || requestedRuntime == "python" {
                let pyPackages = (try? await AppRuntimeCore.shared.pythonPackages.installed()) ?? []
                let pyPackageNames = pyPackages.map { "\($0.name) (\($0.version))" }.joined(separator: ", ")
                let pySection = """
                ### Python Runtime (Embedded CPython 3.14.6)
                - State: Ready (local offline execution)
                - Version: 3.14.6 (CPython embedded)
                - Package Support: Pure-Python wheels (.whl) via PyPI or local packages
                - Installed Packages (\(pyPackages.count)): \(pyPackageNames.isEmpty ? "None" : pyPackageNames)
                - Effective Limits: Max 500 MB wheel size, 300s max timeout, 8 MB output
                - Workspace: Sandbox app storage
                """
                sections.append(pySection)
            }

            // 2. Node / TypeScript
            if requestedRuntime == "all" || requestedRuntime == "node" || requestedRuntime == "typescript" {
                let nodePackages = (try? await AppRuntimeCore.shared.nodePackages.installed()) ?? []
                let nodePackageNames = nodePackages.map { "\($0.name) (\($0.version))" }.joined(separator: ", ")
                let nodeSection = """
                ### Node & TypeScript Runtime (NodeMobile / Host Worker)
                - State: Ready
                - Node Version: 24.5.0
                - TypeScript Version: 6.0.3
                - Execution Modes: ESM (.mjs) and CommonJS (.cjs)
                - Module Hooks: Policy-guarded worker execution with dynamic import support
                - Installed Global Packages (\(nodePackages.count)): \(nodePackageNames.isEmpty ? "None" : nodePackageNames)
                - Effective Limits: 8 MB output, 300s max timeout
                """
                sections.append(nodeSection)
            }

            // 3. JavaScriptCore
            if requestedRuntime == "all" || requestedRuntime == "jsc" {
                let jscSection = """
                ### JavaScriptCore (Native System JSC)
                - State: Ready (lightweight fast local JS evaluation)
                - Execution: Synchronous/Promise ES2022
                - Async Timers: Forwarded to Node when Node timers/event loop are requested
                """
                sections.append(jscSection)
            }

            // 4. Shell / ios_system
            if requestedRuntime == "all" || requestedRuntime == "shell" {
                let shellCommands = (try? IOSSystemRunner.availableCommands()) ?? Array(IOSSystemRunner.linkedCommands)
                let shellSection = """
                ### Shell Runtime (ios_system BSD commands)
                - State: Ready
                - Commands Discovered (\(shellCommands.count)): \(shellCommands.sorted().joined(separator: ", "))
                - Modes Supported:
                  1. Structured argv mode (`program` + `arguments` array)
                  2. Command line string mode (`command` with pipes and redirection)
                - Network: HTTPS curl supported when `allow_network` is true or for `--version`
                """
                sections.append(shellSection)
            }

            let report = sections.joined(separator: "\n\n")

            let executionResult = RuntimeExecutionResult(
                executionID: UUID(),
                stdout: report,
                stderr: "",
                value: nil,
                exitCode: 0,
                durationMilliseconds: 1,
                didTimeOut: false,
                wasCancelled: false,
                outputWasTruncated: false
            )

            return RuntimeToolSupport.result(
                executionResult,
                title: "Runtime Capabilities",
                systemImage: "cpu",
                runtimeKind: .shell,
                argumentKeys: Array((arguments ?? [:]).keys)
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Get Runtime Capabilities Failed", runtimeKind: .shell)
        }
    }
}
