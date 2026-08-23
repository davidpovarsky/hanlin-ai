import CQuickJS
import Foundation
import HanlinPlatformContracts

/// This unchecked conformance is limited to an immutable opaque pointer whose
/// only cross-actor operation is the C wrapper's atomic cancellation flag. The
/// owning session actor outlives every cancellation handler that captures it.
private final class HanlinQuickJSCancellationHandle: @unchecked Sendable {
    private let session: OpaquePointer

    init(session: OpaquePointer) {
        self.session = session
    }

    func cancel() {
        hanlin_quickjs_session_cancel(session)
    }
}

actor HanlinQuickJSSession {
    struct Configuration: Hashable, Sendable {
        let memoryLimitBytes: Int
        let stackLimitBytes: Int
        let timeoutMilliseconds: UInt64
        let maximumOutputBytes: Int

        static let phase2A = Configuration(
            memoryLimitBytes: 16 * 1_048_576,
            stackLimitBytes: 512 * 1_024,
            timeoutMilliseconds: 2_000,
            maximumOutputBytes: 1_048_576
        )
    }

    /// nonisolated(unsafe) is required so `deinit` (which is always nonisolated)
    /// can synchronously release the underlying QuickJS session. Safety holds
    /// because every other access to this property happens on the actor's own
    /// isolated executor, and deinit only runs once no other access is possible.
    private nonisolated(unsafe) var session: OpaquePointer?
    private let cancellationHandle: HanlinQuickJSCancellationHandle
    private let configuration: Configuration
    private var disposed = false

    init(configuration: Configuration = .phase2A) throws {
        guard String(cString: hanlin_quickjs_engine_version()) == "0.16.1",
              let session = hanlin_quickjs_session_create(
                configuration.memoryLimitBytes,
                configuration.stackLimitBytes
              ) else {
            throw HanlinScriptingError.runtimeInitializationFailed
        }
        self.session = session
        cancellationHandle = HanlinQuickJSCancellationHandle(session: session)
        self.configuration = configuration
    }

    deinit {
        if let session {
            hanlin_quickjs_session_destroy(session)
        }
    }

    func loadProgram(
        _ javaScript: String,
        filename: String,
        expectedToolCount: Int = 1
    ) throws {
        _ = try activeSession()
        try evaluate(
            HanlinScriptValueBridge.bootstrap,
            filename: "hanlin-script-abi-1.0.js"
        )
        try evaluate(javaScript, filename: filename)
        try evaluate(
            "if (globalThis.__hanlinToolCount() !== \(expectedToolCount)) { throw new Error('HANLIN_ABI:tool_count_mismatch'); }",
            filename: "hanlin-script-export-check.js"
        )
    }

    func invoke(toolIndex: Int = 0, parameters: HanlinValue) async throws -> HanlinValue {
        let session = try activeSession()
        guard !Task.isCancelled else {
            throw HanlinScriptingError.cancelled
        }
        guard toolIndex >= 0 else {
            throw HanlinScriptingError.invalidBridgeValue("negative_tool_index")
        }
        let input = try HanlinValue.object([
            "__hanlinToolIndex": .integer(Int64(toolIndex)),
            "parameters": parameters
        ]).canonicalJSONData()
        guard input.count <= configuration.maximumOutputBytes else {
            throw HanlinScriptingError.resourceLimit("input_size")
        }
        hanlin_quickjs_session_reset_cancellation(session)
        let cancellationHandle = cancellationHandle
        let result = await withTaskCancellationHandler {
            input.withUnsafeBytes { bytes in
                hanlin_quickjs_session_invoke(
                    session,
                    bytes.bindMemory(to: CChar.self).baseAddress,
                    input.count,
                    configuration.timeoutMilliseconds
                )
            }
        } onCancel: {
            cancellationHandle.cancel()
        }
        return try decode(result)
    }

    func dispose() {
        guard let session else { return }
        self.session = nil
        disposed = true
        hanlin_quickjs_session_destroy(session)
    }

    private func evaluate(_ source: String, filename: String) throws {
        let session = try activeSession()
        let result = source.utf8CString.withUnsafeBufferPointer { sourceBuffer in
            filename.withCString { filenamePointer in
                hanlin_quickjs_session_evaluate(
                    session,
                    sourceBuffer.baseAddress,
                    max(0, sourceBuffer.count - 1),
                    filenamePointer,
                    configuration.timeoutMilliseconds
                )
            }
        }
        try requireSuccess(result)
    }

    private func decode(_ result: HanlinQuickJSResult) throws -> HanlinValue {
        defer { hanlin_quickjs_result_destroy(result) }
        guard result.status == HANLIN_QUICKJS_OK else {
            throw mappedError(result)
        }
        guard let pointer = result.value else {
            throw HanlinScriptingError.invalidBridgeValue("missing_result")
        }
        let data = Data(String(cString: pointer).utf8)
        guard data.count <= configuration.maximumOutputBytes else {
            throw HanlinScriptingError.resourceLimit("output_size")
        }
        do {
            return try HanlinValue.decodeCanonicalJSON(data)
        } catch {
            throw HanlinScriptingError.invalidBridgeValue("invalid_canonical_result")
        }
    }

    private func requireSuccess(_ result: HanlinQuickJSResult) throws {
        defer { hanlin_quickjs_result_destroy(result) }
        guard result.status == HANLIN_QUICKJS_OK else {
            throw mappedError(result)
        }
    }

    private func mappedError(_ result: HanlinQuickJSResult) -> HanlinScriptingError {
        let message = result.message.map { String(cString: $0) } ?? "script_failure"
        if result.status == HANLIN_QUICKJS_TIMED_OUT {
            return .executionTimedOut
        }
        if result.status == HANLIN_QUICKJS_CANCELLED {
            return .cancelled
        }
        if result.status == HANLIN_QUICKJS_MEMORY_LIMIT {
            return .resourceLimit("engine_memory")
        }
        if result.status == HANLIN_QUICKJS_STACK_LIMIT {
            return .resourceLimit("engine_stack")
        }
        if result.status == HANLIN_QUICKJS_PENDING_PROMISE {
            return .unsupportedABI("pending_host_capability")
        }
        if message.contains("HANLIN_BRIDGE:") {
            return .invalidBridgeValue(Self.redactedCode(from: message))
        }
        if message.contains("HANLIN_ABI:missing_execute_tool") {
            return .exportedToolMissing("execute")
        }
        return .moduleEvaluationFailed(Self.redactedCode(from: message))
    }

    private func activeSession() throws -> OpaquePointer {
        guard !disposed, let session else {
            throw HanlinScriptingError.unavailableProvider("disposed_session")
        }
        return session
    }

    private static func redactedCode(from message: String) -> String {
        let tail = message.split(separator: ":").last.map(String.init) ?? "script_failure"
        return String(tail.prefix(128))
    }
}
