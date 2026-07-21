import Foundation

actor PythonRuntimeService {
    private struct BridgeResponse: Decodable {
        let stdout: String?
        let stderr: String?
        let value: RuntimeJSONValue?
        let exitCode: Int?
        let didTimeOut: Bool?
        let error: String?
    }

    private let fileLayout: RuntimeFileLayout
    private var snapshotValue = RuntimeSnapshot.stopped(.localPython)

    init(fileLayout: RuntimeFileLayout = .default) { self.fileLayout = fileLayout }

    func snapshot() -> RuntimeSnapshot { snapshotValue }

    func prepare() throws -> RuntimeSnapshot {
        try fileLayout.prepareIfNeeded()
        let version = try PythonRuntimeBridge.version()
        guard version == "3.14.6" else { throw RuntimeCoreError.runtimeFailure("Expected embedded Python 3.14.6, received \(version).") }
        snapshotValue.state = .ready
        snapshotValue.version = version
        snapshotValue.source = "beeware/Python-Apple-support"
        snapshotValue.lastHealthCheck = .now
        snapshotValue.lastErrorCode = nil
        return snapshotValue
    }

    func execute(_ request: RuntimeExecutionRequest) throws -> RuntimeExecutionResult {
        if snapshotValue.state != .ready { _ = try prepare() }
        let workspace = try fileLayout.validatedDescendant(request.workspace, of: fileLayout.clients, allowRoot: false)
        let started = ContinuousClock.now
        snapshotValue.state = .executing
        snapshotValue.activeExecutionCount += 1
        defer {
            snapshotValue.activeExecutionCount = max(0, snapshotValue.activeExecutionCount - 1)
            snapshotValue.state = .ready
        }
        let seconds = Double(request.limits.timeout.components.seconds)
            + Double(request.limits.timeout.components.attoseconds) / 1_000_000_000_000_000_000
        let json = try JSONSerialization.data(withJSONObject: [
            "source": request.source,
            "arguments": request.arguments,
            "workspace": workspace.path,
            "packages": fileLayout.pythonPackages.path,
            "environment": request.environment,
            "timeoutSeconds": seconds
        ])
        let responseData = try PythonRuntimeBridge.execute(requestJSON: String(decoding: json, as: UTF8.self))
        let response = try JSONDecoder().decode(BridgeResponse.self, from: responseData)
        if let error = response.error { throw RuntimeCoreError.runtimeFailure(error) }
        let duration = started.duration(to: .now)
        let milliseconds = duration.components.seconds * 1_000
            + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
        let stdout = response.stdout ?? ""
        let stderr = response.stderr ?? ""
        let combined = Data(stdout.utf8).count + Data(stderr.utf8).count
        return RuntimeExecutionResult(
            executionID: request.id,
            stdout: String(decoding: stdout.utf8.prefix(request.limits.maximumOutputBytes), as: UTF8.self),
            stderr: String(decoding: stderr.utf8.prefix(max(0, request.limits.maximumOutputBytes - min(request.limits.maximumOutputBytes, Data(stdout.utf8).count))), as: UTF8.self),
            value: response.value,
            exitCode: response.exitCode,
            durationMilliseconds: milliseconds,
            didTimeOut: response.didTimeOut ?? false,
            wasCancelled: Task.isCancelled,
            outputWasTruncated: combined > request.limits.maximumOutputBytes
        )
    }
}
