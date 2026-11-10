import CryptoKit
import Foundation
import Security
import ZIPFoundation

private struct RuntimeHostReadyFile: Codable, Sendable {
    let port: Int
    let nodeVersion: String
    let protocolVersion: Int
    let modulePolicyHooksAvailable: Bool
}

struct RuntimeHostConnection: Sendable {
    let baseURL: URL
    private let token: String

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    func request(path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 60) -> URLRequest {
        var endpoint = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let route = URLComponents(string: path)!
        endpoint.percentEncodedPath = route.percentEncodedPath
        endpoint.percentEncodedQuery = route.percentEncodedQuery
        var request = URLRequest(url: endpoint.url!)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    func data(path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 60) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(path: path, method: method, body: body, timeout: timeout))
        guard let http = response as? HTTPURLResponse else { throw RuntimeCoreError.runtimeFailure("The runtime host returned an invalid response.") }
        guard 200..<300 ~= http.statusCode else {
            let decoded = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw RuntimeCoreError.requestFailed(http.statusCode, decoded ?? String(decoding: data.prefix(16_384), as: UTF8.self))
        }
        return data
    }

    func decode<T: Decodable>(_ type: T.Type, path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 60) async throws -> T {
        try JSONDecoder().decode(T.self, from: await data(path: path, method: method, body: body, timeout: timeout))
    }
}

struct TypeScriptCompilationResult: Codable, Sendable {
    struct Diagnostic: Codable, Sendable, Identifiable {
        let code: Int
        let category: String?
        let message: String
        let file: String?
        let line: Int?
        let column: Int?
        var id: String { "\(code):\(line ?? 0):\(column ?? 0):\(message)" }
    }

    let javaScript: String?
    let sourceMap: String?
    let diagnostics: [Diagnostic]
    let succeeded: Bool
}

struct TypeScriptProjectCompilationResult: Codable, Sendable {
    let compilerVersion: String?
    let compilerIntegrity: String?
    let diagnostics: [TypeScriptCompilationResult.Diagnostic]
    let emittedFiles: [String]
    let succeeded: Bool
}

enum NodeHostHealthFailure: String, Sendable {
    case cancelled
    case transient
    case unreachable
    case protocolFailure
}

struct RuntimeLifecycleContext: Encodable, Sendable {
    let packageName: String
    let packageVersion: String
    let event: String
    let initialCwd: String
}

actor NodeRuntimeService {
    static let expectedNodeVersion = "24.5.0"
    static let hostProtocolVersion = 2


    private let fileLayout: RuntimeFileLayout
    private let environmentStore: RuntimeEnvironmentStore?
    private let commandDispatcher: RuntimeCommandDispatcher
    private var commandPump: Task<Void, Never>?
    private var activeCommands: [String: Task<Void, Never>] = [:]
    private var userOperations: [UUID: RuntimeUserOperation] = [:]
    private struct LaunchContext: Sendable {
        let readyURL: URL
        let token: String
    }

    private var connection: RuntimeHostConnection?
    private var launchContext: LaunchContext?
    private var snapshotValue = RuntimeSnapshot.stopped(.node)
    private var launchAttempted = false
    private var nativeLaunchSucceeded = false
    private var launchTask: Task<RuntimeHostConnection, Error>?
    private var verificationTask: Task<RuntimeHostConnection, Error>?

    init(fileLayout: RuntimeFileLayout = .default, environment: RuntimeEnvironmentStore? = nil, python: PythonRuntimeService? = nil, shell: ShellRuntimeService? = nil) {
        self.fileLayout = fileLayout
        self.environmentStore = environment
        self.commandDispatcher = RuntimeCommandDispatcher(fileLayout: fileLayout, python: python, shell: shell)
    }

    func snapshot() -> RuntimeSnapshot { snapshotValue }

    func ensureRunning(debug: Bool = false) async throws -> RuntimeHostConnection {
        if let connection {
            if let verificationTask { return try await verificationTask.value }
            let task = Task { [weak self] () throws -> RuntimeHostConnection in
                guard let self else { throw CancellationError() }
                return try await self.verifyExistingConnection(connection)
            }
            verificationTask = task
            return try await task.value
        }
        if let launchTask { return try await launchTask.value }

        if nativeLaunchSucceeded && NodeRuntimeBridge.didExit {
            markNodeExited()
            throw RuntimeCoreError.appRestartRequired(.node)
        }

        snapshotValue.state = .preparing
        let previouslyLaunched = launchAttempted
        let context = launchContext
        let task = Task { [weak self] () throws -> RuntimeHostConnection in
            guard let self else { throw CancellationError() }
            if previouslyLaunched {
                guard let context else { throw RuntimeCoreError.runtimeUnavailable(.node) }
                return try await self.reconnectLaunchedHost(context: context)
            }
            return try await self.launchHost(debug: debug)
        }
        launchTask = task
        do {
            return try await task.value
        } catch is CancellationError {
            snapshotValue.healthCategory = NodeHostHealthFailure.cancelled.rawValue
            snapshotValue.lastDiagnostic = "Node host startup observation was cancelled; the shared launch continues."
            throw CancellationError()
        } catch {
            if snapshotValue.state != .appRestartRequired {
                snapshotValue.state = .failed
                if !launchAttempted {
                    snapshotValue.lastErrorCode = "node_setup_failed"
                    snapshotValue.lastDiagnostic = error.localizedDescription
                }
            }
            throw error
        }
    }

    func healthCheck() async throws -> RuntimeSnapshot {
        _ = try await ensureRunning()
        snapshotValue.lastHealthCheck = .now
        return snapshotValue
    }

    func healthCheckIfLaunched() async throws -> RuntimeSnapshot {
        guard launchAttempted else { return snapshotValue }
        _ = try await ensureRunning()
        return snapshotValue
    }

    func stop() -> RuntimeSnapshot {
        // nodejs-mobile is process-lifetime. Do not discard a live connection
        // or report Node as stopped: there is no supported unload operation.
        snapshotValue.lastDiagnostic = "Embedded Node remains active for the app process lifetime."
        return snapshotValue
    }

    func executeJavaScript(_ request: RuntimeExecutionRequest, moduleKind: String? = nil) async throws -> RuntimeExecutionResult {
        try await executeNodeJob(request, moduleKind: moduleKind)
    }

    /// Execute the actual entry file as Node's main module, not a synthetic import.
    func executeCLI(entryPoint: URL, arguments: [String], workspace: URL,
                    environment: [String: String] = [:], standardInput: URL? = nil) async throws -> RuntimeExecutionResult {
        let entry = try fileLayout.validatedReadableFile(entryPoint)
        let input = try standardInput.map { try fileLayout.validatedReadableFile($0) }
        return try await executeNodeJob(RuntimeExecutionRequest(source: "", arguments: arguments,
            workspace: workspace, environment: environment), moduleKind: "esm", entryPoint: entry, standardInput: input)
    }

    private func executeNodeJob(_ request: RuntimeExecutionRequest, moduleKind: String?,
                                entryPoint: URL? = nil, standardInput: URL? = nil) async throws -> RuntimeExecutionResult {
        let operation = RuntimeUserOperation.current
        try operation?.checkInterruption()
        if let operation { userOperations[request.id] = operation }
        let interruption = operation?.registerInterruption { reason in
            Task { await self.interruptExecution(id: request.id, reason: reason) }
        }
        defer {
            userOperations.removeValue(forKey: request.id)
            if let interruption { operation?.unregisterInterruption(interruption) }
        }
        let environment = try await environmentStore?.resolved(scopes: [.shared, .node, .execution(request.id)], overrides: request.environment)
            ?? RuntimePolicy.validatedEnvironment(request.environment)
        let workspace = try fileLayout.validatedWorkspace(request.workspace)
        let resolvedModuleKind = moduleKind ?? Self.inferModuleKind(for: request.source)
        let host = try await ensureRunning()
        snapshotValue.state = .executing
        snapshotValue.activeExecutionCount += 1
        defer {
            snapshotValue.activeExecutionCount = max(0, snapshotValue.activeExecutionCount - 1)
            if snapshotValue.activeExecutionCount == 0 && snapshotValue.state == .executing {
                snapshotValue.state = .ready
            }
        }
        let milliseconds = try request.limits.timeoutMilliseconds()
        var payload: [String: Any] = [
            "executionID": request.id.uuidString.lowercased(),
            "source": request.source, "arguments": request.arguments,
            "workspace": workspace.path, "environment": environment,
            "moduleKind": resolvedModuleKind, "detached": true,
            "maximumOutputBytes": request.limits.maximumOutputBytes
        ]
        if let entryPoint { payload["entryPoint"] = entryPoint.path; payload["executionMode"] = "cli" }
        if let standardInput { payload["standardInputPath"] = standardInput.path }
        if let milliseconds { payload["timeoutMilliseconds"] = milliseconds }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await withTaskCancellationHandler {
            try operation?.checkInterruption()
            try Task.checkCancellation()
            var job: RuntimeJobSnapshot
            do {
                job = try await host.decode(RuntimeJobSnapshot.self, path: "/v1/executions", method: "POST", body: body)
            } catch let error as URLError where [.timedOut, .networkConnectionLost].contains(error.code) {
                // Recover observation of the same ID; never repeat the source after an ambiguous POST.
                job = try await observeJob(RuntimeJobSnapshot.self, host: host, path: "/v1/executions/\(request.id.uuidString.lowercased())")
            }
            var delayMilliseconds = 25
            var lastProgress = ""
            while true {
                if let reason = operation?.snapshot.reason {
                    await interruptExecution(id: request.id, reason: reason)
                    throw RuntimeJobInterruptionError(executionID: request.id, reason: reason)
                }
                try Task.checkCancellation()
                operation?.recordJobOutput(id: request.id, stdout: job.stdoutBytes, stderr: job.stderrBytes)
                let progress = "\(job.state.rawValue):\(job.stdoutBytes):\(job.stderrBytes)"
                if progress != lastProgress, let observer = RuntimeJobProgress.reporter {
                    await observer(job)
                    lastProgress = progress
                }
                if job.state == .interrupted {
                    throw RuntimeJobInterruptionError(executionID: request.id,
                        reason: job.interruptionReason ?? job.error ?? "The runtime process was interrupted.")
                }
                if let result = job.result { return result }
                if job.state.isTerminal {
                    throw RuntimeCoreError.runtimeFailure("Job \(job.executionID): \(job.error ?? job.state.rawValue). Partial output remains available through get_runtime_job.")
                }
                try await Task.sleep(for: .milliseconds(delayMilliseconds))
                delayMilliseconds = min(delayMilliseconds * 2, 1000)
                job = try await observeJob(RuntimeJobSnapshot.self, host: host, path: "/v1/executions/\(request.id.uuidString.lowercased())")
            }
        } onCancel: {
            Task {
                if let reason = operation?.snapshot.reason { await self.interruptExecution(id: request.id, reason: reason) }
                else { await self.cancelExecution(id: request.id) }
            }
        }
    }

    /// Host-lifetime ownership also serves package operations and survives a
    /// lost execution observer. It dispatches only authenticated live receipts.
    private func startCommandPump(_ host: RuntimeHostConnection) {
        guard commandPump == nil else { return }
        commandPump = Task.detached { [weak self] in
            guard let self else { return }
            await self.runCommandPump(host)
        }
    }

    private func runCommandPump(_ host: RuntimeHostConnection) async {
        defer { commandPump = nil }
        while !Task.isCancelled && !NodeRuntimeBridge.didExit {
            do {
                let requests = try await observeJob([RuntimeCommandRequest].self, host: host, path: "/v1/commands/wait")
                let pendingIDs = Set(requests.map(\.ownerKey))
                for id in Array(activeCommands.keys) where !pendingIDs.contains(id) { activeCommands.removeValue(forKey: id) }
                for command in requests {
                    if let active = activeCommands[command.ownerKey] {
                        if command.cancellationRequested { active.cancel() }
                        continue
                    }
                    let dispatcher = commandDispatcher
                    let operation = userOperations[command.parentExecutionID]
                    activeCommands[command.ownerKey] = Task {
                        do {
                            // Inherit only this receipt's explicit operation,
                            // never another chat's capability or progress locals.
                            try await RuntimeUserOperation.$current.withValue(operation) {
                                try operation?.checkInterruption()
                                try await dispatcher.execute(command, node: self)
                            }
                        }
                        catch {
                            let message = error.localizedDescription
                            await Task.detached {
                                let body = try? JSONSerialization.data(withJSONObject: ["error": message])
                                _ = try? await host.data(path: "/v1/executions/\(command.parentExecutionID.uuidString.lowercased())/commands/\(command.id.uuidString.lowercased())/fail", method: "POST", body: body)
                            }.value
                        }
                    }
                }
                try await Task.sleep(for: .milliseconds(requests.isEmpty ? 500 : 25))
            } catch is CancellationError { break }
            catch {
                snapshotValue.healthCategory = NodeHostHealthFailure.protocolFailure.rawValue
                snapshotValue.lastDiagnostic = "Runtime command observation failed: \(error.localizedDescription)"
                do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
            }
        }
        for task in activeCommands.values { task.cancel() }
        activeCommands.removeAll()
        if NodeRuntimeBridge.didExit { markNodeExited() }
    }

    private func observeJob<T: Decodable & Sendable>(_ type: T.Type, host: RuntimeHostConnection, path: String) async throws -> T {
        var delay = 25
        while true {
            try Task.checkCancellation()
            do { return try await host.decode(type, path: path) }
            catch let error as URLError {
                guard [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet].contains(error.code),
                      !NodeRuntimeBridge.didExit else { throw error }
                snapshotValue.healthCategory = NodeHostHealthFailure.transient.rawValue
                snapshotValue.lastDiagnostic = "Reconnecting job observation; existing source and command side effects are retained without replay."
                // Observation may reconnect; source and command side effects are
                // never resubmitted. Keep the command owner alive meanwhile.
                try await Task.sleep(for: .milliseconds(delay))
                delay = min(delay * 2, 1000)
            }
        }
    }

    /// Observe a previously submitted operation without replaying its input.
    func waitForExecution(id: UUID) async throws -> RuntimeExecutionResult {
        let operation = RuntimeUserOperation.current
        try operation?.checkInterruption()
        if let operation { userOperations[id] = operation }
        let interruption = operation?.registerInterruption { reason in
            Task { await self.interruptExecution(id: id, reason: reason) }
        }
        defer {
            userOperations.removeValue(forKey: id)
            if let interruption { operation?.unregisterInterruption(interruption) }
        }
        let host = try await ensureRunning()
        return try await withTaskCancellationHandler {
            var delay = 25
            while true {
                if let reason = operation?.snapshot.reason {
                    await interruptExecution(id: id, reason: reason)
                    throw RuntimeJobInterruptionError(executionID: id, reason: reason)
                }
                try Task.checkCancellation()
                let job = try await observeJob(RuntimeJobSnapshot.self, host: host, path: "/v1/executions/\(id.uuidString.lowercased())")
                operation?.recordJobOutput(id: id, stdout: job.stdoutBytes, stderr: job.stderrBytes)
                if let reporter = RuntimeJobProgress.reporter { await reporter(job) }
                if job.state == .interrupted {
                    throw RuntimeJobInterruptionError(executionID: id,
                        reason: job.interruptionReason ?? job.error ?? "The runtime process was interrupted.")
                }
                if let result = job.result { return result }
                if job.state.isTerminal { throw RuntimeCoreError.runtimeFailure("Job \(id): \(job.error ?? job.state.rawValue). Existing output is retained.") }
                try await Task.sleep(for: .milliseconds(delay))
                delay = min(delay * 2, 1000)
            }
        } onCancel: {
            Task {
                if let reason = operation?.snapshot.reason { await self.interruptExecution(id: id, reason: reason) }
                else { await self.cancelExecution(id: id) }
            }
        }
    }

    func hasLaunched() -> Bool { launchAttempted }

    /// Read live facts without starting an engine just to inspect capabilities.
    func capabilityReportIfLaunched() async throws -> RuntimeJSONValue? {
        guard let connection else { return nil }
        return try await connection.decode(RuntimeJSONValue.self, path: "/v1/runtime/capabilities")
    }

    /// Uses the same Node job/stdio/journal path. External commands require the
    /// command broker; built-in portable-shell operations execute in the Worker.
    func validatePackage(name: String, packageRoot: URL, workspace: URL) async throws -> RuntimeExecutionResult {
        let moduleURL = try prepareHostRuntime().appending(path: "package-validation.mjs")
        let module = String(decoding: try JSONEncoder().encode(moduleURL.absoluteString), as: UTF8.self)
        let packageName = String(decoding: try JSONEncoder().encode(name), as: UTF8.self)
        let root = String(decoding: try JSONEncoder().encode(packageRoot.path), as: UTF8.self)
        // Keep import() in the original job source. Moving it inside the Host
        // helper would resolve from bundled dependencies instead of this stage.
        return try await executeJavaScript(RuntimeExecutionRequest(source: """
            import {validateGlobalPackage} from \(module);
            import {createRequire} from 'node:module';
            const require = createRequire(import.meta.url);
            const receipt = await validateGlobalPackage({name: \(packageName), packageRoot: \(root), importLibrary: async () => {
                try { import.meta.resolve(\(packageName)); }
                catch (error) {
                    if (error.code !== 'ERR_PACKAGE_PATH_NOT_EXPORTED') throw error;
                    require(\(packageName));
                    return 'require';
                }
                await import(\(packageName));
                return 'import';
            }});
            console.log(JSON.stringify(receipt));
            export default receipt;
            """, workspace: workspace), moduleKind: "esm")
    }

    func executePortableShell(_ request: RuntimeExecutionRequest, lifecycle: RuntimeLifecycleContext? = nil) async throws -> RuntimeExecutionResult {
        let moduleURL = try prepareHostRuntime().appending(path: "portable-shell.mjs")
        let module = String(decoding: try JSONEncoder().encode(moduleURL.absoluteString), as: UTF8.self)
        let script = String(decoding: try JSONEncoder().encode(request.source), as: UTF8.self)
        let args = String(decoding: try JSONEncoder().encode(request.arguments), as: UTF8.self)
        let lifecycleJSON = String(decoding: try JSONEncoder().encode(lifecycle), as: UTF8.self)
        let source = """
        import { executePortableShell, packageLifecycleEnvironment } from \(module);
        const lifecycle = \(lifecycleJSON);
        const environment = lifecycle ? await packageLifecycleEnvironment({ ...lifecycle, cwd: process.cwd(), environment: process.env, source: \(script) }) : process.env;
        const exitCode = await executePortableShell(\(script), \(args), {
            cwd: process.cwd(), environment,
            stdin: process.stdin, stdout: process.stdout, stderr: process.stderr
        });
        process.exitCode = exitCode;
        export default { exitCode };
        """
        return try await executeJavaScript(RuntimeExecutionRequest(id: request.id, source: source,
            arguments: request.arguments, workspace: request.workspace, environment: request.environment,
            limits: request.limits), moduleKind: "esm")
    }

    func verifyLifecyclePlan(_ plan: LifecycleExecutionPlan, workspace: URL) async throws {
        let host = try await ensureRunning()
        let body = try JSONSerialization.data(withJSONObject: ["packageRoot": workspace.path,
            "plan": try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan))])
        struct Verification: Decodable, Sendable { let verified: Bool }
        let response = try await host.decode(Verification.self, path: "/v1/packages/lifecycle/verify", method: "POST", body: body)
        guard response.verified else { throw RuntimeCoreError.invalidRequest("Lifecycle source verification failed.") }
    }

    func packageLifecyclePlan(workspace: URL) async throws -> LifecycleExecutionPlan {
        let moduleURL = try prepareHostRuntime().appending(path: "lifecycle-planner.mjs")
        let module = String(decoding: try JSONEncoder().encode(moduleURL.absoluteString), as: UTF8.self)
        let source = """
        import {readFile} from 'node:fs/promises';
        import {planLifecycle} from \(module);
        export default planLifecycle(JSON.parse(await readFile('package.json','utf8')));
        """
        let result = try await executeJavaScript(RuntimeExecutionRequest(source: source, workspace: workspace), moduleKind: "esm")
        guard result.exitCode == 0, let value = result.value else { throw RuntimeCoreError.runtimeFailure(result.stderr) }
        return try JSONDecoder().decode(LifecycleExecutionPlan.self, from: JSONEncoder().encode(value))
    }

    /// Package extraction/resolution is an ordinary durable Node job, without
    /// an HTTP installation deadline. Publishing remains atomic in the Host.
    func pruneOptionalLifecycleFailure(_ plan: LifecycleExecutionPlan, action: LifecycleExecutionPlan.Action,
                                      workspace: URL, failure: RuntimeLifecycleCommandFailure) async throws -> [String] {
        let moduleURL = try prepareHostRuntime().appending(path: "optional-lifecycle.mjs")
        let literal: (String) throws -> String = { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        let encodedPlan = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
        let encodedAction = String(decoding: try JSONEncoder().encode(action), as: UTF8.self)
        let source = """
        import {pruneOptionalLifecycleFailure} from \(try literal(moduleURL.absoluteString));
        const result = await pruneOptionalLifecycleFailure({runtimeRoot: \(try literal(fileLayout.root.path)),
          packageRoot: \(try literal(workspace.path)), plan: \(encodedPlan), action: \(encodedAction),
          error: {message: \(try literal(failure.diagnostic)), executionID: \(try literal(failure.executionID.uuidString.lowercased())), exitCode: \(failure.exitCode)}});
        console.log(JSON.stringify(result.receipt));
        export default result.omittedDirectories;
        """
        let result = try await executeJavaScript(RuntimeExecutionRequest(source: source, workspace: workspace), moduleKind: "esm")
        if result.wasCancelled { throw CancellationError() }
        guard result.exitCode == 0, !result.didTimeOut, let value = result.value else {
            throw RuntimeCoreError.runtimeFailure(result.stderr)
        }
        return try JSONDecoder().decode([String].self, from: JSONEncoder().encode(value))
    }

    func stageNodePackage<T: Decodable & Sendable>(_ type: T.Type, removing: Bool = false, body: Data) async throws -> T {
        let moduleURL = try prepareHostRuntime().appending(path: "global-package-manager.mjs")
        let module = String(decoding: try JSONEncoder().encode(moduleURL.absoluteString), as: UTF8.self)
        let root = String(decoding: try JSONEncoder().encode(fileLayout.root.path), as: UTF8.self)
        _ = try JSONDecoder().decode(RuntimeJSONValue.self, from: body)
        let function = removing ? "stageUninstallGlobalPackage" : "stageGlobalPackage"
        let workspace = try fileLayout.workspace(client: .tools, identifier: "npm-operations")
        let source = """
        import { \(function) } from \(module);
        export default await \(function)({ ...\(String(decoding: body, as: UTF8.self)), root: \(root) });
        """
        let result = try await executeJavaScript(RuntimeExecutionRequest(source: source, workspace: workspace), moduleKind: "esm")
        if result.wasCancelled { throw CancellationError() }
        guard result.exitCode == 0, !result.didTimeOut, let value = result.value else {
            throw RuntimeCoreError.runtimeFailure("Package job \(result.executionID) failed. \(result.stderr)")
        }
        return try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
    }

    func networkDiagnostics(rounds: Int = 2) async throws -> RuntimeExecutionResult {
        let moduleURL = try prepareHostRuntime().appending(path: "network-diagnostics.mjs")
        let module = String(decoding: try JSONEncoder().encode(moduleURL.absoluteString), as: UTF8.self)
        let source = """
        import { probeNodeHTTPS } from \(module);
        const report = await probeNodeHTTPS({ rounds: \(max(1, min(5, rounds))) });
        console.log(JSON.stringify(report));
        export default report;
        """
        return try await executeJavaScript(.init(
            source: source,
            workspace: try fileLayout.workspace(client: .tools, identifier: "node-https-diagnostics"),
            environment: ["HANLIN_NODE_TRACE_WARNINGS": "1"],
            limits: .init(timeout: .seconds(180))
        ), moduleKind: "esm")
    }

    func cancelExecution(id: UUID) async {
        guard let connection else { return }
        _ = try? await connection.data(path: "/v1/executions/\(id.uuidString.lowercased())/cancel", method: "POST", body: Data("{}".utf8), timeout: 3)
    }

    func interruptExecution(id: UUID, reason: String) async {
        guard let connection else { return }
        let body = try? JSONSerialization.data(withJSONObject: ["reason": reason])
        _ = try? await connection.data(path: "/v1/executions/\(id.uuidString.lowercased())/interrupt", method: "POST", body: body, timeout: 3)
    }

    /// Observe an already-running Host without starting an engine or replaying source.
    func existingExecution(id: UUID) async throws -> RuntimeJobSnapshot? {
        guard let connection else { return nil }
        return try await connection.decode(RuntimeJobSnapshot.self, path: "/v1/executions/\(id.uuidString.lowercased())", timeout: 5)
    }

    func compileTypeScript(source: String, fileName: String = "main.ts", tsconfig: [String: RuntimeJSONValue]? = nil) async throws -> TypeScriptCompilationResult {
        let host = try await ensureRunning()
        var body: [String: Any] = ["source": source, "fileName": fileName]
        if let tsconfig {
            let encoded = try JSONEncoder().encode(tsconfig)
            body["tsconfig"] = try JSONSerialization.jsonObject(with: encoded)
        }
        let encodedBody = try JSONSerialization.data(withJSONObject: body)
        return try await host.decode(TypeScriptCompilationResult.self, path: "/v1/typescript/compile", method: "POST", body: encodedBody)
    }

    func compileTypeScriptProject(workspace: URL, arguments: [String]) async throws -> TypeScriptProjectCompilationResult {
        let scopedWorkspace = try fileLayout.validatedWorkspace(workspace)
        let host = try await ensureRunning()
        let body = try JSONSerialization.data(withJSONObject: [
            "workspace": scopedWorkspace.path,
            "arguments": arguments
        ])
        return try await host.decode(
            TypeScriptProjectCompilationResult.self,
            path: "/v1/typescript/project",
            method: "POST",
            body: body,
            timeout: 300
        )
    }

    func currentConnection() async throws -> RuntimeHostConnection {
        try await ensureRunning()
    }

    private func launchHost(debug: Bool) async throws -> RuntimeHostConnection {
        defer { launchTask = nil }
        try fileLayout.prepareIfNeeded()
        let hostURL = try prepareHostRuntime()
        let context = LaunchContext(
            readyURL: fileLayout.nodeRuntime.appending(path: "ready-\(UUID().uuidString).json"),
            token: try makeToken()
        )
        let arguments = [
            "node",
            hostURL.appending(path: "host.mjs").path,
            fileLayout.root.path,
            context.readyURL.path,
            context.token,
            fileLayout.logs.appending(path: "node-runtime.log").path,
            debug ? "1" : "0"
        ]
        try NodeRuntimeBridge.start(arguments: arguments)
        launchAttempted = true
        nativeLaunchSucceeded = true
        launchContext = context
        return try await waitForHostReady(context: context, timeout: .seconds(20))
    }

    private func reconnectLaunchedHost(context: LaunchContext) async throws -> RuntimeHostConnection {
        defer { launchTask = nil }
        return try await waitForHostReady(context: context, timeout: .seconds(6))
    }

    private func waitForHostReady(
        context: LaunchContext,
        timeout: Duration
    ) async throws -> RuntimeHostConnection {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var lastFailure: Error?

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if NodeRuntimeBridge.didExit {
                markNodeExited()
                throw RuntimeCoreError.appRestartRequired(.node)
            }

            if FileManager.default.fileExists(atPath: context.readyURL.path) {
                do {
                    let ready = try JSONDecoder().decode(
                        RuntimeHostReadyFile.self,
                        from: Data(contentsOf: context.readyURL)
                    )
                    guard ready.nodeVersion == Self.expectedNodeVersion,
                          ready.protocolVersion == Self.hostProtocolVersion else {
                        throw RuntimeCoreError.runtimeFailure(
                            "Expected Node \(Self.expectedNodeVersion) and protocol \(Self.hostProtocolVersion), received Node \(ready.nodeVersion) and protocol \(ready.protocolVersion)."
                        )
                    }
                    guard ready.modulePolicyHooksAvailable else {
                        throw RuntimeCoreError.runtimeFailure(
                            "Embedded Node \(ready.nodeVersion) lacks required module policy hooks."
                        )
                    }
                    guard let url = URL(string: "http://127.0.0.1:\(ready.port)") else {
                        throw RuntimeCoreError.runtimeFailure("Node published an invalid loopback address.")
                    }
                    let host = RuntimeHostConnection(baseURL: url, token: context.token)
                    _ = try await host.data(path: "/health", timeout: 3)
                    try? FileManager.default.removeItem(at: context.readyURL)
                    connection = host
                    startCommandPump(host)
                    snapshotValue.state = .ready
                    snapshotValue.version = ready.nodeVersion
                    snapshotValue.source = "heylogin/nodejs-mobile"
                    snapshotValue.lastHealthCheck = .now
                    snapshotValue.lastErrorCode = nil
                    snapshotValue.healthCategory = nil
                    snapshotValue.lastDiagnostic = "Embedded Node host connected and passed its health check."
                    return host
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastFailure = error
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        if NodeRuntimeBridge.didExit {
            markNodeExited()
            throw RuntimeCoreError.appRestartRequired(.node)
        }
        snapshotValue.state = .failed
        snapshotValue.healthCategory = NodeHostHealthFailure.transient.rawValue
        snapshotValue.lastErrorCode = "node_host_not_ready"
        snapshotValue.lastDiagnostic = "Node was launched but its local host is not yet reachable; reconnection remains possible."
        throw lastFailure ?? RuntimeCoreError.runtimeFailure("Embedded Node host did not become ready before the bounded deadline.")
    }

    private func markNodeExited() {
        commandPump?.cancel()
        connection = nil
        snapshotValue.state = .appRestartRequired
        snapshotValue.healthCategory = NodeHostHealthFailure.unreachable.rawValue
        snapshotValue.lastErrorCode = "node_process_exited"
        snapshotValue.lastDiagnostic = "The embedded Node thread returned; nodejs-mobile cannot start a second instance in this process."
    }

    private func verifyExistingConnection(
        _ existing: RuntimeHostConnection
    ) async throws -> RuntimeHostConnection {
        defer { verificationTask = nil }
        var lastFailure: Error?
        var category = NodeHostHealthFailure.transient
        for attempt in 1...3 {
            do {
                _ = try await existing.data(path: "/health", timeout: 3)
                connection = existing
                startCommandPump(existing)
                snapshotValue.state = snapshotValue.activeExecutionCount > 0 ? .executing : .ready
                snapshotValue.lastHealthCheck = .now
                snapshotValue.lastErrorCode = nil
                snapshotValue.healthCategory = nil
                snapshotValue.lastDiagnostic = attempt == 1
                    ? "Node host health check passed."
                    : "Node host health check recovered on bounded retry \(attempt)."
                return existing
            } catch is CancellationError {
                snapshotValue.healthCategory = NodeHostHealthFailure.cancelled.rawValue
                snapshotValue.lastDiagnostic = "Node host health check was cancelled; the existing connection was preserved."
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                snapshotValue.healthCategory = NodeHostHealthFailure.cancelled.rawValue
                snapshotValue.lastDiagnostic = "Node host health check was cancelled; the existing connection was preserved."
                throw CancellationError()
            } catch {
                lastFailure = error
                category = classifyHealthFailure(error)
                snapshotValue.healthCategory = category.rawValue
                snapshotValue.lastDiagnostic = "Node host health attempt \(attempt) failed (\(category.rawValue))."
                if attempt < retryCount(for: category) {
                    try await Task.sleep(for: .milliseconds(150))
                    continue
                }
                break
            }
        }

        if NodeRuntimeBridge.didExit {
            markNodeExited()
            throw RuntimeCoreError.appRestartRequired(.node)
        }
        // Keep the original authenticated endpoint: a suspended or overloaded
        // host may respond on the next foreground activation. Never start a
        // second nodejs-mobile instance just because an HTTP probe timed out.
        connection = existing
        snapshotValue.state = .failed
        snapshotValue.healthCategory = category.rawValue
        snapshotValue.lastErrorCode = "node_health_unreachable"
        snapshotValue.lastDiagnostic = "The Node thread is still present, but its host did not answer. The next use will retry the connection."
        throw lastFailure ?? RuntimeCoreError.runtimeUnavailable(.node)
    }

    private func classifyHealthFailure(_ error: Error) -> NodeHostHealthFailure {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                return .transient
            default:
                return .unreachable
            }
        }
        if let runtimeError = error as? RuntimeCoreError,
           case .requestFailed = runtimeError {
            return .protocolFailure
        }
        return .unreachable
    }

    private func retryCount(for category: NodeHostHealthFailure) -> Int {
        category == .transient ? 3 : 2
    }

    private func prepareHostRuntime() throws -> URL {
        guard let archive = Bundle.main.url(forResource: "RuntimeHostResources", withExtension: "zip") else {
            throw RuntimeCoreError.runtimeFailure("RuntimeHostResources.zip is missing. Run Scripts/Runtime/prepare-runtime-core.sh before building.")
        }
        
        // Compute SHA-256 hash of the bundled RuntimeHostResources.zip
        let archiveData = try Data(contentsOf: archive)
        let digest = SHA256.hash(data: archiveData)
        let archiveHash = digest.map { String(format: "%02x", $0) }.joined()
        
        let destination = fileLayout.nodeRuntime.appending(path: "host-\(archiveHash)", directoryHint: .isDirectory)
        let marker = destination.appending(path: ".ready")
        if FileManager.default.fileExists(atPath: marker.path) { return destination }
        
        let staging = fileLayout.staging.appending(path: "host-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try FileManager.default.unzipItem(at: archive, to: staging)
            try Data(archiveHash.utf8).write(to: staging.appending(path: ".ready"), options: .atomic)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: staging, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private func makeToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw RuntimeCoreError.runtimeFailure("Could not create a runtime launch token.")
        }
        return Data(bytes).base64EncodedString()
    }

    nonisolated static func inferModuleKind(for source: String) -> String {
        let usesESM = source.range(
            of: #"(?m)^\s*(import\s+[\w\{\*\'\"]|export\s+(default|const|let|var|function|class|\{))"#,
            options: .regularExpression
        ) != nil
        if usesESM { return "esm" }
        let usesCommonJS = source.range(
            of: #"\b(require\s*\(|module\.exports\b|exports\.[A-Za-z_$])"#,
            options: .regularExpression
        ) != nil
        return usesCommonJS ? "commonjs" : "esm"
    }
}
