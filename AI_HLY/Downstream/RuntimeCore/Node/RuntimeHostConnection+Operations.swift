import Foundation

extension RuntimeHostConnection {
    /// A finite Host operation uses the original journal and owned input path.
    /// HTTP timeouts only detach observation; they never replay the operation.
    func performOperation(path: String, id: UUID, body: Data) async throws -> RuntimeExecutionResult {
        let owner = RuntimeUserOperation.current
        try owner?.checkInterruption()
        try Task.checkCancellation()
        let artifact: RuntimeExecutionInputArtifact?
        if let fileLayout {
            artifact = try RuntimeExecutionInputArtifact(body: body, executionID: id, layout: fileLayout)
        } else {
            guard body.count <= RuntimeExecutionInputArtifact.maximumInlineBytes else {
                throw RuntimeCoreError.invalidRequest("A large Host operation requires its authoritative RuntimeRoot layout.")
            }
            artifact = nil
        }
        do { try owner?.checkInterruption(); try Task.checkCancellation() }
        catch { artifact?.discardBeforeSubmission(); throw error }
        let route = "/v1/executions/\(id.uuidString.lowercased())"
        let interruption = owner?.registerInterruption { reason in
            Task.detached {
                let body = try? JSONSerialization.data(withJSONObject: ["reason": reason])
                _ = try? await self.data(path: route + "/interrupt", method: "POST", body: body, timeout: 5)
            }
        }
        defer { if let interruption { owner?.unregisterInterruption(interruption) } }
        return try await withTaskCancellationHandler {
            do {
                _ = try await decode(RuntimeJobSnapshot.self, path: path, method: "POST",
                                     body: artifact?.controlBody ?? body, timeout: 5)
            } catch let error as URLError where [.timedOut, .networkConnectionLost].contains(error.code) {
                // An uncertain acknowledgement is observed using the same ID.
            }
            var delay = 25
            while true {
                try owner?.checkInterruption()
                try Task.checkCancellation()
                do {
                    let job = try await decode(RuntimeJobSnapshot.self, path: route, timeout: 5)
                    owner?.recordJobOutput(id: id, stdout: job.stdoutBytes, stderr: job.stderrBytes)
                    if let reporter = RuntimeJobProgress.reporter { await reporter(job) }
                    if job.state == .interrupted {
                        throw RuntimeJobInterruptionError(executionID: id, reason: job.interruptionReason ?? job.error ?? "Host operation interrupted.")
                    }
                    if job.state == .cancelled { throw CancellationError() }
                    if let result = job.result {
                        guard result.exitCode == 0 else {
                            throw RuntimeCoreError.runtimeFailure(job.error ?? result.stderr)
                        }
                        return result
                    }
                    if job.state.isTerminal { throw RuntimeCoreError.runtimeFailure(job.error ?? "Host operation failed; its journal is retained.") }
                } catch let error as URLError where [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
                    if NodeRuntimeBridge.didExit { throw error }
                } catch RuntimeCoreError.requestFailed(404, _) {
                    // POST may still be preparing its owned input; do not POST again.
                    if NodeRuntimeBridge.didExit { throw RuntimeCoreError.runtimeFailure("The original Host exited before acknowledging the operation.") }
                }
                try await Task.sleep(for: .milliseconds(delay))
                delay = min(delay * 2, 1000)
            }
        } onCancel: {
            Task.detached {
                if let reason = owner?.snapshot.reason {
                    let body = try? JSONSerialization.data(withJSONObject: ["reason": reason])
                    _ = try? await self.data(path: route + "/interrupt", method: "POST", body: body, timeout: 5)
                } else {
                    _ = try? await self.data(path: route + "/cancel", method: "POST", body: Data("{}".utf8), timeout: 5)
                }
            }
        }
    }
}
