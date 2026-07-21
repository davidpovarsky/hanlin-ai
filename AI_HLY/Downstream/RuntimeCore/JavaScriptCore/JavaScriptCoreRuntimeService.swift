@preconcurrency import JavaScriptCore
import Foundation

actor JavaScriptCoreRuntimeService {
    private var snapshotValue = RuntimeSnapshot.stopped(.javaScriptCore)

    func snapshot() -> RuntimeSnapshot { snapshotValue }

    func healthCheck() throws -> RuntimeSnapshot {
        guard let context = JSContext(), context.evaluateScript("1 + 2")?.toInt32() == 3 else {
            snapshotValue.state = .failed
            throw RuntimeCoreError.runtimeUnavailable(.javaScriptCore)
        }
        snapshotValue.state = .ready
        snapshotValue.version = "Apple JavaScriptCore"
        snapshotValue.source = "Apple JavaScriptCore.framework"
        snapshotValue.lastHealthCheck = .now
        snapshotValue.lastErrorCode = nil
        return snapshotValue
    }

    func execute(_ request: RuntimeExecutionRequest) throws -> RuntimeExecutionResult {
        guard request.source.utf8.count <= 2 * 1_024 * 1_024 else { throw RuntimeCoreError.invalidRequest("JavaScriptCore source exceeds 2 MB.") }
        guard !request.source.contains("while (true)"), !request.source.contains("for (;;)") else {
            throw RuntimeCoreError.invalidRequest("Potentially unbounded loops must run in the cancellable Node worker runtime.")
        }
        let started = ContinuousClock.now
        guard let context = JSContext() else { throw RuntimeCoreError.runtimeUnavailable(.javaScriptCore) }
        snapshotValue.state = .executing
        snapshotValue.activeExecutionCount += 1
        defer {
            snapshotValue.activeExecutionCount = max(0, snapshotValue.activeExecutionCount - 1)
            snapshotValue.state = .ready
        }
        var stdout = ""
        var stderr = ""
        let append: @convention(block) (String, Bool) -> Void = { text, isError in
            if isError { stderr += text + "\n" } else { stdout += text + "\n" }
        }
        context.setObject(append, forKeyedSubscript: "__hanlinConsole" as NSString)
        context.evaluateScript("""
            globalThis.console = {
              log: (...values) => __hanlinConsole(values.map(value => typeof value === 'string' ? value : JSON.stringify(value)).join(' '), false),
              info: (...values) => __hanlinConsole(values.map(value => typeof value === 'string' ? value : JSON.stringify(value)).join(' '), false),
              warn: (...values) => __hanlinConsole(values.map(value => typeof value === 'string' ? value : JSON.stringify(value)).join(' '), true),
              error: (...values) => __hanlinConsole(values.map(value => typeof value === 'string' ? value : JSON.stringify(value)).join(' '), true)
            };
            """)
        context.setObject(request.arguments, forKeyedSubscript: "arguments" as NSString)
        context.setObject(request.environment, forKeyedSubscript: "environment" as NSString)
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        let value = context.evaluateScript(request.source)
        if let exception { stderr += exception + "\n" }
        let jsonValue = value.flatMap(Self.convert)
        let duration = started.duration(to: .now)
        let milliseconds = duration.components.seconds * 1_000 + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
        let total = stdout.utf8.count + stderr.utf8.count
        return RuntimeExecutionResult(
            executionID: request.id,
            stdout: String(decoding: stdout.utf8.prefix(request.limits.maximumOutputBytes), as: UTF8.self),
            stderr: String(decoding: stderr.utf8.prefix(max(0, request.limits.maximumOutputBytes - min(stdout.utf8.count, request.limits.maximumOutputBytes))), as: UTF8.self),
            value: jsonValue,
            exitCode: exception == nil ? 0 : 1,
            durationMilliseconds: milliseconds,
            didTimeOut: false,
            wasCancelled: false,
            outputWasTruncated: total > request.limits.maximumOutputBytes
        )
    }

    private static func convert(_ value: JSValue) -> RuntimeJSONValue? {
        if value.isUndefined || value.isNull { return .null }
        if value.isBoolean { return .boolean(value.toBool()) }
        if value.isNumber { return .number(value.toDouble()) }
        if value.isString { return .string(value.toString()) }
        guard let object = value.toObject(), JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return .string(value.toString()) }
        return try? JSONDecoder().decode(RuntimeJSONValue.self, from: data)
    }
}
