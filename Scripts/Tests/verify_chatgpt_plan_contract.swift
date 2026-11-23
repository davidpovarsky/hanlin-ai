import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit) && canImport(Security)
import CryptoKit
#endif

private enum CheckFailure: Error { case failed(String) }
private func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
    guard condition() else { throw CheckFailure.failed(name) }
}
private func event(_ object: [String: Any]) throws -> Data {
    Data(("data: " + String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n\n").utf8)
}
private func expectWireError(_ expected: HanlinChatGPTPlanWireError,
                             _ operation: () throws -> Void) throws {
    do { try operation(); throw CheckFailure.failed("expected wire error") }
    catch let error as HanlinChatGPTPlanWireError { try check(error == expected, "wire error kind") }
}
#if canImport(CryptoKit) && canImport(Security)
private func b64(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
private func jwt(key: P256.Signing.PrivateKey, nonce: String, subject: String = "fixture-user",
                 audience: String = "oaiapp_fixture") throws -> String {
    let header = b64(try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": "fixture"]))
    let claims = b64(try JSONSerialization.data(withJSONObject: [
        "iss": "https://auth.openai.com", "sub": subject, "aud": audience, "nonce": nonce,
        "exp": Date().timeIntervalSince1970 + 3600, "iat": Date().timeIntervalSince1970,
        "email": "test@example.invalid", "email_verified": true
    ]))
    let input = header + "." + claims
    return input + "." + b64(try key.signature(for: Data(input.utf8)).rawRepresentation)
}
private final class Replies: @unchecked Sendable {
    private let lock = NSLock()
    private var data: [String: Data] = [:]
    private var refreshes = 0
    private var exchanges = 0
    func set(_ key: String, _ body: Data) { lock.lock(); defer { lock.unlock() }; data[key] = body }
    func counts() -> (Int, Int) { lock.lock(); defer { lock.unlock() }; return (exchanges, refreshes) }
    func response(_ request: URLRequest) -> Data {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                body.append(contentsOf: bytes.prefix(count))
            }
        }
        let form = String(decoding: body, as: UTF8.self)
        lock.lock(); defer { lock.unlock() }
        if request.url?.path == "/api/accounts/oauth/token" {
            if form.contains("grant_type=refresh_token") { refreshes += 1; return data["refresh"] ?? Data() }
            exchanges += 1; return data["exchange"] ?? Data()
        }
        return data[request.url?.path ?? ""] ?? Data()
    }
}
private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let replies = Replies()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.replies.response(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif

@main struct VerifyChatGPTPlanContract {
    static func main() async throws {
        var count = 0
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        let originalArguments = #"{"id":9007199254740993,"text":"שלום"}"#
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "fixture", "store": true, "stream": false, "temperature": 1,
            "max_output_tokens": 100, "previous_response_id": "old",
            "input": [["role": "system", "content": "Instructions"],
                ["type": "function_call", "name": "lookup", "call_id": "c1", "arguments": originalArguments],
                ["type": "function_call_output", "call_id": "c1", "output": "Found"]],
            "tools": [["type": "function", "name": "lookup", "parameters": ["type": "object", "properties": [:]]]]
        ])
        let prepared = try HanlinChatGPTPlanWire.prepare(request)
        let body = try JSONSerialization.jsonObject(with: prepared.httpBody!) as! [String: Any]
        let tools = body["tools"] as! [[String: Any]]
        let input = body["input"] as! [[String: Any]]
        try check(body["store"] as? Bool == false && body["stream"] as? Bool == true, "stateless stream")
        try check(body["temperature"] == nil && body["max_output_tokens"] == nil &&
            body["previous_response_id"] == nil, "preview fields")
        try check(tools.first?["type"] as? String == "namespace" &&
            tools.first?["name"] as? String == "hanlin", "namespace")
        try check(input.count == 3 && input[0]["role"] as? String == "developer" &&
            input[1]["namespace"] as? String == "hanlin" &&
            input[1]["arguments"] as? String == originalArguments, "history and exact arguments")
        count += 1

        let completion = try event(["type": "response.completed", "response": ["status": "completed"]])
        let text = try event(["type": "response.output_text.delta", "delta": "שלום 👋"])
        var validator = HanlinChatGPTPlanSSEValidator()
        var output = Data()
        for byte in text + completion {
            for item in try validator.consume(Data([byte])) { output.append(item) }
        }
        try validator.finish()
        try check(output == text + completion, "byte-fragmented UTF8 unchanged")
        count += 1
        var partial = HanlinChatGPTPlanSSEValidator()
        _ = try partial.consume(text + Data("data: [DONE]\n\n".utf8))
        try expectWireError(.missingCompletion) { try partial.finish() }
        count += 1
        var failed = HanlinChatGPTPlanSSEValidator()
        try expectWireError(.failed("subscription_sharing_usage_limit_exceeded")) {
            _ = try failed.consume(event(["type": "response.failed", "response": [
                "status": "failed", "error": ["code": "subscription_sharing_usage_limit_exceeded"]]]))
        }
        count += 1
        var incomplete = HanlinChatGPTPlanSSEValidator()
        try expectWireError(.incomplete("max_output_tokens")) {
            _ = try incomplete.consume(event(["type": "response.incomplete", "response": [
                "status": "incomplete", "incomplete_details": ["reason": "max_output_tokens"]]]))
        }
        count += 1
        var wrongNamespace = HanlinChatGPTPlanSSEValidator()
        try expectWireError(.invalidEvent) {
            _ = try wrongNamespace.consume(event(["type": "response.output_item.added",
                "item": ["type": "function_call", "name": "lookup", "namespace": "other"]]))
        }
        count += 1

#if canImport(CryptoKit) && canImport(Security)
        let key = P256.Signing.PrivateKey()
        let publicBytes = key.publicKey.x963Representation
        FixtureProtocol.replies.set("/.well-known/jwks.json", try JSONSerialization.data(withJSONObject: [
            "keys": [["kid": "fixture", "kty": "EC", "alg": "ES256", "crv": "P-256",
                "x": b64(Data(publicBytes[1..<33])), "y": b64(Data(publicBytes[33..<65]))]]
        ]))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = HanlinChatGPTPlanClient(session: session)
        let attempt = try HanlinChatGPTPlanClient.makeAttempt(hostID: HanlinChatGPTPlanClient.makeHostID(),
            loopbackPort: 1455, appName: "Lorvex AI Planner")
        let query = URLComponents(url: attempt.url, resolvingAgainstBaseURL: false)!.queryItems!
        let challenge = query.first { $0.name == "code_challenge" }!.value!
        try check(challenge == b64(Data(SHA256.hash(data: Data(attempt.verifier.utf8)))), "PKCE S256")
        try check(query.first { $0.name == "agent_name_hint" }?.value == "Lorvex AI Planner", "app name")
        count += 1
        let idToken = try jwt(key: key, nonce: attempt.nonce)
        FixtureProtocol.replies.set("exchange", try JSONSerialization.data(withJSONObject: [
            "access_token": "fixture-access", "refresh_token": "fixture-refresh", "id_token": idToken,
            "expires_in": 3600, "token_type": "Bearer", "scope": "openid resource.invoke chatgpt.tokens.use.direct"
        ]))
        let callback = URL(string: attempt.redirectURI.absoluteString + "?state=" + attempt.state +
            "&code=fixture-code&client_id=oaiapp_fixture")!
        let account = try await client.exchange(callback: callback, attempt: attempt)
        try check(account.canUsePlan && account.subject == "fixture-user" &&
            account.email == "test@example.invalid", "signed OIDC identity and scopes")
        count += 1
        do {
            let duplicate = URL(string: callback.absoluteString + "&state=other")!
            _ = try await client.exchange(callback: duplicate, attempt: attempt)
            throw CheckFailure.failed("duplicate OAuth callback accepted")
        } catch HanlinChatGPTPlanError.invalidAuthorization {}
        try check(FixtureProtocol.replies.counts().0 == 1, "invalid callback never exchanges")
        count += 1
        FixtureProtocol.replies.set("refresh", try JSONSerialization.data(withJSONObject: [
            "access_token": "fixture-access-2", "refresh_token": "fixture-refresh-2",
            "expires_in": 3600, "token_type": "Bearer", "scope": "openid"
        ]))
        async let first = client.refresh(account)
        async let second = client.refresh(account)
        let (one, two) = try await (first, second)
        let cached = try await client.refresh(account)
        try check(one.accessToken == two.accessToken && one.accessToken == cached.accessToken &&
            one.refreshToken == "fixture-refresh-2" && !one.canUsePlan, "rotation and reduced grants")
        try check(FixtureProtocol.replies.counts().1 == 1, "one refresh for concurrent stale callers")
        count += 1
        FixtureProtocol.replies.set("/v1/models", try JSONSerialization.data(withJSONObject: [
            "models": [["slug": "visible", "display_name": "Visible", "visibility": "list"],
                       ["slug": "hidden", "display_name": "Hidden", "visibility": "hidden"]]
        ]))
        let catalog = try await client.listModels(accessToken: "fixture-access")
        try check(catalog.map(\.slug) == ["visible"], "account-specific display catalog")
        count += 1
        FixtureProtocol.replies.set("/.well-known/openid-configuration",
            try JSONSerialization.data(withJSONObject: ["revocation_endpoint": "https://auth.openai.com/oauth/revoke"]))
        try await client.revoke(one)
        count += 1
        let registration = HanlinChatGPTPlanRegistration(credentials: account)
        let nextHost = HanlinChatGPTPlanClient.makeHostID()
        let returning = try HanlinChatGPTPlanClient.makeAttempt(hostID: nextHost, loopbackPort: 2345,
            appName: "Lorvex AI Planner", registration: registration)
        let returningQuery = URLComponents(url: returning.url, resolvingAgainstBaseURL: false)!.queryItems!
        try check(returning.clientID == account.clientID && returning.expectedSubject == account.subject &&
            returningQuery.first { $0.name == "id_token_hint" } == nil &&
            returningQuery.first { $0.name == "agent_name_hint" } == nil, "token-free returning registration")
        FixtureProtocol.replies.set("exchange", try JSONSerialization.data(withJSONObject: [
            "access_token": "fixture-returning", "refresh_token": "fixture-returning-refresh",
            "id_token": try jwt(key: key, nonce: returning.nonce),
            "expires_in": 3600, "token_type": "Bearer", "scope": "openid resource.invoke chatgpt.tokens.use.direct"
        ]))
        let returningCallback = URL(string: returning.redirectURI.absoluteString + "?state=" + returning.state + "&code=returning")!
        let returned = try await client.exchange(callback: returningCallback, attempt: returning)
        try check(returned.clientID == account.clientID && returned.hostID == nextHost, "saved client and current host")
        count += 1
        let mismatchAttempt = try HanlinChatGPTPlanClient.makeAttempt(hostID: nextHost, loopbackPort: 2345,
            appName: "Lorvex AI Planner", registration: registration)
        FixtureProtocol.replies.set("exchange", try JSONSerialization.data(withJSONObject: [
            "access_token": "fixture-other", "refresh_token": "fixture-other-refresh",
            "id_token": try jwt(key: key, nonce: mismatchAttempt.nonce, subject: "other-user"),
            "expires_in": 3600, "token_type": "Bearer", "scope": "openid resource.invoke chatgpt.tokens.use.direct"
        ]))
        do {
            let mismatchCallback = URL(string: mismatchAttempt.redirectURI.absoluteString + "?state=" + mismatchAttempt.state + "&code=other")!
            _ = try await client.exchange(callback: mismatchCallback, attempt: mismatchAttempt)
            throw CheckFailure.failed("returning registration accepted another subject")
        } catch HanlinChatGPTPlanError.invalidIdentity {}
        count += 1
        print("PASS: \(count) production SIWC OAuth/wire checks (macOS CryptoKit/Security fixtures, no live account).")
#else
        print("PASS: \(count) production SIWC wire checks; OAuth CryptoKit/Security checks require Apple.")
#endif
    }
}
