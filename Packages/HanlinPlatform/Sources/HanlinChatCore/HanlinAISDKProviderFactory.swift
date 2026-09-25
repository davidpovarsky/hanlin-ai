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

public enum HanlinAISDKProviderFactory {
    public static func descriptor(
        for configuration: HanlinChatModelConfiguration
    ) -> HanlinAISDKProviderDescriptor {
        let company = configuration.company?.uppercased() ?? ""
        let apiType = configuration.apiType?.lowercased() ?? ""
        let kind: HanlinAISDKProviderKind

        if company == "ANTHROPIC" || apiType.contains("anthropic") {
            kind = .anthropic
        } else if company == "GOOGLE" || company == "GEMINI" || apiType.contains("gemini") {
            kind = .google
        } else if company == "OPENAI" && !isOpenAICompatibleHost(configuration.endpoint.host) {
            kind = .openAI
        } else {
            kind = .openAICompatible
        }

        var headers: [String: String] = [:]
        if company == "OPENROUTER" || configuration.endpoint.host?.lowercased().contains("openrouter.ai") == true {
            headers["HTTP-Referer"] = "https://hanlin.ai"
            headers["X-Title"] = "Hanlin"
        }

        let components = URLComponents(url: configuration.endpoint, resolvingAgainstBaseURL: false)
        let query = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
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
        case .openAI, .openAICompatible:
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
        case .openAI:
            let provider = try createOpenAIProvider(settings: .init(
                baseURL: baseURL,
                apiKey: configuration.apiKey,
                headers: descriptor.headers,
                name: "hanlin-openai",
                fetch: fetch
            ))
            model = try provider.chatModel(modelId: descriptor.modelID)

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
            providerOptions: providerOptions(configuration: configuration, kind: descriptor.kind)
        )
    }

    private static func providerOptions(
        configuration: HanlinChatModelConfiguration,
        kind: HanlinAISDKProviderKind
    ) -> ProviderOptions? {
        guard configuration.supportsReasoning else { return nil }

        switch kind {
        case .openAI:
            guard let effort = configuration.reasoningEffort, !effort.isEmpty else { return nil }
            return ["openai": ["reasoningEffort": .string(effort)]]
        case .openAICompatible:
            guard let effort = configuration.reasoningEffort, !effort.isEmpty else { return nil }
            return ["hanlin-openai-compatible": ["reasoningEffort": .string(effort)]]
        case .anthropic:
            let budget = max(configuration.thinkingLength, 1_024)
            return ["anthropic": [
                "thinking": .object([
                    "type": .string("enabled"),
                    "budgetTokens": .number(Double(budget))
                ])
            ]]
        case .google:
            var thinking: [String: JSONValue] = ["includeThoughts": .bool(true)]
            if configuration.thinkingLength > 0 {
                thinking["thinkingBudget"] = .number(Double(configuration.thinkingLength))
            }
            return ["google": ["thinkingConfig": .object(thinking)]]
        }
    }

    public static func makeFetch(sessionConfiguration: URLSessionConfiguration) -> FetchFunction {
        let session = URLSession(configuration: sessionConfiguration)
        return { request in
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            let (bytes, response) = try await session.bytes(for: request)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                let task = Task {
                    var buffer = Data()
                    buffer.reserveCapacity(16_384)
                    do {
                        for try await byte in bytes {
                            buffer.append(byte)
                            if byte == 0x0A || buffer.count >= 1024 {
                                continuation.yield(buffer)
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }
                        if !buffer.isEmpty {
                            continuation.yield(buffer)
                        }
                        continuation.finish()
                    } catch {
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
                        continuation.resume(throwing: error)
                    } else if let response {
                        continuation.resume(returning: FetchResponse(body: .data(data ?? Data()), urlResponse: response))
                    } else {
                        continuation.resume(throwing: URLError(.unknown))
                    }
                }
                task.resume()
            }
#endif
        }
    }
}
