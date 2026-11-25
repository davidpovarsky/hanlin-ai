import AISDKProvider
import AISDKProviderUtils
import AnthropicProvider
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GoogleProvider
import OpenAICompatibleProvider
import OpenAIProvider
import SwiftAISDK

/// The host validates its original request lease after diagnostic suspension
/// and immediately before the production transport starts.
public typealias HanlinChatRequestAdmission = @Sendable (URLRequest) async throws -> Void

/// One stream's transport and callbacks. Reused engines do not retain a
/// previous turn's host or authority closure through their provider instance.
public struct HanlinAISDKTurnTransport: Sendable {
    let fetch: FetchFunction

    public init(fetch: @escaping FetchFunction) {
        self.fetch = fetch
    }
}

public enum HanlinAISDKProviderFactory {
    public static func descriptor(
        for configuration: HanlinChatModelConfiguration
    ) -> HanlinAISDKProviderDescriptor {
        let company = configuration.company?.uppercased() ?? ""
        let apiType = configuration.apiType?.lowercased() ?? ""
        let kind: HanlinAISDKProviderKind

        if company == "APPLE" || apiType == "apple-on-device" {
            kind = .appleOnDevice
        } else if company == "ANTHROPIC" || apiType.contains("anthropic") {
            kind = .anthropic
        } else if company == "GOOGLE" || company == "GEMINI" || apiType.contains("gemini") {
            kind = .google
        } else if company == "OPENAI" && !isOpenAICompatibleHost(configuration.endpoint.host) {
            kind = ["openai-response", "openairesponse", "openai-responses", "openai-chatgpt-plan"].contains(apiType) ? .openAIResponses : .openAI
        } else {
            kind = .openAICompatible
        }

        if kind == .appleOnDevice {
            return HanlinAISDKProviderDescriptor(kind: kind, modelID: configuration.baseModelID, baseURL: URL(filePath: "/apple-on-device"))
        }

        var headers: [String: String] = [:]
        if company == "OPENROUTER" || configuration.endpoint.host?.lowercased().contains("openrouter.ai") == true {
            headers["HTTP-Referer"] = "https://hanlin.ai"
            headers["X-Title"] = "Hanlin"
        }

        let components = URLComponents(url: configuration.endpoint, resolvingAgainstBaseURL: false)
        // The public descriptor stores one value per decoded name. Repeated
        // endpoint keys use the last explicit value; valueless items stay ignored.
        let query = Dictionary(
            (components?.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            },
            uniquingKeysWith: { _, last in last }
        )

        return HanlinAISDKProviderDescriptor(
            kind: kind,
            modelID: configuration.baseModelID,
            baseURL: normalizedBaseURL(configuration.endpoint, kind: kind),
            headers: headers,
            queryParameters: query
        )
    }

    private static func isOpenAICompatibleHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return true }
        return host != "api.openai.com"
    }

    private static func normalizedBaseURL(
        _ endpoint: URL,
        kind: HanlinAISDKProviderKind
    ) -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil

        var path = components?.path ?? endpoint.path
        let suffixes: [String]
        switch kind {
        case .appleOnDevice:
            return endpoint
        case .openAI, .openAIResponses, .openAICompatible:
            suffixes = ["/chat/completions", "/responses"]
        case .anthropic:
            suffixes = ["/messages", "/chat/completions"]
        case .google:
            suffixes = ["/openai/chat/completions", "/chat/completions"]
        }
        for suffix in suffixes where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
            break
        }
        components?.path = path.isEmpty ? "/" : path
        return components?.url ?? endpoint
    }
}

struct HanlinAISDKResolvedProvider: Sendable {
    let model: LanguageModel
    let descriptor: HanlinAISDKProviderDescriptor
    let providerOptions: ProviderOptions?
}

extension HanlinAISDKProviderFactory {
    static func resolve(
        configuration: HanlinChatModelConfiguration,
        fetch: FetchFunction? = nil
    ) throws -> HanlinAISDKResolvedProvider {
        let descriptor = descriptor(for: configuration)
        let baseURL = descriptor.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let model: any LanguageModelV3

        switch descriptor.kind {
        case .appleOnDevice:
            throw HanlinAISDKError.nativeProviderInjectionRequired
        case .openAI, .openAIResponses:
            let provider = try createOpenAIProvider(settings: .init(
                baseURL: baseURL,
                apiKey: configuration.apiKey,
                headers: descriptor.headers,
                name: "hanlin-openai",
                fetch: configuration.apiType?.lowercased() == "openai-chatgpt-plan"
                    ? HanlinChatGPTPlanTransport.wrap(fetch ?? makeFetch(sessionConfiguration: .default))
                    : fetch
            ))
            if descriptor.kind == .openAIResponses {
                model = provider.responses(descriptor.modelID)
            } else {
                model = try provider.chatModel(modelId: descriptor.modelID)
            }

        case .anthropic:
            let provider = createAnthropicProvider(settings: .init(
                baseURL: baseURL,
                apiKey: configuration.apiKey,
                headers: descriptor.headers,
                fetch: fetch,
                name: "hanlin-anthropic"
            ))
            model = try provider.chatModel(modelId: descriptor.modelID)

        case .google:
            let provider = createGoogleGenerativeAI(settings: .init(
                baseURL: baseURL,
                apiKey: configuration.apiKey,
                headers: descriptor.headers,
                fetch: fetch,
                name: "hanlin-google"
            ))
            model = try provider.languageModel(modelId: descriptor.modelID)

        case .openAICompatible:
            let provider = createOpenAICompatibleProvider(settings: .init(
                baseURL: baseURL,
                name: "hanlin-openai-compatible",
                apiKey: configuration.apiKey,
                headers: descriptor.headers,
                queryParams: descriptor.queryParameters,
                fetch: fetch,
                includeUsage: true
            ))
            model = try provider.chatModel(modelId: descriptor.modelID)
        }

        return HanlinAISDKResolvedProvider(
            model: .v3(HanlinNonEmptyLanguageModel(base: model)),
            descriptor: descriptor,
            providerOptions: try providerOptions(configuration: configuration, kind: descriptor.kind)
        )
    }

    static func providerOptions(
        configuration: HanlinChatModelConfiguration,
        kind: HanlinAISDKProviderKind,
        cacheScope: HanlinPromptCacheScope? = nil,
        validateExplicitReference: Bool = false
    ) throws -> ProviderOptions? {
        var result: ProviderOptions = [:]
        if kind == .openAIResponses {
            // Preserve the existing stateless Responses contract, including SIWC.
            result["openai"] = ["store": .bool(false)]
        }
        if configuration.supportsReasoning {
            switch kind {
            case .appleOnDevice:
                break
            case .openAI, .openAIResponses:
                if let effort = configuration.reasoningEffort, !effort.isEmpty {
                    result["openai", default: [:]]["reasoningEffort"] = .string(effort)
                }
            case .openAICompatible:
                if let effort = configuration.reasoningEffort, !effort.isEmpty {
                    result["hanlin-openai-compatible"] = ["reasoningEffort": .string(effort)]
                }
            case .anthropic:
                result["anthropic"] = ["thinking": .object([
                    "type": .string("enabled"),
                    "budgetTokens": .number(Double(max(configuration.thinkingLength, 1_024)))
                ])]
            case .google:
                var thinking: [String: JSONValue] = ["includeThoughts": .bool(true)]
                if configuration.thinkingLength > 0 {
                    thinking["thinkingBudget"] = .number(Double(configuration.thinkingLength))
                }
                result["google"] = ["thinkingConfig": .object(thinking)]
            }
        }
        let cache = try cacheProviderOptions(
            configuration: configuration, kind: kind, cacheScope: cacheScope,
            validateExplicitReference: validateExplicitReference
        )
        for (provider, fields) in cache {
            result[provider, default: [:]].merge(fields) { _, cacheValue in cacheValue }
        }
        return result.isEmpty ? nil : result
    }

    static func cacheProviderOptions(
        configuration: HanlinChatModelConfiguration,
        kind: HanlinAISDKProviderKind,
        cacheScope: HanlinPromptCacheScope?,
        validateExplicitReference: Bool
    ) throws -> ProviderOptions {
        let policy = configuration.promptCachePolicy ?? .automatic
        guard policy.requestsExplicitControls,
              configuration.apiType?.lowercased() != "openai-chatgpt-plan" else { return [:] }
        switch kind {
        case .appleOnDevice, .openAICompatible:
            return [:]
        case .openAI, .openAIResponses:
            var options: [String: JSONValue] = [:]
            if let cacheScope {
                options["promptCacheKey"] = .string(cacheScope.key(configuration: configuration))
            }
            if let openAI = policy.openAI {
                if let retention = openAI.retention {
                    options["promptCacheRetention"] = .string(retention.rawValue)
                }
                if openAI.hasModernOptions {
                    if kind == .openAI, openAI.ttl == .twelveHours || openAI.comparisonResponseID != nil {
                        throw HanlinChatError.invalidRequest("Twelve-hour cache lifetime and cache diagnostics require OpenAI Responses.")
                    }
                    var controls: [String: JSONValue] = [:]
                    if let mode = openAI.mode { controls["mode"] = .string(mode.rawValue) }
                    if let ttl = openAI.ttl { controls["ttl"] = .string(ttl.rawValue) }
                    if let responseID = openAI.comparisonResponseID {
                        guard !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw HanlinChatError.invalidRequest("A cache diagnostic comparison requires a response ID.")
                        }
                        controls["comparisonResponseId"] = .string(responseID)
                    }
                    options["promptCacheOptions"] = .object(controls)
                }
            }
            return options.isEmpty ? [:] : ["openai": options]
        case .anthropic:
            return ["anthropic": ["cacheControl": .object([
                "type": .string("ephemeral"),
                "ttl": .string(policy.anthropicTTL.rawValue)
            ])]]
        case .google:
            // Engine construction has no conversation scope. Resolve the reference
            // only when the actual turn supplies its immutable account/conversation.
            guard validateExplicitReference, let reference = policy.googleCachedContent else { return [:] }
            let model = HanlinGoogleCachedContentReference.normalizedModel(configuration.baseModelID)
            guard model.hasPrefix("gemini-2.5-") || model.hasPrefix("gemini-3.") || model.hasPrefix("gemini-3-") else {
                throw HanlinGoogleCachedContentError.unsupportedModel
            }
            guard let cacheScope else {
                throw HanlinChatError.invalidRequest("Explicit Google cached content requires a conversation cache scope.")
            }
            let name = try reference.validatedName(
                modelID: configuration.baseModelID,
                scopeKey: cacheScope.key(configuration: configuration)
            )
            return ["google": ["cachedContent": .string(name)]]
        }
    }

    static func cacheBreakpointOptions(
        configuration: HanlinChatModelConfiguration,
        kind: HanlinAISDKProviderKind
    ) -> ProviderOptions? {
        let policy = configuration.promptCachePolicy ?? .automatic
        guard policy.requestsExplicitControls,
              configuration.apiType?.lowercased() != "openai-chatgpt-plan" else { return nil }
        switch kind {
        case .anthropic:
            return ["anthropic": ["cacheControl": .object([
                "type": .string("ephemeral"), "ttl": .string(policy.anthropicTTL.rawValue)
            ])]]
        case .openAI, .openAIResponses:
            // Reuse the maintained native/model capability gate from settings.
            // An extra stable boundary coexists with the provider's implicit
            // latest-message boundary; it does not select explicit-only mode,
            // extend TTL, or prewarm. Older/custom/plan transports keep defaults.
            let automaticStablePrefix = kind == .openAIResponses
                && HanlinPromptCachePreset.available(
                    company: configuration.company, apiType: configuration.apiType,
                    endpoint: configuration.endpoint, modelID: configuration.baseModelID
                ).contains(.openAIExplicitThirtyMinutes)
            guard policy.openAI?.hasModernOptions == true || automaticStablePrefix else { return nil }
            var marker: [String: JSONValue] = ["mode": .string("explicit")]
            if let ttl = policy.openAI?.ttl { marker["ttl"] = .string(ttl.rawValue) }
            return ["openai": ["promptCacheBreakpoint": .object(marker)]]
        default:
            return nil
        }
    }

    static func validateCachedContentContext(
        configuration: HanlinChatModelConfiguration,
        kind: HanlinAISDKProviderKind,
        hasSystemInstructions: Bool,
        hasTools: Bool
    ) throws {
        let policy = configuration.promptCachePolicy ?? .automatic
        guard kind == .google, policy.requestsExplicitControls,
              policy.googleCachedContent != nil else { return }
        guard !hasSystemInstructions, !hasTools else {
            throw HanlinChatError.invalidRequest(
                "Content-only Google cached content cannot be combined with system instructions or tools. Keep the full context and use implicit caching."
            )
        }
    }

    public static func makeFetch(
        sessionConfiguration: URLSessionConfiguration,
        onRequest: (@Sendable (URLRequest) async -> Void)? = nil,
        onResponse: (@Sendable (URLRequest, HTTPURLResponse) async -> Void)? = nil,
        transportObserver: HanlinChatTransportObserver? = nil,
        requestAdmission: HanlinChatRequestAdmission? = nil
    ) -> FetchFunction {
        let owner = HanlinChatProviderSession(configuration: sessionConfiguration)
        return { request in
            let session = owner.session
            await onRequest?(request)
            try Task.checkCancellation()
            try await requestAdmission?(request)
            try Task.checkCancellation()
            let traceID = UUID()
            transportObserver?(.request(id: traceID, request: request))
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            let bytes: URLSession.AsyncBytes
            let response: URLResponse
            do {
                (bytes, response) = try await session.bytes(for: request)
            } catch {
                transportObserver?(.end(id: traceID, error: String(describing: error)))
                throw error
            }
            if let httpResponse = response as? HTTPURLResponse {
                transportObserver?(.response(id: traceID, response: httpResponse))
                await onResponse?(request, httpResponse)
            }
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                let task = Task {
                    var buffer = Data()
                    buffer.reserveCapacity(16_384)
                    do {
                        for try await byte in bytes {
                            buffer.append(byte)
                            if byte == 0x0A || buffer.count >= 1024 {
                                transportObserver?(.bytes(id: traceID, data: buffer))
                                continuation.yield(buffer)
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }
                        if !buffer.isEmpty {
                            transportObserver?(.bytes(id: traceID, data: buffer))
                            continuation.yield(buffer)
                        }
                        transportObserver?(.end(id: traceID, error: nil))
                        continuation.finish()
                    } catch {
                        if !buffer.isEmpty {
                            transportObserver?(.bytes(id: traceID, data: buffer))
                        }
                        transportObserver?(.end(id: traceID, error: String(describing: error)))
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
            return FetchResponse(body: .stream(stream), urlResponse: response)
#else
            return try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        transportObserver?(.end(id: traceID, error: String(describing: error)))
                        continuation.resume(throwing: error)
                    } else if let response {
                        if let httpResponse = response as? HTTPURLResponse {
                            transportObserver?(.response(id: traceID, response: httpResponse))
                            Task { await onResponse?(request, httpResponse) }
                        }
                        transportObserver?(.bytes(id: traceID, data: data ?? Data()))
                        transportObserver?(.end(id: traceID, error: nil))
                        continuation.resume(returning: FetchResponse(body: .data(data ?? Data()), urlResponse: response))
                    } else {
                        transportObserver?(.end(id: traceID, error: "missing_response"))
                        continuation.resume(throwing: URLError(.unknown))
                    }
                }
                task.resume()
            }
#endif
        }
    }
}
