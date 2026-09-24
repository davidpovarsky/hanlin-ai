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

    public func makeAISDKFetch() -> FetchFunction {
        HanlinAISDKProviderFactory.makeFetch(sessionConfiguration: sessionConfiguration)
    }

    public func stream(
        messages: [HanlinChatMessage],
        configuration: HanlinChatModelConfiguration,
        systemContext: String? = nil,
        tools: [[String: Any]]? = nil
    ) throws -> AsyncThrowingStream<HanlinChatStreamEvent, Error> {
        let request = try HanlinChatRequestBuilder.buildRequest(
            messages: messages,
            configuration: configuration,
            systemContext: systemContext,
            tools: tools
        )

        return stream(request: request, configuration: configuration)
    }

    /// Executes a prebuilt request through the same production transport and
    /// stream parser used by every Hanlin chat surface. App-only orchestration
    /// can customize the shared request body before calling this entry point.
    public func stream(
        request: URLRequest,
        configuration: HanlinChatModelConfiguration
    ) -> AsyncThrowingStream<HanlinChatStreamEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<HanlinChatStreamEvent, Error>.makeStream()

#if os(iOS) || os(macOS) || os(watchOS) || os(tvOS) || os(visionOS)
        let session = URLSession(configuration: sessionConfiguration)
        let task = Task.detached(priority: .userInitiated) {
            defer { session.finishTasksAndInvalidate() }

            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.finish(throwing: HanlinChatError.networkFailure("Invalid server response"))
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    var errorDetail = ""
                    for try await line in bytes.lines {
                        errorDetail += line
                        if errorDetail.count > 2048 { break }
                    }
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

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    if let event = parser.parse(line: line) {
                        continuation.yield(event)
                        if event.isDone {
                            break
                        }
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: HanlinChatError.cancelled)
            } catch {
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
