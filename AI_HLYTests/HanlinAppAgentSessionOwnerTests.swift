import AISDKProvider
import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinPlatformContracts
import HanlinProductSplit
import HanlinScriptExtensions
import Security
import SwiftData
import Testing
@testable import AI_Hanlin

private actor AppPartQueue {
    var parts: [HanlinChatStructuredPart]
    var receivedPrompts: [String] = []
    init(_ parts: [HanlinChatStructuredPart]) { self.parts = parts }
    func next(promptDescription: String) throws -> HanlinChatStructuredPart {
        guard !parts.isEmpty else { throw HanlinHostError.invalidArguments }
        receivedPrompts.append(promptDescription)
        return parts.removeFirst()
    }
}

private struct AppPartModel: LanguageModelV3 {
    let provider = "app-component-fixture"
    let modelId = "app-component-fixture"
    let queue: AppPartQueue
    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        throw HanlinHostError.unsupportedProviderCapability
    }
    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let content = try await queue.next(promptDescription: String(describing: options.prompt)).providerContent()
        return .init(stream: AsyncThrowingStream { c in
            c.yield(.custom(content))
            c.yield(.finish(finishReason: .init(unified: .stop), usage: .init(), providerMetadata: nil))
            c.finish()
        })
    }
}

@MainActor private final class AppPresentationRecorder: HanlinAppAgentPresentationConsumer {
    var installed: [HanlinHostSession] = []
    var live: [HanlinAppAgentRowBinding] = []
    var replayed: [HanlinAppAgentRowBinding] = []
    var drained: [UUID] = []
    func installed(session: HanlinAgentSession) { installed.append(session.identity) }
    func validateCompleteParts(_ parts: [HanlinChatStructuredPart]) throws {
        // This recorder proves application correlation, not official A2UI validation/rendering.
        throw HanlinHostError.unsupportedProviderCapability
    }
    func receive(_ event: HanlinAgentEvent, binding: HanlinAppAgentRowBinding) throws {
        if case .structuredPart = event.event { live.append(binding) }
    }
    func completed(_ completion: HanlinAgentRunCompletion) {}
    func invalidated(_ session: HanlinHostSession) {}
    func producerStreamDrained(runID: UUID) { drained.append(runID) }
    func replay(_ record: HanlinConversationRecord, bindings: [HanlinAppAgentRowBinding]) throws {
        try record.validate(); replayed += bindings
    }
}

@MainActor private final class AppHistoryWriteGate {
    private var blocked: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { continuation in
            blocked = continuation
            observer?.resume(); observer = nil
        }
    }
    func waitUntilPaused() async {
        if blocked != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { blocked?.resume(); blocked = nil }
}


/// Used only by an explicitly injected ephemeral URLSession. Every URL is
/// intercepted so a regression cannot send a synthetic credential to the network.
private final class ProviderCredentialURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests: [String: [URLRequest]] = [:]
    nonisolated(unsafe) private static var streamingHosts = Set<String>()

    static func register(host: String, streaming: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        requests[host] = []
        if streaming { streamingHosts.insert(host) } else { streamingHosts.remove(host) }
    }
    static func snapshot(host: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests[host] ?? []
    }
    static func remove(host: String) {
        lock.lock(); defer { lock.unlock() }
        requests.removeValue(forKey: host)
        streamingHosts.remove(host)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        Self.lock.lock()
        let registered = Self.requests[host] != nil
        let streaming = Self.streamingHosts.contains(host)
        if registered { Self.requests[host, default: []].append(request) }
        Self.lock.unlock()
        guard registered else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let discovery = url.path.hasSuffix("/models")
        let body: String
        if streaming {
            body = "data: {\"id\":\"t1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Current transport response\"}}]}\n\n"
                + "data: {\"id\":\"t2\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
                + "data: [DONE]\n\n"
        } else {
            body = discovery ? #"{"data":[{"id":"fixture-model","object":"model"}]}"# : #"{"error":{"message":"synthetic probe control"}}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: streaming || discovery ? 200 : 400,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor private final class ProviderTransportDiagnostics {
    var requests: [Int] = []
    var responses: [Int] = []
    func requested(_ turn: Int) { requests.append(turn) }
    func responded(_ turn: Int) { responses.append(turn) }
}

@MainActor
private final class ProviderCredentialTestFixture {
    struct PersistedRowIdentity: Equatable {
        let entityName: String
        let storeIdentifier: String
        let encodedData: Data
    }

    let directory: URL
    let databaseURL: URL
    let service: String
    let credentials: HanlinAppProviderCredentials

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("provider-credentials-\(UUID().uuidString)", isDirectory: true)
        databaseURL = directory.appendingPathComponent("original.store")
        service = "com.itorah.chavrusachat.tests.provider-credentials.\(UUID().uuidString)"
        credentials = HanlinAppProviderCredentials(keychain: .init(service: service,
            accessGroup: nil, synchronizable: false, accessibility: .afterFirstUnlock))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func open(allowsSave: Bool = true) throws -> ModelContainer {
        try ModelContainer(for: APIKeys.self, SearchKeys.self, ToolKeys.self, AllModels.self, ChatRecords.self,
            configurations: ModelConfiguration(url: databaseURL, allowsSave: allowsSave, cloudKitDatabase: .none))
    }

    func rowIdentity(_ id: PersistentIdentifier) throws -> PersistedRowIdentity {
        guard let storeIdentifier = id.storeIdentifier, !storeIdentifier.isEmpty else {
            throw HanlinHostError.staleContext
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedData = try encoder.encode(id)
        let decoded = try JSONDecoder().decode(PersistentIdentifier.self, from: encodedData)
        let roundTripped = try encoder.encode(decoded)
        guard roundTripped == encodedData,
              decoded.entityName == id.entityName,
              decoded.storeIdentifier == storeIdentifier else {
            throw HanlinHostError.resultMismatch
        }
        return PersistedRowIdentity(entityName: id.entityName, storeIdentifier: storeIdentifier, encodedData: encodedData)
    }

    func references() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let entries = result as? [[String: Any]] else {
            throw HanlinKeychainCredentialStore.Failure.unavailable(status)
        }
        return entries.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    func removeOwnedFixture() {
        // Unique non-synchronizable synthetic fixture service only.
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true
        ] as CFDictionary)
        #expect(status == errSecSuccess || status == errSecItemNotFound)
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor OwnerControlledTextSource {
    private var continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation?
    private var observer: CheckedContinuation<Void, Never>?

    func install() -> LanguageModelV3StreamResult {
        let pair = AsyncThrowingStream<LanguageModelV3StreamPart, Error>.makeStream()
        continuation = pair.continuation
        observer?.resume(); observer = nil
        return .init(stream: pair.stream)
    }

    func waitUntilInstalled() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }

    func finish() {
        continuation?.yield(.finish(finishReason: .init(unified: .stop), usage: .init(), providerMetadata: nil))
        continuation?.finish()
    }
}

private struct OwnerControlledTextModel: LanguageModelV3 {
    let provider = "owner-drain-fixture"
    let modelId = "owner-drain-fixture"
    let source: OwnerControlledTextSource

    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        throw HanlinHostError.unsupportedProviderCapability
    }

    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        await source.install()
    }
}

@Suite @MainActor struct HanlinAppAgentSessionOwnerTests {
    @Test(.timeLimit(.minutes(1)))
    func sameOwnerRestartJoinsItsCancelledOriginalWriterBeforeAdmission() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Original same-owner restart", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id), owner = HanlinAppAgentSessionOwner()
        let source = OwnerControlledTextSource(), config = configuration()
        let first = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: UUID(),
            rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let stream = try await owner.stream(request: first, modelContext: context, configuration: config,
            engineFactory: { HanlinAISDKAgentEngine(configuration: config, model: .v3(OwnerControlledTextModel(source: source))) },
            toolAdapter: nil, messages: [.init(role: .user, text: "Original")], systemPrompt: nil)
        defer { owner.cancel(); Task { await source.finish() } }
        await source.waitUntilInstalled()
        let originalSession = try #require(owner.session)
        #expect(originalSession.isRunning)
        let next = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: first.sceneID,
            rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let queue = AppPartQueue([try .init(messageID: next.rowID, partID: UUID(), sequence: 0, payload: .textDelta("Replacement"))])

        owner.cancel()
        #expect(owner.session == nil)
        // No yield, timer or old consumer drain separates Stop from this original admission.
        let replacement = try await owner.stream(request: next, modelContext: context, configuration: config,
            engineFactory: { factory(config, queue: queue) }, toolAdapter: nil,
            messages: [.init(role: .user, text: "Replacement")], systemPrompt: nil)
        #expect(!originalSession.isRunning)
        let current = try #require(owner.session)
        #expect(current.identity != originalSession.identity)
        #expect(current.identity.conversationID == originalSession.identity.conversationID)
        for try await event in replacement { try owner.receive(event, uiRunID: next.uiRunID) }
        try owner.producerStreamDrained(uiRunID: next.uiRunID)
        await source.finish()
        do { for try await _ in stream {} }
        catch { /* The previous original run remains cancelled rather than replayed. */ }
        #expect(owner.bindings.contains { $0.reference.rowID == next.rowID && $0.session == current.identity })
        #expect(row.agentSDKRecordData != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func differentOwnerCannotUseTheDrainBarrierToBypassALiveWriter() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Original foreign writer", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id)
        let owner = HanlinAppAgentSessionOwner(), other = HanlinAppAgentSessionOwner()
        let source = OwnerControlledTextSource(), config = configuration()
        let first = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: UUID(),
            rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let stream = try await owner.stream(request: first, modelContext: context, configuration: config,
            engineFactory: { HanlinAISDKAgentEngine(configuration: config, model: .v3(OwnerControlledTextModel(source: source))) },
            toolAdapter: nil, messages: [.init(role: .user, text: "Original")], systemPrompt: nil)
        defer { owner.cancel(); other.cancel(); Task { await source.finish() } }
        await source.waitUntilInstalled()
        let originalSession = try #require(owner.session)
        let foreign = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: UUID(),
            rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        var constructed = false
        do {
            _ = try await other.stream(request: foreign, modelContext: context, configuration: config,
                engineFactory: {
                    constructed = true
                    return HanlinAISDKAgentEngine(configuration: config, model: .v3(OwnerControlledTextModel(source: source)))
                }, toolAdapter: nil, messages: [.init(role: .user, text: "Foreign")], systemPrompt: nil)
            Issue.record("A different owner bypassed the original canonical-writer exclusion")
        } catch { #expect(error as? HanlinHostError == .unresolvedWrite) }
        #expect(!constructed && other.session == nil && originalSession.isRunning)
        await source.finish()
        for try await event in stream { try owner.receive(event, uiRunID: first.uiRunID) }
        try owner.producerStreamDrained(uiRunID: first.uiRunID)
        #expect(!originalSession.isRunning)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringPriorDrainCannotAdmitALateReplacement() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Original cancelled drain admission", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id), owner = HanlinAppAgentSessionOwner()
        let source = OwnerControlledTextSource(), config = configuration()
        let first = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: UUID(),
            rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let stream = try await owner.stream(request: first, modelContext: context, configuration: config,
            engineFactory: { HanlinAISDKAgentEngine(configuration: config, model: .v3(OwnerControlledTextModel(source: source))) },
            toolAdapter: nil, messages: [.init(role: .user, text: "Original")], systemPrompt: nil)
        await source.waitUntilInstalled()
        let originalSession = try #require(owner.session)
        let next = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: first.sceneID,
            rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let previousInvalidation = originalSession.onSessionInvalidated
        var revokedDuringDrain = false
        var duplicatePreparationRejected = false
        originalSession.onSessionInvalidated = { value in
            previousInvalidation?(value)
            revokedDuringDrain = true
            do {
                _ = try owner.prepareDataAccess(request: next, modelContext: context)
                Issue.record("A second preparation entered while the original replacement was draining")
            } catch {
                duplicatePreparationRejected = (error as? HanlinHostError) == .duplicateInvocation
            }
            owner.cancel()
        }
        defer {
            originalSession.onSessionInvalidated = previousInvalidation
            owner.cancel()
            Task { await source.finish() }
        }
        owner.cancel()
        let access = try owner.prepareDataAccess(request: next, modelContext: context)
        var constructed = false
        do {
            _ = try await owner.stream(request: next, modelContext: context, configuration: config,
                engineFactory: {
                    constructed = true
                    return HanlinAISDKAgentEngine(configuration: config, model: .v3(OwnerControlledTextModel(source: source)))
                }, toolAdapter: nil, messages: [.init(role: .user, text: "Must not start")],
                systemPrompt: nil, dataAccess: access)
            Issue.record("Cancellation during the actual prior drain admitted a replacement")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(revokedDuringDrain && duplicatePreparationRejected && !constructed && owner.session == nil)
        #expect(throws: HanlinHostError.staleContext) {
            try owner.requireDataAccess(access, request: next, modelContext: context)
        }
        #expect(!originalSession.isRunning)
        await source.finish()
        do { for try await _ in stream {} }
        catch { /* The original run remains revoked. */ }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func activeClearAdmitsANewWriterOnlyAfterTheOriginalCASConflictDrains(temporary: Bool) async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Active original history", type: "chat")
        if !temporary { context.insert(row); try context.save() }
        let id = try #require(row.id), owner = HanlinAppAgentSessionOwner()
        let source = OwnerControlledTextSource(), config = configuration()
        let first = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: UUID(),
            rowID: UUID(), uiRunID: UUID(), temporary: temporary, interaction: nil)
        let stream = try await owner.stream(request: first, modelContext: context, configuration: config,
            engineFactory: { HanlinAISDKAgentEngine(configuration: config, model: .v3(OwnerControlledTextModel(source: source))) },
            toolAdapter: nil, messages: [.init(role: .user, text: "Old history")], systemPrompt: nil)
        defer { owner.cancel(); Task { await source.finish() } }
        await source.waitUntilInstalled()
        let originalSession = try #require(owner.session)
        var oldEvents = stream.makeAsyncIterator()
        let firstObserved = try await oldEvents.next()
        let firstEvent = try #require(firstObserved)
        try owner.receive(firstEvent, uiRunID: first.uiRunID)
        #expect(originalSession.isRunning)

        let replacement = try owner.clearHistory(conversation: row, conversationID: id,
            modelContext: context, temporary: temporary, replacementText: "Original history cleared")
        #expect(replacement.record === row && owner.session == nil && owner.bindings.isEmpty)
        let next = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: first.sceneID,
            rowID: UUID(), uiRunID: UUID(), temporary: temporary, interaction: nil)
        let queue = AppPartQueue([try .init(messageID: next.rowID, partID: UUID(), sequence: 0, payload: .textDelta("New history"))])
        // The original clear and this new request have no scheduling delay between them.
        let newStream = try await owner.stream(request: next, modelContext: context, configuration: config,
            engineFactory: { factory(config, queue: queue) }, toolAdapter: nil,
            messages: [.init(role: .user, text: "New history")], systemPrompt: nil)
        #expect(!originalSession.isRunning)
        do { try await originalSession.invalidateAndDrain(); Issue.record("The old Session's real CAS rejection was erased") }
        catch { #expect(error as? HanlinHostError == .storeConflict) }
        let current = try #require(owner.session)
        #expect(current.identity != originalSession.identity)
        for try await event in newStream { try owner.receive(event, uiRunID: next.uiRunID) }
        try owner.producerStreamDrained(uiRunID: next.uiRunID)
        #expect(owner.bindings.allSatisfy { $0.reference.rowID == next.rowID && $0.session == current.identity })
        #expect(!owner.bindings.isEmpty)
        await source.finish()
        do { while let _ = try await oldEvents.next() {} }
        catch { /* The original cancelled writer keeps its real failure. */ }
        if temporary {
            #expect(row.agentSDKRecordData == nil && row.modelContext == nil)
            #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
            #expect(try context.fetch(FetchDescriptor<ChatMessages>()).isEmpty)
        } else {
            let bytes = try #require(row.agentSDKRecordData)
            let record = try JSONDecoder().decode(HanlinConversationRecord.self, from: bytes)
            #expect(!record.entries.contains { $0.runID == firstEvent.runID })
            #expect(record.entries.contains { $0.runID != firstEvent.runID })
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func changedOrFailedActiveClearCannotForgiveAnUnqualifiedWriter(temporary: Bool) async throws {
        // Both real store modes cover a changed receipt; the persistent case also
        // keeps a genuine unsupported-record clear failure, using the original decoder.
        for failedClear in (temporary ? [false] : [false, true]) {
            let container = try database(), context = container.mainContext
            let row = ChatRecords(name: "Unqualified clear", type: "chat")
            if !temporary { context.insert(row); try context.save() }
            let id = try #require(row.id), owner = HanlinAppAgentSessionOwner()
            let source = OwnerControlledTextSource(), config = configuration()
            let first = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: UUID(),
                rowID: UUID(), uiRunID: UUID(), temporary: temporary, interaction: nil)
            let stream = try await owner.stream(request: first, modelContext: context, configuration: config,
                engineFactory: { HanlinAISDKAgentEngine(configuration: config, model: .v3(OwnerControlledTextModel(source: source))) },
                toolAdapter: nil, messages: [.init(role: .user, text: "Old writer")], systemPrompt: nil)
            defer { owner.cancel(); Task { await source.finish() } }
            await source.waitUntilInstalled()
            let originalSession = try #require(owner.session)
            #expect(originalSession.isRunning)
            let expectedError: HanlinHostError
            if failedClear {
                let unsupported = HanlinConversationRecord(formatVersion: HanlinConversationRecord.currentFormat + 1,
                    namespace: originalSession.identity.context.namespace, conversationID: id, revision: 0)
                row.agentSDKRecordData = try JSONEncoder().encode(unsupported)
                try context.save()
                do {
                    _ = try owner.clearHistory(conversation: row, conversationID: id,
                        modelContext: context, temporary: false, replacementText: "Must not appear")
                    Issue.record("An unsupported original record produced a successful clear receipt")
                } catch { #expect(error as? HanlinHostError == .unsupportedVersion) }
                expectedError = .unsupportedVersion
            } else {
                let firstClear = try owner.clearHistory(conversation: row, conversationID: id,
                    modelContext: context, temporary: temporary, replacementText: "First clear receipt")
                let changedClear = try owner.clearHistory(conversation: row, conversationID: id,
                    modelContext: context, temporary: temporary, replacementText: "Changed clear receipt")
                #expect(firstClear !== changedClear && changedClear.record === row)
                expectedError = .storeConflict
            }
            let preservedBytes = row.agentSDKRecordData
            let next = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: first.sceneID,
                rowID: UUID(), uiRunID: UUID(), temporary: temporary, interaction: nil)
            var constructed = false
            do {
                _ = try await owner.stream(request: next, modelContext: context, configuration: config,
                    engineFactory: {
                        constructed = true
                        return HanlinAISDKAgentEngine(configuration: config, model: .v3(OwnerControlledTextModel(source: source)))
                    }, toolAdapter: nil, messages: [.init(role: .user, text: "Must not start")], systemPrompt: nil)
                Issue.record("A failed or changed original clear receipt authorized another writer")
            } catch { #expect(error as? HanlinHostError == expectedError) }
            #expect(!constructed && owner.session == nil && !originalSession.isRunning)
            #expect(row.agentSDKRecordData == preservedBytes)
            if temporary {
                #expect(row.modelContext == nil)
                #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
            }
            await source.finish()
            do { for try await _ in stream {} }
            catch { /* Keep the original failed producer outcome. */ }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func deletedOriginalRowDuringInternalInvalidationCannotConstructANewEngine() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Deleted during original invalidation", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id), owner = HanlinAppAgentSessionOwner()
        let source = OwnerControlledTextSource(), config = configuration()
        let first = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: UUID(),
            rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let stream = try await owner.stream(request: first, modelContext: context, configuration: config,
            engineFactory: { HanlinAISDKAgentEngine(configuration: config, model: .v3(OwnerControlledTextModel(source: source))) },
            toolAdapter: nil, messages: [.init(role: .user, text: "Original finished run")], systemPrompt: nil)
        await source.waitUntilInstalled()
        await source.finish()
        for try await event in stream { try owner.receive(event, uiRunID: first.uiRunID) }
        try owner.producerStreamDrained(uiRunID: first.uiRunID)
        let originalSession = try #require(owner.session)
        let previousInvalidation = originalSession.onSessionInvalidated
        var deleted = false
        originalSession.onSessionInvalidated = { value in
            previousInvalidation?(value)
            context.delete(row)
            do { try context.save(); deleted = true }
            catch { Issue.record(error) }
        }
        defer { originalSession.onSessionInvalidated = previousInvalidation; owner.cancel() }
        let next = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: UUID(),
            rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        var constructed = false
        do {
            _ = try await owner.stream(request: next, modelContext: context, configuration: config,
                engineFactory: {
                    constructed = true
                    return HanlinAISDKAgentEngine(configuration: config, model: .v3(OwnerControlledTextModel(source: source)))
                }, toolAdapter: nil, messages: [.init(role: .user, text: "Must not start")],
                systemPrompt: nil, dataAccess: nil)
            Issue.record("A deleted original row reached new engine admission after invalidation")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(deleted && !constructed && owner.session == nil)
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
    }

    @Test func originalConsentExpiresRevokesAndRejectsStaleSheetAnswers() async throws {
        let ns = try HanlinConversationNamespace(app: "hanlin", account: "consent", workspace: "test", space: UUID().uuidString)
        let identity = HanlinHostSession(conversationID: UUID(), context: .init(namespace: ns, sceneID: UUID(), generation: UUID()))
        let logical = try HanlinLogicalToolID(providerInstanceID: .init(validating: "hanlin.host"), localToolID: .init(validating: "fixture"))
        func invocation(deadline: Date) throws -> HanlinHostInvocation {
            .init(request: .init(id: try .init(validating: UUID().uuidString.lowercased()), logicalToolID: logical,
                aliasUsed: "fixture", descriptorRevision: try .init(1), routingTableRevision: .init(1), arguments: .object([:]),
                origin: .assistantModel, deadline: deadline, limits: try .init()), session: identity,
                runID: UUID(), step: 0, providerCallID: UUID().uuidString, writeGuarantee: .hostManagedMutation,
                originalArgumentsJSON: Data("{}".utf8))
        }
        let consent = HanlinAppToolConsent()
        let scope = HanlinToolApprovalScope(app: ns.app, account: ns.account, workspace: ns.workspace,
            providerID: logical.providerInstanceID.rawValue, toolID: logical.localToolID.rawValue,
            manifestFingerprint: String(repeating: "a", count: 64), permissionFingerprint: String(repeating: "b", count: 64))
        var changes: [(UUID, String, Bool?)] = []
        consent.onChange = { request, choice in changes.append((request.id, request.providerCallID, choice)) }
        #expect(await consent.request(try invocation(deadline: .now.addingTimeInterval(-1)), approvalScope: scope) == false)
        #expect(consent.pending == nil)
        let expiring = try invocation(deadline: .now.addingTimeInterval(0.15))
        let expiredTask = Task { @MainActor in await consent.request(expiring, approvalScope: scope) }
        #expect(await expiredTask.value == false)
        #expect(consent.pending == nil)

        let live = try invocation(deadline: .now.addingTimeInterval(30))
        let cancelled = Task { @MainActor in await consent.request(live, approvalScope: scope) }
        for _ in 0..<100 where consent.pending == nil { await Task.yield() }
        let oldID = try #require(consent.pending?.id)
        cancelled.cancel()
        #expect(await cancelled.value == false)
        #expect(consent.pending == nil)
        let replacement = Task { @MainActor in await consent.request(live, approvalScope: scope) }
        for _ in 0..<100 where consent.pending == nil { await Task.yield() }
        let currentID = try #require(consent.pending?.id)
        consent.answer(id: oldID, allowed: true)
        #expect(consent.pending?.id == currentID)
        consent.revoke()
        #expect(await replacement.value == false)
        #expect(consent.pending == nil)
        #expect(changes.filter { $0.0 == currentID }.map { $0.1 } == [live.providerCallID, live.providerCallID])
        #expect(changes.filter { $0.0 == currentID }.first?.2 == nil)
        #expect(changes.filter { $0.0 == currentID }.last?.2 == false)
        #expect(!changes.contains { $0.2 == true }, "A stale answer never creates an approval event")
    }

    @Test func nativeConsentUsesOriginalOperationAcrossForeignAnswerContextAndRevocation() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Consent operation owner", type: "chat")
        context.insert(row); try context.save()
        let conversationID = try #require(row.id), owner = HanlinAppAgentSessionOwner()
        defer { owner.cancel() }
        let request = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: conversationID,
            sceneID: UUID(), rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let original = RuntimeUserOperation(), foreign = RuntimeUserOperation(), config = configuration()
        let queue = AppPartQueue([try .init(messageID: request.rowID, partID: UUID(), sequence: 0,
                                           payload: .textDelta("Original conversation"))])
        let stream = try await RuntimeUserOperation.$current.withValue(original) {
            try await owner.stream(request: request, modelContext: context, configuration: config,
                engineFactory: { factory(config, queue: queue) }, toolAdapter: nil,
                messages: [.init(role: .user, text: "Original request")], systemPrompt: nil)
        }
        var iterator = stream.makeAsyncIterator()
        let firstEvent = try #require(try await iterator.next())
        try owner.receive(firstEvent, uiRunID: request.uiRunID)
        let identity = try #require(owner.session?.identity)
        let logical = try HanlinLogicalToolID(providerInstanceID: .init(validating: "hanlin.host"),
                                              localToolID: .init(validating: "consent-fixture"))
        let invocation = HanlinHostInvocation(request: .init(
            id: try .init(validating: UUID().uuidString.lowercased()), logicalToolID: logical,
            aliasUsed: "consent-fixture", descriptorRevision: try .init(1), routingTableRevision: .init(1),
            arguments: .object([:]), origin: .assistantModel, deadline: .now.addingTimeInterval(30),
            limits: try .init()), session: identity, runID: firstEvent.runID, step: 0,
            providerCallID: "original-native-call", writeGuarantee: .hostManagedMutation,
            originalArgumentsJSON: Data("{}".utf8))
        let scope = HanlinToolApprovalScope(app: identity.context.namespace.app,
            account: identity.context.namespace.account, workspace: UUID().uuidString,
            providerID: logical.providerInstanceID.rawValue, toolID: logical.localToolID.rawValue,
            manifestFingerprint: String(repeating: "a", count: 64), permissionFingerprint: String(repeating: "b", count: 64))
        var phasesAtEvent: [RuntimeUserOperation.Presentation] = []
        owner.onApprovalEvent = { _, _ in phasesAtEvent.append(original.snapshot.presentation) }
        // The shared Host worker and the user's later answer can run in an
        // unrelated TaskLocal context; the original admitted operation owns UI.
        let pending = Task { @MainActor in
            await RuntimeUserOperation.$current.withValue(foreign) {
                await owner.consent.request(invocation, approvalScope: scope)
            }
        }
        for _ in 0..<100 where owner.consent.pending == nil { await Task.yield() }
        let oldID = try #require(owner.consent.pending?.id)
        #expect(original.snapshot.presentation == .awaitingApproval)
        #expect(foreign.snapshot.presentation == .waitingForResponse)
        RuntimeUserOperation.$current.withValue(foreign) {
            owner.consent.answer(id: oldID, allowed: false)
        }
        #expect(await pending.value == false)
        #expect(original.snapshot.presentation == .waitingForResponse)
        let replacement = Task { @MainActor in
            await RuntimeUserOperation.$current.withValue(foreign) {
                await owner.consent.request(invocation, approvalScope: scope)
            }
        }
        for _ in 0..<100 where owner.consent.pending == nil { await Task.yield() }
        let currentID = try #require(owner.consent.pending?.id)
        owner.consent.answer(id: oldID, allowed: true)
        #expect(owner.consent.pending?.id == currentID)
        #expect(original.snapshot.presentation == .awaitingApproval)
        // Revocation emits resolution before clearing the original owner.
        owner.cancel()
        #expect(await replacement.value == false)
        #expect(original.snapshot.presentation == .waitingForResponse)
        #expect(foreign.snapshot.presentation == .waitingForResponse)
        #expect(phasesAtEvent == [.awaitingApproval, .waitingForResponse, .awaitingApproval, .waitingForResponse])
    }


    #if targetEnvironment(simulator)
    @Test(.timeLimit(.minutes(2)))
    func actualEventKitToolRecoversTheOriginalChatAndReadsTheFullDateWindow() async throws {
        let fixture = try HanlinEventKitAcceptanceFixture()
        defer { fixture.removeOwnedItems() }
        let container = try ModelContainer(for: ChatRecords.self, ToolKeys.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let row = ChatRecords(name: "Native calendar continuation", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id), scene = UUID()
        let rows = [UUID(), UUID()], runs = [UUID(), UUID()]
        let queue = AppPartQueue(try rows.map {
            try HanlinChatStructuredPart(messageID: $0, partID: UUID(), sequence: 0,
                payload: .textDelta("Original chat continues after the native calendar tool"))
        })
        let owner = HanlinAppAgentSessionOwner(), recorder = AppPresentationRecorder()
        owner.presentation = recorder
        defer { owner.cancel() }
        let api = APIManager(context: context)
        let sources = LegacyToolCanonicalAdapter.sources(memoryEnabled: false, mapEnabled: false,
            calendarEnabled: true, searchEnabled: false, knowledgeEnabled: false, codeEnabled: false,
            healthEnabled: false, weatherEnabled: false, canvasEnabled: false)
        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [], mcpTools: [], legacySources: sources)
        var dispatchedOutcomes: [NativeToolExecutionOutcome] = []
        let executors = AssistantToolBridge.Executors(executeNative: { _, _, _, _ in
            Issue.record("Calendar escaped the original legacy route")
            return .init(modelText: "Unexpected native route", outcome: .failed)
        }, executeScripting: { _, _ in
            Issue.record("Calendar escaped the original legacy route")
            return .init(modelText: "Unexpected scripting route", outcome: .failed)
        }, executeLegacy: { name, arguments, toolContext in
            // The production default invokes the shared SDK EventKit service.
            let result = await api.executeLegacyTool(name: name, argumentsJSON: arguments,
                context: toolContext, continuation: nil)
            dispatchedOutcomes.append(result.outcome)
            return result
        })
        let adapter = HanlinAISDKToolAdapter(session: .init(chatID: id.uuidString, isTemporaryChat: false),
            preparedTools: .init(authority: authority, executors: executors, legacySources: sources))
        let config = configuration()
        var constructions = 0
        let arguments: HanlinJSONValue = .object([
            "keyword": .string(fixture.marker), "event_type": .string("both")
        ])
        let approve: @MainActor (AgentEvent) -> Void = { event in
            if case .toolApprovalChanged(let approval) = event, approval.disposition == .awaiting {
                Task { @MainActor in
                    guard let pending = owner.consent.pending,
                          pending.tool == "search_calendar_and_reminders" else { return }
                    owner.consent.answer(id: pending.id, allowed: true)
                }
            }
        }
        for index in 0..<2 {
            let stream = try await owner.stream(request: .init(conversation: row, conversationID: id,
                sceneID: scene, rowID: rows[index], uiRunID: runs[index], temporary: false, interaction: nil),
                modelContext: context, configuration: config,
                engineFactory: { constructions += 1; return factory(config, queue: queue) },
                toolAdapter: adapter, messages: [.init(role: .user, text: "Read my calendar, then continue")],
                systemPrompt: nil)
            for try await event in stream { try owner.receive(event, uiRunID: runs[index]) }
            try owner.producerStreamDrained(uiRunID: runs[index])
            if index == 0 {
                let result = try await owner.executeInlineTool(rowID: rows[0], partID: "native-calendar-read",
                    alias: "search_calendar_and_reminders", arguments: arguments, onEvent: approve)
                for title in fixture.titles { #expect(result.contains(title)) }
                #expect(dispatchedOutcomes == [.succeeded])
                #expect(!owner.inlineToolIsRunning)
                do {
                    _ = try await owner.executeInlineTool(rowID: rows[0], partID: "native-calendar-invalid",
                        alias: "search_calendar_and_reminders", arguments: .object([
                            "start_date": .string("2026-12-23"), "end_date": .string("2026-11-23"),
                            "event_type": .string("calendar")
                        ]), onEvent: approve)
                    Issue.record("Reversed native dates unexpectedly succeeded")
                } catch {}
                #expect(dispatchedOutcomes.last == .invalidArguments)
                #expect(!owner.inlineToolIsRunning)
                let cancelled = Task { @MainActor in
                    await api.executeLegacyTool(name: "search_calendar_and_reminders",
                        argumentsJSON: String(decoding: try arguments.canonicalJSONData(), as: UTF8.self),
                        context: .init(localeIdentifier: "en"), continuation: nil)
                }
                cancelled.cancel()
                let cancelledResult = try await cancelled.value
                #expect(cancelledResult.outcome == .cancelled && cancelledResult.isError)
                let recovered = try await owner.executeInlineTool(rowID: rows[0], partID: "native-calendar-recovered",
                    alias: "search_calendar_and_reminders", arguments: arguments, onEvent: approve)
                for title in fixture.titles { #expect(recovered.contains(title)) }
                #expect(dispatchedOutcomes == [.succeeded, .invalidArguments, .succeeded])
                #expect(!owner.inlineToolIsRunning)
            }
        }
        #expect(constructions == 1 && recorder.installed.count == 1)
        #expect(recorder.live.map(\.reference.rowID) == rows)
        #expect(Set(recorder.live.map(\.canonicalRunID)).count == 2)
        #expect(owner.session != nil && !owner.inlineToolIsRunning)
        let lease = try HanlinConversationRunLease.acquire(container: container, conversationID: id)
        lease.release()
        await owner.invalidate()
        let reopened = HanlinAppAgentSessionOwner(), replay = AppPresentationRecorder()
        reopened.presentation = replay
        try await reopened.restoreHistory(conversation: row, conversationID: id, sceneID: scene,
            temporary: false, modelContext: context)
        #expect(Set(replay.replayed.map(\.reference.rowID)) == Set(rows))
    }
    #endif

    private func database() throws -> ModelContainer {
        try ModelContainer(for: ChatRecords.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func configuration() -> HanlinChatModelConfiguration {
        .init(modelID: "app-component-fixture", endpoint: URL(filePath: "/fixture"), apiKey: "")
    }

    private func factory(_ config: HanlinChatModelConfiguration, queue: AppPartQueue) -> HanlinAISDKAgentEngine {
        .init(configuration: config, model: .v3(AppPartModel(queue: queue)), descriptor: .init(kind: .openAICompatible,
            modelID: config.modelID, baseURL: URL(filePath: "/fixture"), structuredPartChannel: HanlinChatStructuredPart.channel))
    }

    private func dataDatabase() throws -> ModelContainer {
        try ModelContainer(for: ChatRecords.self, APIKeys.self, MemoryArchive.self, UserInfo.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }


    @Test(arguments: [HanlinKeychainCredentialStore.Kind.model, .search, .tool])
    func originalProviderCredentialRowsReopenAndRecoverWithoutSchemaChanges(kind: HanlinKeychainCredentialStore.Kind) throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        switch kind {
        case .model:
            try exerciseCredentialRoundTrip(fixture) { APIKeys(name: "Original", company: "KEYCHAIN_FIXTURE", key: "synthetic-legacy") }
        case .search:
            try exerciseCredentialRoundTrip(fixture) { SearchKeys(name: "Original", company: "KEYCHAIN_FIXTURE", key: "synthetic-legacy") }
        case .tool:
            try exerciseCredentialRoundTrip(fixture) { ToolKeys(name: "Original", company: "KEYCHAIN_FIXTURE", key: "synthetic-legacy") }
        }
    }

    private func exerciseCredentialRoundTrip<Record: HanlinProviderCredentialRecord>(
        _ fixture: ProviderCredentialTestFixture, makeRecord: () -> Record
    ) throws {
        var originalID: PersistentIdentifier?
        var originalIdentity: ProviderCredentialTestFixture.PersistedRowIdentity?
        var reference = ""
        do {
            let container = try fixture.open(), context = container.mainContext
            context.autosaveEnabled = false
            let record = makeRecord()
            context.insert(record); try context.save()
            originalID = record.persistentModelID
            originalIdentity = try fixture.rowIdentity(record.persistentModelID)
            #expect(try fixture.credentials.resolve(record) == "synthetic-legacy")
            try fixture.credentials.save("synthetic-secured", for: record,
                expectedStoredValue: "synthetic-legacy", in: context)
            reference = try #require(record.storedCredential)
            #expect(HanlinKeychainCredentialStore.isReference(reference))
            #expect(!reference.contains("synthetic"))
            #expect(record.persistentModelID == originalID)
            #expect(try context.fetch(FetchDescriptor<Record>()).count == 1)
        }
        // Reopen the real on-disk original model, not a copied/encoded replacement.
        do {
            let container = try fixture.open(), context = container.mainContext
            context.autosaveEnabled = false
            let record = try #require(context.fetch(FetchDescriptor<Record>()).first)
            #expect(try fixture.rowIdentity(record.persistentModelID) == originalIdentity)
            #expect(record.storedCredential == reference)
            #expect(try fixture.credentials.resolve(record) == "synthetic-secured")
            #expect(try fixture.credentials.keychain.previousStoredValue(for: reference, kind: Record.credentialKind) == "synthetic-legacy")
            try fixture.credentials.restorePrevious(for: record, expectedReference: reference, in: context)
        }
        do {
            let container = try fixture.open()
            let restored = try #require(container.mainContext.fetch(FetchDescriptor<Record>()).first)
            #expect(try fixture.rowIdentity(restored.persistentModelID) == originalIdentity)
            #expect(restored.storedCredential == "synthetic-legacy")
            #expect(try fixture.credentials.resolve(restored) == "synthetic-legacy")
            #expect(try fixture.credentials.keychain.resolve(reference, kind: Record.credentialKind) == "synthetic-secured")
        }
    }

    @Test func originalCredentialEditorRemainsTransientAndLegacyCompatible() throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        context.autosaveEnabled = false
        let record = APIKeys(name: "Original editor", company: "KEYCHAIN_FIXTURE", key: "synthetic-original")
        context.insert(record); try context.save()
        var first = HanlinCredentialEditDraft(), stale = HanlinCredentialEditDraft()
        try first.load(record, credentials: fixture.credentials)
        try stale.load(record, credentials: fixture.credentials)
        first.replaceText("synthetic-unsaved")
        #expect(record.key == "synthetic-original")
        #expect(context.hasChanges == false)
        #expect(try ModelContext(container).fetch(FetchDescriptor<APIKeys>()).first?.key == "synthetic-original")
        #expect(try fixture.references().isEmpty)
        // Discarding the transient draft cannot persist it.
        first = HanlinCredentialEditDraft()
        try first.load(record, credentials: fixture.credentials)
        #expect(first.text == "synthetic-original")
        first.replaceText("synthetic-explicit-save")
        try first.save(to: record, in: context, credentials: fixture.credentials)
        // Activation secures actual secret edits while the earlier untouched row
        // remains readable in its original legacy representation.
        let committedReference = try #require(record.key)
        #expect(HanlinKeychainCredentialStore.isReference(committedReference))
        #expect(try fixture.credentials.resolve(record) == "synthetic-explicit-save")
        #expect(try fixture.references().count == 1)
        stale.replaceText("synthetic-stale-editor")
        #expect(throws: Error.self) { try stale.save(to: record, in: context, credentials: fixture.credentials) }
        #expect(record.key == committedReference)
        let reopened = try fixture.open()
        #expect(try reopened.mainContext.fetch(FetchDescriptor<APIKeys>()).first?.key == committedReference)
    }

    @Test func originalCredentialStaleContextCannotCheckpointOverNewerSavedValue() throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), editorContext = container.mainContext
        editorContext.autosaveEnabled = false
        let record = APIKeys(name: "Original stale context", company: "KEYCHAIN_FIXTURE",
            key: "synthetic-original", requestURL: "https://example.invalid/original")
        editorContext.insert(record); try editorContext.save()
        var draft = HanlinCredentialEditDraft()
        try draft.load(record, credentials: fixture.credentials)
        draft.replaceText("synthetic-stale")
        record.requestURL = "https://example.invalid/unsaved-editor"
        let otherContext = ModelContext(container)
        otherContext.autosaveEnabled = false
        let newer = try #require(otherContext.fetch(FetchDescriptor<APIKeys>()).first)
        newer.key = "synthetic-newer-context"
        try otherContext.save()
        #expect(throws: Error.self) { try draft.save(to: record, in: editorContext, credentials: fixture.credentials) }
        let diskReader = ModelContext(container)
        let saved = try #require(diskReader.fetch(FetchDescriptor<APIKeys>()).first)
        #expect(saved.key == "synthetic-newer-context")
        #expect(saved.requestURL == "https://example.invalid/original")
        #expect(try fixture.references().isEmpty)
        editorContext.rollback()
    }

    @Test func originalSecuredCredentialRotationRetainsPredecessorAndRejectsStaleDraft() throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        let record = APIKeys(name: "Original rotated credential", company: "KEYCHAIN_FIXTURE", key: "synthetic-original")
        context.insert(record); try context.save()
        try fixture.credentials.save("synthetic-first", for: record,
            expectedStoredValue: "synthetic-original", in: context)
        let firstReference = try #require(record.key)
        var current = HanlinCredentialEditDraft(), stale = HanlinCredentialEditDraft()
        try current.load(record, credentials: fixture.credentials)
        try stale.load(record, credentials: fixture.credentials)
        current.replaceText("synthetic-second")
        try current.save(to: record, in: context, credentials: fixture.credentials)
        let secondReference = try #require(record.key)
        #expect(secondReference != firstReference)
        #expect(try fixture.credentials.resolve(record) == "synthetic-second")
        #expect(try fixture.credentials.keychain.resolve(firstReference, kind: .model) == "synthetic-first")
        #expect(try fixture.credentials.keychain.previousStoredValue(for: secondReference, kind: .model) == firstReference)
        stale.replaceText("synthetic-stale")
        #expect(throws: Error.self) { try stale.save(to: record, in: context, credentials: fixture.credentials) }
        #expect(try fixture.references().count == 2)
        #expect(record.key == secondReference)
        try fixture.credentials.restorePrevious(for: record, expectedReference: secondReference, in: context)
        #expect(record.key == firstReference)
        #expect(try fixture.credentials.resolve(record) == "synthetic-first")
        #expect(try fixture.credentials.keychain.resolve(secondReference, kind: .model) == "synthetic-second")

        record.key = "hanlin-keychain:v1:model:\(UUID().uuidString.lowercased())"
        try context.save()
        var unavailable = HanlinCredentialEditDraft()
        #expect(throws: Error.self) { try unavailable.load(record, credentials: fixture.credentials) }
        #expect(unavailable.isReadyToSave == false)
        #expect(throws: Error.self) { try unavailable.save(to: record, in: context, credentials: fixture.credentials) }
        #expect(record.key?.hasPrefix("hanlin-keychain:v1:model:") == true)
        #expect(try fixture.references().count == 2)
    }

    @Test(arguments: ["", "synthetic-persisted"])
    func originalDiscoveryAndProbesUseUnsavedCredentialWithoutImplicitFallback(storedKey: String) async throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        context.autosaveEnabled = false
        let host = UUID().uuidString.lowercased() + ".provider-credential-test.invalid"
        let endpoint = "https://\(host)/v1/chat/completions"
        ProviderCredentialURLProtocol.register(host: host)
        defer { ProviderCredentialURLProtocol.remove(host: host) }
        let transport = URLSessionConfiguration.ephemeral
        transport.protocolClasses = [ProviderCredentialURLProtocol.self]
        let session = URLSession(configuration: transport)
        defer { session.invalidateAndCancel() }
        let provider = APIKeys(name: "Original discovery editor", company: "TEST_DRAFT",
            key: storedKey, requestURL: endpoint, isHidden: false)
        context.insert(provider); try context.save()
        var draft = HanlinCredentialEditDraft()
        try draft.load(provider, credentials: fixture.credentials)
        draft.replaceText("synthetic-entered")
        let override = ModelRefreshProviderConfiguration(provider: provider, credential: draft.text)
        let models = try await ModelRefreshService.fetchModelsFromAPI(apiKey: provider,
            configurationOverride: override, session: session)
        #expect(models.map(\.id) == ["fixture-model"])
        _ = try await ModelRefreshService.probeModelCapabilities(modelId: "fixture-model",
            company: "TEST_DRAFT", context: context, configurationOverride: override, session: session,
            update: { _, _, _ in })
        let requests = ProviderCredentialURLProtocol.snapshot(host: host)
        #expect(requests.count >= 2, "Both the actual discovery and actual capability pipeline reached the transport")
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-entered" })
        #expect(provider.key == storedKey)
        #expect(context.hasChanges == false)
        #expect(try ModelContext(container).fetch(FetchDescriptor<APIKeys>()).first?.key == storedKey)
        #expect(try fixture.references().isEmpty)

        let empty = ModelRefreshProviderConfiguration(provider: provider, credential: "")
        do {
            _ = try await ModelRefreshService.fetchModelsFromAPI(apiKey: provider,
                configurationOverride: empty, session: session)
            Issue.record("An explicitly empty discovery draft fell back to its saved credential")
        } catch { #expect(error is ModelFetchError) }
        do {
            _ = try await ModelRefreshService.probeModelCapabilities(modelId: "fixture-model",
                company: "TEST_DRAFT", context: context, configurationOverride: empty, session: session,
                update: { _, _, _ in })
            Issue.record("An explicitly empty probe draft fell back to its saved credential")
        } catch { #expect(error is ModelCapabilityProbeError) }
        #expect(ProviderCredentialURLProtocol.snapshot(host: host).count == requests.count)

        if storedKey.isEmpty {
            do {
                _ = try await ModelRefreshService.fetchModelsFromAPI(apiKey: provider, session: session)
                Issue.record("Absent override invented a saved key")
            } catch { #expect(error is ModelFetchError) }
        } else {
            _ = try await ModelRefreshService.fetchModelsFromAPI(apiKey: provider, session: session)
            #expect(ProviderCredentialURLProtocol.snapshot(host: host).last?.value(forHTTPHeaderField: "Authorization") == "Bearer \(storedKey)")
        }
        let other = APIKeys(name: "Other original provider", company: "OTHER", key: "", requestURL: endpoint)
        let foreign = ModelRefreshProviderConfiguration(provider: other, credential: "synthetic-foreign")
        let countBeforeForeign = ProviderCredentialURLProtocol.snapshot(host: host).count
        do {
            _ = try await ModelRefreshService.fetchModelsFromAPI(apiKey: provider,
                configurationOverride: foreign, session: session)
            Issue.record("A transient key crossed provider ownership")
        } catch { #expect(error is ModelFetchError) }
        #expect(ProviderCredentialURLProtocol.snapshot(host: host).count == countBeforeForeign)
        #expect(provider.key == storedKey)
    }

    @Test func originalCredentialCommitSurvivesPublicationFailureAndRetryDoesNotResave() throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        context.autosaveEnabled = false
        let provider = APIKeys(name: "Original publication failure", company: "KEYCHAIN_FIXTURE",
            key: "synthetic-original", requestURL: "https://example.invalid/v1/chat/completions", isHidden: false)
        context.insert(provider)
        context.insert(AllModels(name: "fixture-model", displayName: "Fixture", position: 0, company: "KEYCHAIN_FIXTURE"))
        try context.save()
        try fixture.credentials.save("synthetic-before-edit", for: provider,
            expectedStoredValue: "synthetic-original", in: context)
        var draft = HanlinCredentialEditDraft()
        try draft.load(provider, credentials: fixture.credentials)
        draft.replaceText("synthetic-committed")
        let blocker = fixture.directory.appendingPathComponent("not-a-directory")
        try Data("owned synthetic blocker".utf8).write(to: blocker)
        let brokenStore = HanlinCompactAgentConfigStore(customURL: blocker.appendingPathComponent("config.json"))
        let brokenPublisher = HanlinScriptingPlatformAIIntegration(modelContext: context, compactConfigStore: brokenStore)
        let timestamp = Date(timeIntervalSince1970: 12345)
        let result = try draft.saveAndPublish(to: provider, in: context, credentials: fixture.credentials,
            update: { $0.timestamp = timestamp },
            publishCompactConfiguration: { try brokenPublisher.publishCompactAgentConfig() })
        #expect(result == .needsRetry)
        let committedReference = try #require(provider.key)
        #expect(draft.expectedStoredValue == committedReference)
        #expect(draft.text == "synthetic-committed")
        #expect(draft.edited == false)
        #expect(try fixture.credentials.resolve(provider) == "synthetic-committed")
        #expect(try ModelContext(container).fetch(FetchDescriptor<APIKeys>()).first?.key == committedReference)
        #expect(try fixture.references().count == 2)
        let fixedStore = HanlinCompactAgentConfigStore(customURL: fixture.directory.appendingPathComponent("published.json"))
        let publisher = HanlinScriptingPlatformAIIntegration(modelContext: context, compactConfigStore: fixedStore)
        #expect(HanlinCredentialEditDraft.retryPublication { try publisher.publishCompactAgentConfig() } == .updated)
        #expect(provider.key == committedReference)
        #expect(provider.timestamp == timestamp)
        #expect(try fixture.references().count == 2, "Retry only publishes the compact file")
        #expect(try fixedStore.load()?.credentialReference == committedReference)
        #expect(try fixedStore.load()?.apiKey.isEmpty == true)
    }

    @Test(arguments: [HanlinKeychainCredentialStore.Kind.model, .search, .tool])
    func protectedCredentialMetadataSavesPreserveOriginalRowsAndGenerations(kind: HanlinKeychainCredentialStore.Kind) throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        switch kind {
        case .model:
            try exerciseProtectedMetadata(fixture,
                make: { APIKeys(name: "Original", company: "FIXTURE", key: "synthetic-legacy") },
                update: { $0.timestamp = $1 }, timestamp: { $0.timestamp })
        case .search:
            try exerciseProtectedMetadata(fixture,
                make: { SearchKeys(name: "Original", company: "FIXTURE", key: "synthetic-legacy") },
                update: { $0.timestamp = $1 }, timestamp: { $0.timestamp })
        case .tool:
            try exerciseProtectedMetadata(fixture,
                make: { ToolKeys(name: "Original", company: "FIXTURE", key: "synthetic-legacy") },
                update: { $0.timestamp = $1 }, timestamp: { $0.timestamp })
        }
    }

    private func exerciseProtectedMetadata<Record: HanlinProviderCredentialRecord>(
        _ fixture: ProviderCredentialTestFixture, make: () -> Record,
        update: (Record, Date) -> Void, timestamp: (Record) -> Date
    ) throws {
        let container = try fixture.open(), context = container.mainContext
        context.autosaveEnabled = false
        let record = make()
        context.insert(record); try context.save()
        let originalIdentity = try fixture.rowIdentity(record.persistentModelID)
        var draft = HanlinCredentialEditDraft()
        try draft.load(record, credentials: fixture.credentials)
        let changedDate = Date(timeIntervalSince1970: 12345)
        try draft.save(to: record, in: context, credentials: fixture.credentials) { update($0, changedDate) }
        #expect(record.storedCredential == "synthetic-legacy")
        #expect(timestamp(record) == changedDate)
        #expect(try fixture.references().isEmpty)
        // Typing and undoing back to the exact original bytes is not a migration.
        draft.replaceText("synthetic-legacy-changed")
        draft.replaceText("synthetic-legacy")
        #expect(draft.hasCredentialReplacement == false)
        try draft.save(to: record, in: context, credentials: fixture.credentials)
        #expect(record.storedCredential == "synthetic-legacy")
        #expect(try fixture.references().isEmpty)

        draft.replaceText("synthetic-\u{00e9}")
        #expect(draft.hasCredentialReplacement)
        try draft.save(to: record, in: context, credentials: fixture.credentials)
        let first = try #require(record.storedCredential)
        #expect(HanlinKeychainCredentialStore.isReference(first))
        #expect(try fixture.references().count == 1)
        try draft.save(to: record, in: context, credentials: fixture.credentials) { update($0, changedDate.addingTimeInterval(1)) }
        #expect(record.storedCredential == first)
        #expect(try fixture.references().count == 1)
        // Canonical Unicode equality must not discard a real opaque-byte change.
        draft.replaceText("synthetic-e\u{0301}")
        #expect(draft.hasCredentialReplacement)
        try draft.save(to: record, in: context, credentials: fixture.credentials)
        #expect(record.storedCredential != first)
        #expect(try fixture.references().count == 2)
        #expect(Data(try #require(try fixture.credentials.resolve(record)).utf8) == Data("synthetic-e\u{0301}".utf8))
        let reopened = try fixture.open()
        let saved = try #require(reopened.mainContext.fetch(FetchDescriptor<Record>()).first)
        #expect(try fixture.rowIdentity(saved.persistentModelID) == originalIdentity)
        #expect(saved.storedCredential == record.storedCredential)
        #expect(timestamp(saved) == changedDate.addingTimeInterval(1))
        #expect(Data(try #require(try fixture.credentials.resolve(saved)).utf8) == Data("synthetic-e\u{0301}".utf8))
    }

    @Test(arguments: [Optional<String>.none, Optional<String>.some("")])
    func protectedCredentialMetadataSaveRetainsNilAndEmptyRepresentations(initial: String?) throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        let record = APIKeys(name: "Original optional key", company: "FIXTURE", key: initial)
        context.insert(record); try context.save()
        let originalIdentity = try fixture.rowIdentity(record.persistentModelID)
        var draft = HanlinCredentialEditDraft()
        try draft.load(record, credentials: fixture.credentials)
        draft.replaceText("")
        #expect(draft.hasCredentialReplacement == false)
        let timestamp = Date(timeIntervalSince1970: 54321)
        try draft.save(to: record, in: context, credentials: fixture.credentials) { $0.timestamp = timestamp }
        #expect(record.key == initial)
        #expect(record.timestamp == timestamp)
        #expect(try fixture.references().isEmpty)
        let reopened = try fixture.open()
        let saved = try #require(reopened.mainContext.fetch(FetchDescriptor<APIKeys>()).first)
        #expect(try fixture.rowIdentity(saved.persistentModelID) == originalIdentity)
        #expect(saved.key == initial)
        #expect(throws: Error.self) {
            try fixture.credentials.saveMetadata(for: record, expectedStoredValue: initial, in: context) {
                $0.key = "must-not-bypass-secured-write"
            }
        }
        #expect(record.key == initial)
        #expect(try fixture.references().isEmpty)
    }

    @Test(arguments: [HanlinKeychainCredentialStore.Kind.model, .search, .tool])
    func protectedCredentialExplicitMigrationIsTargetedAndRecoverable(kind: HanlinKeychainCredentialStore.Kind) throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        switch kind {
        case .model:
            try exerciseExplicitCredentialMigration(fixture) { value in
                APIKeys(name: value, company: value, key: value)
            }
        case .search:
            try exerciseExplicitCredentialMigration(fixture) { value in
                SearchKeys(name: value, company: value, key: value)
            }
        case .tool:
            try exerciseExplicitCredentialMigration(fixture) { value in
                ToolKeys(name: value, company: value, key: value)
            }
        }
    }

    private func exerciseExplicitCredentialMigration<Record: HanlinProviderCredentialRecord>(
        _ fixture: ProviderCredentialTestFixture, make: (String) -> Record
    ) throws {
        let container = try fixture.open(), context = container.mainContext
        let record = make("synthetic-selected"), unrelated = make("synthetic-unrelated")
        context.insert(record); context.insert(unrelated); try context.save()
        let originalID = record.persistentModelID
        let originalIdentity = try fixture.rowIdentity(originalID)
        #expect(try fixture.rowIdentity(unrelated.persistentModelID) != originalIdentity)
        var draft = HanlinCredentialEditDraft()
        try draft.load(record, credentials: fixture.credentials)
        #expect(draft.hasCredentialReplacement == false)
        #expect(draft.canMigrate(record))
        try draft.migrate(record, in: context, credentials: fixture.credentials)
        let reference = try #require(record.storedCredential)
        #expect(HanlinKeychainCredentialStore.isReference(reference))
        #expect(try fixture.credentials.resolve(record) == "synthetic-selected")
        #expect(try fixture.credentials.keychain.previousStoredValue(for: reference, kind: Record.credentialKind) == "synthetic-selected")
        #expect(unrelated.storedCredential == "synthetic-unrelated")
        #expect(record.persistentModelID == originalID)
        #expect(draft.canMigrate(record) == false)
        #expect(throws: Error.self) { try draft.migrate(record, in: context, credentials: fixture.credentials) }
        #expect(try fixture.references().count == 1)
        do {
            let reopened = try fixture.open()
            let rows = try reopened.mainContext.fetch(FetchDescriptor<Record>())
            #expect(rows.count == 2)
            let saved = try #require(rows.first(where: { (try? fixture.rowIdentity($0.persistentModelID)) == originalIdentity }))
            #expect(saved.storedCredential == reference)
            #expect(try fixture.credentials.resolve(saved) == "synthetic-selected")
        }
        try fixture.credentials.restorePrevious(for: record, expectedReference: reference, in: context)
        #expect(record.storedCredential == "synthetic-selected")
        #expect(unrelated.storedCredential == "synthetic-unrelated")
        #expect(try fixture.credentials.keychain.resolve(reference, kind: Record.credentialKind) == "synthetic-selected")
        do {
            let readOnly = try fixture.open(allowsSave: false), reader = readOnly.mainContext
            reader.autosaveEnabled = false
            let rows = try reader.fetch(FetchDescriptor<Record>())
            #expect(rows.count == 2)
            let saved = try #require(rows.first(where: { (try? fixture.rowIdentity($0.persistentModelID)) == originalIdentity }))
            var migration = HanlinCredentialEditDraft()
            try migration.load(saved, credentials: fixture.credentials)
            #expect(migration.canMigrate(saved))
            #expect(throws: Error.self) {
                try migration.migrate(saved, in: reader, credentials: fixture.credentials)
            }
        }
        let reopened = try fixture.open()
        let rows = try reopened.mainContext.fetch(FetchDescriptor<Record>())
        #expect(rows.count == 2)
        let saved = try #require(rows.first(where: { (try? fixture.rowIdentity($0.persistentModelID)) == originalIdentity }))
        #expect(saved.storedCredential == "synthetic-selected")
        #expect(try fixture.references().count == 2, "A failed migration retains its staged checkpoint without replacing the original durable row")
    }

    @Test func protectedCredentialMigrationRejectsBuiltInMarkersAndEmptyKeys() throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        func check<Record: HanlinProviderCredentialRecord>(_ record: Record) throws {
            context.insert(record); try context.save()
            let stored = record.storedCredential
            var draft = HanlinCredentialEditDraft()
            try draft.load(record, credentials: fixture.credentials)
            #expect(draft.canMigrate(record) == false)
            #expect(throws: Error.self) { try draft.migrate(record, in: context, credentials: fixture.credentials) }
            #expect(record.storedCredential == stored)
        }
        try check(APIKeys(name: "Local", company: "LOCAL", key: "LOCAL"))
        try check(ToolKeys(name: "Apple Maps", company: "APPLEMAP", key: "APPLEMAP"))
        try check(AutomaticSearchMigration.makeAutomaticSearchKey())
        #expect(try fixture.references().isEmpty)
    }

    @Test func protectedCredentialNewProviderCommitsOnlyReferenceAndFailedInsertRetainsExistingRows() throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        var committedReference = ""
        do {
            let container = try fixture.open(), context = container.mainContext
            let record = APIKeys(name: "New original provider", company: "NEW_FIXTURE", key: nil,
                requestURL: "https://example.invalid", isHidden: false)
            try fixture.credentials.insert(record, value: "synthetic-new-provider", in: context)
            committedReference = try #require(record.key)
            #expect(HanlinKeychainCredentialStore.isReference(committedReference))
            #expect(try fixture.credentials.resolve(record) == "synthetic-new-provider")
        }
        do {
            let readOnly = try fixture.open(allowsSave: false), context = readOnly.mainContext
            context.autosaveEnabled = false
            let failed = APIKeys(name: "Failed original provider", company: "FAILED_FIXTURE", key: nil)
            #expect(throws: Error.self) {
                try fixture.credentials.insert(failed, value: "synthetic-failed-provider", in: context)
            }
        }
        let reopened = try fixture.open()
        let rows = try reopened.mainContext.fetch(FetchDescriptor<APIKeys>())
        #expect(rows.count == 1)
        #expect(rows.first?.company == "NEW_FIXTURE")
        #expect(rows.first?.key == committedReference)
        #expect(try fixture.references().count == 2, "Failed insertion retains its staged generation without creating a canonical row")
    }

    @Test(arguments: ["synthetic-reentered", ""])
    func protectedCredentialExplicitReplacementRecoversMissingReferenceWithoutPlaintextFallback(value: String) throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        let missing = "hanlin-keychain:v1:model:\(UUID().uuidString.lowercased())"
        let record = APIKeys(name: "Original unavailable", company: "FIXTURE", key: missing)
        context.insert(record); try context.save()
        let originalIdentity = try fixture.rowIdentity(record.persistentModelID)
        var draft = HanlinCredentialEditDraft()
        #expect(throws: Error.self) { try draft.load(record, credentials: fixture.credentials) }
        #expect(draft.isReadyToSave == false)
        #expect(throws: Error.self) { try draft.save(to: record, in: context, credentials: fixture.credentials) }
        #expect(record.key == missing)
        draft.replaceText(value)
        #expect(draft.hasCredentialReplacement)
        try draft.save(to: record, in: context, credentials: fixture.credentials)
        let replacement = try #require(record.key)
        #expect(replacement != missing)
        #expect(HanlinKeychainCredentialStore.isReference(replacement))
        #expect(try fixture.credentials.resolve(record) == value)
        #expect(try fixture.credentials.keychain.previousStoredValue(for: replacement, kind: .model) == missing)
        #expect(try fixture.references().count == 1)
        let reopened = try fixture.open()
        let saved = try #require(reopened.mainContext.fetch(FetchDescriptor<APIKeys>()).first)
        #expect(try fixture.rowIdentity(saved.persistentModelID) == originalIdentity)
        #expect(saved.key == replacement)
        #expect(try fixture.credentials.resolve(saved) == value)
    }

    @Test func protectedCredentialMetadataFailureAndStaleDraftPreserveOriginalDiskRow() throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        context.autosaveEnabled = false
        let timestamp = Date(timeIntervalSince1970: 11223)
        let record = APIKeys(name: "Original metadata failure", company: "FIXTURE", key: "synthetic-original",
            requestURL: "https://example.invalid/original", timestamp: timestamp)
        context.insert(record); try context.save()
        var stale = HanlinCredentialEditDraft()
        try stale.load(record, credentials: fixture.credentials)
        record.requestURL = "https://example.invalid/unsaved"
        let otherContext = ModelContext(container)
        otherContext.autosaveEnabled = false
        let newer = try #require(otherContext.fetch(FetchDescriptor<APIKeys>()).first)
        try fixture.credentials.save("synthetic-newer", for: newer,
            expectedStoredValue: "synthetic-original", in: otherContext)
        let reference = try #require(newer.key)
        #expect(stale.hasCredentialReplacement == false)
        #expect(throws: Error.self) {
            try stale.save(to: record, in: context, credentials: fixture.credentials) { $0.timestamp = Date() }
        }
        context.rollback()
        do {
            let readOnly = try fixture.open(allowsSave: false), reader = readOnly.mainContext
            reader.autosaveEnabled = false
            let saved = try #require(reader.fetch(FetchDescriptor<APIKeys>()).first)
            var draft = HanlinCredentialEditDraft()
            try draft.load(saved, credentials: fixture.credentials)
            #expect(throws: Error.self) {
                try draft.save(to: saved, in: reader, credentials: fixture.credentials) {
                    $0.timestamp = timestamp.addingTimeInterval(1)
                }
            }
            #expect(saved.key == reference)
        }
        let reopened = try fixture.open()
        let saved = try #require(reopened.mainContext.fetch(FetchDescriptor<APIKeys>()).first)
        #expect(saved.key == reference)
        #expect(saved.timestamp == timestamp)
        #expect(saved.requestURL == "https://example.invalid/original")
        #expect(try fixture.credentials.resolve(saved) == "synthetic-newer")
        #expect(try fixture.references().count == 1, "Metadata-only failure and stale save create no Keychain generations")
    }

    @Test func originalCredentialStageFailureLeavesOriginalDiskRowUnchanged() throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        context.autosaveEnabled = false
        let record = APIKeys(name: "Original denied staging", company: "KEYCHAIN_FIXTURE", key: "synthetic-original")
        context.insert(record); try context.save()
        // Apple documents an empty explicit access group as invalid. This is an
        // actual SecItemAdd failure, not an injected successful/failed storage mock.
        let denied = HanlinAppProviderCredentials(keychain: .init(service: fixture.service,
            accessGroup: "", synchronizable: false, accessibility: .afterFirstUnlock))
        #expect(throws: Error.self) {
            try denied.save("synthetic-replacement", for: record,
                expectedStoredValue: "synthetic-original", in: context)
        }
        #expect(record.key == "synthetic-original")
        #expect(context.hasChanges == false)
        #expect(try fixture.references().isEmpty)
        let reopened = try fixture.open()
        #expect(try reopened.mainContext.fetch(FetchDescriptor<APIKeys>()).first?.key == "synthetic-original")
    }

    @Test func originalCredentialReadOnlySaveRetainsStagedRecoveryWithoutReplacingLegacyRow() throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        do {
            let container = try fixture.open(), context = container.mainContext
            context.insert(APIKeys(name: "Original read-only", company: "KEYCHAIN_FIXTURE", key: "synthetic-original"))
            try context.save()
        }
        do {
            let readOnly = try fixture.open(allowsSave: false), context = readOnly.mainContext
            context.autosaveEnabled = false
            let record = try #require(context.fetch(FetchDescriptor<APIKeys>()).first)
            #expect(throws: Error.self) {
                try fixture.credentials.save("synthetic-staged", for: record,
                    expectedStoredValue: "synthetic-original", in: context)
            }
            #expect(record.key == "synthetic-original")
            #expect(context.hasChanges == false)
        }
        let references = try fixture.references()
        #expect(references.count == 1, "The real Keychain write succeeded before the original disk commit failed")
        let staged = try #require(references.first)
        #expect(try fixture.credentials.keychain.resolve(staged, kind: .model) == "synthetic-staged")
        #expect(try fixture.credentials.keychain.previousStoredValue(for: staged, kind: .model) == "synthetic-original")
        let reopened = try fixture.open()
        #expect(try reopened.mainContext.fetch(FetchDescriptor<APIKeys>()).first?.key == "synthetic-original")
    }

    @Test func originalCredentialHandlesFailClosedAndPreserveCurrentRequestAuthority() async throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        let row = ChatRecords(name: "Original secured request", type: "chat")
        let provider = APIKeys(name: "Original secured provider", company: "KEYCHAIN_FIXTURE", key: "synthetic-original")
        context.insert(row); context.insert(provider); try context.save()
        try fixture.credentials.save("synthetic-secured", for: provider,
            expectedStoredValue: "synthetic-original", in: context)
        let reference = try #require(provider.key)
        let id = try #require(row.id), owner = HanlinAppAgentSessionOwner()
        let request = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id,
            sceneID: UUID(), rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let model = HanlinModelReference(provider: "KEYCHAIN_FIXTURE", modelID: "selected-original")
        let api = APIManager(context: context, agentSessionOwner: owner, providerCredentials: fixture.credentials)
        try api.bindDataAccess(request: request, model: model)
        let port: any HanlinCredentialResolver = api
        let namespace = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library",
            workspace: "swiftdata", space: id.uuidString)
        #expect(try await port.credential(for: model, namespace: namespace) == "synthetic-secured")
        let composed = "synthetic-\u{00e9}", decomposed = "synthetic-e\u{0301}"
        #expect(composed == decomposed, "Control: Swift String equality folds canonical Unicode equivalents")
        let unicodeHandle = try fixture.credentials.keychain.stage(composed, kind: .model, previousStoredValue: reference)
        provider.key = unicodeHandle; try context.save()
        #expect(try fixture.credentials.matches(composed, for: provider))
        #expect(try fixture.credentials.matches(decomposed, for: provider) == false)
        #expect(Data(try await port.credential(for: model, namespace: namespace).utf8) == Data(composed.utf8))
        let wrongKind = try fixture.credentials.keychain.stage("synthetic-search", kind: .search, previousStoredValue: nil)
        for invalid in [wrongKind, "hanlin-keychain:v99:model:future",
                        "hanlin-keychain:v1:model:\(UUID().uuidString.lowercased())"] {
            provider.key = invalid; try context.save()
            do {
                _ = try await port.credential(for: model, namespace: namespace)
                Issue.record("An unresolved or foreign-kind handle escaped as a provider credential")
            } catch { #expect(error is HanlinKeychainCredentialStore.Failure) }
        }
        provider.key = reference; try context.save()
        #expect(try await port.credential(for: model, namespace: namespace) == "synthetic-secured")
        owner.revoke()
        do {
            _ = try await port.credential(for: model, namespace: namespace)
            Issue.record("The secured credential survived original owner revocation")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
    }

    @Test func originalSecuredSearchSelectionSurvivesUnavailableKeychain() throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        let reference = "hanlin-keychain:v1:search:\(UUID().uuidString.lowercased())"
        let manual = SearchKeys(name: "Original selected search", company: "TAVILY", key: reference, isUsing: true)
        let automatic = AutomaticSearchMigration.makeAutomaticSearchKey(isUsing: true)
        context.insert(manual); context.insert(automatic); try context.save()
        #expect(throws: Error.self) { _ = try fixture.credentials.resolve(manual) }
        AutomaticSearchMigration.reconcileDefaultProvider(in: context)
        #expect(manual.isUsing)
        #expect(automatic.isUsing == false)
        #expect(manual.key == reference)
    }

    @Test func originalCompactPublisherExportsOnlySecuredReferenceAndRetainsLegacyCompatibility() throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        let provider = APIKeys(name: "Original compact", company: "KEYCHAIN_FIXTURE", key: "synthetic-legacy-compact",
            requestURL: "https://example.invalid/v1/chat/completions", isHidden: false)
        let model = AllModels(name: "fixture-model", displayName: "Fixture model", position: 0, company: "KEYCHAIN_FIXTURE")
        context.insert(provider); context.insert(model); try context.save()
        let url = fixture.directory.appendingPathComponent("original-compact-config.json")
        let store = HanlinCompactAgentConfigStore(customURL: url)
        let publisher = HanlinScriptingPlatformAIIntegration(modelContext: context, compactConfigStore: store)
        try publisher.publishCompactAgentConfig()
        #expect(try store.load()?.apiKey == "synthetic-legacy-compact")
        try fixture.credentials.save("synthetic-secured-compact", for: provider,
            expectedStoredValue: "synthetic-legacy-compact", in: context)
        try publisher.publishCompactAgentConfig()
        let raw = try Data(contentsOf: url)
        #expect(raw.range(of: Data("synthetic-secured-compact".utf8)) == nil)
        #expect(raw.range(of: Data("synthetic-legacy-compact".utf8)) == nil)
        let config = try #require(try store.load())
        #expect(config.apiKey.isEmpty)
        #expect(config.credentialReference == provider.key)
        #expect(config.chatModelConfiguration.apiKey.isEmpty)
        #expect(throws: Error.self) { _ = try config.resolvedChatModelConfiguration(using: nil) }
        let keychain = fixture.credentials.keychain
        let resolved = try config.resolvedChatModelConfiguration(using: { handle in
            try #require(try keychain.resolve(handle, kind: .model))
        })
        #expect(resolved.apiKey == "synthetic-secured-compact")
        try store.clear()
        #expect(try store.load() == nil)
        #expect(try keychain.resolve(provider.key, kind: .model) == "synthetic-secured-compact",
            "Removing configuration is not permission to delete a shared credential")
    }

    @Test(arguments: ["revoke", "rotate", "rotateSameValue", "endpoint", "deleteOrigin", "rebind", "cancel"])
    func originalProviderAdmissionRejectsChangesDuringDiagnosticAwait(change: String) async throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        context.autosaveEnabled = false
        let host = "provider-admission-\(UUID().uuidString.lowercased()).invalid"
        ProviderCredentialURLProtocol.register(host: host, streaming: true)
        defer { ProviderCredentialURLProtocol.remove(host: host) }
        let endpoint = "https://\(host)/v1/chat/completions"
        let row = ChatRecords(name: "Original transport origin", type: "chat")
        let provider = APIKeys(name: "Original transport provider", company: "TRANSPORT_FIXTURE",
            key: "synthetic-legacy", requestURL: endpoint)
        context.insert(row); context.insert(provider); try context.save()
        try fixture.credentials.save("synthetic-current", for: provider,
            expectedStoredValue: "synthetic-legacy", in: context)
        let originalReference = try #require(provider.key)
        let owner = HanlinAppAgentSessionOwner()
        defer { owner.cancel() }
        let request = HanlinAppAgentSessionOwner.Request(conversation: row,
            conversationID: try #require(row.id), sceneID: UUID(), rowID: UUID(),
            uiRunID: UUID(), temporary: false, interaction: nil)
        let model = HanlinModelReference(provider: "TRANSPORT_FIXTURE", modelID: "fixture-model")
        let api = APIManager(context: context, agentSessionOwner: owner, providerCredentials: fixture.credentials)
        try api.bindDataAccess(request: request, model: model)
        let admission = try api.makeProviderRequestAdmission(model: model, configuration: provider, credential: "synthetic-current")
        let gate = AppHistoryWriteGate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderCredentialURLProtocol.self]
        let fetch = HanlinAISDKProviderFactory.makeFetch(sessionConfiguration: configuration,
            onRequest: { _ in await gate.pause() }, requestAdmission: admission)
        let config = HanlinChatModelConfiguration(modelID: model.modelID, company: model.provider,
            apiType: "OpenAI", endpoint: try #require(URL(string: endpoint)), apiKey: "synthetic-current")
        let transportRequest = try HanlinChatRequestBuilder.buildRequest(
            formattedMessages: [["role": "user", "content": "Synthetic private prompt waiting at admission"]],
            configuration: config)
        #expect(transportRequest.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-current")
        #expect(transportRequest.httpBody?.isEmpty == false)
        let work = Task { try await fetch(transportRequest) }
        defer { work.cancel(); gate.release() }
        await gate.waitUntilPaused()
        #expect(ProviderCredentialURLProtocol.snapshot(host: host).isEmpty)
        switch change {
        case "revoke": owner.revoke()
        case "rotate", "rotateSameValue", "endpoint":
            let writer = ModelContext(container)
            writer.autosaveEnabled = false
            let original = try #require(writer.fetch(FetchDescriptor<APIKeys>())
                .first(where: { $0.persistentModelID == provider.persistentModelID }))
            if change == "endpoint" {
                original.requestURL = endpoint + "?changed=1"
                try writer.save()
            } else {
                try fixture.credentials.save(change == "rotate" ? "synthetic-rotated" : "synthetic-current",
                    for: original, expectedStoredValue: originalReference, in: writer)
            }
        case "deleteOrigin": context.delete(row); try context.save()
        case "rebind": _ = try owner.prepareDataAccess(request: request, modelContext: context)
        case "cancel": work.cancel()
        default: Issue.record("Unrecognized transport adversary")
        }
        gate.release()
        do {
            _ = try await work.value
            Issue.record("An obsolete request reached the production fetch transport")
        } catch {
            if change == "cancel" { #expect(error is CancellationError) }
            else { #expect(error as? HanlinHostError == .staleContext) }
        }
        #expect(ProviderCredentialURLProtocol.snapshot(host: host).isEmpty,
            "The original URLSession must not begin a request after revocation during diagnostics")
    }

    @Test func originalDirectTransportRechecksOwnerInsideItsProducer() async throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        let host = "direct-admission-\(UUID().uuidString.lowercased()).invalid"
        ProviderCredentialURLProtocol.register(host: host, streaming: true)
        defer { ProviderCredentialURLProtocol.remove(host: host) }
        let endpoint = try #require(URL(string: "https://\(host)/v1/chat/completions"))
        let row = ChatRecords(name: "Original direct origin", type: "chat")
        let provider = APIKeys(name: "Original direct provider", company: "TRANSPORT_FIXTURE",
            key: "synthetic-direct", requestURL: endpoint.absoluteString)
        context.insert(row); context.insert(provider); try context.save()
        let owner = HanlinAppAgentSessionOwner()
        defer { owner.cancel() }
        let request = HanlinAppAgentSessionOwner.Request(conversation: row,
            conversationID: try #require(row.id), sceneID: UUID(), rowID: UUID(),
            uiRunID: UUID(), temporary: false, interaction: nil)
        let model = HanlinModelReference(provider: "TRANSPORT_FIXTURE", modelID: "fixture-model")
        let api = APIManager(context: context, agentSessionOwner: owner, providerCredentials: fixture.credentials)
        try api.bindDataAccess(request: request, model: model)
        let admission = try api.makeProviderRequestAdmission(model: model, configuration: provider, credential: "synthetic-direct")
        let gate = AppHistoryWriteGate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderCredentialURLProtocol.self]
        let engine = HanlinChatEngine(sessionConfiguration: configuration)
        let config = HanlinChatModelConfiguration(modelID: model.modelID, company: model.provider,
            apiType: "OpenAI", endpoint: endpoint, apiKey: "synthetic-direct")
        let transportRequest = try HanlinChatRequestBuilder.buildRequest(
            formattedMessages: [["role": "user", "content": "Synthetic direct private prompt"]], configuration: config)
        #expect(transportRequest.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-direct")
        let stream = await engine.stream(request: transportRequest, configuration: config,
            requestAdmission: { request in await gate.pause(); try await admission(request) })
        let work = Task { for try await _ in stream {} }
        defer { work.cancel(); gate.release() }
        await gate.waitUntilPaused()
        owner.revoke()
        gate.release()
        do { try await work.value; Issue.record("The detached direct producer bypassed owner revocation") }
        catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(ProviderCredentialURLProtocol.snapshot(host: host).isEmpty)
    }

    @Test func originalReusedSDKEngineUsesEachTurnsManagerAndTransport() async throws {
        let fixture = try ProviderCredentialTestFixture()
        defer { fixture.removeOwnedFixture() }
        let container = try fixture.open(), context = container.mainContext
        let host = "reused-admission-\(UUID().uuidString.lowercased()).invalid"
        ProviderCredentialURLProtocol.register(host: host, streaming: true)
        defer { ProviderCredentialURLProtocol.remove(host: host) }
        let endpoint = try #require(URL(string: "https://\(host)/v1/chat/completions"))
        let row = ChatRecords(name: "Original reused conversation", type: "chat")
        let provider = APIKeys(name: "Original reused provider", company: "TRANSPORT_FIXTURE",
            key: "synthetic-reused", requestURL: endpoint.absoluteString)
        context.insert(row); context.insert(provider); try context.save()
        let owner = HanlinAppAgentSessionOwner()
        defer { owner.cancel() }
        let conversationID = try #require(row.id), sceneID = UUID()
        let model = HanlinModelReference(provider: "TRANSPORT_FIXTURE", modelID: "fixture-model")
        let config = HanlinChatModelConfiguration(modelID: model.modelID, company: model.provider,
            apiType: "OpenAI", endpoint: endpoint, apiKey: "synthetic-reused")
        let network = URLSessionConfiguration.ephemeral
        network.protocolClasses = [ProviderCredentialURLProtocol.self]
        let engine = HanlinChatEngine(sessionConfiguration: network)
        let diagnostics = ProviderTransportDiagnostics()
        var engineCreations = 0
        var priorAdmission: HanlinChatRequestAdmission?
        var priorManager: APIManager?
        var firstIdentity: HanlinHostSession?

        for turn in 1...2 {
            let request = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: conversationID,
                sceneID: sceneID, rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
            let api = APIManager(context: context, agentSessionOwner: owner, providerCredentials: fixture.credentials)
            let access = try api.bindDataAccess(request: request, model: model)
            if let priorAdmission {
                let previousManager = try #require(priorManager)
                do {
                    try await priorAdmission(URLRequest(url: endpoint))
                    Issue.record("A previous APIManager borrowed the new turn's lease")
                } catch { #expect(error as? HanlinHostError == .staleContext) }
                #expect(previousManager.agentSessionOwner === owner,
                    "The old manager is still alive; its obsolete epoch, not deallocation, denies this request")
                #expect(ProviderCredentialURLProtocol.snapshot(host: host).count == 1)
            }
            let admission = try api.makeProviderRequestAdmission(model: model, configuration: provider, credential: "synthetic-reused")
            let fetch = await engine.makeAISDKFetch(
                onRequest: { _ in await diagnostics.requested(turn) },
                onResponse: { _, _ in await diagnostics.responded(turn) },
                requestAdmission: admission)
            let stream = try await owner.stream(request: request, modelContext: context, configuration: config,
                engineFactory: {
                    engineCreations += 1
                    return try HanlinAISDKAgentEngine(configuration: config)
                }, toolAdapter: nil, messages: [.init(role: .user, text: "Original turn \(turn)")],
                systemPrompt: nil, dataAccess: access, transport: .init(fetch: fetch))
            var visible = ""
            for try await event in stream {
                try owner.receive(event, uiRunID: request.uiRunID)
                if case .textDelta(let text) = event.event { visible += text }
            }
            try owner.producerStreamDrained(uiRunID: request.uiRunID)
            #expect(visible == "Current transport response")
            if let firstIdentity { #expect(owner.session?.identity == firstIdentity) }
            else { firstIdentity = owner.session?.identity }
            priorManager = api
            priorAdmission = admission
        }
        #expect(engineCreations == 1)
        #expect(diagnostics.requests == [1, 2] && diagnostics.responses == [1, 2])
        let requests = ProviderCredentialURLProtocol.snapshot(host: host)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-reused" })
        weak var releasedManager = priorManager
        priorManager = nil
        #expect(releasedManager == nil, "The retained engine does not own a completed turn's APIManager")
        #expect(row.agentSDKRecordData != nil)
    }

    @Test func originalInjectedProviderCannotBeReplacedByTurnTransport() async throws {
        let host = "injected-admission-\(UUID().uuidString.lowercased()).invalid"
        ProviderCredentialURLProtocol.register(host: host, streaming: true)
        defer { ProviderCredentialURLProtocol.remove(host: host) }
        let endpoint = try #require(URL(string: "https://\(host)/v1/chat/completions"))
        let config = HanlinChatModelConfiguration(modelID: "fixture-model", company: "TRANSPORT_FIXTURE",
            apiType: "OpenAI", endpoint: endpoint, apiKey: "synthetic-injected")
        let network = URLSessionConfiguration.ephemeral
        network.protocolClasses = [ProviderCredentialURLProtocol.self]
        let fetch = HanlinAISDKProviderFactory.makeFetch(sessionConfiguration: network)
        let engine = HanlinAISDKAgentEngine(configuration: config,
            model: .v3(AppPartModel(queue: AppPartQueue([]))))
        do {
            _ = try await engine.stream(messages: [.init(role: .user, text: "Original injected model")],
                baseSystemPrompt: nil, tools: [], transport: .init(fetch: fetch),
                prepareStep: { .init(activeToolAliases: []) })
            Issue.record("Per-turn options replaced the original injected provider")
        } catch {
            guard let sdkError = error as? HanlinAISDKError, case .invalidConversation = sdkError else {
                Issue.record("Unexpected rejection type for an injected transport override"); return
            }
        }
        #expect(ProviderCredentialURLProtocol.snapshot(host: host).isEmpty)
    }

    @Test func originalCredentialPortRejectsForeignModelNamespaceRequestAndDeletedOrigin() async throws {
        let container = try dataDatabase(), context = container.mainContext
        let row = ChatRecords(name: "Original data request", type: "chat")
        let provider = APIKeys(name: "Original provider", company: "DATA_PORT_FIXTURE",
            key: "synthetic-test-credential", requestURL: "https://example.invalid")
        context.insert(row); context.insert(provider); try context.save()
        let id = try #require(row.id), owner = HanlinAppAgentSessionOwner()
        let request = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: UUID(),
            rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let model = HanlinModelReference(provider: "DATA_PORT_FIXTURE", modelID: "selected-original")
        let api = APIManager(context: context, agentSessionOwner: owner)
        try api.bindDataAccess(request: request, model: model)
        let credentials: any HanlinCredentialResolver = api
        let namespace = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library",
            workspace: "swiftdata", space: id.uuidString)
        #expect(try await credentials.credential(for: model, namespace: namespace) == "synthetic-test-credential")
        let foreign = try HanlinConversationNamespace(app: "hanlin", account: "foreign-account",
            workspace: "swiftdata", space: id.uuidString)
        for (requestedModel, requestedNamespace) in [
            (HanlinModelReference(provider: "OTHER", modelID: model.modelID), namespace),
            (HanlinModelReference(provider: model.provider, modelID: "other-model"), namespace),
            (model, foreign)
        ] {
            do {
                _ = try await credentials.credential(for: requestedModel, namespace: requestedNamespace)
                Issue.record("A foreign credential request escaped the original scope")
            } catch { #expect(error as? HanlinHostError == .staleContext) }
        }

        let access = try owner.prepareDataAccess(request: request, modelContext: context)
        let foreignRequest = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id,
            sceneID: request.sceneID, rowID: request.rowID, uiRunID: UUID(), temporary: false, interaction: nil)
        #expect(throws: HanlinHostError.staleContext) {
            try owner.requireDataAccess(access, request: foreignRequest, modelContext: context)
        }
        // Rebinding makes the previous API lease stale even for the same conversation/model.
        do { _ = try await credentials.credential(for: model, namespace: namespace); Issue.record("An older request epoch survived") }
        catch { #expect(error as? HanlinHostError == .staleContext) }
        try api.bindDataAccess(request: request, model: model)
        context.delete(row); try context.save()
        do { _ = try await credentials.credential(for: model, namespace: namespace); Issue.record("Deleted origin returned a credential") }
        catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(provider.key == "synthetic-test-credential")
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
    }

    @Test func originalMemoryPortRechecksOptInsAndCannotReplaceOriginlessRows() async throws {
        let container = try dataDatabase(), context = container.mainContext
        let row = ChatRecords(name: "Original memory request", type: "chat"), flags = UserInfo()
        let older = MemoryArchive(content: "RecallToken older", timestamp: .init(timeIntervalSince1970: 10))
        let newer = MemoryArchive(content: "RecallToken newer", timestamp: .init(timeIntervalSince1970: 20))
        context.insert(row); context.insert(flags); context.insert(older); context.insert(newer); try context.save()
        let id = try #require(row.id), owner = HanlinAppAgentSessionOwner()
        let request = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id,
            sceneID: UUID(), rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let api = APIManager(context: context, agentSessionOwner: owner)
        try api.bindDataAccess(request: request, model: .init(provider: "fixture", modelID: "fixture"))
        let memories: any HanlinMemoryStore = api
        let namespace = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library",
            workspace: "swiftdata", space: id.uuidString)
        #expect(try await memories.read(namespace: namespace) == ["RecallToken newer", "RecallToken older"])
        #expect(await api.retrieveMemory(keyword: "RecallToken") == "RecallToken newer\n\nRecallToken older")
        let originalIDs = Set(try context.fetch(FetchDescriptor<MemoryArchive>()).map(\.id))

        flags.useCrossMemory = false
        do { _ = try await memories.read(namespace: namespace); Issue.record("Global recall ignored cross-memory opt-out") }
        catch { #expect(error as? HanlinHostError == .denied) }
        #expect(await api.retrieveMemory(keyword: "RecallToken") == "")
        _ = api.updateMemory(originalContent: "RecallToken older", updatedContent: "Must not change")
        #expect(older.content == "RecallToken older")
        flags.useCrossMemory = true; flags.useMemory = false
        do { _ = try await memories.read(namespace: namespace); Issue.record("Global recall ignored memory opt-out") }
        catch { #expect(error as? HanlinHostError == .denied) }
        #expect(await api.retrieveMemory(keyword: "RecallToken") == "")
        #expect(api.saveMemory(content: "Must not persist") == false)
        let deniedTool = await api.executeLegacyTool(name: "save_memory",
            argumentsJSON: #"{"content":"Must not persist through the original tool"}"#,
            context: .init(localeIdentifier: "en", chatID: id.uuidString, requestID: request.uiRunID.uuidString),
            continuation: nil)
        #expect(deniedTool.outcome == .rejectedByCapability)

        flags.useMemory = true
        do { try await memories.replace(["Must not replace"], namespace: namespace); Issue.record("Originless rows were replaced") }
        catch { #expect(error as? APIManager.DataPortError == .legacyMemoryReplacementUnsupported) }
        #expect(Set(try context.fetch(FetchDescriptor<MemoryArchive>()).map(\.id)) == originalIDs)
        #expect(older.content == "RecallToken older" && newer.content == "RecallToken newer")
        #expect(api.saveMemory(content: "Explicit original append"))
        #expect(try context.fetch(FetchDescriptor<MemoryArchive>()).count == 3)
        owner.revoke()
        do { _ = try await memories.read(namespace: namespace); Issue.record("Revoked owner returned memory") }
        catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(api.saveMemory(content: "Revoked write") == false)
        #expect(try context.fetch(FetchDescriptor<MemoryArchive>()).count == 3)
    }

    @Test func originalDataEpochSurvivesEngineReplacementAndIsRevokedDuringPreparation() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Original preparation", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id), owner = HanlinAppAgentSessionOwner(), recorder = AppPresentationRecorder()
        owner.presentation = recorder
        let first = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: UUID(),
            rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let access = try owner.prepareDataAccess(request: first, modelContext: context)
        let queue = AppPartQueue([try .init(messageID: first.rowID, partID: UUID(), sequence: 0, payload: .textDelta("Original"))])
        let config = configuration()
        let stream = try await owner.stream(request: first, modelContext: context, configuration: config,
            engineFactory: { factory(config, queue: queue) }, toolAdapter: nil,
            messages: [.init(role: .user, text: "Original")], systemPrompt: nil, dataAccess: access)
        for try await event in stream { try owner.receive(event, uiRunID: first.uiRunID) }
        try owner.producerStreamDrained(uiRunID: first.uiRunID)
        try owner.requireDataAccess(access, request: first, modelContext: context)
        let committed = row.agentSDKRecordData

        let next = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: first.sceneID,
            rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let nextAccess = try owner.prepareDataAccess(request: next, modelContext: context)
        let changedConfig = HanlinChatModelConfiguration(modelID: "replacement", endpoint: URL(filePath: "/fixture"), apiKey: "")
        do {
            _ = try await owner.stream(request: next, modelContext: context, configuration: changedConfig,
                engineFactory: {
                    owner.cancel() // The actual synchronous source revocation occurs while the factory can suspend.
                    await Task.yield()
                    return factory(changedConfig, queue: queue)
                }, toolAdapter: nil, messages: [.init(role: .user, text: "Cancelled")],
                systemPrompt: nil, dataAccess: nextAccess)
            Issue.record("Cancellation during preparation admitted a new Session")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(throws: HanlinHostError.staleContext) {
            try owner.requireDataAccess(nextAccess, request: next, modelContext: context)
        }
        #expect(owner.session == nil && row.agentSDKRecordData == committed)
    }

    @Test func deletingConversationDuringOriginalEnginePreparationCannotAdmitLateSession() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Original suspended preparation", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id), owner = HanlinAppAgentSessionOwner()
        let recorder = AppPresentationRecorder(), gate = AppHistoryWriteGate()
        owner.presentation = recorder
        let request = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id,
            sceneID: UUID(), rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let config = configuration()
        let queue = AppPartQueue([try .init(messageID: request.rowID, partID: UUID(), sequence: 0,
            payload: .textDelta("Late preparation must not install"))])
        let pending = Task { @MainActor in
            try await owner.stream(request: request, modelContext: context, configuration: config,
                engineFactory: {
                    await gate.pause()
                    return factory(config, queue: queue)
                }, toolAdapter: nil, messages: [.init(role: .user, text: "Original")], systemPrompt: nil)
        }
        await gate.waitUntilPaused()
        do { try HanlinConversationMutation.delete(row, in: context) }
        catch { gate.release(); _ = try? await pending.value; throw error }
        gate.release()
        do {
            _ = try await pending.value
            Issue.record("A deleted original conversation admitted delayed engine preparation")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(owner.session == nil && recorder.installed.isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChatMessages>()).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func stoppingInlineToolReleasesOnlyItsLeaseBeforeNonCooperativeExecutorDrains() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Original inline Stop", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id), owner = HanlinAppAgentSessionOwner()
        let request = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id,
            sceneID: UUID(), rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let alias = "fixture_inline_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let gate = AppHistoryWriteGate()
        let (phases, phaseWriter) = AsyncStream<Bool>.makeStream()
        let schema = NativeToolSchema.function(name: alias, description: "Synthetic paused original executor",
            parameters: ["type": "object", "properties": [:], "additionalProperties": false])
        let source = HanlinCanonicalToolAuthority.NativeSource(
            entry: .init(name: alias, title: alias, summary: "Synthetic lifecycle fixture",
                presentationProfile: .generic(toolName: alias)),
            canonicalSchema: schema, modelSchema: schema, preferredAlias: alias)
        let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [source], mcpTools: [])
        let executors = AssistantToolBridge.Executors(executeNative: { _, _, _, _ in
            phaseWriter.yield(true)
            // Deliberately ignores cancellation until this original executor is released.
            await gate.pause()
            return NativeToolResult(modelText: "Synthetic original executor drained", outcome: .succeeded)
        }, executeScripting: { _, _ in
            NativeToolResult(modelText: "Unexpected scripting", outcome: .failed)
        })
        let adapter = HanlinAISDKToolAdapter(session: .init(chatID: id.uuidString, isTemporaryChat: false),
            preparedTools: .init(authority: authority, executors: executors), currentRoundID: UUID())
        let config = configuration()
        let queue = AppPartQueue([try .init(messageID: request.rowID, partID: UUID(), sequence: 0,
            payload: .textDelta("Original inline source"))])
        let stream = try await owner.stream(request: request, modelContext: context, configuration: config,
            engineFactory: { factory(config, queue: queue) }, toolAdapter: adapter,
            messages: [.init(role: .user, text: "Original")], systemPrompt: nil)
        for try await event in stream { try owner.receive(event, uiRunID: request.uiRunID) }
        try owner.producerStreamDrained(uiRunID: request.uiRunID)
        var observedEvents = 0
        let pending = Task { @MainActor in
            defer { phaseWriter.yield(false); phaseWriter.finish() }
            return try await owner.executeInlineTool(rowID: request.rowID, partID: "synthetic-query",
                alias: alias, arguments: .object([:])) { event in
                observedEvents += 1
                if case .toolApprovalChanged(let approval) = event,
                   approval.disposition == .awaiting {
                    Task { @MainActor in
                        guard let pending = owner.consent.pending, pending.tool == alias else { return }
                        owner.consent.answer(id: pending.id, allowed: true)
                    }
                }
            }
        }
        defer {
            gate.release()
            pending.cancel()
            owner.cancel()
            for grant in HanlinToolApprovalStore.shared.grants
                where grant.scope.toolID == alias || grant.toolTitle == alias {
                _ = HanlinToolApprovalStore.shared.revoke(id: grant.id)
            }
        }
        var iterator = phases.makeAsyncIterator()
        let entered = try #require(await iterator.next())
        guard entered else {
            _ = try? await pending.value
            Issue.record("The original inline fixture did not enter its native executor")
            return
        }
        await gate.waitUntilPaused()
        #expect(owner.inlineToolIsRunning)
        owner.cancel()
        #expect(!owner.inlineToolIsRunning && owner.session == nil)
        let countAfterStop = observedEvents
        // This must succeed while the old non-cooperative executor is still paused.
        let nextLease = try HanlinConversationRunLease.acquire(container: container, conversationID: id)
        defer { nextLease.release() }
        gate.release()
        do {
            _ = try await pending.value
            Issue.record("The cancelled original inline operation reported live completion")
        } catch {}
        #expect(observedEvents == countAfterStop)
        #expect(!nextLease.isRevoked)
        #expect(throws: HanlinHostError.duplicateInvocation) {
            try HanlinConversationRunLease.acquire(container: container, conversationID: id)
        }
    }

    @Test func originalTypedAttachmentStorePreservesBytesAndRejectsForeignSessionMetadataAndTurn() async throws {
        let registry = AuthorizedAttachmentRegistry(), attachments: any HanlinAttachmentStore = registry
        let image = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let id = UUID(), namespace = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library",
            workspace: "swiftdata", space: id.uuidString)
        let session = HanlinHostSession(conversationID: id, context: .init(namespace: namespace, sceneID: UUID(), generation: UUID()))
        let reference = try await attachments.importData(image, mediaType: "image/png", session: session)
        #expect(try await attachments.read(reference, session: session) == image)
        let otherSession = HanlinHostSession(conversationID: id, context: session.context)
        let foreignNamespace = try HanlinConversationNamespace(app: "hanlin", account: "foreign", workspace: "swiftdata", space: id.uuidString)
        let alteredReferences = [
            HanlinAttachmentReference(handle: reference.handle, namespace: foreignNamespace, mediaType: reference.mediaType, byteCount: reference.byteCount),
            HanlinAttachmentReference(handle: reference.handle, namespace: namespace, mediaType: "image/jpeg", byteCount: reference.byteCount),
            HanlinAttachmentReference(handle: reference.handle, namespace: namespace, mediaType: reference.mediaType, byteCount: reference.byteCount + 1)
        ]
        for changed in alteredReferences {
            do { _ = try await attachments.read(changed, session: session); Issue.record("Forged attachment metadata read native bytes") }
            catch { #expect(error as? HanlinHostError == .staleContext) }
        }
        do { _ = try await attachments.read(reference, session: otherSession); Issue.record("Another native Session read the attachment") }
        catch { #expect(error as? HanlinHostError == .staleContext) }

        let requestID = UUID().uuidString
        let originalHandle = try await registry.register(data: image, mimeType: "image/png", chatID: id.uuidString, requestID: requestID)
        do {
            _ = try await registry.reference(forLegacyHandle: originalHandle, session: session, requestID: UUID().uuidString)
            Issue.record("A diagnostics/foreign turn adopted the original attachment")
        } catch {}
        let adopted = try await registry.reference(forLegacyHandle: originalHandle, session: session, requestID: requestID)
        #expect(try await attachments.read(adopted, session: session) == image)
        do {
            _ = try await registry.resolve(handle: originalHandle, chatID: id.uuidString, requestID: requestID)
            Issue.record("The legacy unbound path bypassed a HostSession binding")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
        try await attachments.remove(adopted, session: session)
        do { _ = try await attachments.read(adopted, session: session); Issue.record("Removed original bytes remained readable") }
        catch {}
        #expect(try await attachments.read(reference, session: session) == image)
    }

    @Test func actualSDKAdapterUsesOriginalAttachmentTurnAcrossDiagnosticsRoundsAndRevocation() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Original attachment owner", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id), owner = HanlinAppAgentSessionOwner(), recorder = AppPresentationRecorder()
        owner.presentation = recorder
        let request = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id, sceneID: UUID(),
            rowID: UUID(), uiRunID: UUID(), temporary: false, interaction: nil)
        let image = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let handle = try await AuthorizedAttachmentRegistry.shared.register(data: image, mimeType: "image/png",
            chatID: id.uuidString, requestID: request.uiRunID.uuidString)
        let alias = "fixture_original_attachment", diagnosticRound = UUID()
        #expect(diagnosticRound != request.uiRunID)
        let schema = NativeToolSchema.function(name: alias, description: "Read an original authorized image", parameters: [
            "type": "object", "properties": ["handle": ["type": "string"]], "required": ["handle"]])
        let source = HanlinCanonicalToolAuthority.NativeSource(
            entry: .init(name: alias, title: "Original image", summary: "Original image", presentationProfile: .generic(toolName: alias)),
            canonicalSchema: schema, modelSchema: schema, preferredAlias: alias)
        let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [source], mcpTools: [])
        var reads = [Data]()
        var observedRequestIDs = [String]()
        let executors = AssistantToolBridge.Executors(executeNative: { _, _, arguments, toolContext in
            observedRequestIDs.append(toolContext.requestID ?? "")
            #expect(toolContext.requestID != request.uiRunID.uuidString)
            #expect(toolContext.requestID != diagnosticRound.uuidString)
            do {
                let object = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: String]
                let requestedHandle = try #require(object?["handle"])
                let bytes = try await toolContext.resolveAttachment(handle: requestedHandle)
                reads.append(bytes)
                return NativeToolResult(modelText: "Original image resolved", outcome: .succeeded)
            } catch { return NativeToolResult(modelText: "Attachment authority unavailable", outcome: .failed) }
        }, executeScripting: { _, _ in NativeToolResult(modelText: "Unexpected scripting", outcome: .failed) })
        let adapter = HanlinAISDKToolAdapter(session: .init(chatID: id.uuidString, isTemporaryChat: false),
            preparedTools: .init(authority: authority, executors: executors), currentRoundID: diagnosticRound)
        let config = configuration()
        let queue = AppPartQueue([try .init(messageID: request.rowID, partID: UUID(), sequence: 0, payload: .textDelta("Original"))])
        let stream = try await owner.stream(request: request, modelContext: context, configuration: config,
            engineFactory: { factory(config, queue: queue) }, toolAdapter: adapter,
            messages: [.init(role: .user, text: "Read original image")], systemPrompt: nil)
        // `HanlinAISDKAgentEngine.stream` prepares step 0 asynchronously in its producer task and
        // yields `.stepStarted(index: 0, _)` strictly after `adapter.prepareStep(stepNumber: 0)`
        // assigns the step-0 diagnostics round UUID. Synchronize on that lifecycle event rather
        // than reading `adapter.currentRoundID` immediately after `owner.stream(...)` returns.
        var iterator = stream.makeAsyncIterator()
        var startedInitialStep = false
        while let event = try await iterator.next() {
            try owner.receive(event, uiRunID: request.uiRunID)
            if case .stepStarted(let index, _) = event.event, index == 0 {
                startedInitialStep = true
                break
            }
        }
        #expect(startedInitialStep)
        let firstRoundID = try #require(adapter.currentRoundID)
        #expect(firstRoundID != diagnosticRound)
        #expect(firstRoundID != request.uiRunID)
        let definition = try #require(adapter.allToolDefinitions().first { $0.name == alias })
        let arguments = String(decoding: try JSONSerialization.data(withJSONObject: ["handle": handle]), as: UTF8.self)
        let output = try await definition.execute(arguments, "original-attachment")
        #expect(!output.isError && reads == [image])
        #expect(observedRequestIDs == [firstRoundID.uuidString])
        _ = await adapter.prepareStep(stepNumber: 1)
        let secondRoundID = try #require(adapter.currentRoundID)
        #expect(secondRoundID != firstRoundID)
        #expect(secondRoundID != diagnosticRound)
        #expect(secondRoundID != request.uiRunID)
        // The producer has already prepared step 1 while the consumer is still
        // draining step 0. Resolve the original receipt, not the mutable current ID.
        #expect(adapter.takePreparedRoundID(forStep: 0) == firstRoundID)
        #expect(adapter.takePreparedRoundID(forStep: 0) == nil)
        #expect(adapter.takePreparedRoundID(forStep: 1) == secondRoundID)
        adapter.finishPreparedRound(forStep: 0, roundID: firstRoundID)
        #expect(adapter.currentRoundID == secondRoundID)
        adapter.finishPreparedRound(forStep: 1, roundID: firstRoundID)
        #expect(adapter.currentRoundID == secondRoundID, "A mismatched completion has no authority")
        let secondRoundOutput = try await definition.execute(arguments, "second-round-attachment")
        #expect(!secondRoundOutput.isError && reads == [image, image])
        #expect(observedRequestIDs == [firstRoundID.uuidString, secondRoundID.uuidString])
        let otherTurnHandle = try await AuthorizedAttachmentRegistry.shared.register(data: image, mimeType: "image/png",
            chatID: id.uuidString, requestID: UUID().uuidString)
        let otherTurnArguments = String(decoding: try JSONSerialization.data(withJSONObject: ["handle": otherTurnHandle]), as: UTF8.self)
        let otherTurnOutput = try await definition.execute(otherTurnArguments, "other-turn-attachment")
        #expect(otherTurnOutput.isError && reads == [image, image])
        while let event = try await iterator.next() { try owner.receive(event, uiRunID: request.uiRunID) }
        try owner.producerStreamDrained(uiRunID: request.uiRunID)
        owner.cancel()
        let revoked = try await definition.execute(arguments, "revoked-attachment")
        #expect(revoked.isError && reads == [image, image])
        #expect(observedRequestIDs == [
            firstRoundID.uuidString,
            secondRoundID.uuidString,
            secondRoundID.uuidString,
            secondRoundID.uuidString
        ])
        adapter.finishPreparedRound(forStep: 1, roundID: secondRoundID)
        #expect(adapter.currentRoundID == nil)
        #expect(adapter.takePreparedRoundID(forStep: 1) == nil)
        await AuthorizedAttachmentRegistry.shared.revoke(handle: otherTurnHandle)
        await AuthorizedAttachmentRegistry.shared.revoke(handle: handle)
    }

    @Test func existingSwiftDataRowPreservesLegacyFieldsAndRejectsConflictForeignScopeAndDeletion() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Original title", type: "chat", input: "Unsent draft")
        context.insert(row); try context.save()
        let id = try #require(row.id)
        let ns = try HanlinConversationNamespace(app: "hanlin", account: "a", workspace: "w", space: id.uuidString)
        let store = HanlinAppConversationStore(context: context, conversation: row, namespace: ns, conversationID: id, temporary: false)
        let original = HanlinConversationRecord(namespace: ns, conversationID: id, revision: 0, draft: "SDK draft",
            entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .text("Canonical history"))])
        try await store.save(original, replacing: nil)
        #expect(try await store.load(id, namespace: ns) == original)
        #expect(row.name == "Original title" && row.input == "Unsent draft")
        let preserved = row.agentSDKRecordData
        do { try await store.save(original, replacing: nil); Issue.record("Duplicate create bypassed CAS") }
        catch { #expect(error as? HanlinHostError == .storeConflict) }
        let foreign = try HanlinConversationNamespace(app: "hanlin", account: "foreign", workspace: "w", space: id.uuidString)
        do { _ = try await store.load(id, namespace: foreign); Issue.record("Foreign namespace loaded original bytes") }
        catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(row.agentSDKRecordData == preserved)
        context.delete(row); try context.save()
        do { _ = try await store.load(id, namespace: ns); Issue.record("Deleted conversation was recreated") }
        catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
    }


    @Test func clearHistoryCommitsCanonicalBarrierAndVisibleReplacementToOriginalDiskStore() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "hanlin-clear-history-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "OriginalChat.store"), id = UUID(), messageID = UUID()
        let namespace = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library",
            workspace: "swiftdata", space: id.uuidString)
        let oldText = "History to remove שלום e\u{301}"
        let marker = "History cleared"
        let canvas = CanvasData(title: "Independent canvas", content: "Retained document", type: "text")

        @MainActor func database() throws -> ModelContainer {
            try ModelContainer(for: ChatRecords.self, ChatSavedExcerpt.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        }
        @MainActor func clearOriginalStore() async throws {
            let container = try database(), context = container.mainContext
            let row = ChatRecords(id: id, name: "Retained title", type: "chat",
                description: oldText, input: "Retained unsent draft", canvas: canvas)
            let oldMessage = ChatMessages(id: messageID, role: "assistant", text: oldText, record: row)
            context.insert(row); context.insert(oldMessage); try context.save()
            try ChatSavedExcerpt.save(source: .init(chatRecordID: id, messageID: messageID, groupID: nil,
                runID: nil, title: "Independent bookmark"), markdown: oldText, quote: oldText, in: context)
            let store = HanlinAppConversationStore(context: context, conversation: row,
                namespace: namespace, conversationID: id, temporary: false)
            try await store.save(.init(namespace: namespace, conversationID: id, revision: 0,
                model: .init(provider: "original-provider", modelID: "original-model"), draft: "Old canonical draft",
                entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .text(oldText))]), replacing: nil)
            let owner = HanlinAppAgentSessionOwner()
            let request = HanlinAppAgentSessionOwner.Request(conversation: row, conversationID: id,
                sceneID: UUID(), rowID: messageID, uiRunID: UUID(), temporary: false, interaction: nil)
            let access = try owner.prepareDataAccess(request: request, modelContext: context)
            let unrelated = ChatRecords(name: "Unrelated pending edit", type: "chat", input: "Keep this pending draft")
            context.insert(unrelated) // The clear checkpoint must preserve an unrelated pending insert.
            let replacement = try owner.clearHistory(conversation: row, conversationID: id,
                modelContext: context, temporary: false, replacementText: marker)
            #expect(replacement.text == marker && replacement.record === row)
            #expect(owner.session == nil && owner.bindings.isEmpty)
            #expect(throws: HanlinHostError.staleContext) {
                try owner.requireDataAccess(access, request: request, modelContext: context)
            }
            let cleared = try #require(await store.load(id, namespace: namespace))
            #expect(cleared.revision == 1 && cleared.entries.isEmpty && cleared.model == nil && cleared.draft.isEmpty)
        }
        try await clearOriginalStore()
        #expect(FileManager.default.fileExists(atPath: url.path))
        let reopened = try database(), context = reopened.mainContext
        let rows = try context.fetch(FetchDescriptor<ChatRecords>())
        let row = try #require(rows.first(where: { $0.id == id }))
        #expect(rows.count == 2 && rows.contains { $0.input == "Keep this pending draft" })
        #expect(row.name == "Retained title" && row.input == "Retained unsent draft" && row.canvas == canvas)
        #expect(row.infoDescription == marker)
        let messages = try context.fetch(FetchDescriptor<ChatMessages>())
        #expect(messages.count == 1 && messages[0].text == marker && messages[0].record?.id == id)
        #expect(!messages.contains { $0.id == messageID })
        let bookmarks = try context.fetch(FetchDescriptor<ChatSavedExcerpt>())
        #expect(bookmarks.count == 1 && bookmarks[0].quote == oldText)
        let store = HanlinAppConversationStore(context: context, conversation: row,
            namespace: namespace, conversationID: id, temporary: false)
        let cleared = try #require(await store.load(id, namespace: namespace))
        #expect(cleared.revision == 1 && cleared.entries.isEmpty && cleared.model == nil && cleared.draft.isEmpty)
        #expect(!String(decoding: try #require(row.agentSDKRecordData), as: UTF8.self).contains("History to remove"))
    }

    @Test(arguments: [false, true])
    func clearHistoryRejectsAlreadySuspendedOriginalStoreWriter(hadCanonicalRecord: Bool) async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Original row", type: "chat"), id = try #require(row.id)
        context.insert(row); try context.save()
        let namespace = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library",
            workspace: "swiftdata", space: id.uuidString)
        let store = HanlinAppConversationStore(context: context, conversation: row,
            namespace: namespace, conversationID: id, temporary: false)
        if hadCanonicalRecord {
            try await store.save(.init(namespace: namespace, conversationID: id, revision: 0,
                entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .text("Earlier history"))]), replacing: nil)
        }
        let gate = AppHistoryWriteGate()
        defer { gate.release() }
        let writer = Task { @MainActor in
            let observed = try await store.load(id, namespace: namespace)
            #expect((observed != nil) == hadCanonicalRecord)
            let stale = HanlinConversationRecord(namespace: namespace, conversationID: id,
                revision: observed.map { $0.revision + 1 } ?? 0,
                entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .text("Must not resurrect"))])
            await gate.pause() // Actual suspension after capturing the original expected revision.
            do {
                try await store.save(stale, replacing: observed?.revision)
                return false
            } catch {
                #expect(error as? HanlinHostError == .storeConflict)
                return true
            }
        }
        await gate.waitUntilPaused()
        let owner = HanlinAppAgentSessionOwner()
        _ = try owner.clearHistory(conversation: row, conversationID: id,
            modelContext: context, temporary: false, replacementText: "History cleared")
        let barrier = try #require(await store.load(id, namespace: namespace))
        #expect(barrier.revision == (hadCanonicalRecord ? 1 : 0) && barrier.entries.isEmpty)
        gate.release()
        #expect(try await writer.value)
        #expect(try await store.load(id, namespace: namespace) == barrier)
        // The barrier also admits a genuinely new writer that read the new revision.
        let next = HanlinConversationRecord(namespace: namespace, conversationID: id, revision: barrier.revision + 1,
            entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .text("New user turn"))])
        try await store.save(next, replacing: barrier.revision)
        #expect(try await store.load(id, namespace: namespace) == next)
    }

    @Test func clearHistorySaveFailureRestoresOriginalDiskContentWithoutSuccessMarker() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "hanlin-clear-readonly-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "OriginalChat.store"), id = UUID(), messageID = UUID()
        let namespace = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library",
            workspace: "swiftdata", space: id.uuidString)
        let original = HanlinConversationRecord(namespace: namespace, conversationID: id, revision: 0,
            entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .text("Original canonical content"))])
        @MainActor func database(allowsSave: Bool) throws -> ModelContainer {
            try ModelContainer(for: ChatRecords.self,
                configurations: ModelConfiguration(url: url, allowsSave: allowsSave, cloudKitDatabase: .none))
        }
        @MainActor func seed() async throws {
            let container = try database(allowsSave: true), context = container.mainContext
            let row = ChatRecords(id: id, name: "Original title", type: "chat", description: "Original preview")
            let message = ChatMessages(id: messageID, role: "user", text: "Original visible content", record: row)
            context.insert(row); context.insert(message); try context.save()
            let store = HanlinAppConversationStore(context: context, conversation: row,
                namespace: namespace, conversationID: id, temporary: false)
            try await store.save(original, replacing: nil)
        }
        try await seed()
        @MainActor func rejectReadOnlyClear() async throws {
            let container = try database(allowsSave: false), context = container.mainContext
            context.autosaveEnabled = false
            let row = try #require(context.fetch(FetchDescriptor<ChatRecords>()).first)
            #expect(!context.hasChanges)
            let owner = HanlinAppAgentSessionOwner()
            do {
                _ = try owner.clearHistory(conversation: row, conversationID: id, modelContext: context,
                    temporary: false, replacementText: "Must not appear")
                Issue.record("A read-only original store reported a successful history deletion")
            } catch { #expect(!context.hasChanges, "Failed clear rolls back its own pending changes") }
            #expect(row.infoDescription == "Original preview")
            let store = HanlinAppConversationStore(context: context, conversation: row,
                namespace: namespace, conversationID: id, temporary: false)
            #expect(try await store.load(id, namespace: namespace) == original)
            let messages = try context.fetch(FetchDescriptor<ChatMessages>())
            #expect(messages.count == 1 && messages[0].id == messageID && messages[0].text == "Original visible content")
        }
        try await rejectReadOnlyClear()
        let reopened = try database(allowsSave: true), context = reopened.mainContext
        let row = try #require(context.fetch(FetchDescriptor<ChatRecords>()).first)
        let store = HanlinAppConversationStore(context: context, conversation: row,
            namespace: namespace, conversationID: id, temporary: false)
        #expect(try await store.load(id, namespace: namespace) == original)
        #expect(try context.fetch(FetchDescriptor<ChatMessages>()).map(\.id) == [messageID])
    }

    @Test func temporaryClearHistoryDropsOriginalSessionHistoryWithoutInsertingStoreRows() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Temporary original", type: "chat")
        let id = try #require(row.id), scene = UUID(), messageID = UUID(), uiRun = UUID()
        let part = try HanlinChatStructuredPart(messageID: messageID, partID: UUID(), sequence: 0,
            payload: .textDelta("Temporary content to clear"))
        let owner = HanlinAppAgentSessionOwner(), recorder = AppPresentationRecorder(), queue = AppPartQueue([part])
        owner.presentation = recorder
        let config = configuration()
        let stream = try await owner.stream(request: .init(conversation: row, conversationID: id, sceneID: scene,
            rowID: messageID, uiRunID: uiRun, temporary: true, interaction: nil), modelContext: context,
            configuration: config, engineFactory: { factory(config, queue: queue) }, toolAdapter: nil,
            messages: [.init(role: .user, text: "Temporary original")], systemPrompt: nil)
        for try await event in stream { try owner.receive(event, uiRunID: uiRun) }
        try owner.producerStreamDrained(uiRunID: uiRun)
        #expect(!owner.bindings.isEmpty)
        let replacement = try owner.clearHistory(conversation: row, conversationID: id,
            modelContext: context, temporary: true, replacementText: "Temporary history cleared")
        #expect(replacement.text == "Temporary history cleared")
        #expect(row.agentSDKRecordData == nil && row.modelContext == nil)
        #expect(owner.session == nil && owner.bindings.isEmpty)
        let previousReplays = recorder.replayed.count
        try await owner.restoreHistory(conversation: row, conversationID: id, sceneID: scene,
            temporary: true, modelContext: context)
        #expect(owner.bindings.isEmpty && recorder.replayed.count == previousReplays)
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChatMessages>()).isEmpty)
    }

    @Test(arguments: [false, true])
    func clearHistoryPreservesUnrecognizedOrExhaustedCanonicalRecord(futureFormat: Bool) async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Original", type: "chat", description: "Original preview")
        let id = try #require(row.id)
        let message = ChatMessages(role: "user", text: "Original visible content", record: row)
        context.insert(row); context.insert(message)
        let namespace = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library",
            workspace: "swiftdata", space: id.uuidString)
        let original = HanlinConversationRecord(formatVersion: futureFormat ? HanlinConversationRecord.currentFormat + 1 : HanlinConversationRecord.currentFormat,
            namespace: namespace, conversationID: id, revision: futureFormat ? 0 : UInt64.max,
            entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .text("Original canonical content"))])
        let bytes = try JSONEncoder().encode(original)
        row.agentSDKRecordData = bytes; try context.save()
        let owner = HanlinAppAgentSessionOwner()
        do {
            _ = try owner.clearHistory(conversation: row, conversationID: id, modelContext: context,
                temporary: false, replacementText: "Must not appear")
            Issue.record("History clear erased metadata without an available canonical revision")
        } catch {
            #expect(error as? HanlinHostError == (futureFormat ? .unsupportedVersion : .storageLimitExceeded))
        }
        #expect(row.agentSDKRecordData == bytes && row.infoDescription == "Original preview")
        let messages = try context.fetch(FetchDescriptor<ChatMessages>())
        #expect(messages.count == 1 && messages[0].id == message.id)
    }

    @Test func diskBackedOriginalConversationReopensWithoutLosingLegacyOrCanonicalHistory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "hanlin-sdk05-durable-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "OriginalChat.store")
        let id = UUID()
        let namespace = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library",
            workspace: "swiftdata", space: id.uuidString)
        let runID = UUID(), timestamp = Date(timeIntervalSince1970: 1_000)
        let original = HanlinConversationRecord(namespace: namespace, conversationID: id, revision: 0,
            model: .init(provider: "original-provider", modelID: "original-model"),
            draft: "Canonical draft שלום",
            entries: [
                .init(runID: runID, step: 0, sequence: 0, timestamp: timestamp,
                      payload: .text("Canonical history שלום e\u{301}")),
                .init(runID: runID, step: 0, sequence: 1, timestamp: timestamp, payload: .cancelled)
            ])
        let legacyCanvas = CanvasData(title: "Original canvas", content: "Current canvas",
            type: "text", history: ["Earlier canvas", "Current canvas"], index: 1)
        let presentationBytes = Data("original-presentation-assignment".utf8)

        @MainActor func openDatabase() throws -> ModelContainer {
            try ModelContainer(for: ChatRecords.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        }
        @MainActor func seedOriginalStore() async throws -> Data {
            let container = try openDatabase(), context = container.mainContext
            let row = ChatRecords(id: id, name: "Original persistent title", type: "chat",
                lastEdited: timestamp, input: "Original unsent draft שלום", canvas: legacyCanvas)
            row.presentationAssignmentData = presentationBytes
            context.insert(row)
            try context.save()
            let store = HanlinAppConversationStore(context: context, conversation: row,
                namespace: namespace, conversationID: id, temporary: false)
            try await store.save(original, replacing: nil)
            return try #require(row.agentSDKRecordData)
        }
        let originalBytes = try await seedOriginalStore()
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0 > 0)

        @MainActor func reopenAndRejectFutureFormat() async throws {
            let container = try openDatabase(), context = container.mainContext
            let rows = try context.fetch(FetchDescriptor<ChatRecords>())
            #expect(rows.count == 1)
            let row = try #require(rows.first)
            #expect(row.id == id && row.name == "Original persistent title")
            #expect(row.input == "Original unsent draft שלום" && row.lastEdited == timestamp)
            #expect(row.canvas == legacyCanvas && row.presentationAssignmentData == presentationBytes)
            #expect(row.agentSDKRecordData == originalBytes)
            let store = HanlinAppConversationStore(context: context, conversation: row,
                namespace: namespace, conversationID: id, temporary: false)
            #expect(try await store.load(id, namespace: namespace) == original)
            let future = HanlinConversationRecord(formatVersion: HanlinConversationRecord.currentFormat + 1,
                namespace: namespace, conversationID: id, revision: 1, draft: "Must not replace",
                entries: original.entries)
            do {
                try await store.save(future, replacing: 0)
                Issue.record("Unknown future SDK format changed the original disk-backed conversation")
            } catch { #expect(error as? HanlinHostError == .unsupportedVersion) }
            #expect(row.agentSDKRecordData == originalBytes)
            try context.save()
        }
        try await reopenAndRejectFutureFormat()
        let finalContainer = try openDatabase(), finalContext = finalContainer.mainContext
        let finalRows = try finalContext.fetch(FetchDescriptor<ChatRecords>())
        #expect(finalRows.count == 1)
        let finalRow = try #require(finalRows.first)
        #expect(finalRow.agentSDKRecordData == originalBytes)
        #expect(finalRow.name == "Original persistent title" && finalRow.input == "Original unsent draft שלום")
        #expect(finalRow.canvas == legacyCanvas && finalRow.presentationAssignmentData == presentationBytes)
        let finalStore = HanlinAppConversationStore(context: finalContext, conversation: finalRow,
            namespace: namespace, conversationID: id, temporary: false)
        #expect(try await finalStore.load(id, namespace: namespace) == original)
    }

    @Test func originalStoreKeepsItsContainerAliveAcrossDeferredPersistenceAfterCreatorReturns() async throws {
        weak var originalStorage: ModelContainer?
        func makeStore() throws -> (HanlinAppConversationStore, ChatRecords, HanlinConversationRecord) {
            let container = try database(), context = container.mainContext
            originalStorage = container
            let row = ChatRecords(name: "Original deferred receipt", type: "chat", input: "Unsent original draft")
            context.insert(row); try context.save()
            let id = try #require(row.id)
            let namespace = try HanlinConversationNamespace(app: "hanlin", account: "lifetime",
                workspace: "original", space: id.uuidString)
            let store = HanlinAppConversationStore(context: context, conversation: row,
                namespace: namespace, conversationID: id, temporary: false)
            let record = HanlinConversationRecord(namespace: namespace, conversationID: id, revision: 0,
                entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .text("Deferred original receipt"))])
            return (store, row, record)
        }
        let (store, row, record) = try makeStore()
        // No creator-owned ModelContainer remains. Fail before a SwiftData fetch
        // if the asynchronous adapter has lost the actual storage owner.
        _ = try #require(originalStorage, "The original store must own its container while deferred writes remain")
        let persistence = Task { @MainActor in
            await Task.yield()
            try await store.save(record, replacing: nil)
        }
        try await persistence.value
        #expect(try await store.load(record.conversationID, namespace: record.namespace) == record)
        #expect(try store.requireOriginalConversation() === row)
        #expect(row.name == "Original deferred receipt" && row.input == "Unsent original draft")
        let context = try #require(originalStorage).mainContext
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).count == 1)
        context.delete(row); try context.save()
        do {
            _ = try await store.load(record.conversationID, namespace: record.namespace)
            Issue.record("Retaining storage must never recreate a deleted conversation")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
    }

    @Test func identicalContentAndPartIDsKeepExactRowRunBindingAndOriginalReplaySession() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "History", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id), scene = UUID(), partID = UUID()
        let rows = [UUID(), UUID(), UUID()], uiRuns = [UUID(), UUID(), UUID()]
        let parts = try rows.map { try HanlinChatStructuredPart(messageID: $0, partID: partID, sequence: 0, payload: .textDelta("Identical text")) }
        let queue = AppPartQueue(parts), owner = HanlinAppAgentSessionOwner(), recorder = AppPresentationRecorder()
        owner.presentation = recorder
        var constructions = 0
        var previous: HanlinAgentEvent?
        for index in 0..<2 {
            let config = configuration() // updatedAt deliberately differs; real engine inputs do not.
            let stream = try await owner.stream(request: .init(conversation: row, conversationID: id, sceneID: scene,
                rowID: rows[index], uiRunID: uiRuns[index], temporary: false, interaction: nil), modelContext: context,
                configuration: config, engineFactory: { constructions += 1; return factory(config, queue: queue) },
                toolAdapter: nil, messages: [.init(role: .user, text: "Identical text")], systemPrompt: nil)
            var first = true
            for try await event in stream {
                try owner.receive(event, uiRunID: uiRuns[index])
                if first, let previous {
                    #expect(throws: HanlinHostError.resultMismatch) { try owner.receive(previous, uiRunID: uiRuns[index]) }
                }
                first = false; previous = event
            }
            try owner.producerStreamDrained(uiRunID: uiRuns[index])
        }
        #expect(constructions == 1 && recorder.installed.count == 1)
        #expect(recorder.live.map(\.reference.rowID) == Array(rows.prefix(2)))
        #expect(recorder.live.map(\.reference.uiRunID) == Array(uiRuns.prefix(2)))
        #expect(Set(recorder.live.map(\.canonicalRunID)).count == 2)
        let originalBindings = recorder.live
        await owner.invalidate()
        let restoredOwner = HanlinAppAgentSessionOwner(), restored = AppPresentationRecorder()
        restoredOwner.presentation = restored
        try await restoredOwner.restoreHistory(conversation: row, conversationID: id, sceneID: scene,
            temporary: false, modelContext: context)
        #expect(restoredOwner.session == nil && restored.installed.isEmpty)
        #expect(restored.replayed == originalBindings && restoredOwner.bindings == originalBindings)
        restored.replayed = []
        let config = configuration()
        let stream = try await restoredOwner.stream(request: .init(conversation: row, conversationID: id, sceneID: scene,
            rowID: rows[2], uiRunID: uiRuns[2], temporary: false, interaction: nil), modelContext: context,
            configuration: config, engineFactory: { factory(config, queue: queue) }, toolAdapter: nil,
            messages: [.init(role: .user, text: "Next")], systemPrompt: nil)
        for try await event in stream { try restoredOwner.receive(event, uiRunID: uiRuns[2]) }
        try restoredOwner.producerStreamDrained(uiRunID: uiRuns[2])
        #expect(restored.replayed == originalBindings)
        #expect(restored.installed.first != originalBindings.first?.session)
        #expect(restored.live.first?.reference.rowID == rows[2])
    }

    @Test func originalHostActionContinuesThroughTheSameOwnerEngineAndCanonicalStore() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Original action conversation", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id), scene = UUID()
        let rows = [UUID(), UUID()], runs = [UUID(), UUID()]
        let queue = AppPartQueue(try rows.map {
            try HanlinChatStructuredPart(messageID: $0, partID: UUID(), sequence: 0, payload: .textDelta("Original reply"))
        })
        let owner = HanlinAppAgentSessionOwner(), recorder = AppPresentationRecorder()
        owner.presentation = recorder
        let config = configuration()
        var constructions = 0
        for index in 0..<2 {
            let interaction: HanlinHostInteractionRequest?
            if index == 1 {
                interaction = try owner.inlineInteraction(rowID: rows[0], partID: "original-form",
                    actionID: "phase2-tool-submit", arguments: .object(["name": .string("Grace")]))
            } else { interaction = nil }
            let stream = try await owner.stream(request: .init(conversation: row, conversationID: id,
                sceneID: scene, rowID: rows[index], uiRunID: runs[index], temporary: false, interaction: interaction),
                modelContext: context, configuration: config,
                engineFactory: { constructions += 1; return factory(config, queue: queue) },
                toolAdapter: nil, messages: [.init(role: .user, text: "Show the original form")], systemPrompt: nil)
            for try await event in stream {
                #expect(event.interactionOrigin == interaction?.origin)
                try owner.receive(event, uiRunID: runs[index])
            }
            try owner.producerStreamDrained(uiRunID: runs[index])
        }
        #expect(constructions == 1)
        #expect(recorder.installed.count == 1)
        #expect(recorder.live.map(\.reference.rowID) == rows)
        #expect(Set(recorder.live.map(\.canonicalRunID)).count == 2)
        let prompts = await queue.receivedPrompts
        #expect(prompts.count == 2)
        #expect(prompts[1].contains("phase2-tool-submit"))
        #expect(prompts[1].contains("Grace"))
        await owner.invalidate()
        #expect(throws: HanlinHostError.staleContext) {
            try owner.inlineInteraction(rowID: rows[0], partID: "original-form",
                actionID: "phase2-tool-submit", arguments: .object(["name": .string("Grace")]))
        }
    }

    @Test func temporaryCanonicalMetadataSurvivesCancellationWithoutDatabaseWrite() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Temporary", type: "chat")
        let id = try #require(row.id), scene = UUID(), rows = [UUID(), UUID()]
        let parts = try rows.map { try HanlinChatStructuredPart(messageID: $0, partID: UUID(), sequence: 0, payload: .textDelta("Temporary")) }
        let owner = HanlinAppAgentSessionOwner(), recorder = AppPresentationRecorder(), queue = AppPartQueue(parts)
        owner.presentation = recorder
        for index in 0..<2 {
            let config = configuration(), uiRun = UUID()
            let stream = try await owner.stream(request: .init(conversation: row, conversationID: id, sceneID: scene,
                rowID: rows[index], uiRunID: uiRun, temporary: true, interaction: nil), modelContext: context,
                configuration: config, engineFactory: { factory(config, queue: queue) }, toolAdapter: nil,
                messages: [.init(role: .user, text: "Temporary")], systemPrompt: nil)
            for try await event in stream { try owner.receive(event, uiRunID: uiRun) }
            try owner.producerStreamDrained(uiRunID: uiRun)
            if index == 0 { owner.cancel() }
        }
        #expect(recorder.replayed.count == 1 && recorder.replayed.first?.reference.rowID == rows[0])
        #expect(row.agentSDKRecordData == nil)
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
    }

    @Test func historyOpenRejectsDeletedForeignAndCancelledOriginsWithoutCreatingSession() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Deleted history", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id), scene = UUID()
        let owner = HanlinAppAgentSessionOwner(), recorder = AppPresentationRecorder()
        owner.presentation = recorder
        do {
            try await owner.restoreHistory(conversation: row, conversationID: UUID(), sceneID: scene,
                temporary: false, modelContext: context)
            Issue.record("Foreign conversation loaded")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
        let cancelled = Task { @MainActor in
            try await owner.restoreHistory(conversation: row, conversationID: id, sceneID: scene,
                temporary: false, modelContext: context)
        }
        cancelled.cancel()
        do { try await cancelled.value; Issue.record("Cancelled restore delivered") }
        catch { #expect(error is CancellationError) }
        context.delete(row); try context.save()
        do {
            try await owner.restoreHistory(conversation: row, conversationID: id, sceneID: scene,
                temporary: false, modelContext: context)
            Issue.record("Deleted origin loaded")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
        #expect(owner.session == nil && recorder.installed.isEmpty && recorder.replayed.isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
    }

    @Test func historicalReceiptDedupRejectsChangedLargeIntegerOutcomeAndPreservesBytes() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Historical original", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id)
        let ns = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library", workspace: "swiftdata", space: id.uuidString)
        let session = HanlinHostSession(conversationID: id, context: .init(namespace: ns, sceneID: UUID(), generation: UUID()))
        let logical = try HanlinLogicalToolID(providerInstanceID: .init(validating: "hanlin.host"), localToolID: .init(validating: "open_mini_app"))
        let call = HanlinHostCallIdentity(session: session, runID: UUID(), step: 0, providerCallID: "original",
            invocationID: try .init(validating: UUID().uuidString.lowercased()), logicalToolID: logical)
        let request = SplitBridgeRequest(caller: try .init(validating: "hanlin.host"), target: try .init(validating: "hanlin.demo.swift-parity"),
            installedPackage: try .init(validating: "compiled.hanlin.demo.swift-parity"), session: try .init(validating: session.id.uuidString.lowercased()),
            chat: id, generation: 0, action: try .init(validating: "share.value"), capability: try .init(validating: "inter-app.share"),
            issuedAt: .now, expiresAt: .now.addingTimeInterval(30), payload: .null)
        let originReference = "hanlin.split.origin.v1:" + request.id.uuidString.lowercased() + ":fixture-existing-origin"
        let store = HanlinAppConversationStore(context: context, conversation: row, namespace: ns, conversationID: id, temporary: false)
        try await store.save(.init(namespace: ns, conversationID: id, revision: 0,
            entries: [.init(runID: call.runID, step: 0, sequence: 0, payload: .presentationReference(version: 1, opaqueReference: originReference))]), replacing: nil)
        let resultID = UUID()
        func receipt(_ value: Int64) throws -> (HanlinHostResultEvent, String) {
            let response = SplitBridgeReturn(request: request, outcome: .result(.integer(value)))
            let key = try HanlinAppSplitOriginCoordinator.historicalReceiptReference(response, resultID: resultID)
            let result = HanlinHostExecutionResult(result: .init(invocationID: call.invocationID, logicalToolID: logical,
                outcome: .completed([.structured(.integer(value))]), completedAt: .now), effectState: .confirmedCommitted,
                context: session.context, reconciliationReference: key)
            return (try .init(resultID: resultID, call: call, result: result), key)
        }
        let (original, originalKey) = try receipt(9_007_199_254_740_992)
        try await store.persistHistoricalReceipt(original, originReference: originReference, receiptReference: originalKey)
        let preserved = row.agentSDKRecordData
        let (duplicate, duplicateKey) = try receipt(9_007_199_254_740_992)
        try await store.persistHistoricalReceipt(duplicate, originReference: originReference, receiptReference: duplicateKey)
        #expect(row.agentSDKRecordData == preserved)
        let (conflict, conflictKey) = try receipt(9_007_199_254_740_993)
        do {
            try await store.persistHistoricalReceipt(conflict, originReference: originReference, receiptReference: conflictKey)
            Issue.record("Changed large-integer outcome deduplicated as the original receipt")
        } catch { #expect(error as? HanlinHostError == .resultMismatch) }
        #expect(row.agentSDKRecordData == preserved)
        let loaded = try await store.load(id, namespace: ns)
        #expect(loaded?.revision == 1)
    }

    @Test func liveSettledAndProvisionalReceiptsHaveDistinctReconciliationRules() async throws {
        let values: [(HanlinValue, HanlinValue)] = [(.integer(9_007_199_254_740_992), .integer(9_007_199_254_740_993)),
            (.string("K"), .string("\u{212A}"))]
        for (originalValue, conflictingValue) in values {
            for provisional in [false, true] {
                let container = try database(), context = container.mainContext
                let row = ChatRecords(name: "Original live receipt", type: "chat")
                context.insert(row); try context.save()
                let id = try #require(row.id)
                let ns = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library", workspace: "swiftdata", space: id.uuidString)
                let session = HanlinHostSession(conversationID: id, context: .init(namespace: ns, sceneID: UUID(), generation: UUID()))
                let logical = try HanlinLogicalToolID(providerInstanceID: .init(validating: "hanlin.host"), localToolID: .init(validating: "open_mini_app"))
                let call = HanlinHostCallIdentity(session: session, runID: UUID(), step: 0, providerCallID: "original",
                    invocationID: try .init(validating: UUID().uuidString.lowercased()), logicalToolID: logical)
                let request = SplitBridgeRequest(caller: try .init(validating: "hanlin.host"), target: try .init(validating: "hanlin.demo.swift-parity"),
                    installedPackage: try .init(validating: "compiled.hanlin.demo.swift-parity"), session: try .init(validating: session.id.uuidString.lowercased()),
                    chat: id, generation: 0, action: try .init(validating: "share.value"), capability: try .init(validating: "inter-app.share"),
                    issuedAt: .now, expiresAt: .now.addingTimeInterval(30), payload: .null)
                let resultID = UUID(), provisionalReference = "hanlin.split.return.v1:" + request.id.uuidString.lowercased()
                let originReference = "hanlin.split.origin.v1:" + request.id.uuidString.lowercased() + ":fixture-committed-origin"
                func receipt(_ value: HanlinValue) throws -> (HanlinHostResultEvent, String) {
                    let key = try HanlinAppSplitOriginCoordinator.historicalReceiptReference(.init(request: request, outcome: .result(value)), resultID: resultID)
                    let digest = try #require(key.split(separator: ":").last)
                    let result = HanlinHostExecutionResult(result: .init(invocationID: call.invocationID, logicalToolID: logical,
                        outcome: .completed([.structured(value)]), completedAt: .now), effectState: .confirmedCommitted,
                        context: session.context, reconciliationReference: provisionalReference + ":" + String(digest))
                    return (try .init(resultID: resultID, call: call, result: result), key)
                }
                let (expected, expectedKey) = try receipt(originalValue)
                let prior = provisional ? HanlinHostExecutionResult(result: .init(invocationID: call.invocationID, logicalToolID: logical,
                    outcome: .failed(.init(code: .nativeFailure, userMessage: "Original process lost the result")), completedAt: .now),
                    effectState: .uncertain, context: session.context, reconciliationReference: provisionalReference) : expected.result
                let store = HanlinAppConversationStore(context: context, conversation: row, namespace: ns, conversationID: id, temporary: false)
                // Exact shape the original Session commits: identity + metadata receipt, with NO
                // additional cold marker. A settled live result must already be final here.
                try await store.save(.init(namespace: ns, conversationID: id, revision: 0, entries: [
                    .init(runID: call.runID, step: 0, sequence: 0, payload: .presentationReference(version: 1, opaqueReference: originReference)),
                    .init(runID: call.runID, step: 0, sequence: 1, payload: .hostResultIdentity(resultID: resultID, call: call)),
                    .init(runID: call.runID, step: 0, sequence: 2, payload: .toolResult(providerCallID: call.providerCallID, result: prior.metadataReceipt()))]), replacing: nil)
                try await store.persistHistoricalReceipt(expected, originReference: originReference, receiptReference: expectedKey,
                    replacingUncertainReference: provisionalReference)
                let preserved = row.agentSDKRecordData
                let loaded = try await store.load(id, namespace: ns)
                #expect(loaded?.revision == (provisional ? 1 : 0))
                let (changed, changedKey) = try receipt(conflictingValue)
                do {
                    try await store.persistHistoricalReceipt(changed, originReference: originReference, receiptReference: changedKey,
                        replacingUncertainReference: provisionalReference)
                    Issue.record("Conflicting outcome overwrote a settled original receipt without a cold marker")
                } catch { #expect(error as? HanlinHostError == .resultMismatch) }
                #expect(row.agentSDKRecordData == preserved)
            }
        }
    }

    @Test func acceptedOriginAcknowledgementCannotClearAnotherWindowOrNewerDelivery() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Existing origin", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id)
        func request() throws -> SplitBridgeRequest {
            .init(caller: try .init(validating: "hanlin.host"), target: try .init(validating: "hanlin.demo.swift-parity"),
                installedPackage: try .init(validating: "compiled.hanlin.demo.swift-parity"), session: try .init(validating: UUID().uuidString.lowercased()),
                chat: id, generation: 0, action: try .init(validating: "share.value"), capability: try .init(validating: "inter-app.share"),
                issuedAt: .now, expiresAt: .now.addingTimeInterval(30), payload: .null)
        }
        let coordinator = HanlinAppSplitOriginCoordinator(modelContext: context), first = try request(), next = try request()
        let window = UUID(), otherWindow = UUID()
        let firstURL = SplitForegroundRoute.returnToAI.url(reference: first.id)
        let firstClaim = try #require(coordinator.claimReturn(firstURL, receivingWindowID: window))
        // Simulates the transport's trusted post-accept callback; not mailbox or UI mount proof.
        coordinator.navigateToOriginalConversation(first)
        #expect(coordinator.acceptedOrigin(forReceivingWindowID: window) == first)
        #expect(coordinator.acceptedOrigin(forReceivingWindowID: otherWindow) == nil)
        coordinator.acknowledgeAcceptedOrigin(requestID: first.id, receivingWindowID: otherWindow)
        #expect(coordinator.acceptedOrigin(forReceivingWindowID: window) == first)
        coordinator.acknowledgeAcceptedOrigin(requestID: first.id, receivingWindowID: window)
        #expect(coordinator.acceptedOrigin(forReceivingWindowID: window) == nil)
        let nextURL = SplitForegroundRoute.returnToAI.url(reference: next.id)
        _ = try #require(coordinator.claimReturn(nextURL, receivingWindowID: otherWindow))
        coordinator.navigateToOriginalConversation(next)
        coordinator.acknowledgeAcceptedOrigin(requestID: first.id, receivingWindowID: window)
        await coordinator.receiveReturn(firstURL, modelContext: context, receivingWindowID: window, claimID: firstClaim)
        #expect(coordinator.acceptedOrigin(forReceivingWindowID: otherWindow) == next)
        coordinator.acknowledgeAcceptedOrigin(requestID: next.id, receivingWindowID: otherWindow)
        #expect(coordinator.acceptedOrigin(forReceivingWindowID: otherWindow) == nil)
        _ = try #require(coordinator.claimReturn(firstURL, receivingWindowID: window))
        context.delete(row); try context.save()
        coordinator.navigateToOriginalConversation(first)
        #expect(coordinator.acceptedOrigin(forReceivingWindowID: window) == nil && coordinator.lastFailure == .correlationMismatch)
    }

    @Test func actualNativeBoundaryPreservesExactInputsAndRejectsInvalidOrChangedContextBeforeEffects() async throws {
        let cases: [(input: String, invalidate: Bool, calls: Int, code: HanlinErrorCode?)] = [
            (#"{"value":9007199254740993}"#, false, 1, nil),
            (#"{"value":1.234567890123456789}"#, false, 1, nil),
            (#"{}"#, false, 0, .invalidArguments),
            (#"{"value":1,"K":1,"\u212A":2}"#, false, 1, nil),
            (#"{"value":1}"#, true, 0, .operationUnavailable)
        ]
        for item in cases {
            let container = try database(), context = container.mainContext
            let row = ChatRecords(name: "Exact original operation", type: "chat")
            context.insert(row); try context.save()
            let id = try #require(row.id)
            let ns = try HanlinConversationNamespace(app: "hanlin", account: "a", workspace: "w", space: id.uuidString)
            let identity = HanlinHostSession(conversationID: id, context: .init(namespace: ns, sceneID: UUID(), generation: UUID()))
            let store = HanlinAppConversationStore(context: context, conversation: row, namespace: ns, conversationID: id, temporary: false)
            let alias = "fixture_exact_original", profile = ToolPresentationProfile.generic(toolName: alias)
            let schema = NativeToolSchema.function(name: alias, description: "Exact original operation", parameters: [
                "type": "object", "properties": ["value": ["type": "number"]], "required": ["value"]])
            let source = HanlinCanonicalToolAuthority.NativeSource(entry: .init(name: alias, title: "Fixture", summary: "Fixture", presentationProfile: profile),
                canonicalSchema: schema, modelSchema: schema, preferredAlias: alias)
            let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [source], mcpTools: [])
            var calls = 0, current = true
            var toolEvents: [AgentEvent] = []
            let executors = AssistantToolBridge.Executors(executeNative: { _, _, arguments, _ in
                calls += 1
                do { try HanlinHostSchemaValidation.requireSameValue(originalJSON: Data(item.input.utf8), projectedJSON: Data(arguments.utf8)) }
                catch { Issue.record("Original executor received a changed business value") }
                return NativeToolResult(modelText: "Authoritative operation acknowledgement", outcome: .succeeded)
            }, executeScripting: { _, _ in NativeToolResult(modelText: "Unexpected", outcome: .failed) })
            let adapter = HanlinAISDKToolAdapter(session: .init(chatID: id.uuidString, isTemporaryChat: true),
                preparedTools: .init(authority: authority, executors: executors), callbacks: .init(onAgentEvent: { event in
                    toolEvents.append(event)
                    if case .toolExecutionStarted = event, item.invalidate { current = false }
                }))
            let host = HanlinAppHostIntegration(identity: identity, store: store, isCurrent: { current })
            host.toolAdapter = adapter
            host.confirmInvocation = { _, _ in
            Issue.record("A non-sensitive read unexpectedly requested consent")
            return false
        }
            let catalog = try await host.catalog(for: identity.context)
            let dispatcher = HanlinHostDispatcher(host: host)
            // A stale context suppresses delivery but retains the original no-dispatch receipt.
            do {
                _ = try await dispatcher.dispatchEvent(alias: alias, argumentsJSON: item.input, providerCallID: "exact",
                    runID: UUID(), step: 0, session: identity, catalog: catalog, limits: .init())
                #expect(!item.invalidate)
            } catch { #expect(item.invalidate && error as? HanlinHostError == .staleContext) }
            let receipts = await dispatcher.receipts(for: identity)
            let receipt = try #require(receipts.first)
            #expect(calls == item.calls && receipts.count == 1)
            if item.invalidate {
                let started = toolEvents.compactMap { event -> String? in
                    if case .toolExecutionStarted(let execution) = event { return execution.id }; return nil
                }
                let failed = toolEvents.compactMap { event -> String? in
                    if case .toolExecutionFailed(let id, _) = event { return id }; return nil
                }
                #expect(started == ["exact:execution"] && failed == started,
                    "Pre-dispatch rejection must end the already-emitted execution without invoking the tool")
            }
            #expect(receipt.effectState == (item.calls == 1 ? .confirmedCommitted : .notDispatched))
            if let code = item.code {
                guard case .failed(let error) = receipt.result.outcome else { Issue.record("Missing typed pre-dispatch denial"); continue }
                #expect(error.code == code)
            }
            #expect(adapter.sdkOutcomeHandlers.isEmpty && adapter.sdkProgressHandlers.isEmpty && adapter.sdkPreDispatchHandlers.isEmpty)
        }
    }

    #if HANLIN_A2UI_POC
    @Test func officialToolPayloadUsesOriginalRendererAndPersistsExactBytesWithoutInferringArbitraryJSON() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "A2UIFixtures/form.jsonl")
        let messages = try String(contentsOf: fixture, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
        let arguments = try JSONSerialization.data(withJSONObject: ["messages": messages])
        let result = await PresentA2UITool().execute(argumentsJSON: String(decoding: arguments, as: UTF8.self),
            context: .init(localeIdentifier: "he"))
        #expect(result.outcome == .succeeded)
        let original = try #require(result.embeddedPayload)
        #expect(original.officialA2UIMessages == messages.map { Data($0.utf8) })
        let reopened = try JSONDecoder().decode(HanlinEmbeddedResultPayload.self, from: JSONEncoder().encode(original))
        #expect(reopened.officialA2UIMessages == original.officialA2UIMessages)
        #expect(HanlinEmbeddedResultPayload(payload: .string(messages.joined())).officialA2UIMessages == nil)
        let rejected = await PresentA2UITool().execute(argumentsJSON: #"{"messages":["{\"untrusted\":true}"]}"#,
            context: .init(localeIdentifier: "he"))
        #expect(rejected.outcome == .invalidArguments && rejected.embeddedPayload == nil)
    }
    #endif

    @Test func cachedSearchCatalogKeepsOriginalRoutesAndInvalidatesChangedSchemasBeforeDispatch() async throws {
        let container = try database(), context = container.mainContext
        let row = ChatRecords(name: "Search catalog", type: "chat")
        context.insert(row); try context.save()
        let id = try #require(row.id)
        let ns = try HanlinConversationNamespace(app: "hanlin", account: "a", workspace: "w", space: id.uuidString)
        let identity = HanlinHostSession(conversationID: id, context: .init(namespace: ns, sceneID: UUID(), generation: UUID()))
        let store = HanlinAppConversationStore(context: context, conversation: row, namespace: ns, conversationID: id, temporary: false)
        let search = try #require(LegacyToolCanonicalAdapter.sources(memoryEnabled: false, mapEnabled: false,
            calendarEnabled: false, searchEnabled: true, knowledgeEnabled: false, codeEnabled: false,
            healthEnabled: false, weatherEnabled: false, canvasEnabled: false).first { $0.toolName == "search_online" })
        let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [], mcpTools: [], legacySources: [search])
        var calls: [String] = [], current = true
        let executors = AssistantToolBridge.Executors(executeNative: { _, _, _, _ in
            Issue.record("Search escaped its original legacy route")
            return NativeToolResult(modelText: "Unexpected route", outcome: .failed)
        }, executeScripting: { _, _ in
            Issue.record("Search escaped its original legacy route")
            return NativeToolResult(modelText: "Unexpected route", outcome: .failed)
        }, executeLegacy: { alias, arguments, _ in
            #expect(alias == "search_online")
            calls.append(arguments)
            return NativeToolResult(modelText: "Search receipt", outcome: .succeeded)
        })
        let adapter = HanlinAISDKToolAdapter(session: .init(chatID: id.uuidString, isTemporaryChat: true),
            preparedTools: .init(authority: authority, executors: executors, legacySources: [search]))
        let host = HanlinAppHostIntegration(identity: identity, store: store, isCurrent: { current })
        host.toolAdapter = adapter
        host.confirmInvocation = { _, _ in
            Issue.record("A non-sensitive read unexpectedly requested consent")
            return false
        }
        let catalog = try await host.catalog(for: identity.context)
        for _ in 0..<8 {
            #expect(try await host.catalog(for: identity.context).revision == catalog.revision)
        }
        let dispatcher = HanlinHostDispatcher(host: host)
        let input = #"{"query":"חדשות בישראל 🙂","progress_summary":"מחפש מקורות","result_presentation":"card"}"#
        let result = try await dispatcher.dispatchEvent(alias: "search_online", argumentsJSON: input,
            providerCallID: "search-original", runID: UUID(), step: 0, session: identity, catalog: catalog, limits: .init())
        #expect(result.result.effectState == .confirmedCommitted && calls.count == 1)
        try HanlinHostSchemaValidation.requireSameValue(originalJSON: Data(input.utf8),
            projectedJSON: Data(try #require(calls.first).utf8),
            removingMetadataKeys: [ToolSchemaDecorator.progressSummaryKey, ToolSchemaDecorator.resultPresentationKey])

        var changedSchema = search.modelSchema
        var function = try #require(changedSchema["function"] as? [String: Any])
        function["parameters"] = ["type": "object", "properties": ["query": ["type": "integer"]], "required": ["query"]]
        changedSchema["function"] = function
        let changedSource = HanlinCanonicalToolAuthority.LegacySource(descriptor: search.descriptor,
            preferredAlias: search.preferredAlias, modelSchema: changedSchema, toolName: search.toolName,
            presentationProfile: search.presentationProfile, resultTitle: search.resultTitle)
        let changedAuthority = try HanlinCanonicalToolAuthority.build(nativeSources: [], mcpTools: [], legacySources: [changedSource])
        adapter.preparedTools = .init(authority: changedAuthority, executors: executors, legacySources: [changedSource])
        let changedCatalog = try await host.catalog(for: identity.context)
        #expect(changedCatalog.revision != catalog.revision)
        let stale = try await dispatcher.dispatchEvent(alias: "search_online", argumentsJSON: input,
            providerCallID: "stale-search", runID: UUID(), step: 0, session: identity, catalog: catalog, limits: .init())
        #expect(stale.result.effectState == .notDispatched && calls.count == 1)

        // A manifest that explicitly requests consent still revalidates its route after review.
        let sensitiveDescriptor = HanlinToolDescriptor(
            logicalID: search.descriptor.logicalID, descriptorRevision: search.descriptor.descriptorRevision,
            owner: search.descriptor.owner, title: search.descriptor.title, summary: search.descriptor.summary,
            inputSchema: search.descriptor.inputSchema, risk: .sensitiveRead, presentation: search.descriptor.presentation)
        let sensitiveSource = HanlinCanonicalToolAuthority.LegacySource(
            descriptor: sensitiveDescriptor, preferredAlias: search.preferredAlias, modelSchema: search.modelSchema,
            toolName: search.toolName, presentationProfile: search.presentationProfile, resultTitle: search.resultTitle)
        let sensitiveAuthority = try HanlinCanonicalToolAuthority.build(nativeSources: [], mcpTools: [], legacySources: [sensitiveSource])
        adapter.preparedTools = .init(authority: sensitiveAuthority, executors: executors, legacySources: [sensitiveSource])
        let restored = try await host.catalog(for: identity.context)
        #expect(restored.revision != catalog.revision)
        host.confirmInvocation = { _, _ in
            adapter.preparedTools = .init(authority: changedAuthority, executors: executors, legacySources: [changedSource])
            return true
        }
        let changedDuringReview = try await dispatcher.dispatchEvent(alias: "search_online", argumentsJSON: input,
            providerCallID: "changed-during-review", runID: UUID(), step: 0, session: identity, catalog: restored, limits: .init())
        #expect(changedDuringReview.result.effectState == .notDispatched && calls.count == 1)
        current = false
        do {
            _ = try await host.catalog(for: identity.context)
            Issue.record("Cached catalog bypassed the original conversation check")
        } catch { #expect(error as? HanlinHostError == .staleContext) }
    }

    @Test func appHostInvokesOriginalExecutorOnceAndUsesExplicitNativeOutcome() async throws {
        for (nativeOutcome, approved, expires) in [(NativeToolExecutionOutcome.succeeded, true, false),
            (.rejectedByCapability, true, false), (.failed, true, false), (.succeeded, false, false), (.succeeded, true, true)] {
            let container = try database(), context = container.mainContext
            let row = ChatRecords(name: "Host", type: "chat")
            context.insert(row); try context.save()
            let id = try #require(row.id)
            let ns = try HanlinConversationNamespace(app: "hanlin", account: "a", workspace: "w", space: id.uuidString)
            let identity = HanlinHostSession(conversationID: id, context: .init(namespace: ns, sceneID: UUID(), generation: UUID()))
            let store = HanlinAppConversationStore(context: context, conversation: row, namespace: ns, conversationID: id, temporary: false)
            let alias = "fixture_general_operation", profile = ToolPresentationProfile.generic(toolName: alias)
            let schema = NativeToolSchema.function(name: alias, description: "Original injected operation",
                parameters: NativeToolSchema.object(properties: [:], required: []))
            let source = HanlinCanonicalToolAuthority.NativeSource(entry: .init(name: alias, title: "Fixture", summary: "Fixture", isSensitive: true, presentationProfile: profile),
                canonicalSchema: schema, modelSchema: schema, preferredAlias: alias)
            let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [source], mcpTools: [])
            var calls = 0, callbackCount = 0
            let executors = AssistantToolBridge.Executors(executeNative: { _, _, _, _ in
                calls += 1
                return NativeToolResult(modelText: "Original sanctioned feedback", outcome: nativeOutcome)
            }, executeScripting: { _, _ in NativeToolResult(modelText: "Unexpected", outcome: .failed) })
            let adapter = HanlinAISDKToolAdapter(session: .init(chatID: id.uuidString, isTemporaryChat: true),
                preparedTools: .init(authority: authority, executors: executors),
                callbacks: .init(onAgentEvent: { _ in callbackCount += 1 }))
            let host = HanlinAppHostIntegration(identity: identity, store: store, isCurrent: { true })
            host.toolAdapter = adapter
            var confirmations = 0
            var rememberedGrantID: UUID?
            defer {
                if let rememberedGrantID { _ = HanlinToolApprovalStore.shared.revoke(id: rememberedGrantID) }
            }
            host.confirmInvocation = { invocation, scope in
                confirmations += 1
                if expires {
                    let remaining = max(0, invocation.request.deadline?.timeIntervalSinceNow ?? 0)
                    try? await Task.sleep(for: .seconds(remaining + 0.01))
                }
                if approved {
                    guard HanlinToolApprovalStore.shared.remember(scope, title: alias) else { return false }
                    rememberedGrantID = HanlinToolApprovalStore.shared.grants.first { $0.scope == scope }?.id
                }
                return approved
            }
            let catalog = try await host.catalog(for: identity.context)
            let tool = try #require(catalog.tools.first(where: { $0.route.alias == alias }))
            #expect(tool.descriptor.risk == .sensitiveRead) // Explicit sensitivity drives consent, independently of effects.
            #expect(tool.writeGuarantee == .hostManagedMutation)
            let dispatcher = HanlinHostDispatcher(host: host), run = UUID()
            let limits = try HanlinToolInvocationLimits(timeoutMilliseconds: expires ? 1_000 : 30_000)
            let first = try await dispatcher.dispatchEvent(alias: alias, argumentsJSON: "{}", providerCallID: "original",
                runID: run, step: 2, session: identity, catalog: catalog, limits: limits)
            let countBeforeReplay = callbackCount
            let replay = try await dispatcher.dispatchEvent(alias: alias, argumentsJSON: "{}", providerCallID: "original",
                runID: run, step: 2, session: identity, catalog: catalog, limits: limits)
            let dispatched = approved && !expires
            #expect(confirmations == 1, "Expiry must cross the live approval boundary, and replay cannot prompt again")
            #expect(calls == (dispatched ? 1 : 0) && callbackCount == countBeforeReplay)
            #expect(dispatched ? callbackCount > 0 : callbackCount == 0)
            #expect(first.resultID == replay.resultID && first.call == replay.call)
            #expect(adapter.completedCallIDs.contains("original") == dispatched)
            let expected: HanlinHostEffectState = !dispatched ? .notDispatched : nativeOutcome == .succeeded ? .confirmedCommitted
                : nativeOutcome == .rejectedByCapability ? .confirmedNoEffect : .uncertain
            #expect(first.result.effectState == expected)
            #expect(first.call.session == identity && first.call.step == 2)
            #expect(adapter.sdkOutcomeHandlers.isEmpty && adapter.sdkProgressHandlers.isEmpty && adapter.sdkPreDispatchHandlers.isEmpty)
        }
    }
}
