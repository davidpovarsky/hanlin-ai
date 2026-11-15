import Foundation

@MainActor
struct GetRuntimeJobTool: NativeTool {
    let name = "get_runtime_job"
    var catalogEntry: NativeToolCatalogEntry {
        .init(name: name, title: "Runtime job", summary: "Inspect or cancel an existing runtime job and read retained output pages.", categories: ["runtime", "diagnostics"], keywords: ["job", "output", "cancel", "progress"], examples: ["Read output from a runtime job"], systemImage: "list.bullet.rectangle", presentationProfile: RuntimeToolSupport.profile(name: name, image: "list.bullet.rectangle", running: "Reading runtime job...", completed: "Runtime job inspected", arguments: ["operation", "runtime", "job_id"]))
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(name: name, description: "Read a retained Node/TypeScript, Python, Shell or JavaScriptCore job, request cancellation, or read lossless stdout/stderr byte pages. Status includes a retained input size/hash receipt when present, without injecting source or environment into the conversation. Cancellation remains requested until the actual worker/native call stops. Queued Shell and JavaScriptCore calls can be cancelled; running calls must finish naturally. Reading never repeats program side effects.", parameters: NativeToolSchema.object(properties: [
            "operation": NativeToolSchema.string(description: "Operation", enumValues: ["status", "read", "cancel"]),
            "runtime": NativeToolSchema.string(description: "Execution engine; running jsc cannot be killed safely and must return naturally", enumValues: ["node", "python", "shell", "jsc"]),
            "job_id": NativeToolSchema.string(description: "UUID returned by runtime execution/progress"),
            "channel": NativeToolSchema.string(description: "Output channel for read", enumValues: ["stdout", "stderr"]),
            "offset": NativeToolSchema.integer(description: "Byte offset; starts at zero", minimum: 0),
            "limit": NativeToolSchema.integer(description: "Bytes per page (transport limit 65536, full files retained)", minimum: 1, maximum: 65536)
        ], required: ["operation", "runtime", "job_id"]))
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(from: argumentsJSON, allowedKeys: ["operation", "runtime", "job_id", "channel", "offset", "limit"])
            let operation = try NativeToolJSON.strictRequiredString(arguments, "operation")
            let runtime = try NativeToolJSON.strictRequiredString(arguments, "runtime")
            guard ["status", "read", "cancel"].contains(operation), ["node", "python", "shell", "jsc"].contains(runtime),
                  let id = UUID(uuidString: try NativeToolJSON.strictRequiredString(arguments, "job_id")) else { throw RuntimeCoreError.invalidRequest("Invalid runtime job request.") }
            let kind: RuntimeKind = runtime == "node" ? .node : runtime == "shell" ? .shell : runtime == "jsc" ? .javaScriptCore : .localPython
            let core = AppRuntimeCore.shared
            if kind != .node { try await core.jobs.recoverInterrupted(kind) }
            guard var record = try await core.jobs.snapshot(id: id, kind: kind) else { throw RuntimeCoreError.invalidRequest("Job not found.") }
            if operation == "cancel", !record.state.isTerminal {
                if kind == .node {
                    await core.node.cancelExecution(id: id)
                } else if kind == .shell {
                    try await core.shell.cancel(id: id)
                } else if kind == .javaScriptCore {
                    try await core.javaScriptCore.cancel(id: id)
                } else {
                    PythonRuntimeBridge.cancel(id: id)
                    try await core.jobs.requestCancellation(id: id, kind: kind)
                }
                record = try await core.jobs.snapshot(id: id, kind: kind) ?? record
            }
            if kind == .node, await core.node.hasLaunched() {
                record = try await core.node.existingExecution(id: id) ?? record
            } else if kind != .node {
                record = try await core.jobs.refresh(id: id, kind: kind) ?? record
            }
            let text: String
            if operation == "read" {
                let channel = try NativeToolJSON.strictOptionalString(arguments, "channel") ?? "stdout"
                let offset = try NativeToolJSON.strictInt(arguments, "offset", default: 0, range: 0...Int.max)
                let limit = try NativeToolJSON.strictInt(arguments, "limit", default: 4096, range: 1...65536)
                let page = try await core.jobs.output(id: id, kind: kind, channel: channel, offset: Int64(offset), limit: limit)
                text = String(decoding: try JSONSerialization.data(withJSONObject: page, options: [.sortedKeys]), as: UTF8.self)
            } else {
                // Status does not inject large logs into the model context. Read pages explicitly.
                if kind == .node, !(await core.node.hasLaunched()), !record.state.isTerminal {
                    record.state = .interrupted
                    record.error = "The Node host is not running in this app session. Partial output is retained."
                }
                var status: [String: Any] = ["job_id": id.uuidString, "state": record.state.rawValue, "cancellation_requested": record.cancellationRequested, "stdout_bytes": record.stdoutBytes, "stderr_bytes": record.stderrBytes]
                if let input = record.inputArtifact {
                    status["input_artifact"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input))
                }
                if let error = record.error { status["error"] = AgentDiagnosticsRedactor.sanitize(error) }
                text = String(decoding: try JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]), as: UTF8.self)
            }
            return NativeToolResult(modelText: text, userText: text, outcome: .succeeded)
        } catch { return RuntimeToolSupport.failure(error, title: "Runtime job request failed") }
    }
}
