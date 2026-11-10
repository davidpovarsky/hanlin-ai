import Foundation

actor PythonRuntimeService {
    private struct BridgeResponse: Decodable {
        let stdout: String?
        let stderr: String?
        let value: RuntimeJSONValue?
        let exitCode: Int?
        let didTimeOut: Bool?
        let wasCancelled: Bool?
        let outputWasTruncated: Bool?
        let outputFiles: [String: RuntimeOutputArtifact]?
        let error: String?
    }
    private let fileLayout: RuntimeFileLayout
    private let jobs: RuntimeJobStore
    private var snapshotValue = RuntimeSnapshot.stopped(.localPython)
    private var activeIDs: Set<UUID> = []
    private var stopGeneration: UInt64 = 0
    private var stopRequested = false

    init(fileLayout: RuntimeFileLayout = .default, jobs: RuntimeJobStore? = nil) {
        self.fileLayout = fileLayout
        self.jobs = jobs ?? RuntimeJobStore(fileLayout: fileLayout)
    }
    func snapshot() -> RuntimeSnapshot { snapshotValue }
    func prepare() throws -> RuntimeSnapshot {
        try fileLayout.prepareIfNeeded()
        let version = try PythonRuntimeBridge.version()
        guard version == "3.14.6" else { throw RuntimeCoreError.runtimeFailure("Expected embedded Python 3.14.6, received \(version).") }
        stopRequested = false
        snapshotValue.state = activeIDs.isEmpty ? .ready : .executing
        snapshotValue.version = version
        snapshotValue.source = "beeware/Python-Apple-support"
        snapshotValue.lastHealthCheck = .now
        snapshotValue.lastErrorCode = nil
        return snapshotValue
    }
    func stop() async -> RuntimeSnapshot {
        stopGeneration &+= 1
        stopRequested = true
        for id in activeIDs {
            PythonRuntimeBridge.cancel(id: id)
            try? await jobs.requestCancellation(id: id, kind: .localPython)
        }
        snapshotValue.state = activeIDs.isEmpty ? .stopped : .executing
        snapshotValue.lastDiagnostic = activeIDs.isEmpty ? nil : "Stop requested; native Python calls must yield before cancellation can finish."
        return snapshotValue
    }
    func execute(_ request: RuntimeExecutionRequest) async throws -> RuntimeExecutionResult {
        try Task.checkCancellation()
        if snapshotValue.state != .ready && snapshotValue.state != .executing { _ = try prepare() }
        let generation = stopGeneration
        let workspace = try fileLayout.validatedWorkspace(request.workspace)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let initial = try await jobs.create(id: request.id, kind: .localPython)
        let observer = RuntimeJobProgress.reporter
        if let observer { await observer(initial) }
        do {
            guard generation == stopGeneration else { throw CancellationError() }
            PythonRuntimeBridge.register(id: request.id)
            activeIDs.insert(request.id)
            snapshotValue.state = .executing
            snapshotValue.activeExecutionCount = activeIDs.count
            defer {
                PythonRuntimeBridge.unregister(id: request.id)
                activeIDs.remove(request.id)
                snapshotValue.activeExecutionCount = activeIDs.count
                snapshotValue.state = activeIDs.isEmpty ? (stopRequested ? .stopped : .ready) : .executing
            }
            let milliseconds = try request.limits.timeoutMilliseconds()
            var body: [String: Any] = [
                "executionID": request.id.uuidString, "source": request.source, "arguments": request.arguments,
                "workspace": workspace.path, "packages": fileLayout.pythonPackages.path, "environment": request.environment,
                "outputDirectory": jobs.directory(id: request.id, kind: .localPython).path,
                "maximumOutputBytes": request.limits.maximumOutputBytes
            ]
            if let milliseconds { body["timeoutSeconds"] = Double(milliseconds) / 1000 }
            let registry = fileLayout.registry.appending(path: "PythonPackages.json")
            if FileManager.default.fileExists(atPath: registry.path) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let installed = try decoder.decode([PythonPackageRecord].self, from: Data(contentsOf: registry))
                body["packageDirectories"] = try installed.sorted { $0.installedAt > $1.installedAt }.map { item in
                    try fileLayout.validatedDescendant(fileLayout.pythonPackages.appending(path: "\(item.normalizedName)-\(item.version)"), of: fileLayout.pythonPackages, allowRoot: false).path
                }
            }
            let json = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
            let started = ContinuousClock.now
            let jobs = self.jobs
            let responseData = try await withThrowingTaskGroup(of: Data?.self) { group in
                group.addTask {
                    try await PythonRuntimeBridge.execute(requestJSON: json, id: request.id) {
                        Task {
                            try? await jobs.markRunning(id: request.id, kind: .localPython)
                            if let observer, let record = try? await jobs.snapshot(id: request.id, kind: .localPython) { await observer(record) }
                        }
                    }
                }
                group.addTask {
                    do {
                        while !Task.isCancelled {
                            try await Task.sleep(for: .milliseconds(500))
                            if let observer, let record = try await jobs.refresh(id: request.id, kind: .localPython) { await observer(record) }
                        }
                    } catch is CancellationError { return nil }
                    return nil
                }
                defer { group.cancelAll() }
                for try await data in group { if let data { return data } }
                throw RuntimeCoreError.runtimeFailure("Python job ended without a result.")
            }
            let response = try JSONDecoder().decode(BridgeResponse.self, from: responseData)
            if let error = response.error { throw RuntimeCoreError.runtimeFailure(error) }
            let duration = started.duration(to: .now)
            let result = RuntimeExecutionResult(
                executionID: request.id, stdout: response.stdout ?? "", stderr: response.stderr ?? "", value: response.value,
                exitCode: response.exitCode, durationMilliseconds: duration.components.seconds * 1000 + Int64(duration.components.attoseconds / 1_000_000_000_000_000),
                didTimeOut: response.didTimeOut ?? false, wasCancelled: response.wasCancelled ?? false,
                outputWasTruncated: response.outputWasTruncated ?? false, outputFiles: response.outputFiles
            )
            try await jobs.complete(result, kind: .localPython)
            if let observer, let record = try await jobs.snapshot(id: request.id, kind: .localPython) { await observer(record) }
            return result
        } catch {
            try? await jobs.fail(id: request.id, kind: .localPython, error: error)
            throw error
        }
    }
}
