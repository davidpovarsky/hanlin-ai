import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProvider

/// Metadata for an explicitly created Gemini generateContent cache.
/// It contains no cached content or credential. Persist it in the owning conversation's store.
public struct HanlinGoogleCachedContentReference: Codable, Hashable, Sendable {
    public let name: String
    public let modelID: String
    public let expiresAt: Date
    public let scopeKey: String
    public let tokenCount: Int?

    public init(name: String, modelID: String, expiresAt: Date, scopeKey: String, tokenCount: Int? = nil) {
        self.name = name
        self.modelID = Self.normalizedModel(modelID)
        self.expiresAt = expiresAt
        self.scopeKey = scopeKey
        self.tokenCount = tokenCount
    }

    public func validatedName(modelID: String, scopeKey: String, now: Date = .now) throws -> String {
        try validateIdentity(modelID: modelID, scopeKey: scopeKey)
        guard expiresAt.timeIntervalSince1970.isFinite, expiresAt > now else {
            throw HanlinGoogleCachedContentError.expired
        }
        return name
    }

    func validateIdentity(modelID: String, scopeKey: String) throws {
        guard Self.validName(name) else { throw HanlinGoogleCachedContentError.invalidResourceName }
        guard !scopeKey.isEmpty, self.scopeKey == scopeKey else {
            throw HanlinGoogleCachedContentError.scopeMismatch
        }
        guard self.modelID == Self.normalizedModel(modelID) else {
            throw HanlinGoogleCachedContentError.modelMismatch
        }
    }

    static func normalizedModel(_ value: String) -> String {
        value.hasPrefix("models/") ? String(value.dropFirst("models/".count)) : value
    }

    static func validName(_ value: String) -> Bool {
        let prefix = "cachedContents/"
        guard value.hasPrefix(prefix) else { return false }
        let identifier = value.dropFirst(prefix.count)
        return !identifier.isEmpty && identifier.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" || $0 == "_"
        }
    }
}

public enum HanlinGoogleCachedContentError: Error, LocalizedError, Equatable, Sendable {
    case invalidResourceName
    case unsupportedModel
    case modelMismatch
    case scopeMismatch
    case expired
    case invalidTTL
    case invalidContents
    case invalidEndpoint
    case notConfigured
    case invalidResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResourceName: "The cached-content resource name is invalid."
        case .unsupportedModel: "Explicit cached content requires a supported Gemini 2.5 or 3 generateContent model."
        case .modelMismatch: "Cached content belongs to a different model."
        case .scopeMismatch: "Cached content belongs to a different conversation or account scope."
        case .expired: "Cached content has expired. Create a new resource or explicitly return to implicit caching."
        case .invalidTTL: "A finite, positive cache lifetime is required."
        case .invalidContents: "Cached content must contain at least one valid content object."
        case .invalidEndpoint: "Explicit cached content requires the original Google generative-language endpoint."
        case .notConfigured: "A Google API credential and a nonempty conversation scope are required."
        case .invalidResponse: "The cached-content service returned invalid metadata."
        case .httpStatus(let code): "The cached-content service returned HTTP \(code)."
        }
    }
}

/// Explicit, opt-in resource operations against Google's original API.
///
/// Creation/renewal can incur storage charges and are never invoked automatically by chat.
/// This content-only API deliberately does not cache tool declarations or system instructions:
/// callers must not combine its references with system/tools in generateContent. The shared
/// request policy rejects that conflict rather than silently dropping instructions or tools.
/// Provider implicit caching remains the default path for normal agent conversations.
public struct HanlinGoogleCachedContentManager: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let modelID: String
    private let scopeKey: String
    private let apiKey: String
    private let transport: Transport

    public init(
        modelID: String,
        scopeKey: String,
        apiKey: String,
        transport: Transport? = nil
    ) throws {
        let normalized = HanlinGoogleCachedContentReference.normalizedModel(modelID)
        // Explicit resources are not supported by Gemini 4 or by the Interactions API.
        // The service remains authoritative for the particular model's eligibility/minimum tokens.
        guard normalized.hasPrefix("gemini-2.5-") || normalized.hasPrefix("gemini-3.") ||
                normalized.hasPrefix("gemini-3-") else {
            throw HanlinGoogleCachedContentError.unsupportedModel
        }
        guard normalized.unicodeScalars.allSatisfy({
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == ".")
        }) else { throw HanlinGoogleCachedContentError.unsupportedModel }
        guard !scopeKey.isEmpty, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HanlinGoogleCachedContentError.notConfigured
        }
        self.modelID = normalized
        self.scopeKey = scopeKey
        self.apiKey = apiKey
        self.transport = transport ?? Self.originalTransport()
    }

    public init(
        configuration: HanlinChatModelConfiguration,
        scope: HanlinPromptCacheScope,
        transport: Transport? = nil
    ) throws {
        let url = configuration.endpoint
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "generativelanguage.googleapis.com",
              url.port == nil || url.port == 443,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !url.path.contains("interactions") else {
            throw HanlinGoogleCachedContentError.invalidEndpoint
        }
        try self.init(
            modelID: configuration.baseModelID,
            scopeKey: scope.key(configuration: configuration),
            apiKey: configuration.apiKey,
            transport: transport
        )
    }

    /// Create a content-only cache. JSONValue is the original Swift AI SDK wire value type.
    /// Use {"role":"user","parts":[{"text":"..."}]} or the documented inlineData/fileData forms.
    /// Once submitted, cancellation or transport loss cannot prove that creation
    /// did not occur. A successful received receipt is returned even if the caller
    /// was just cancelled, so it can explicitly delete the TTL-bounded resource.
    public func create(
        contents: [JSONValue],
        ttl: TimeInterval,
        displayName: String? = nil
    ) async throws -> HanlinGoogleCachedContentReference {
        guard !contents.isEmpty, contents.allSatisfy({ value in
            if case .object(let object) = value, case .array(let parts)? = object["parts"] {
                return !parts.isEmpty
            }
            return false
        }) else { throw HanlinGoogleCachedContentError.invalidContents }
        var body: [String: JSONValue] = [
            "model": .string("models/" + modelID),
            "contents": .array(contents),
            "ttl": .string(try Self.ttlString(ttl))
        ]
        if let displayName {
            guard displayName.unicodeScalars.count <= 128 else {
                throw HanlinGoogleCachedContentError.invalidContents
            }
            body["displayName"] = .string(displayName)
        }
        let data = try await send(method: "POST", resource: "cachedContents", body: .object(body))
        return try decodeReference(data)
    }

    /// Refresh metadata of a reference already bound to this manager's scope and model.
    public func get(_ reference: HanlinGoogleCachedContentReference) async throws -> HanlinGoogleCachedContentReference {
        try reference.validateIdentity(modelID: modelID, scopeKey: scopeKey)
        let data = try await send(method: "GET", resource: reference.name)
        return try decodeReference(data, expectedName: reference.name)
    }

    /// Renew TTL explicitly. This does not retry creation or silently recreate expired data.
    public func updateTTL(
        _ reference: HanlinGoogleCachedContentReference,
        ttl: TimeInterval
    ) async throws -> HanlinGoogleCachedContentReference {
        try reference.validateIdentity(modelID: modelID, scopeKey: scopeKey)
        let data = try await send(
            method: "PATCH", resource: reference.name,
            body: .object(["ttl": .string(try Self.ttlString(ttl))])
        )
        return try decodeReference(data, expectedName: reference.name)
    }

    /// Delete only the supplied scoped resource. An already expired/deleted resource is success.
    public func delete(_ reference: HanlinGoogleCachedContentReference) async throws {
        try reference.validateIdentity(modelID: modelID, scopeKey: scopeKey)
        _ = try await send(method: "DELETE", resource: reference.name, acceptsNotFound: true)
    }

    private static func ttlString(_ ttl: TimeInterval) throws -> String {
        guard ttl.isFinite, ttl > 0 else { throw HanlinGoogleCachedContentError.invalidTTL }
        // Google Duration allows up to nine fractional digits. No arbitrary application TTL cap.
        let raw = String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), ttl)
        let stripped = raw.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        guard stripped != "0" else { throw HanlinGoogleCachedContentError.invalidTTL }
        return stripped + "s"
    }

    private func send(
        method: String,
        resource: String,
        body: JSONValue? = nil,
        acceptsNotFound: Bool = false
    ) async throws -> Data {
        try Task.checkCancellation()
        guard resource == "cachedContents" || HanlinGoogleCachedContentReference.validName(resource),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/" + resource) else {
            throw HanlinGoogleCachedContentError.invalidResourceName
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            do { request.httpBody = try encoder.encode(body) }
            catch { throw HanlinGoogleCachedContentError.invalidContents }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await transport(request)
        // Never discard a received creation identity solely because cancellation
        // arrived after the server accepted a billable, TTL-bounded resource.
        if method != "POST" { try Task.checkCancellation() }
        guard response.url?.scheme == "https",
              response.url?.host == "generativelanguage.googleapis.com" else {
            throw HanlinGoogleCachedContentError.invalidEndpoint
        }
        if acceptsNotFound && (response.statusCode == 404 || response.statusCode == 410) { return Data() }
        guard (200..<300).contains(response.statusCode) else {
            // Do not log/return raw response bodies; provider errors can echo input or credentials.
            throw HanlinGoogleCachedContentError.httpStatus(response.statusCode)
        }
        return data
    }

    private func decodeReference(_ data: Data, expectedName: String? = nil) throws -> HanlinGoogleCachedContentReference {
        struct Metadata: Decodable {
            struct Usage: Decodable { let totalTokenCount: Int? }
            let name: String
            let model: String
            let expireTime: String
            let usageMetadata: Usage?
        }
        guard let metadata = try? JSONDecoder().decode(Metadata.self, from: data),
              HanlinGoogleCachedContentReference.validName(metadata.name),
              expectedName == nil || metadata.name == expectedName,
              HanlinGoogleCachedContentReference.normalizedModel(metadata.model) == modelID,
              let expiresAt = Self.parseDate(metadata.expireTime),
              metadata.usageMetadata?.totalTokenCount.map({ $0 >= 0 }) ?? true else {
            throw HanlinGoogleCachedContentError.invalidResponse
        }
        return HanlinGoogleCachedContentReference(
            name: metadata.name, modelID: modelID, expiresAt: expiresAt, scopeKey: scopeKey,
            tokenCount: metadata.usageMetadata?.totalTokenCount
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func originalTransport() -> Transport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        return { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HanlinGoogleCachedContentError.invalidResponse
            }
            return (data, http)
        }
    }

    // API credentials are never forwarded to a redirect target.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? { nil }
    }
}
