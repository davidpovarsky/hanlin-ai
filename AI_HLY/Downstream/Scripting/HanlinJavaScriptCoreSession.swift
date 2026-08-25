@preconcurrency import JavaScriptCore
import Foundation
import HanlinPlatformContracts

private final class HanlinJSCInvocationContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, any Error>?

    init(_ continuation: CheckedContinuation<String, any Error>) {
        self.continuation = continuation
    }

    func resolve(_ value: String) { resume(.success(value)) }
    func reject(_ error: HanlinScriptingError) { resume(.failure(error)) }

    private func resume(_ result: Result<String, any Error>) {
        lock.lock()
        let current = continuation
        continuation = nil
        lock.unlock()
        current?.resume(with: result)
    }
}

/// A persistent JavaScriptCore compatibility session. JavaScriptCore exposes no
/// public hard memory, stack, or interrupt limit API, so this adapter relies on
/// an isolated VM/context, bounded bridge values, cooperative cancellation, and
/// deterministic disposal. It must only run package code allowed by trust policy.
actor HanlinJavaScriptCoreSession {
    struct Configuration: Hashable, Sendable {
        let maximumInputBytes: Int
        let maximumOutputBytes: Int

        static let scriptingCompatibility = Self(
            maximumInputBytes: 1_048_576,
            maximumOutputBytes: 1_048_576
        )
    }

    private var virtualMachine: JSVirtualMachine?
    private var context: JSContext?
    private let configuration: Configuration
    private var activeInvocation: (id: UUID, continuation: HanlinJSCInvocationContinuation)?
    private var disposed = false

    init(configuration: Configuration = .scriptingCompatibility) throws {
        guard let virtualMachine = JSVirtualMachine(),
              let context = JSContext(virtualMachine: virtualMachine) else {
            throw HanlinScriptingError.runtimeInitializationFailed
        }
        self.virtualMachine = virtualMachine
        self.context = context
        self.configuration = configuration
    }

    func loadProgram(_ javaScript: String, filename: String, expectedToolCount: Int) throws {
        let context = try activeContext()
        try evaluate(HanlinScriptValueBridge.bootstrap, filename: "hanlin-script-abi-1.0.js", in: context)
        try evaluate(javaScript, filename: filename, in: context)
        try evaluate(
            "if (globalThis.__hanlinToolCount() !== \(expectedToolCount)) { throw new Error('HANLIN_ABI:tool_count_mismatch'); }",
            filename: "hanlin-script-export-check.js",
            in: context
        )
    }

    func invoke(toolIndex: Int, parameters: HanlinValue) async throws -> HanlinValue {
        let context = try activeContext()
        guard activeInvocation == nil else {
            throw HanlinScriptingError.unavailableProvider("worker_session_busy")
        }
        guard !Task.isCancelled else { throw HanlinScriptingError.cancelled }
        let input = try HanlinValue.object([
            "__hanlinToolIndex": .integer(Int64(toolIndex)),
            "parameters": parameters
        ]).canonicalJSONData()
        guard input.count <= configuration.maximumInputBytes,
              let inputString = String(data: input, encoding: .utf8) else {
            throw HanlinScriptingError.resourceLimit("input_size")
        }
        let literalData = try JSONEncoder().encode(inputString)
        guard let literal = String(data: literalData, encoding: .utf8) else {
            throw HanlinScriptingError.invalidBridgeValue("input_encoding")
        }

        let invocationID = UUID()
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            await self?.timeoutInvocation(id: invocationID)
        }
        defer { timeoutTask.cancel() }
        let result: String
        do {
            result = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let bridge = HanlinJSCInvocationContinuation(continuation)
                    activeInvocation = (invocationID, bridge)
                    let resolve: @convention(block) (String) -> Void = { value in
                        bridge.resolve(value)
                    }
                    let reject: @convention(block) (JSValue) -> Void = { error in
                        bridge.reject(.moduleEvaluationFailed(
                            Self.redactedCode(from: error.toString())
                        ))
                    }
                    context.setObject(resolve, forKeyedSubscript: "__hanlinResolve" as NSString)
                    context.setObject(reject, forKeyedSubscript: "__hanlinReject" as NSString)
                    context.exceptionHandler = { _, value in
                        reject(value ?? JSValue(undefinedIn: context))
                    }
                    context.evaluateScript(
                        "Promise.resolve(globalThis.__hanlinInvoke(\(literal))).then(__hanlinResolve, __hanlinReject);",
                        withSourceURL: URL(string: "hanlin://invoke.js")
                    )
                }
            } onCancel: { [weak self] in
                Task { await self?.cancelInvocation(id: invocationID) }
            }
        } catch {
            finishInvocation(id: invocationID)
            throw error
        }
        finishInvocation(id: invocationID)
        guard !Task.isCancelled else { throw HanlinScriptingError.cancelled }
        let data = Data(result.utf8)
        guard data.count <= configuration.maximumOutputBytes else {
            throw HanlinScriptingError.resourceLimit("output_size")
        }
        do { return try HanlinValue.decodeCanonicalJSON(data) }
        catch { throw HanlinScriptingError.invalidBridgeValue("invalid_canonical_result") }
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        context?.evaluateScript("globalThis.__hanlinCancelCurrent?.();")
        activeInvocation?.continuation.reject(.unavailableProvider("disposed_session"))
        activeInvocation = nil
        context?.exceptionHandler = nil
        context = nil
        virtualMachine = nil
    }

    private func evaluate(_ source: String, filename: String, in context: JSContext) throws {
        var exception: JSValue?
        context.exceptionHandler = { _, value in exception = value }
        context.evaluateScript(source, withSourceURL: URL(string: "hanlin-package:///\(filename)"))
        context.exceptionHandler = nil
        if let exception {
            throw HanlinScriptingError.moduleEvaluationFailed(Self.redactedCode(from: exception.toString()))
        }
    }

    private func activeContext() throws -> JSContext {
        guard !disposed, let context else {
            throw HanlinScriptingError.unavailableProvider("disposed_session")
        }
        return context
    }

    private func cancelInvocation(id: UUID) {
        guard activeInvocation?.id == id else { return }
        context?.evaluateScript("globalThis.__hanlinCancelCurrent?.();")
        activeInvocation?.continuation.reject(.cancelled)
    }

    private func timeoutInvocation(id: UUID) {
        guard activeInvocation?.id == id else { return }
        context?.evaluateScript("globalThis.__hanlinCancelCurrent?.();")
        activeInvocation?.continuation.reject(.executionTimedOut)
    }

    private func finishInvocation(id: UUID) {
        guard activeInvocation?.id == id else { return }
        activeInvocation = nil
        context?.setObject(nil, forKeyedSubscript: "__hanlinResolve" as NSString)
        context?.setObject(nil, forKeyedSubscript: "__hanlinReject" as NSString)
        context?.exceptionHandler = nil
    }

    private static func redactedCode(from message: String?) -> String {
        let tail = message?.split(separator: ":").last.map(String.init) ?? "script_failure"
        return String(tail.prefix(128))
    }
}
