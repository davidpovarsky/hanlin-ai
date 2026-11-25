import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import AISDKProvider
@testable import HanlinChatCore

@Suite("Explicit Google cached-content lifecycle")
struct HanlinGoogleCachedContentTests {
    private static let expiry = Date(timeIntervalSince1970: 2_000_000_000)
    private static let content: [JSONValue] = [.object([
        "role": .string("user"), "parts": .array([.object(["text": .string("public test corpus")])])
    ])]

    @Test func lifecycleUsesOriginalWireAndScopedMetadata() async throws {
        let wire = CacheWire([
            (200, metadata()),
            (200, metadata()),
            (200, metadata(expiry: "2034-01-01T00:00:00.123456Z")),
            (204, "")
        ])
        let manager = try manager(wire)
        let reference = try await manager.create(contents: Self.content, ttl: 300.5, displayName: "test")
        #expect(reference.name == "cachedContents/test-123")
        #expect(reference.modelID == "gemini-2.5-flash")
        #expect(reference.scopeKey == "account-conversation-scope")
        #expect(reference.tokenCount == 2048)
        _ = try await manager.get(reference)
        let renewed = try await manager.updateTTL(reference, ttl: 600)
        #expect(renewed.expiresAt > reference.expiresAt)
        try await manager.delete(renewed)
        let requests = await wire.requests
        #expect(requests.map(\.httpMethod) == ["POST", "GET", "PATCH", "DELETE"])
        #expect(requests.allSatisfy { $0.url?.query == nil && $0.url?.host == "generativelanguage.googleapis.com" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "x-goog-api-key") == "fixture-only-credential" })
        let creationBody = try #require(requests[0].httpBody)
        let creation = try #require(try JSONSerialization.jsonObject(with: creationBody) as? [String: Any])
        #expect(creation["ttl"] as? String == "300.5s")
        #expect(creation["model"] as? String == "models/gemini-2.5-flash")
        #expect(creation["systemInstruction"] == nil && creation["tools"] == nil)
        let renewalBody = try #require(requests[2].httpBody)
        let renewal = try #require(try JSONSerialization.jsonObject(with: renewalBody) as? [String: Any])
        #expect(renewal.count == 1 && renewal["ttl"] as? String == "600s")
    }

    @Test func referenceRejectsWrongScopeModelExpiredAndPathTraversal() throws {
        let good = reference()
        #expect(try good.validatedName(modelID: "models/gemini-2.5-flash", scopeKey: good.scopeKey, now: .distantPast) == good.name)
        #expect(throws: HanlinGoogleCachedContentError.scopeMismatch) {
            try good.validatedName(modelID: good.modelID, scopeKey: "other-account", now: .distantPast)
        }
        #expect(throws: HanlinGoogleCachedContentError.modelMismatch) {
            try good.validatedName(modelID: "gemini-2.5-pro", scopeKey: good.scopeKey, now: .distantPast)
        }
        #expect(throws: HanlinGoogleCachedContentError.expired) {
            try good.validatedName(modelID: good.modelID, scopeKey: good.scopeKey, now: good.expiresAt)
        }
        for name in ["cachedContents/../other", "cachedContents/a?key=secret", "cachedContents/a%2Fb", "https://other.test/a", "cachedContents/"] {
            let bad = reference(name: name)
            #expect(throws: HanlinGoogleCachedContentError.invalidResourceName) {
                try bad.validatedName(modelID: bad.modelID, scopeKey: bad.scopeKey, now: .distantPast)
            }
        }
    }

    @Test func validationFailsBeforeNetworkAndImplicitOnlyModelsAreRejected() async throws {
        let wire = CacheWire([])
        let manager = try manager(wire)
        for ttl in [0.0, -1.0, .infinity, .nan, 0.00000000001] {
            await #expect(throws: HanlinGoogleCachedContentError.invalidTTL) {
                try await manager.create(contents: Self.content, ttl: ttl)
            }
        }
        await #expect(throws: HanlinGoogleCachedContentError.invalidContents) {
            try await manager.create(contents: [], ttl: 300)
        }
        await #expect(throws: HanlinGoogleCachedContentError.scopeMismatch) {
            try await manager.delete(reference(scope: "different-account"))
        }
        for model in ["gemini-4-carbon", "models/gemini-4-neon", "other", "gemini-3-../other"] {
            #expect(throws: HanlinGoogleCachedContentError.unsupportedModel) {
                try HanlinGoogleCachedContentManager(modelID: model, scopeKey: "scope", apiKey: "fixture")
            }
        }
        #expect(await wire.requests.isEmpty)
    }

    @Test func failedCreationIsNotRetriedAndErrorCannotEchoInput() async throws {
        let wire = CacheWire([(429, "{\"error\":{\"message\":\"fixture-only-credential public test corpus\"}}")])
        let manager = try manager(wire)
        await #expect(throws: HanlinGoogleCachedContentError.httpStatus(429)) {
            try await manager.create(contents: Self.content, ttl: 300)
        }
        #expect(await wire.requests.count == 1)
        let message = HanlinGoogleCachedContentError.httpStatus(429).localizedDescription
        #expect(!message.contains("credential") && !message.contains("corpus"))
    }

    @Test func providerMetadataCannotChangeResourceOrModel() async throws {
        let wire = CacheWire([
            (200, metadata(name: "cachedContents/other")),
            (200, metadata(model: "models/gemini-2.5-pro")),
            (200, "{\"name\":\"cachedContents/test-123\",\"model\":\"models/gemini-2.5-flash\",\"expireTime\":\"invalid\"}")
        ])
        let manager = try manager(wire)
        for _ in 0..<3 {
            await #expect(throws: HanlinGoogleCachedContentError.invalidResponse) { try await manager.get(reference()) }
        }
    }

    @Test func deleteIsIdempotentForExpiredResource() async throws {
        let wire = CacheWire([(404, ""), (410, "")])
        let manager = try manager(wire)
        try await manager.delete(reference())
        try await manager.delete(reference())
        #expect(await wire.requests.count == 2)
    }

    @Test func cancellationBeforeRequestDoesNotSend() async throws {
        let wire = CacheWire([])
        let manager = try manager(wire)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await manager.create(contents: Self.content, ttl: 300)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await wire.requests.isEmpty)
    }

    @Test func successfulCreationReceiptSurvivesLateCancellation() async throws {
        let body = Data(metadata().utf8)
        let manager = try HanlinGoogleCachedContentManager(
            modelID: "gemini-2.5-flash", scopeKey: "account-conversation-scope",
            apiKey: "fixture-only-credential", transport: { request in
                withUnsafeCurrentTask { $0?.cancel() }
                return (body, HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: "HTTP/1.1", headerFields: nil)!)
            })
        let task = Task { try await manager.create(contents: Self.content, ttl: 300) }
        let created = try await task.value
        #expect(created.name == "cachedContents/test-123")
        #expect(created.scopeKey == "account-conversation-scope")
    }

    @Test func referencesRoundTripWithoutCorpusOrCredential() throws {
        let data = try JSONEncoder().encode(reference())
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("fixture-only-credential") && !text.contains("public test corpus"))
        #expect(try JSONDecoder().decode(HanlinGoogleCachedContentReference.self, from: data) == reference())
    }

    private func manager(_ wire: CacheWire) throws -> HanlinGoogleCachedContentManager {
        try HanlinGoogleCachedContentManager(
            modelID: "models/gemini-2.5-flash", scopeKey: "account-conversation-scope",
            apiKey: "fixture-only-credential", transport: { try await wire.send($0) }
        )
    }
    private func reference(name: String = "cachedContents/test-123", scope: String = "account-conversation-scope") -> HanlinGoogleCachedContentReference {
        .init(name: name, modelID: "gemini-2.5-flash", expiresAt: Self.expiry, scopeKey: scope, tokenCount: 2048)
    }
    private func metadata(name: String = "cachedContents/test-123", model: String = "models/gemini-2.5-flash", expiry: String = "2033-05-18T03:33:20Z") -> String {
        "{\"name\":\"\(name)\",\"model\":\"\(model)\",\"expireTime\":\"\(expiry)\",\"usageMetadata\":{\"totalTokenCount\":2048}}"
    }
}

private actor CacheWire {
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [(Int, String)]) { self.responses = responses }
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw HanlinGoogleCachedContentError.invalidResponse }
        let (status, body) = responses.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}
