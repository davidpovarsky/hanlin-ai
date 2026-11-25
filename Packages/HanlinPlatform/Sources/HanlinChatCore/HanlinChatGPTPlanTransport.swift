import AISDKProviderUtils
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Structured, credential-free diagnostics for ChatGPT plan admission and terminal events.
public struct HanlinChatGPTPlanFailure: Sendable, Equatable {
    public let status: Int
    public let code: String?
    public let parameter: String?
    public let requestID: String?
    public let bodyShape: String
}

public enum HanlinChatGPTPlanTransportError: Error, LocalizedError, Sendable {
    case invalidRoute
    case invalidBody
    case unsupportedTool(String)
    case response(HanlinChatGPTPlanFailure)
    case incompleteStream

    public var errorDescription: String? {
        switch self {
        case .invalidRoute:
            "ChatGPT plan requests require POST https://api.openai.com/v1/responses."
        case .invalidBody:
            "The ChatGPT plan request or response did not match the Responses contract."
        case .unsupportedTool(let type):
            "This tool type is unavailable through ChatGPT plan usage: \(type)"
        case .response(let error):
            "OpenAI HTTP \(error.status), code: \(error.code ?? "unknown"), parameter: \(error.parameter ?? "none"), request: \(error.requestID ?? "unavailable")."
        case .incompleteStream:
            "The ChatGPT response ended before response.completed."
        }
    }
}

/// The shared plan route retains canonical tool namespaces and original provider bytes.
/// Ordinary OpenAI API requests do not use this adapter.
public enum HanlinChatGPTPlanTransport {
    public static func prepareRequest(_ request: URLRequest) throws -> URLRequest {
        guard HanlinChatGPTPlanWire.isSupportedRoute(request) else {
            throw HanlinChatGPTPlanTransportError.invalidRoute
        }
        do { return try HanlinChatGPTPlanWire.prepare(request) }
        catch HanlinChatGPTPlanWireError.unsupportedTool {
            throw HanlinChatGPTPlanTransportError.unsupportedTool("provider tool")
        } catch { throw HanlinChatGPTPlanTransportError.invalidBody }
    }

    public static func makeFetch(base: FetchFunction? = nil) -> FetchFunction {
        let fetch = base ?? HanlinAISDKProviderFactory.makeFetch(sessionConfiguration: .ephemeral)
        return { request in
            let response = try await fetch(prepareRequest(request))
            guard let http = response.urlResponse as? HTTPURLResponse else {
                throw HanlinChatGPTPlanTransportError.invalidBody
            }
            let requestID = http.value(forHTTPHeaderField: "x-request-id")
            guard (200..<300).contains(http.statusCode) else {
                var bytes = Data()
                for try await chunk in response.body.makeStream() {
                    bytes.append(chunk.prefix(max(0, 65_536 - bytes.count)))
                    if bytes.count >= 65_536 { break }
                }
                throw HanlinChatGPTPlanTransportError.response(
                    failure(bytes, status: http.statusCode, requestID: requestID))
            }
            guard http.value(forHTTPHeaderField: "content-type")?.lowercased()
                .hasPrefix("text/event-stream") == true else {
                throw HanlinChatGPTPlanTransportError.invalidBody
            }
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                let task = Task {
                    do {
                        var validator = HanlinChatGPTPlanSSEValidator()
                        for try await bytes in response.body.makeStream() {
                            try Task.checkCancellation()
                            for event in try validator.consume(bytes) { continuation.yield(event) }
                        }
                        try validator.finish()
                        continuation.finish()
                    } catch let error as HanlinChatGPTPlanWireError {
                        continuation.finish(throwing: transportError(error, status: http.statusCode, requestID: requestID))
                    } catch { continuation.finish(throwing: error) }
                }
                continuation.onTermination = { @Sendable termination in
                    if case .cancelled = termination { task.cancel() }
                }
            }
            return FetchResponse(body: .stream(stream), urlResponse: response.urlResponse)
        }
    }

    static func wrap(_ fetch: @escaping FetchFunction) -> FetchFunction { makeFetch(base: fetch) }

    private static func transportError(_ error: HanlinChatGPTPlanWireError,
                                       status: Int, requestID: String?) -> HanlinChatGPTPlanTransportError {
        switch error {
        case .missingCompletion: .incompleteStream
        case .failed(let code), .incomplete(let code):
            .response(.init(status: status, code: code, parameter: nil, requestID: requestID, bodyShape: "event"))
        case .unsupportedTool: .unsupportedTool("provider tool")
        case .invalidEvent, .invalidRequest: .invalidBody
        }
    }

    private static func failure(_ bytes: Data, status: Int, requestID: String?) -> HanlinChatGPTPlanFailure {
        let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        let code = error?["code"] as? String ?? object?["error"] as? String ?? object?["code"] as? String
        return .init(status: status, code: code, parameter: error?["param"] as? String,
                     requestID: requestID, bodyShape: object == nil ? "non-json" : error != nil ? "error" : "object")
    }
}
