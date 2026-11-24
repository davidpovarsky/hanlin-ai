import AISDKProvider
import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinPlatformContracts
import SwiftData

/// A revocable admission lease for one actual Expo/NativeScript adapter. Closing
/// the adapter changes this synchronously, including while a provider is resolving.
final class HanlinMiniAppAssistantLease: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    func invalidate() { lock.withLock { active = false } }
    func requireActive() throws {
        try Task.checkCancellation()
        guard lock.withLock({ active }) else { throw CancellationError() }
    }
}

enum HanlinMiniAppAssistantError: String, Error, LocalizedError, Sendable {
    case invalidRequest = "The assistant request is invalid."
    case unavailable = "No configured model is available for this assistant request."
    case staleConfiguration = "The selected model or provider configuration changed. Start a new request."
    case unsupportedContent = "The selected model does not support this content or response format."
    case unknownRequest = "This assistant request does not belong to the active session."
    case concurrentRead = "Only one reader may consume an assistant request."
    case responseTooLarge = "The assistant response exceeded the native bridge's memory budget."
    case invalidStructuredResponse = "The assistant response did not match the original JSON schema."
    case providerFailure = "The assistant provider could not complete the request."
    var errorDescription: String? { rawValue }
}

struct HanlinMiniAppAssistantRequest: Decodable, Sendable {
    struct Message: Decodable, Sendable {
        enum Role: String, Decodable, Sendable { case user, assistant }
        struct Part: Decodable, Sendable {
            let type: String
            let text: String?
            let url: String?
            let base64: String?
            let mediaType: String?
        }
        let role: Role
        let content: Content
        enum Content: Decodable, Sendable {
            case text(String), parts([Part])
            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) { self = .text(text) }
                else { self = .parts(try container.decode([Part].self)) }
            }
        }
    }
    /// The UUID returned by assistant.models(), not an endpoint or credential.
    let model: UUID?
    let conversationID: String?
    let system: String?
    let messages: [Message]
    let temperature: Double?
    let maxOutputTokens: Int?
    let reasoning: Bool?
    /// Preserve the caller's original schema bytes across the native boundary.
    let responseSchemaJSON: String?

    func sdkMessages() throws -> [HanlinAISDKMessage] {
        guard !messages.isEmpty,
              temperature.map({ $0.isFinite }) ?? true,
              maxOutputTokens.map({ $0 > 0 }) ?? true,
              conversationID.map({ !$0.isEmpty && $0.utf8.count <= 256 }) ?? true else {
            throw HanlinMiniAppAssistantError.invalidRequest
        }
        var result: [HanlinAISDKMessage] = []
        if let system, !system.isEmpty {
            result.append(.init(role: .system, text: system, cacheBreakpoint: true))
        }
        for message in messages {
            let parts: [HanlinAISDKMessagePart]
            switch message.content {
            case .text(let text): parts = [.text(text)]
            case .parts(let values):
                guard !values.isEmpty else { throw HanlinMiniAppAssistantError.invalidRequest }
                parts = try values.map { part in
                    switch part.type {
                    case "text":
                        guard let text = part.text, part.url == nil, part.base64 == nil else {
                            throw HanlinMiniAppAssistantError.invalidRequest
                        }
                        return .text(text)
                    case "image":
                        guard message.role == .user, part.text == nil else {
                            throw HanlinMiniAppAssistantError.invalidRequest
                        }
                        if let raw = part.url, part.base64 == nil,
                           let url = URL(string: raw), url.scheme?.lowercased() == "https",
                           url.host != nil, url.user == nil, url.password == nil {
                            return .imageURL(url, mediaType: part.mediaType)
                        }
                        if let raw = part.base64, part.url == nil,
                           let mediaType = part.mediaType, mediaType.hasPrefix("image/"),
                           let bytes = Data(base64Encoded: raw), !bytes.isEmpty {
                            return .imageData(bytes, mediaType: mediaType)
                        }
                        throw HanlinMiniAppAssistantError.invalidRequest
                    default: throw HanlinMiniAppAssistantError.invalidRequest
                    }
                }
            }
            result.append(.init(role: message.role == .user ? .user : .assistant, parts: parts))
        }
        return result
    }
}

struct HanlinMiniAppAssistantModel: Encodable, Sendable {
    let id: UUID
    let modelID: String
    let displayName: String
    let provider: String
    let imageInput: Bool
    let structuredOutput: Bool
    let onDevice: Bool
}

/// One service per adapter. No global current MiniApp, shared response cache,
/// transcript database, credentials in JavaScript, or delegated host tools.
actor HanlinMiniAppAssistantAIService: HanlinMiniAppAssistantService {
    typealias StreamFactory = @Sendable (HanlinMiniAppAssistantRequest, HanlinMiniAppAssistantLease) async throws
        -> AsyncThrowingStream<HanlinAISDKStreamEvent, Error>
    typealias ModelListing = @Sendable () async throws -> [HanlinMiniAppAssistantModel]

    private struct WireEvent: Encodable, Sendable {
        let type: String
        var text: String? = nil
        var value: JSONValue? = nil
        var finishReason: String? = nil
        var usage: HanlinChatTokenUsage? = nil
        var id: String? = nil
        var url: String? = nil
        var title: String? = nil
    }
    private struct ReadReceipt: Encodable { let event: WireEvent }
    private struct StartReceipt: Encodable { let requestID: String }
    private struct Handle: Decodable { let requestID: String }
    private struct Pending {
        var task: Task<Void, Never>?
        var queued: [(String, Bool)] = []
        var queuedBytes = 0
        var readIndex = 0
        var waiter: CheckedContinuation<String, any Error>?
        var failure: HanlinMiniAppAssistantError?
    }

    // Bounds transient wire buffering only. This is not a model token/usage quota.
    private static let maximumPayloadBytes = 8 * 1_048_576
    private static let maximumBufferedBytes = 8 * 1_048_576
    private let context: HanlinHostCallContext
    private nonisolated let lease = HanlinMiniAppAssistantLease()
    private let makeStream: StreamFactory
    private let listModels: ModelListing
    private var requests: [String: Pending] = [:]

    init(context: HanlinHostCallContext, makeStream: @escaping StreamFactory,
         listModels: @escaping ModelListing) {
        self.context = context
        self.makeStream = makeStream
        self.listModels = listModels
    }

    nonisolated func invalidate() {
        lease.invalidate()
        Task { await close() }
    }

    private func close() {
        let pending = Array(requests.values)
        requests.removeAll()
        for request in pending {
            request.task?.cancel()
            request.waiter?.resume(throwing: CancellationError())
        }
    }

    func invoke(operation: String, payloadJSON: String) async throws -> String {
        do {
            try lease.requireActive()
            try await HanlinHostServicesBroker.shared.requireCapability("assistant", context: context)
            try lease.requireActive()
            let data = Data(payloadJSON.utf8)
            guard data.count <= Self.maximumPayloadBytes else { throw HanlinMiniAppAssistantError.invalidRequest }
            switch operation {
            case "assistant.models":
                let models = try await listModels()
                try lease.requireActive()
                return String(decoding: try JSONEncoder().encode(models), as: UTF8.self)
            case "assistant.start":
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      Set(object.keys).isSubset(of: ["model", "conversationID", "system", "messages",
                        "temperature", "maxOutputTokens", "reasoning", "responseSchemaJSON"]) else {
                    throw HanlinMiniAppAssistantError.invalidRequest
                }
                let request = try JSONDecoder().decode(HanlinMiniAppAssistantRequest.self, from: data)
                return try await start(request)
            case "assistant.next":
                let handle = try JSONDecoder().decode(Handle.self, from: data)
                return try await next(handle.requestID)
            case "assistant.cancel":
                let handle = try JSONDecoder().decode(Handle.self, from: data)
                cancel(handle.requestID)
                return #"{"ok":true}"#
            default: throw HanlinMiniAppAssistantError.invalidRequest
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HanlinMiniAppAssistantError {
            throw error
        } catch is DecodingError {
            throw HanlinMiniAppAssistantError.invalidRequest
        } catch {
            // Provider errors can carry request headers/body. Do not put them in JS.
            throw HanlinMiniAppAssistantError.providerFailure
        }
    }

    private func start(_ request: HanlinMiniAppAssistantRequest) async throws -> String {
        _ = try request.sdkMessages()
        let validation: HanlinHostSchemaValidation?
        if let schema = request.responseSchemaJSON {
            do {
                let bytes = Data(schema.utf8)
                validation = try HanlinHostSchemaValidation(schemaJSON: bytes)
                _ = try HanlinHostSchemaValidation.providerSchema(bytes)
            } catch is CancellationError { throw CancellationError() }
            catch { throw HanlinMiniAppAssistantError.invalidRequest }
        } else { validation = nil }
        let stream = try await makeStream(request, lease)
        try lease.requireActive()
        let requestID = UUID().uuidString.lowercased()
        requests[requestID] = Pending()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.consume(stream, requestID: requestID, validation: validation)
        }
        requests[requestID]?.task = task
        return String(decoding: try JSONEncoder().encode(StartReceipt(requestID: requestID)), as: UTF8.self)
    }

    private func consume(_ stream: AsyncThrowingStream<HanlinAISDKStreamEvent, Error>,
                         requestID: String, validation: HanlinHostSchemaValidation?) async {
        var structuredText = Data()
        do {
            for try await event in stream {
                try lease.requireActive()
                guard requests[requestID] != nil else { return }
                switch event {
                case .textDelta(let text):
                    if validation != nil {
                        guard structuredText.count + text.utf8.count <= 1_048_576 else {
                            throw HanlinMiniAppAssistantError.responseTooLarge
                        }
                        structuredText.append(contentsOf: text.utf8)
                    } else { try enqueue(.init(type: "text", text: text), requestID: requestID) }
                case .reasoningDelta(let text):
                    // A schema request exposes only its validated complete value.
                    if validation == nil { try enqueue(.init(type: "reasoning", text: text), requestID: requestID) }
                case .source(let id, let url, let title):
                    if validation == nil {
                        try enqueue(.init(type: "source", id: id, url: url, title: title), requestID: requestID)
                    }
                case .finished(let reason, let usage):
                    if let validation {
                        do {
                            guard reason == "stop" else { throw HanlinMiniAppAssistantError.invalidStructuredResponse }
                            try validation.validate(argumentsJSON: structuredText)
                            let value = try JSONDecoder().decode(JSONValue.self, from: structuredText)
                            try HanlinHostSchemaValidation.requireSameValue(
                                originalJSON: structuredText, projectedJSON: JSONEncoder().encode(value))
                            try enqueue(.init(type: "structured", value: value), requestID: requestID)
                        } catch is CancellationError { throw CancellationError() }
                        catch { throw HanlinMiniAppAssistantError.invalidStructuredResponse }
                    }
                    try enqueue(.init(type: "finish", finishReason: reason, usage: usage),
                                requestID: requestID, terminal: true)
                    return
                case .cancelled: throw CancellationError()
                case .toolCall, .toolApprovalRequest, .toolResult:
                    // No tool definitions are offered and this bridge owns no tool authority.
                    throw HanlinMiniAppAssistantError.unsupportedContent
                default: break
                }
            }
            throw HanlinMiniAppAssistantError.providerFailure
        } catch is CancellationError {
            cancel(requestID)
        } catch {
            fail(requestID, error: error as? HanlinMiniAppAssistantError ?? .providerFailure)
        }
    }

    private func enqueue(_ event: WireEvent, requestID: String, terminal: Bool = false) throws {
        guard var request = requests[requestID] else { throw CancellationError() }
        let wire = String(decoding: try JSONEncoder().encode(ReadReceipt(event: event)), as: UTF8.self)
        if let waiter = request.waiter {
            request.waiter = nil
            if terminal { requests.removeValue(forKey: requestID) }
            else { requests[requestID] = request }
            waiter.resume(returning: wire)
        } else {
            guard request.queuedBytes + wire.utf8.count <= Self.maximumBufferedBytes else {
                throw HanlinMiniAppAssistantError.responseTooLarge
            }
            request.queued.append((wire, terminal))
            request.queuedBytes += wire.utf8.count
            requests[requestID] = request
        }
    }

    private func next(_ requestID: String) async throws -> String {
        try lease.requireActive()
        guard var request = requests[requestID] else { throw HanlinMiniAppAssistantError.unknownRequest }
        guard request.waiter == nil else { throw HanlinMiniAppAssistantError.concurrentRead }
        if request.readIndex < request.queued.count {
            let (wire, terminal) = request.queued[request.readIndex]
            request.queued[request.readIndex] = ("", false)
            request.readIndex += 1
            request.queuedBytes -= wire.utf8.count
            if request.readIndex >= 256 {
                request.queued.removeFirst(request.readIndex)
                request.readIndex = 0
            }
            if terminal { requests.removeValue(forKey: requestID) }
            else { requests[requestID] = request }
            return wire
        }
        if let failure = request.failure {
            requests.removeValue(forKey: requestID)
            throw failure
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                requests[requestID]?.waiter = continuation
            }
        } onCancel: {
            Task { await self.cancel(requestID) }
        }
    }

    private func cancel(_ requestID: String) {
        guard let request = requests.removeValue(forKey: requestID) else { return }
        request.task?.cancel()
        request.waiter?.resume(throwing: CancellationError())
    }

    private func fail(_ requestID: String, error: HanlinMiniAppAssistantError) {
        guard var request = requests[requestID] else { return }
        request.task?.cancel()
        request.task = nil
        if let waiter = request.waiter {
            requests.removeValue(forKey: requestID)
            waiter.resume(throwing: error)
        } else {
            request.failure = error
            requests[requestID] = request
        }
    }
}

/// Reads the original app-owned rows and credential registry. Every HTTP attempt
/// checks the captured provider generation again, including retries and redirects.
@MainActor
final class HanlinMiniAppAssistantModelResolver {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func models() throws -> [HanlinMiniAppAssistantModel] {
        try eligibleModels().map { model in
            let native = HanlinAppleModelCatalogAdapter.isNative(model)
            return .init(id: model.id, modelID: model.name ?? "", displayName: model.presentationName,
                provider: model.company ?? "", imageInput: model.supportsMultimodal && !native,
                structuredOutput: !native, onDevice: native)
        }
    }

    private func eligibleModels() throws -> [AllModels] {
        let providers = try context.fetch(FetchDescriptor<APIKeys>())
        let groups = Dictionary(grouping: providers, by: { $0.company ?? "" })
        return HanlinDefaultChatPolicy.orderedModels(try context.fetch(FetchDescriptor<AllModels>())).filter { model in
            guard !model.isHidden, model.supportsTextGen, !(model.name ?? "").isEmpty else { return false }
            if HanlinAppleModelCatalogAdapter.isNative(model) { return HanlinAppleModelCatalogAdapter.isAvailable }
            guard let rows = groups[model.company ?? ""], rows.count == 1, let row = rows.first,
                  !row.isHidden, model.company?.uppercased() != "LOCAL",
                  let credential = try? HanlinAppProviderCredentials.shared.resolve(row), !credential.isEmpty else { return false }
            return true
        }
    }

    func stream(_ request: HanlinMiniAppAssistantRequest, host: HanlinHostCallContext,
                lease: HanlinMiniAppAssistantLease) async throws -> AsyncThrowingStream<HanlinAISDKStreamEvent, Error> {
        try lease.requireActive()
        let eligible = try eligibleModels()
        let selected: AllModels?
        if let id = request.model {
            let matches = eligible.filter { $0.id == id }
            guard matches.count == 1 else { throw HanlinMiniAppAssistantError.unavailable }
            selected = matches.first
        } else {
            selected = HanlinDefaultChatPolicy.defaultModel(in: eligible)
                ?? eligible.first(where: { HanlinAppleModelCatalogAdapter.isNative($0) })
        }
        guard let model = selected else { throw HanlinMiniAppAssistantError.unavailable }
        let messages = try request.sdkMessages()
        let containsImage = messages.contains { message in message.parts.contains {
            if case .text = $0 { return false }; return true
        } }
        guard !containsImage || model.supportsMultimodal else { throw HanlinMiniAppAssistantError.unsupportedContent }
        let engine: HanlinAISDKAgentEngine
        if HanlinAppleModelCatalogAdapter.isNative(model) {
            guard request.responseSchemaJSON == nil, !containsImage else {
                throw HanlinMiniAppAssistantError.unsupportedContent
            }
            engine = try HanlinAppleOnDeviceProvider.makeEngine(configuration:
                HanlinAppleModelCatalogAdapter.configuration(for: model,
                    temperature: request.temperature ?? HanlinDefaultChatPolicy.temperature,
                    maxTokens: request.maxOutputTokens ?? HanlinDefaultChatPolicy.maxTokens))
        } else {
            let provider = try HanlinApplicationModelAccess(context: context).provider(model.company ?? "")
            guard !provider.isHidden, let key = try HanlinAppProviderCredentials.shared.resolve(provider),
                  !key.isEmpty, let rawEndpoint = provider.requestURL, let endpoint = URL(string: rawEndpoint),
                  ["https", "http"].contains(endpoint.scheme?.lowercased() ?? ""), endpoint.host != nil else {
                throw HanlinMiniAppAssistantError.unavailable
            }
            let configuration = HanlinChatModelConfiguration(
                modelID: model.name ?? "", displayName: model.displayName, company: model.company,
                apiType: provider.apiType.rawValue, endpoint: endpoint, apiKey: key,
                temperature: request.temperature ?? HanlinDefaultChatPolicy.temperature,
                maxTokens: request.maxOutputTokens ?? HanlinDefaultChatPolicy.maxTokens,
                supportsReasoning: model.supportsReasoning && (request.reasoning ?? !model.supportReasoningChange),
                supportReasoningChange: model.supportReasoningChange,
                thinkingLength: HanlinDefaultChatPolicy.thinkingLength, supportsToolUse: false,
                promptCachePolicy: model.promptCachePolicy)
            let providerID = provider.persistentModelID
            let modelID = model.id
            let wireModelID = model.name
            let company = model.company
            let storedCredential = provider.key
            let apiType = provider.apiType.rawValue
            let admission: HanlinChatRequestAdmission = { [self] _ in
                try lease.requireActive()
                try await MainActor.run {
                    let live = try HanlinApplicationModelAccess(context: self.context).provider(company ?? "")
                    let liveModels = try self.context.fetch(FetchDescriptor<AllModels>()).filter { $0.id == modelID }
                    guard !live.isDeleted, live.persistentModelID == providerID, !live.isHidden,
                          live.key == storedCredential, live.requestURL == rawEndpoint,
                          live.apiType.rawValue == apiType,
                          liveModels.count == 1, let liveModel = liveModels.first,
                          !liveModel.isDeleted, liveModel.name == wireModelID, liveModel.company == company,
                          !liveModel.isHidden, liveModel.supportsTextGen,
                          liveModel.promptCachePolicy == configuration.promptCachePolicy,
                          !containsImage || liveModel.supportsMultimodal else {
                        throw HanlinMiniAppAssistantError.staleConfiguration
                    }
                    let reader = ModelContext(self.context.container)
                    reader.autosaveEnabled = false
                    let rows = try reader.fetch(FetchDescriptor<APIKeys>()).filter { $0.company == company }
                    let models = try reader.fetch(FetchDescriptor<AllModels>()).filter { $0.id == modelID }
                    guard rows.count == 1, let current = rows.first,
                          current.persistentModelID == providerID, !current.isHidden,
                          current.key == storedCredential, current.requestURL == rawEndpoint,
                          current.apiType.rawValue == apiType,
                          models.count == 1, let currentModel = models.first,
                          currentModel.name == wireModelID, currentModel.company == company,
                          !currentModel.isHidden, currentModel.supportsTextGen,
                          currentModel.promptCachePolicy == configuration.promptCachePolicy,
                          !containsImage || currentModel.supportsMultimodal,
                          try HanlinAppProviderCredentials.shared.matches(key, for: current) else {
                        throw HanlinMiniAppAssistantError.staleConfiguration
                    }
                    try lease.requireActive()
                }
            }
            let fetch = await HanlinChatEngine().makeAISDKFetch(requestAdmission: admission)
            try lease.requireActive()
            engine = try HanlinAISDKAgentEngine(configuration: configuration, fetch: fetch,
                telemetry: AgentDiagnosticsConfiguration.level == .off ? nil : HanlinOpenTelemetryTracer.local.telemetrySettings())
        }
        try lease.requireActive()
        return try await engine.stream(
            messages: messages, baseSystemPrompt: nil, tools: [], maxSteps: 1,
            responseSchema: request.responseSchemaJSON.map { Data($0.utf8) },
            cacheScope: .init(namespace: ["hanlin-miniapp", host.appID?.rawValue ?? "",
                host.installedPackageID?.rawValue ?? "", host.appSessionID.rawValue],
                conversationID: request.conversationID ?? host.appSessionID.rawValue,
                promptVersion: "hanlin-miniapp-assistant-v1"),
            prepareStep: { () -> HanlinAISDKStepPreparation in .init(activeToolAliases: []) })
    }
}
