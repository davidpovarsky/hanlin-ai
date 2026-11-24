// HanlinChatEngine.swift
// HanlinChatCore
//
// Production streaming chat engine.
// Executes network requests using ephemeral URLSession, validates HTTP status,
// parses streaming SSE chunks, and supports clean cancellation.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProviderUtils

public actor HanlinChatEngine {
    public let sessionConfiguration: URLSessionConfiguration

    public init(sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.sessionConfiguration = sessionConfiguration
    }

    public func makeAISDKFetch(
        onRequest: (@Sendable (URLRequest) async -> Void)? = nil,
        onResponse: (@Sendable (URLRequest, HTTPURLResponse) async -> Void)? = nil,
        transportObserver: HanlinChatTransportObserver? = nil,
        requestAdmission: HanlinChatRequestAdmission? = nil
    ) -> FetchFunction {
        HanlinAISDKProviderFactory.makeFetch(
            sessionConfiguration: sessionConfiguration,
            onRequest: onRequest,
            onResponse: onResponse,
            transportObserver: transportObserver,
            requestAdmission: requestAdmission
        )
    }

    public func stream(
        messages: [HanlinChatMessage],
        configuration: HanlinChatModelConfiguration,
        systemContext: String? = nil,
        tools: [[String: Any]]? = nil,
        cacheScope: HanlinPromptCacheScope? = nil
    ) throws -> AsyncThrowingStream<HanlinChatStreamEvent, Error> {
        if HanlinAISDKProviderFactory.descriptor(for: configuration).kind == .openAIResponses {
            return try streamResponses(messages: messages, configuration: configuration,
                systemContext: systemContext, tools: tools, cacheScope: cacheScope)
        }
        let request = try HanlinChatRequestBuilder.buildRequest(
            messages: messages,
            configuration: configuration,
            systemContext: systemContext,
            tools: tools,
            cacheScope: cacheScope
        )

        return stream(request: request, configuration: configuration)
    }


    /// Routes Responses through the same original SDK as the application agent.
    /// This compact message contract contains text only; preserve every supplied
    /// instruction/message instead of translating a Chat Completions wire body.
    private func streamResponses(
        messages: [HanlinChatMessage],
        configuration: HanlinChatModelConfiguration,
        systemContext: String?,
        tools: [[String: Any]]?,
        cacheScope: HanlinPromptCacheScope?
    ) throws -> AsyncThrowingStream<HanlinChatStreamEvent, Error> {
        guard tools?.isEmpty ?? true else {
            throw HanlinChatError.invalidRequest(
                "Responses tools require the canonical agent's execution and approval callbacks."
            )
        }
        var sdkMessages: [HanlinAISDKMessage] = []
        if let stable = configuration.systemPrompt, !stable.isEmpty {
            sdkMessages.append(.init(role: .system, text: stable, cacheBreakpoint: true))
        }
        if let context = systemContext, !context.isEmpty {
            sdkMessages.append(.init(role: .system, text: "Context:\n\(context)"))
        }
        for message in messages {
            let role: HanlinAISDKMessage.Role
            switch message.role {
            case "system", "developer": role = .system
            case "assistant": role = .assistant
            case "user": role = .user
            default:
                throw HanlinChatError.invalidRequest(
                    "This compact Responses message role requires the canonical typed agent interface."
                )
            }
            sdkMessages.append(.init(role: role, text: message.content,
                cacheBreakpoint: role == .system && sdkMessages.isEmpty))
        }
        let (stream, continuation) = AsyncThrowingStream<HanlinChatStreamEvent, Error>.makeStream()
        let fetch = makeAISDKFetch(onResponse: { _, response in
            continuation.yield(.init(responseMetadata: .init(
                statusCode: response.statusCode,
                providerRequestID: response.value(forHTTPHeaderField: "x-request-id")
                    ?? response.value(forHTTPHeaderField: "request-id")
            )))
        })
        let sdkEngine = try HanlinAISDKAgentEngine(configuration: configuration, fetch: fetch)
        let originalMessages = sdkMessages
        let task = Task {
            do {
                try Task.checkCancellation()
                let source = try await sdkEngine.stream(
                    messages: originalMessages, baseSystemPrompt: nil, tools: [],
                    cacheScope: cacheScope, prepareStep: { .init(activeToolAliases: []) }
                )
                for try await event in source {
                    try Task.checkCancellation()
                    switch event {
                    case .textDelta(let text):
                        continuation.yield(.init(content: text))
                    case .reasoningDelta(let text):
                        continuation.yield(.init(reasoning: text))
                    case .finished(let reason, let usage):
                        continuation.yield(.init(tokenUsage: usage, finishReason: reason, isDone: true))
                    case .cancelled:
                        throw HanlinChatError.cancelled
                    default:
                        break
                    }
                }
                try Task.checkCancellation()
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: HanlinChatError.cancelled)
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }

    /// Executes a prebuilt request through the same production transport and
    /// stream parser used by every Hanlin chat surface. App-only orchestration
    /// can customize the shared request body before calling this entry point.
    public func stream(
        request: URLRequest,
        configuration: HanlinChatModelConfiguration,
        transportObserver: HanlinChatTransportObserver? = nil,
        requestAdmission: HanlinChatRequestAdmission? = nil
    ) -> AsyncThrowingStream<HanlinChatStreamEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<HanlinChatStreamEvent, Error>.makeStream()

#if os(iOS) || os(macOS) || os(watchOS) || os(tvOS) || os(visionOS)
        let session = URLSession(configuration: sessionConfiguration)
        let traceID = UUID()
        let task = Task.detached(priority: .userInitiated) {
            defer { session.finishTasksAndInvalidate() }
            var transportStarted = false
            var tracePending = Data()

            do {
                try Task.checkCancellation()
                try await requestAdmission?(request)
                try Task.checkCancellation()
                transportObserver?(.request(id: traceID, request: request))
                transportStarted = true
                let (bytes, response) = try await session.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    transportObserver?(.end(id: traceID, error: "invalid_response"))
                    continuation.finish(throwing: HanlinChatError.networkFailure("Invalid server response"))
                    return
                }
                transportObserver?(.response(id: traceID, response: httpResponse))

                guard (200...299).contains(httpResponse.statusCode) else {
                    var errorDetail = ""
                    for try await byte in bytes {
                        tracePending.append(byte)
                        if tracePending.count >= 2048 { break }
                    }
                    transportObserver?(.bytes(id: traceID, data: tracePending))
                    errorDetail = String(decoding: tracePending, as: UTF8.self)
                    tracePending.removeAll()
                    transportObserver?(.end(id: traceID, error: "http_\(httpResponse.statusCode)_body_preview_capped_at_2048_bytes"))
                    continuation.finish(throwing: HanlinChatError.serverError(
                        statusCode: httpResponse.statusCode,
                        message: errorDetail.isEmpty ? "Request rejected" : errorDetail
                    ))
                    return
                }

                continuation.yield(HanlinChatStreamEvent(
                    responseMetadata: HanlinChatResponseMetadata(
                        statusCode: httpResponse.statusCode,
                        providerRequestID: httpResponse.value(forHTTPHeaderField: "x-request-id")
                            ?? httpResponse.value(forHTTPHeaderField: "request-id")
                    )
                ))

                let parser = HanlinChatStreamParser(apiType: configuration.apiType)

                // Frame UTF-8 only after a complete line. Capture the very same
                // bytes once, before decoding, including a trailing fragment.
                var pending = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    pending.append(byte)
                    tracePending.append(byte)
                    if byte == 0x0A || tracePending.count >= 1024 {
                        transportObserver?(.bytes(id: traceID, data: tracePending))
                        tracePending.removeAll(keepingCapacity: true)
                    }
                    guard byte == 0x0A else { continue }
                    let line = String(decoding: pending, as: UTF8.self)
                    pending.removeAll(keepingCapacity: true)
                    if let event = parser.parse(line: line) {
                        continuation.yield(event)
                        if event.isDone { break }
                    }
                }
                if !pending.isEmpty {
                    if let event = parser.parse(line: String(decoding: pending, as: UTF8.self)) {
                        continuation.yield(event)
                    }
                }
                if !tracePending.isEmpty { transportObserver?(.bytes(id: traceID, data: tracePending)) }
                transportObserver?(.end(id: traceID, error: nil))
                continuation.finish()
            } catch is CancellationError {
                if !tracePending.isEmpty { transportObserver?(.bytes(id: traceID, data: tracePending)) }
                if transportStarted { transportObserver?(.end(id: traceID, error: "cancelled")) }
                continuation.finish(throwing: HanlinChatError.cancelled)
            } catch {
                if !tracePending.isEmpty { transportObserver?(.bytes(id: traceID, data: tracePending)) }
                if transportStarted { transportObserver?(.end(id: traceID, error: String(describing: error))) }
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
#else
        continuation.finish(throwing: HanlinChatError.networkFailure("Streaming network execution is supported on Apple platforms"))
#endif

        return stream
    }
}
