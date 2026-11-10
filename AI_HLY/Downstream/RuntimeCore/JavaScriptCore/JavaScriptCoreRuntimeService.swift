@preconcurrency import JavaScriptCore
import Foundation

actor JavaScriptCoreRuntimeService {
    private static let executionQueue = DispatchQueue(label: "hanlin.javascriptcore.execution", qos: .userInitiated)
    private typealias Pending = RuntimeQueuedExecution<URL, RuntimeExecutionResult>
    private let environmentStore: RuntimeEnvironmentStore?
    private let jobs: RuntimeJobStore
    private var active: [UUID: Pending] = [:]
    private var stopGeneration: UInt64 = 0
    private var stopRequested = false
    init(environment: RuntimeEnvironmentStore? = nil, fileLayout: RuntimeFileLayout = .default, jobs: RuntimeJobStore? = nil) {
        self.environmentStore = environment
        self.jobs = jobs ?? RuntimeJobStore(fileLayout: fileLayout)
    }
    private var snapshotValue = RuntimeSnapshot.stopped(.javaScriptCore)

    func snapshot() -> RuntimeSnapshot { snapshotValue }

    func healthCheck() throws -> RuntimeSnapshot {
        guard let context = JSContext(), context.evaluateScript("1 + 2")?.toInt32() == 3 else {
            snapshotValue.state = .failed
            throw RuntimeCoreError.runtimeUnavailable(.javaScriptCore)
        }
        snapshotValue.state = active.isEmpty ? .ready : .executing
        snapshotValue.version = "Apple JavaScriptCore"
        snapshotValue.source = "Apple JavaScriptCore.framework"
        snapshotValue.lastHealthCheck = .now
        snapshotValue.lastErrorCode = nil
        return snapshotValue
    }

    func stop() async -> RuntimeSnapshot {
        stopGeneration &+= 1
        stopRequested = true
        for id in Array(active.keys) { try? await cancel(id: id) }
        if active.isEmpty { snapshotValue = .stopped(.javaScriptCore) }
        else { snapshotValue.lastDiagnostic = "Stop requested. Queued JavaScript is skipped; running JavaScriptCore must return naturally. Use Node workers for interruptible work." }
        return snapshotValue
    }

    func cancel(id: UUID) async throws {
        active[id]?.cancelBeforeStarting()
        try await jobs.requestCancellation(id: id, kind: .javaScriptCore)
    }

    func execute(_ request: RuntimeExecutionRequest) async throws -> RuntimeExecutionResult {
        guard request.limits.timeout == nil else {
            throw RuntimeCoreError.invalidRequest("JavaScriptCore cannot safely enforce a running-code deadline. Select Node workers for explicit deadlines; no source was executed.")
        }
        let generation = stopGeneration
        let owner = RuntimeUserOperation.current
        try owner?.checkInterruption()
        try Task.checkCancellation()
        let environment = try await environmentStore?.resolved(scopes: [.shared, .javaScriptCore, .execution(request.id)], overrides: request.environment)
            ?? RuntimePolicy.validatedEnvironment(request.environment)
        guard generation == stopGeneration else { throw CancellationError() }
        try owner?.checkInterruption()
        try Task.checkCancellation()
        let initial = try await jobs.create(id: request.id, kind: .javaScriptCore)
        let pending = Pending()
        active[request.id] = pending
        let jobs = self.jobs
        let interruption = owner?.registerInterruption { reason in
            pending.cancelBeforeStarting()
            Task { try? await jobs.requestInterruption(id: request.id, kind: .javaScriptCore, reason: reason) }
        }
        defer { if let interruption { owner?.unregisterInterruption(interruption) } }
        if generation != stopGeneration || Task.isCancelled { pending.cancelBeforeStarting() }
        stopRequested = generation != stopGeneration
        snapshotValue.state = .executing
        snapshotValue.activeExecutionCount = active.count
        defer {
            active.removeValue(forKey: request.id)
            snapshotValue.activeExecutionCount = active.count
            if active.isEmpty { snapshotValue.state = stopRequested ? .stopped : .ready }
        }
        let observer = RuntimeJobProgress.reporter
        let progress = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                    if let record = try await jobs.refresh(id: request.id, kind: .javaScriptCore), let observer { await observer(record) }
                } catch { return }
            }
        }
        defer { progress.cancel() }
        if let observer { await observer(initial) }
        let directory = jobs.directory(id: request.id, kind: .javaScriptCore)
        do {
            let output = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RuntimeExecutionResult, any Error>) in
                    guard pending.bind(continuation, input: directory) else { return }
                    Self.executionQueue.async {
                        guard let directory = pending.takeForRunning() else { return }
                        do {
                            try owner?.checkInterruption()
                            Task { try? await jobs.markRunning(id: request.id, kind: .javaScriptCore) }
                            pending.complete(.success(try Self.evaluate(request, environment: environment, directory: directory)))
                        } catch { pending.complete(.failure(error)) }
                    }
                }
            } onCancel: {
                pending.cancelBeforeStarting()
                Task { try? await jobs.requestCancellation(id: request.id, kind: .javaScriptCore) }
            }
            let result = output.recordingCancellation(Task.isCancelled)
            owner?.recordJobOutput(id: request.id, stdout: result.outputFiles?["stdout"]?.bytes ?? 0, stderr: result.outputFiles?["stderr"]?.bytes ?? 0)
            let completed = try await jobs.complete(result, kind: .javaScriptCore)
            if let observer, let record = try await jobs.snapshot(id: request.id, kind: .javaScriptCore) { await observer(record) }
            return completed
        } catch {
            try? await jobs.fail(id: request.id, kind: .javaScriptCore, error: error)
            throw error
        }
    }

    /// Contexts/callbacks stay on the synchronous execution queue. Public JSC
    /// APIs cannot safely kill running code; the actor stays responsive meanwhile.
    private static func evaluate(_ request: RuntimeExecutionRequest, environment: [String: String], directory: URL) throws -> RuntimeExecutionResult {
        let started = ContinuousClock.now
        guard let context = JSContext() else { throw RuntimeCoreError.runtimeUnavailable(.javaScriptCore) }
        let capture = try JavaScriptCoreOutputCapture(directory: directory)
        defer { capture.close() }
        let append: @convention(block) (String, Bool) -> Void = { [weak context] text, isError in
            do { try capture.append(text + "\n", isError: isError) }
            catch {
                capture.failure = capture.failure ?? error
                context?.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: context)
            }
        }
        context.setObject(append, forKeyedSubscript: "__hanlinConsole" as NSString)
        defer {
            context.exceptionHandler = nil
            context.setObject(nil, forKeyedSubscript: "__hanlinConsole" as NSString)
        }
        context.evaluateScript("""
            globalThis.console = {
              log: (...values) => __hanlinConsole(values.map(value => typeof value === 'string' ? value : JSON.stringify(value)).join(' '), false),
              info: (...values) => __hanlinConsole(values.map(value => typeof value === 'string' ? value : JSON.stringify(value)).join(' '), false),
              warn: (...values) => __hanlinConsole(values.map(value => typeof value === 'string' ? value : JSON.stringify(value)).join(' '), true),
              error: (...values) => __hanlinConsole(values.map(value => typeof value === 'string' ? value : JSON.stringify(value)).join(' '), true)
            };
            """)
        context.setObject(request.arguments, forKeyedSubscript: "arguments" as NSString)
        context.setObject(environment, forKeyedSubscript: "environment" as NSString)
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        let value = context.evaluateScript(request.source)
        if let exception { try capture.append(exception + "\n", isError: true) }
        if let error = capture.failure { throw error }
        let jsonValue = value.flatMap(Self.convert)
        let duration = started.duration(to: .now)
        let milliseconds = duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000
        return try capture.result(id: request.id, value: jsonValue, exitCode: exception == nil ? 0 : 1,
            milliseconds: milliseconds, previewBytes: request.limits.maximumOutputBytes)
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
