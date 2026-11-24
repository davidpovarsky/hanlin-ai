import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import SwiftAISDK
import Synchronization
import Testing
@testable import HanlinChatCore

@Suite("Original OpenTelemetry bridge", .timeLimit(.minutes(1)))
struct HanlinOpenTelemetryTracerTests {
    @Test
    func settingsDisableContentAndUseTheInjectedTracer() {
        let tracer = HanlinOpenTelemetryTracer()
        let settings = tracer.telemetrySettings()
        #expect(settings.isEnabled == true)
        #expect(settings.recordInputs == false)
        #expect(settings.recordOutputs == false)
        #expect(settings.functionId == "hanlin.chat")
        #expect(settings.metadata == nil)
        #expect((settings.tracer as? HanlinOpenTelemetryTracer) === tracer)
        tracer.shutdown()
    }

    @Test
    func originalSDKExportsCacheCountsAndDropsContent() throws {
        let exporter = CapturingHanlinSpanExporter()
        let tracer = HanlinOpenTelemetryTracer(exporter: exporter)
        defer { tracer.shutdown() }
        let span = tracer.startSpan(name: "ai.streamText", options: .init(attributes: [
            "ai.model.provider": .string("anthropic.messages"),
            "ai.model.id": .string("claude-sonnet-4"),
            "ai.prompt.messages": .string("PRIVATE_PROMPT"),
            "ai.request.headers.Authorization": .string("PRIVATE_CREDENTIAL"),
            "ai.telemetry.metadata.user": .string("PRIVATE_PERSON"),
            "ai.settings.stopSequences": .stringArray(["PRIVATE_STOP"])
        ]))
        span.setAttributes([
            "ai.usage.inputTokens": .int(150),
            "ai.usage.outputTokens": .int(25),
            "ai.usage.cachedInputTokens": .int(100),
            "ai.usage.cacheWriteTokens": .int(30),
            "ai.usage.reasoningTokens": .int(5),
            "ai.response.text": .string("PRIVATE_RESPONSE"),
            "ai.toolCall.args": .string("PRIVATE_TOOL_ARGUMENT"),
            "ai.toolCall.result": .string("PRIVATE_TOOL_RESULT"),
            "ai.response.providerMetadata": .string("PRIVATE_PROVIDER_METADATA"),
            "ai.response.finishReason": .string("stop"),
            "gen_ai.response.finish_reasons": .stringArray(["stop"])
        ])
        span.addEvent("ai.stream.firstChunk", attributes: [
            "ai.response.msToFirstChunk": .double(12),
            "ai.response.text": .string("PRIVATE_CHUNK")
        ])
        span.addEvent("PRIVATE_EVENT", attributes: nil)
        span.end()
        tracer.forceFlush()
        let data = try #require(exporter.spans.first)
        #expect(exporter.spans.count == 1)
        #expect(data.name == "ai.streamText")
        #expect(data.attributes["ai.model.provider"] == .string("anthropic.messages"))
        #expect(data.attributes["ai.usage.inputTokens"] == .int(150))
        #expect(data.attributes["ai.usage.cachedInputTokens"] == .int(100))
        #expect(data.attributes["ai.usage.cacheWriteTokens"] == .int(30))
        #expect(data.attributes["gen_ai.usage.input_tokens"] == .int(150))
        #expect(data.attributes["gen_ai.usage.output_tokens"] == .int(25))
        #expect(data.attributes["gen_ai.usage.cache_read.input_tokens"] == .int(100))
        #expect(data.attributes["gen_ai.usage.cache_write.input_tokens"] == .int(30))
        #expect(data.attributes["gen_ai.usage.reasoning.output_tokens"] == .int(5))
        #expect(data.events.count == 1)
        #expect(data.events.first?.attributes["ai.response.msToFirstChunk"] == .double(12))
        #expect(!String(decoding: try JSONEncoder().encode(data), as: UTF8.self).contains("PRIVATE"))
    }

    @Test
    func errorsNamesAndInvalidNumbersCannotExportRawContent() throws {
        let exporter = CapturingHanlinSpanExporter()
        let tracer = HanlinOpenTelemetryTracer(exporter: exporter)
        defer { tracer.shutdown() }
        let span = tracer.startSpan(name: "PRIVATE_SPAN")
        span.updateName("PRIVATE_UPDATED_SPAN")
        span.setStatus(.init(code: .error, message: "PRIVATE_STATUS"))
        span.recordException(.init(name: "PRIVATE_DOMAIN", message: "PRIVATE_ERROR", stack: "PRIVATE_STACK"))
        span.setAttributes([
            "ai.usage.cachedInputTokens": .int(-1),
            "ai.usage.cacheWriteTokens": .int(0),
            "ai.response.msToFirstChunk": .double(.infinity),
            "ai.model.id": .string("PRIVATE MODEL CONTENT"),
            "gen_ai.response.finish_reasons": .stringArray(["PRIVATE_REASON"])
        ])
        span.end()
        tracer.forceFlush()
        let data = try #require(exporter.spans.first)
        #expect(data.name == "ai.operation")
        #expect(data.status == .error(description: "Model operation failed"))
        #expect(data.attributes["ai.usage.cachedInputTokens"] == nil)
        #expect(data.attributes["gen_ai.usage.cache_read.input_tokens"] == nil)
        #expect(data.attributes["ai.usage.cacheWriteTokens"] == .int(0))
        #expect(data.attributes["ai.response.msToFirstChunk"] == nil)
        #expect(data.attributes["ai.model.id"] == nil)
        #expect(data.events.first?.name == "exception")
        #expect(data.events.first?.attributes["exception.type"] == .string("ModelOperationError"))
        #expect(!String(decoding: try JSONEncoder().encode(data), as: UTF8.self).contains("PRIVATE"))
    }

    @Test
    func taskContextPreservesParentageAcrossSuspensionAndSeparatesConcurrentRequests() async throws {
        let exporter = CapturingHanlinSpanExporter()
        let tracer = HanlinOpenTelemetryTracer(exporter: exporter)
        defer { tracer.shutdown() }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    await tracer.startActiveSpan("ai.streamText") { root in
                        await Task.yield()
                        let child = tracer.startSpan(name: "ai.streamText.doStream")
                        #expect(child.spanContext().traceId == root.spanContext().traceId)
                        #expect(child.spanContext().spanId != root.spanContext().spanId)
                        child.end()
                        root.end()
                    }
                }
            }
        }
        tracer.forceFlush()
        let spans = exporter.spans
        let roots = spans.filter { $0.name == "ai.streamText" }
        let children = spans.filter { $0.name == "ai.streamText.doStream" }
        #expect(roots.count == 4)
        #expect(children.count == 4)
        #expect(Set(roots.map { $0.traceId.hexString }).count == 4)
        #expect(roots.allSatisfy { $0.parentSpanId == nil })
        for child in children {
            let parent = try #require(roots.first { $0.traceId == child.traceId })
            #expect(child.parentSpanId == parent.spanId)
        }
        let next = tracer.startSpan(name: "ai.generateText")
        next.end()
        tracer.forceFlush()
        let subsequent = try #require(exporter.spans.first { $0.name == "ai.generateText" })
        #expect(subsequent.parentSpanId == nil)
        #expect(!roots.contains { $0.traceId == subsequent.traceId })
    }

    @Test
    func streamingSpanOutlivesActiveClosureAndEndsExactlyOnce() async throws {
        let exporter = CapturingHanlinSpanExporter()
        let tracer = HanlinOpenTelemetryTracer(exporter: exporter)
        defer { tracer.shutdown() }
        let span = await tracer.startActiveSpan("ai.streamText") { span in span }
        tracer.forceFlush()
        #expect(span.isRecording())
        #expect(exporter.spans.isEmpty)
        span.setAttribute("ai.usage.cacheWriteTokens", value: .int(20))
        span.end()
        span.end()
        span.setAttribute("ai.usage.cacheWriteTokens", value: .int(999))
        tracer.forceFlush()
        #expect(!span.isRecording())
        #expect(exporter.spans.count == 1)
        let data = try #require(exporter.spans.first)
        #expect(data.attributes["ai.usage.cacheWriteTokens"] == .int(20))
    }

    @Test
    func shutdownDrainsBoundedProcessorAndIsIdempotent() {
        let exporter = CapturingHanlinSpanExporter()
        let tracer = HanlinOpenTelemetryTracer(exporter: exporter)
        let span = tracer.startSpan(name: "ai.generateText")
        span.end()
        tracer.shutdown()
        tracer.shutdown()
        #expect(exporter.spans.count == 1)
        #expect(exporter.shutdownCount == 1)
        let afterShutdown = tracer.startSpan(name: "ai.generateText")
        #expect(!afterShutdown.isRecording())
        afterShutdown.end()
        tracer.forceFlush()
        #expect(exporter.spans.count == 1)
    }
}

/// This is an exporter sink for the original OpenTelemetry SDK, not a substitute
/// tracer/processor. Every test above exercises the real SDK span lifecycle.
private final class CapturingHanlinSpanExporter: OpenTelemetrySdk.SpanExporter, Sendable {
    private struct State {
        var spans: [SpanData] = []
        var shutdownCount = 0
    }
    private let state = Mutex(State())

    var spans: [SpanData] { state.withLock { $0.spans } }
    var shutdownCount: Int { state.withLock { $0.shutdownCount } }

    @discardableResult
    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        state.withLock { $0.spans.append(contentsOf: spans) }
        return .success
    }

    @discardableResult
    func export(spans: [SpanData], explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        state.withLock { $0.spans.append(contentsOf: spans) }
        return .success
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode { .success }
    func flush(explicitTimeout: TimeInterval?) async -> SpanExporterResultCode { .success }
    func shutdown(explicitTimeout: TimeInterval?) { state.withLock { $0.shutdownCount += 1 } }
    func shutdown(explicitTimeout: TimeInterval?) async { state.withLock { $0.shutdownCount += 1 } }
}
