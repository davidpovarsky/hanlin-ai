import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import OSLog
import SwiftAISDK
import Synchronization

/// Connects Swift AI SDK's existing spans to the original OpenTelemetry Swift SDK.
///
/// The adapter retains operation metadata and usage counts, never prompts,
/// completions, headers, tool arguments/results, exception messages, or stacks.
/// An exporter must be supplied explicitly; this type never configures a global
/// tracer, reads exporter credentials, or installs a network exporter.
public final class HanlinOpenTelemetryTracer: SwiftAISDK.Tracer, Sendable {
    /// The native app's local diagnostics destination. No network export occurs.
    public static let local = HanlinOpenTelemetryTracer(exporter: HanlinOSLogSpanExporter())

    private let backend: HanlinTelemetryBackend

    /// The caller owns exporter configuration and any explicit remote destination.
    /// Export uses the original SDK's bounded batch processor (256 queued spans).
    public init(exporter: (any OpenTelemetrySdk.SpanExporter)? = nil) {
        backend = HanlinTelemetryBackend(exporter: exporter)
    }

    public func telemetrySettings() -> SwiftAISDK.TelemetrySettings {
        SwiftAISDK.TelemetrySettings(
            isEnabled: true,
            recordInputs: false,
            recordOutputs: false,
            functionId: "hanlin.chat",
            tracer: self
        )
    }

    public func startSpan(name: String, options: SwiftAISDK.SpanOptions?) -> any SwiftAISDK.Span {
        makeSpan(name: name, options: options)
    }

    public func startActiveSpan<T>(
        _ name: String,
        options: SwiftAISDK.SpanOptions?,
        _ fn: @Sendable (any SwiftAISDK.Span) async throws -> T
    ) async rethrows -> T {
        let span = makeSpan(name: name, options: options)
        // SwiftAISDK.recordSpan owns end(), including streaming spans whose
        // lifetime continues after this closure. Do not end the span here.
        return try await HanlinTelemetryContext.$parent.withValue(span.context) {
            try await fn(span)
        }
    }

    /// Flush during an explicit diagnostics/export lifecycle boundary, off the UI
    /// path. Exporters are responsible for respecting the supplied time budget.
    public func forceFlush(timeout: TimeInterval = 5) {
        backend.forceFlush(timeout: timeout.isFinite ? max(0, timeout) : 5)
    }

    /// Idempotently drains the processor and releases its worker.
    public func shutdown() {
        backend.shutdown()
    }

    private func makeSpan(name: String, options: SwiftAISDK.SpanOptions?) -> HanlinOpenTelemetrySpan {
        let token = backend.start(
            name: HanlinTelemetryPrivacy.spanName(name),
            attributes: HanlinTelemetryPrivacy.attributes(options?.attributes ?? [:]),
            parent: HanlinTelemetryContext.parent
        )
        return HanlinOpenTelemetrySpan(backend: backend, token: token)
    }
}

private enum HanlinTelemetryContext {
    @TaskLocal static var parent: OpenTelemetryApi.SpanContext?
}

/// Original OpenTelemetry reference types stay behind one mutex. Only Sendable
/// contexts and opaque handles cross it; no unchecked conformance is required.
private final class HanlinTelemetryBackend: Sendable {
    struct Token: Sendable {
        let id: UUID
        let context: OpenTelemetryApi.SpanContext
    }

    private struct State {
        let provider: TracerProviderSdk
        var spans: [UUID: any OpenTelemetryApi.Span] = [:]
        var isShutdown = false
    }

    private let state: Mutex<State>

    init(exporter: (any OpenTelemetrySdk.SpanExporter)?) {
        let limits = SpanLimits()
            .settingAttributeCountLimit(64)
            .settingAttributeValueLengthLimit(160)
            .settingEventCountLimit(16)
            .settingAttributePerEventCountLimit(8)
        let builder = TracerProviderBuilder().with(spanLimits: limits)
        if let exporter {
            builder.add(spanProcessor: BatchSpanProcessor(
                spanExporter: exporter,
                scheduleDelay: 1,
                exportTimeout: 5,
                maxQueueSize: 256,
                maxExportBatchSize: 64
            ))
        }
        state = Mutex(State(provider: builder.build()))
    }

    deinit {
        state.withLock { state in
            if !state.isShutdown {
                state.provider.shutdown()
            }
        }
    }

    func start(
        name: String,
        attributes: [String: OpenTelemetryApi.AttributeValue],
        parent: OpenTelemetryApi.SpanContext?
    ) -> Token {
        state.withLock { state in
            let builder = state.provider
                .get(instrumentationName: "HanlinChatCore")
                .spanBuilder(spanName: name)
            if let parent {
                builder.setParent(parent)
            } else {
                builder.setNoParent()
            }
            // Context is task-scoped above, never OpenTelemetry's global/thread
            // active context, which could join unrelated concurrent requests.
            builder.setActive(false)
            for (key, value) in attributes {
                builder.setAttribute(key: key, value: value)
            }
            let span = builder.startSpan()
            let token = Token(id: UUID(), context: span.context)
            if !state.isShutdown, span.isRecording {
                state.spans[token.id] = span
            }
            return token
        }
    }

    func setAttributes(_ attributes: [String: OpenTelemetryApi.AttributeValue], for id: UUID) {
        state.withLock { $0.spans[id]?.setAttributes(attributes) }
    }

    func addEvent(_ name: String, attributes: [String: OpenTelemetryApi.AttributeValue], for id: UUID) {
        state.withLock { $0.spans[id]?.addEvent(name: name, attributes: attributes) }
    }

    func setStatus(_ status: OpenTelemetryApi.Status, for id: UUID) {
        state.withLock { $0.spans[id]?.status = status }
    }

    func updateName(_ name: String, for id: UUID) {
        state.withLock { $0.spans[id]?.name = name }
    }

    func end(_ id: UUID) {
        state.withLock { state in
            // Remove first: repeated end() and later mutations become no-ops.
            state.spans.removeValue(forKey: id)?.end()
        }
    }

    func isRecording(_ id: UUID) -> Bool {
        state.withLock { $0.spans[id]?.isRecording ?? false }
    }

    func forceFlush(timeout: TimeInterval) {
        state.withLock { state in
            guard !state.isShutdown else { return }
            state.provider.forceFlush(timeout: timeout)
        }
    }

    func shutdown() {
        state.withLock { state in
            guard !state.isShutdown else { return }
            state.isShutdown = true
            state.spans.removeAll()
            state.provider.shutdown()
        }
    }
}

private final class HanlinOpenTelemetrySpan: SwiftAISDK.Span, Sendable {
    private let backend: HanlinTelemetryBackend
    private let token: HanlinTelemetryBackend.Token
    var context: OpenTelemetryApi.SpanContext { token.context }

    init(backend: HanlinTelemetryBackend, token: HanlinTelemetryBackend.Token) {
        self.backend = backend
        self.token = token
    }

    func spanContext() -> SwiftAISDK.SpanContext {
        SwiftAISDK.SpanContext(
            traceId: context.traceId.hexString,
            spanId: context.spanId.hexString,
            traceFlags: Int(context.traceFlags.byte)
        )
    }

    @discardableResult
    func setAttribute(_ key: String, value: SwiftAISDK.AttributeValue) -> Self {
        setAttributes([key: value])
    }

    @discardableResult
    func setAttributes(_ attributes: SwiftAISDK.Attributes) -> Self {
        backend.setAttributes(HanlinTelemetryPrivacy.attributes(attributes), for: token.id)
        return self
    }

    @discardableResult
    func addEvent(_ name: String, attributes: SwiftAISDK.Attributes?) -> Self {
        guard HanlinTelemetryPrivacy.eventNames.contains(name) else { return self }
        backend.addEvent(
            name,
            attributes: HanlinTelemetryPrivacy.attributes(attributes ?? [:]),
            for: token.id
        )
        return self
    }

    @discardableResult
    func setStatus(_ status: SwiftAISDK.SpanStatus) -> Self {
        let safeStatus: OpenTelemetryApi.Status
        switch status.code {
        case .unset: safeStatus = .unset
        case .ok: safeStatus = .ok
        case .error: safeStatus = .error(description: "Model operation failed")
        }
        backend.setStatus(safeStatus, for: token.id)
        return self
    }

    @discardableResult
    func updateName(_ name: String) -> Self {
        backend.updateName(HanlinTelemetryPrivacy.spanName(name), for: token.id)
        return self
    }

    func end() { backend.end(token.id) }
    func isRecording() -> Bool { backend.isRecording(token.id) }

    @discardableResult
    func recordException(_ exception: SwiftAISDK.ExceptionEvent) -> Self {
        // The SDK can place a provider response or user content in NSError's
        // description/domain. Record a fixed category, never any raw error text.
        backend.addEvent(
            "exception",
            attributes: ["exception.type": .string("ModelOperationError")],
            for: token.id
        )
        return self
    }
}

private enum HanlinTelemetryPrivacy {
    static let eventNames: Set<String> = [
        "ai.stream.firstChunk", "ai.stream.finish", "ai.stream.abort"
    ]

    private static let spanNames: Set<String> = [
        "ai.streamText", "ai.streamText.doStream",
        "ai.generateText", "ai.generateText.doGenerate", "ai.toolCall",
        "ai.streamObject", "ai.streamObject.doStream",
        "ai.generateObject", "ai.generateObject.doGenerate"
    ]

    private static let identifiers: Set<String> = [
        "ai.model.provider", "ai.model.id", "ai.toolCall.name",
        "gen_ai.system", "gen_ai.provider.name",
        "gen_ai.request.model", "gen_ai.response.model"
    ]

    private static let tokenCounts: Set<String> = [
        "ai.usage.inputTokens", "ai.usage.outputTokens", "ai.usage.totalTokens",
        "ai.usage.promptTokens", "ai.usage.completionTokens",
        "ai.usage.reasoningTokens", "ai.usage.cachedInputTokens", "ai.usage.cacheWriteTokens",
        "gen_ai.usage.input_tokens", "gen_ai.usage.output_tokens",
        "gen_ai.usage.reasoning.output_tokens", "gen_ai.usage.cache_read.input_tokens",
        "gen_ai.usage.cache_write.input_tokens"
    ]

    private static let numericMetadata: Set<String> = [
        "ai.response.msToFirstChunk", "ai.response.msToFinish",
        "ai.response.avgOutputTokensPerSecond",
        "ai.settings.maxOutputTokens", "ai.settings.topP", "ai.settings.topK",
        "ai.settings.presencePenalty", "ai.settings.frequencyPenalty",
        "ai.settings.maxRetries", "ai.settings.timeout",
        "gen_ai.request.max_tokens", "gen_ai.request.temperature",
        "gen_ai.request.top_p", "gen_ai.request.top_k",
        "gen_ai.request.presence_penalty", "gen_ai.request.frequency_penalty"
    ]

    private static let finishReasons: Set<String> = [
        "stop", "length", "tool-calls", "content-filter", "error", "other", "unknown",
        "end_turn", "max_tokens", "stop_sequence", "tool_use",
        "STOP", "MAX_TOKENS", "SAFETY", "RECITATION", "OTHER"
    ]

    // Original SDK attributes remain available. These are aliases of the same
    // counts, not extra charges; never add aliases or nested span usage together.
    private static let usageAliases = [
        "ai.usage.inputTokens": "gen_ai.usage.input_tokens",
        "ai.usage.outputTokens": "gen_ai.usage.output_tokens",
        "ai.usage.reasoningTokens": "gen_ai.usage.reasoning.output_tokens",
        "ai.usage.cachedInputTokens": "gen_ai.usage.cache_read.input_tokens",
        "ai.usage.cacheWriteTokens": "gen_ai.usage.cache_write.input_tokens"
    ]

    static func spanName(_ name: String) -> String {
        spanNames.contains(name) ? name : "ai.operation"
    }

    static func attributes(_ attributes: SwiftAISDK.Attributes) -> [String: OpenTelemetryApi.AttributeValue] {
        var result: [String: OpenTelemetryApi.AttributeValue] = [:]
        for (key, value) in attributes {
            if tokenCounts.contains(key), case .int(let count) = value, count >= 0 {
                result[key] = .int(count)
            } else if numericMetadata.contains(key) {
                switch value {
                case .int(let number): result[key] = .int(number)
                case .double(let number) where number.isFinite: result[key] = .double(number)
                default: break
                }
            } else if identifiers.contains(key), case .string(let identifier) = value,
                      isIdentifier(identifier) {
                result[key] = .string(identifier)
            } else if key == "ai.telemetry.functionId", value == .string("hanlin.chat") {
                result[key] = .string("hanlin.chat")
            } else if key == "ai.response.finishReason", case .string(let reason) = value {
                result[key] = .string(finishReasons.contains(reason) ? reason : "other")
            } else if key == "gen_ai.response.finish_reasons", case .stringArray(let reasons) = value {
                result[key] = .array(AttributeArray(values: reasons.prefix(8).map {
                    .string(finishReasons.contains($0) ? $0 : "other")
                }))
            }
        }
        for (source, destination) in usageAliases where result[destination] == nil {
            result[destination] = result[source]
        }
        return result
    }

    private static func isIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 160 && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                || [UInt8(45), 46, 47, 58, 95].contains($0)
        }
    }
}

/// A local-only exporter for the native app's diagnostics mode. It logs bounded
/// operation metadata and counts; unknown counts remain visibly unavailable.
public final class HanlinOSLogSpanExporter: OpenTelemetrySdk.SpanExporter, Sendable {
    private let logger = Logger(subsystem: "com.hanlin.ai", category: "model.telemetry")

    public init() {}

    @discardableResult
    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        write(spans)
        return .success
    }

    @discardableResult
    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        write(spans)
        return .success
    }

    public func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode { .success }
    public func flush(explicitTimeout: TimeInterval?) async -> SpanExporterResultCode { .success }
    public func shutdown(explicitTimeout: TimeInterval?) {}
    public func shutdown(explicitTimeout: TimeInterval?) async {}

    private func write(_ spans: [SpanData]) {
        for span in spans {
            let operation = HanlinTelemetryPrivacy.spanName(span.name)
            let durationMS = max(0, span.endTime.timeIntervalSince(span.startTime) * 1_000)
            let input = count("ai.usage.inputTokens", in: span)
            let output = count("ai.usage.outputTokens", in: span)
            let read = count("ai.usage.cachedInputTokens", in: span)
            let write = count("ai.usage.cacheWriteTokens", in: span)
            let failed = span.status.isError
            logger.debug("operation=\(operation, privacy: .public) duration_ms=\(durationMS, privacy: .public) input=\(input, privacy: .public) output=\(output, privacy: .public) cache_read=\(read, privacy: .public) cache_write=\(write, privacy: .public) failed=\(failed, privacy: .public)")
        }
    }

    private func count(_ key: String, in span: SpanData) -> String {
        guard case .int(let count) = span.attributes[key], count >= 0 else { return "unavailable" }
        return String(count)
    }
}
