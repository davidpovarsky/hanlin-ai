import Foundation

struct RuntimeCommandRequest: Decodable, Sendable {
    let id: UUID
    let parentExecutionID: UUID
    let command: String
    let arguments: [String]
    let cwd: String
    let environment: [String: String]
    let standardInputPath: String
    let cancellationRequested: Bool
    let engine: String?
    let entryPoint: String?
}

/// Reuses AppRuntimeCore's actors. There is no extra engine, HTTP server, OS
/// process emulation or implicit external service behind this adapter.
struct RuntimeCommandDispatcher: Sendable {
    let fileLayout: RuntimeFileLayout
    let python: PythonRuntimeService?
    let shell: ShellRuntimeService?

    func execute(_ request: RuntimeCommandRequest, node: NodeRuntimeService) async throws {
        let directory = fileLayout.root.appending(path: "jobs/node/\(request.parentExecutionID.uuidString.lowercased())/commands/\(request.id.uuidString.lowercased())")
        do {
            let directory = try fileLayout.validatedDescendant(directory, of: fileLayout.root)
            let input = try fileLayout.validatedDescendant(directory.appending(path: "stdin"), of: directory)
            guard input.path == URL(fileURLWithPath: request.standardInputPath).standardizedFileURL.path else { throw RuntimeCoreError.invalidPath }
            if request.cancellationRequested { throw CancellationError() }
            try Task.checkCancellation()
            let workspace = try fileLayout.validatedWorkspace(URL(fileURLWithPath: request.cwd, isDirectory: true))
            let environment = try RuntimePolicy.validatedEnvironment(request.environment)
            let result: RuntimeExecutionResult
            let engine = request.engine ?? (["node", "nodejs"].contains(request.command) ? "node" : ["python", "python3"].contains(request.command) ? "python" : "shell")
            switch engine {
            case "node", "python":
                if request.entryPoint == nil, ["--version", "-v"].contains(request.arguments.first ?? ""), engine == "node" {
                    result = try await node.executeJavaScript(RuntimeExecutionRequest(source: "console.log('v' + process.versions.node)", workspace: workspace, environment: environment))
                } else if request.entryPoint == nil, request.arguments.first == "--version", engine == "python", let python {
                    result = try await python.execute(RuntimeExecutionRequest(source: "import platform; print('Python ' + platform.python_version())", workspace: workspace, environment: environment))
                } else {
                    let script = request.entryPoint ?? request.arguments.first ?? ""
                    guard !script.isEmpty, !script.hasPrefix("-") else {
                        throw RuntimeCoreError.invalidRequest("This linked CLI adapter currently accepts a script file or --version; the requested CLI mode has not been implemented.")
                    }
                    let entry = URL(fileURLWithPath: script, relativeTo: workspace.appendingPathComponent("", isDirectory: true)).standardizedFileURL
                    let arguments = request.entryPoint == nil ? Array(request.arguments.dropFirst()) : request.arguments
                    if engine == "node" {
                        result = try await node.executeCLI(entryPoint: entry, arguments: arguments, workspace: workspace, environment: environment, standardInput: input)
                    } else if let python {
                        result = try await python.executeCLI(entryPoint: entry, arguments: arguments, workspace: workspace, environment: environment, standardInput: input)
                    } else { throw RuntimeCoreError.runtimeUnavailable(.localPython) }
                }
            case "shell":
                guard let shell else { throw RuntimeCoreError.runtimeUnavailable(.shell) }
                result = try await shell.execute(tokens: [request.command] + request.arguments, workspace: workspace,
                    environment: environment, allowNetwork: true, standardInputURL: input, id: request.id)
            default:
                throw RuntimeCoreError.invalidRequest("No linked command adapter is available for the requested engine.")
            }
            guard let output = result.outputFiles, let stdout = output["stdout"], let stderr = output["stderr"] else {
                throw RuntimeCoreError.runtimeFailure("The command did not retain its output artifacts.")
            }
            try writeResponse(directory: directory, exitCode: result.exitCode ?? 1,
                stdout: stdout.path, stderr: stderr.path, executionID: result.executionID)
        } catch {
            // Synchronous atomic receipt survives observation cancellation. The
            // Host consumes this file; losing an HTTP response never replays work.
            let directory = try fileLayout.validatedDescendant(directory, of: fileLayout.root)
            let stdout = directory.appending(path: "adapter-stdout.log")
            let stderr = directory.appending(path: "adapter-stderr.log")
            try Data().write(to: stdout, options: .atomic)
            let cancelled = error is CancellationError
            try Data((cancelled ? "Command cancelled.\n" : error.localizedDescription + "\n").utf8).write(to: stderr, options: .atomic)
            try writeResponse(directory: directory, exitCode: cancelled ? 130 : 127,
                stdout: stdout.path, stderr: stderr.path, executionID: nil)
        }
    }

    private func writeResponse(directory: URL, exitCode: Int, stdout: String, stderr: String, executionID: UUID?) throws {
        var response: [String: Any] = ["exitCode": exitCode, "stdoutPath": stdout, "stderrPath": stderr]
        if let executionID { response["executionID"] = executionID.uuidString.lowercased() }
        try JSONSerialization.data(withJSONObject: response).write(to: directory.appending(path: "response.json"), options: .atomic)
    }
}
