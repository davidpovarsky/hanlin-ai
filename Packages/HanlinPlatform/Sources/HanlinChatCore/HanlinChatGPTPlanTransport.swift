import AISDKProviderUtils
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum HanlinChatGPTPlanTransport {
    static func wrap(_ fetch: @escaping FetchFunction) -> FetchFunction {
        { request in
            let prepared = try HanlinChatGPTPlanWire.prepare(request)
            let response = try await fetch(prepared)
            guard let http = response.urlResponse as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return response }
            let body = response.body.makeStream()
            let validated = AsyncThrowingStream<Data, Error> { continuation in
                let task = Task {
                    do {
                        var validator = HanlinChatGPTPlanSSEValidator()
                        for try await bytes in body {
                            try Task.checkCancellation()
                            for event in try validator.consume(bytes) { continuation.yield(event) }
                        }
                        try validator.finish()
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable termination in
                    if case .cancelled = termination { task.cancel() }
                }
            }
            return FetchResponse(body: .stream(validated), urlResponse: response.urlResponse)
        }
    }
}
