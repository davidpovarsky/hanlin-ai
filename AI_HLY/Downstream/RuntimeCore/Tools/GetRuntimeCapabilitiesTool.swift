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
                        description: RuntimeL10n.string("Optional runtime filter ('python', 'node', 'typescript', 'jsc', 'shell', 'mcp', or 'all'). Default is 'all'."),
                        enumValues: ["python", "node", "typescript", "jsc", "shell", "mcp", "all"]
                    )
                ],
                required: []
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(from: argumentsJSON, allowedKeys: ["runtime"])
            let requestedRuntime = try NativeToolJSON.strictOptionalString(arguments, "runtime") ?? "all"
            let kinds: [String: RuntimeKind] = ["node": .node, "typescript": .typeScript, "python": .localPython, "jsc": .javaScriptCore, "shell": .shell]
            guard requestedRuntime == "all" || requestedRuntime == "mcp" || kinds[requestedRuntime] != nil else {
                throw RuntimeCoreError.invalidRequest("Unknown runtime: \(requestedRuntime)")
            }
            let snapshots = await AppRuntimeCore.shared.snapshots()
            let selected = requestedRuntime == "all" ? snapshots : snapshots.filter { $0.kind == kinds[requestedRuntime] }
            let contract = RuntimeCapabilityContract(snapshots: selected)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var report = String(decoding: try encoder.encode(contract), as: UTF8.self)
            if requestedRuntime == "all" || requestedRuntime == "mcp" || requestedRuntime == "node" || requestedRuntime == "typescript" {
                do {
                    if let live = try await AppRuntimeCore.shared.node.capabilityReportIfLaunched() {
                        report += "\nNode live capabilities:\n" + String(decoding: try encoder.encode(live), as: UTF8.self)
                    }
                } catch {
                    report += "\nNode live capability query unavailable: \(error.localizedDescription)"
                }
                let provider = MCPRuntimeProvider.shared
                await provider.loadIfNeeded(startHost: false)
                report += "\nMCP enabled: \(provider.configuration.isEnabled); host: \(provider.runtimeSnapshot.state.rawValue); workers: \(provider.runtimeSnapshot.activeWorkerCount)"
            }

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
                argumentKeys: Array(arguments.keys)
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Get Runtime Capabilities Failed", runtimeKind: .shell)
        }
    }
}
