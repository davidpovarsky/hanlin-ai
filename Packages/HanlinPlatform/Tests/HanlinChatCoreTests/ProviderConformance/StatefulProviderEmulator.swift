import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProvider
import AISDKProviderUtils
@testable import HanlinChatCore

public enum ProviderResponseEmission: Sendable {
    case sseChunks([String])
    case dataChunks([Data])
    case httpError(statusCode: Int, body: Data?)
    case abruptCloseAfter(chunks: [String])
    case emptyStream
}

public final class StatefulProviderEmulator: @unchecked Sendable {
    public let profile: ProviderConformanceProfile
    public let scenarioName: String
    public let roundExpectations: [Int: RoundExpectation]
    public let roundResponses: [Int: ProviderResponseEmission]
    public let transcript: ConformanceTranscript
    public let ledger: ToolExecutionLedger

    private var interceptedRequests: [URLRequest] = []
    private var rawBodies: [Data] = []
    private let lock = NSLock()

    // Controllable gate for testing cancellation and overlapping runs
    public var preResponseHook: (@Sendable (Int) async -> Void)?

    public init(
        profile: ProviderConformanceProfile,
        scenarioName: String,
        roundExpectations: [Int: RoundExpectation],
        roundResponses: [Int: ProviderResponseEmission],
        ledger: ToolExecutionLedger = ToolExecutionLedger()
    ) {
        self.profile = profile
        self.scenarioName = scenarioName
        self.roundExpectations = roundExpectations
        self.roundResponses = roundResponses
        self.ledger = ledger
        self.transcript = ConformanceTranscript(profile: profile, scenarioName: scenarioName)
    }

    public var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return interceptedRequests.count
    }

    public var allRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return interceptedRequests
    }

    public var allBodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return rawBodies
    }

    private func recordRequest(_ request: URLRequest, body: Data) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let count = interceptedRequests.count
        interceptedRequests.append(request)
        rawBodies.append(body)
        return count
    }

    public func makeFetchFunction() -> FetchFunction {
        return { [weak self] request in
            guard let self = self else {
                throw URLError(.cancelled)
            }

            let bodyData = ProviderRequestValidators.extractBody(from: request)
            let roundIndex = self.recordRequest(request, body: bodyData)

            // Optional pre-response hook (e.g. for concurrency gating)
            if let hook = self.preResponseHook {
                await hook(roundIndex)
            }

            // CORE TESTING PRINCIPLE:
            // Parse and validate ALL invariants for roundIndex BEFORE emitting any response.
            if let expectation = self.roundExpectations[roundIndex] {
                do {
                    try ProviderRequestValidators.validate(
                        request: request,
                        round: roundIndex,
                        expectation: expectation,
                        profile: self.profile
                    )
                } catch {
                    self.transcript.errorMessage = "\(error)"
                    // Fail immediately with precise protocol-diff error!
                    throw error
                }
            }

            // ONLY if invariants pass: retrieve and emit the next provider-native response
            guard let emission = self.roundResponses[roundIndex] else {
                let err = ConformanceProtocolError(
                    category: .TEST_HARNESS,
                    ownership: .testHarness,
                    round: roundIndex,
                    message: "No provider response emission configured for round \(roundIndex)."
                )
                self.transcript.errorMessage = err.description
                throw err
            }

            return try self.produceResponse(emission: emission, request: request, roundIndex: roundIndex, bodyData: bodyData)
        }
    }

    private func produceResponse(
        emission: ProviderResponseEmission,
        request: URLRequest,
        roundIndex: Int,
        bodyData: Data
    ) throws -> FetchResponse {
        let requestURL = request.url ?? URL(string: "https://conformance.provider/v1")!

        switch emission {
        case .httpError(let statusCode, let body):
            let httpResponse = HTTPURLResponse(
                url: requestURL,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            self.transcript.recordRound(
                round: roundIndex,
                url: requestURL.absoluteString,
                headers: request.allHTTPHeaderFields ?? [:],
                bodyData: bodyData,
                responseChunks: [],
                rawFinish: "http_\(statusCode)",
                normalizedFinish: "error"
            )
            return FetchResponse(body: .data(body ?? Data()), urlResponse: httpResponse)

        case .emptyStream:
            let httpResponse = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                continuation.finish()
            }
            self.transcript.recordRound(
                round: roundIndex,
                url: requestURL.absoluteString,
                headers: request.allHTTPHeaderFields ?? [:],
                bodyData: bodyData,
                responseChunks: [],
                rawFinish: nil,
                normalizedFinish: nil
            )
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)

        case .abruptCloseAfter(let chunks):
            let httpResponse = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for chunk in chunks {
                    continuation.yield(Data(chunk.utf8))
                }
                // Abruptly terminate with connection error before normal stream finish
                continuation.finish(throwing: URLError(.networkConnectionLost))
            }
            self.transcript.recordRound(
                round: roundIndex,
                url: requestURL.absoluteString,
                headers: request.allHTTPHeaderFields ?? [:],
                bodyData: bodyData,
                responseChunks: chunks,
                rawFinish: "abrupt_close",
                normalizedFinish: "error"
            )
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)

        case .sseChunks(let chunks):
            let httpResponse = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for chunk in chunks {
                    continuation.yield(Data(chunk.utf8))
                }
                continuation.finish()
            }
            self.transcript.recordRound(
                round: roundIndex,
                url: requestURL.absoluteString,
                headers: request.allHTTPHeaderFields ?? [:],
                bodyData: bodyData,
                responseChunks: chunks,
                rawFinish: nil,
                normalizedFinish: nil
            )
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)

        case .dataChunks(let byteChunks):
            let httpResponse = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for chunk in byteChunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            self.transcript.recordRound(
                round: roundIndex,
                url: requestURL.absoluteString,
                headers: request.allHTTPHeaderFields ?? [:],
                bodyData: bodyData,
                responseChunks: byteChunks.map { String(decoding: $0, as: UTF8.self) },
                rawFinish: nil,
                normalizedFinish: nil
            )
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }
    }
}
