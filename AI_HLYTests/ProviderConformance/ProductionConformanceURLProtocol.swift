import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class ProductionConformanceURLProtocol: URLProtocol, @unchecked Sendable {
    public typealias RequestValidator = @Sendable (Int, URLRequest, Data) throws -> Void

    private static let lock = NSLock()
    private nonisolated(unsafe) static var isConfigured: Bool = false
    private nonisolated(unsafe) static var scriptedResponses: [Data] = []
    private nonisolated(unsafe) static var validators: [Int: RequestValidator] = [:]
    private nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
    private nonisolated(unsafe) static var capturedBodies: [Data] = []
    private nonisolated(unsafe) static var recordedValidationErrors: [Error] = []
    private nonisolated(unsafe) static var errorForNextRound: URLError?
    private nonisolated(unsafe) static var httpStatusCodeForNextRound: Int = 200
    private nonisolated(unsafe) static var preResponseHook: (@Sendable (Int) async -> Void)?

    private static let interceptedHosts: Set<String> = [
        ProductionConformanceFixtures.testHost,
        "api.openai.com",
        "openrouter.ai",
        "api.anthropic.com",
        "generativelanguage.googleapis.com"
    ]

    public static func configure(
        responses: [Data],
        validators: [Int: RequestValidator] = [:],
        preResponseHook: (@Sendable (Int) async -> Void)? = nil
    ) {
        lock.withLock {
            isConfigured = true
            scriptedResponses = responses
            self.validators = validators
            self.preResponseHook = preResponseHook
            capturedRequests = []
            capturedBodies = []
            recordedValidationErrors = []
            errorForNextRound = nil
            httpStatusCodeForNextRound = 200
        }
    }

    public static func reset() {
        lock.withLock {
            isConfigured = false
            scriptedResponses = []
            validators = [:]
            preResponseHook = nil
            capturedRequests = []
            capturedBodies = []
            recordedValidationErrors = []
            errorForNextRound = nil
            httpStatusCodeForNextRound = 200
        }
    }

    public static func injectErrorForNextRound(_ error: URLError) {
        lock.withLock {
            errorForNextRound = error
        }
    }

    public static func injectHTTPStatusForNextRound(_ code: Int) {
        lock.withLock {
            httpStatusCodeForNextRound = code
        }
    }

    public static func allBodies() -> [Data] {
        lock.withLock { capturedBodies }
    }

    public static func allRequests() -> [URLRequest] {
        lock.withLock { capturedRequests }
    }

    public static func validationErrors() -> [Error] {
        lock.withLock { recordedValidationErrors }
    }

    public override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return interceptedHosts.contains(host) || isConfigured
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        let bodyData = Self.extractBodyData(from: request)

        let (roundIndex, validator, nextResponseData, nextError, statusCode, hook): (Int, RequestValidator?, Data?, URLError?, Int, (@Sendable (Int) async -> Void)?) = Self.lock.withLock {
            let idx = Self.capturedRequests.count
            Self.capturedRequests.append(request)
            Self.capturedBodies.append(bodyData)
            let v = Self.validators[idx]
            let res = Self.scriptedResponses.isEmpty ? nil : Self.scriptedResponses.removeFirst()
            let err = Self.errorForNextRound
            Self.errorForNextRound = nil
            let code = Self.httpStatusCodeForNextRound
            Self.httpStatusCodeForNextRound = 200
            let h = Self.preResponseHook
            return (idx, v, res, err, code, h)
        }

        Task {
            if let hook {
                await hook(roundIndex)
            }

            // CORE VALIDATION: validate outgoing request BEFORE responding
            if let validator {
                do {
                    try validator(roundIndex, self.request, bodyData)
                } catch {
                    Self.lock.withLock {
                        Self.recordedValidationErrors.append(error)
                    }
                    self.client?.urlProtocol(
                        self,
                        didFailWithError: URLError(.badServerResponse, userInfo: [
                            NSLocalizedDescriptionKey: "Protocol invariant failure on round \(roundIndex): \(error)"
                        ])
                    )
                    return
                }
            }

            if let nextError {
                self.client?.urlProtocol(self, didFailWithError: nextError)
                return
            }

            guard let responseData = nextResponseData else {
                self.client?.urlProtocol(
                    self,
                    didFailWithError: URLError(.badServerResponse, userInfo: [
                        NSLocalizedDescriptionKey: "No scripted response remaining for round \(roundIndex)"
                    ])
                )
                return
            }

            let httpResponse = HTTPURLResponse(
                url: self.request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/event-stream",
                    "x-request-id": "conf-req-\(roundIndex)"
                ]
            )!

            self.client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: responseData)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    public override func stopLoading() {}

    private static func extractBodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
