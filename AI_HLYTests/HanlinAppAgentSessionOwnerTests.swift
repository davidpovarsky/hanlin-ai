import AISDKProvider
import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinPlatformContracts
#if HANLIN_PRODUCT_SPLIT_ACCEPTANCE
import HanlinProductSplit
#endif
import SwiftData
import Testing
@testable import AI_Hanlin

private actor AppPartQueue {
    var parts: [HanlinChatStructuredPart]
    init(_ parts: [HanlinChatStructuredPart]) { self.parts = parts }
    func next() throws -> HanlinChatStructuredPart {
        guard !parts.isEmpty else { throw HanlinHostError.invalidArguments }
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
        let content = try await queue.next().providerContent()
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

@Suite @MainActor struct HanlinAppAgentSessionOwnerTests {
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
        #expect(await consent.request(try invocation(deadline: .now.addingTimeInterval(-1))) == false)
        #expect(consent.pending == nil)
        let expiring = try invocation(deadline: .now.addingTimeInterval(0.15))
        let expiredTask = Task { @MainActor in await consent.request(expiring) }
        #expect(await expiredTask.value == false)
        #expect(consent.pending == nil)

        let live = try invocation(deadline: .now.addingTimeInterval(30))
        let cancelled = Task { @MainActor in await consent.request(live) }
        for _ in 0..<100 where consent.pending == nil { await Task.yield() }
        let oldID = try #require(consent.pending?.id)
        cancelled.cancel()
        #expect(await cancelled.value == false)
        #expect(consent.pending == nil)
        let replacement = Task { @MainActor in await consent.request(live) }
        for _ in 0..<100 where consent.pending == nil { await Task.yield() }
        let currentID = try #require(consent.pending?.id)
        consent.answer(id: oldID, allowed: true)
        #expect(consent.pending?.id == currentID)
        consent.revoke()
        #expect(await replacement.value == false)
        #expect(consent.pending == nil)
    }

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

    #if HANLIN_PRODUCT_SPLIT_ACCEPTANCE
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

    #endif

    @Test func actualNativeBoundaryRejectsLossyOrInvalidInputAndChangedContextBeforeEffects() async throws {
        let cases: [(input: String, invalidate: Bool, calls: Int, code: HanlinErrorCode?)] = [
            (#"{"value":9007199254740993}"#, false, 1, nil),
            (#"{"value":1.234567890123456789}"#, false, 0, .schemaProjectionWidensInput),
            (#"{}"#, false, 0, .invalidArguments),
            (#"{"value":1,"K":1,"\u212A":2}"#, false, 0, .schemaProjectionWidensInput),
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
            let executors = AssistantToolBridge.Executors(executeNative: { _, _, arguments, _ in
                calls += 1
                do { try HanlinHostSchemaValidation.requireSameValue(originalJSON: Data(item.input.utf8), projectedJSON: Data(arguments.utf8)) }
                catch { Issue.record("Original executor received a changed business value") }
                return NativeToolResult(modelText: "Authoritative operation acknowledgement", outcome: .succeeded)
            }, executeScripting: { _, _ in NativeToolResult(modelText: "Unexpected", outcome: .failed) })
            let adapter = HanlinAISDKToolAdapter(session: .init(chatID: id.uuidString, isTemporaryChat: true),
                preparedTools: .init(authority: authority, executors: executors), callbacks: .init(onAgentEvent: { event in
                    if case .toolExecutionStarted = event, item.invalidate { current = false }
                }))
            let host = HanlinAppHostIntegration(identity: identity, store: store, isCurrent: { current })
            host.toolAdapter = adapter
            host.confirmInvocation = { _ in true }
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

    @Test func appHostInvokesOriginalExecutorOnceAndUsesExplicitNativeOutcome() async throws {
        for (nativeOutcome, approved) in [(NativeToolExecutionOutcome.succeeded, true), (.rejectedByCapability, true), (.failed, true), (.succeeded, false)] {
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
            let source = HanlinCanonicalToolAuthority.NativeSource(entry: .init(name: alias, title: "Fixture", summary: "Fixture", presentationProfile: profile),
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
            host.confirmInvocation = { _ in approved }
            let catalog = try await host.catalog(for: identity.context)
            let tool = try #require(catalog.tools.first(where: { $0.route.alias == alias }))
            #expect(tool.descriptor.risk == .read) // Current shadow metadata is not a no-write guarantee.
            #expect(tool.writeGuarantee == .hostManagedMutation)
            let dispatcher = HanlinHostDispatcher(host: host), run = UUID()
            let first = try await dispatcher.dispatchEvent(alias: alias, argumentsJSON: "{}", providerCallID: "original",
                runID: run, step: 2, session: identity, catalog: catalog, limits: .init())
            let countBeforeReplay = callbackCount
            let replay = try await dispatcher.dispatchEvent(alias: alias, argumentsJSON: "{}", providerCallID: "original",
                runID: run, step: 2, session: identity, catalog: catalog, limits: .init())
            #expect(calls == (approved ? 1 : 0) && callbackCount == countBeforeReplay)
            #expect(approved ? callbackCount > 0 : callbackCount == 0)
            #expect(first.resultID == replay.resultID && first.call == replay.call)
            #expect(adapter.completedCallIDs.contains("original") == approved)
            let expected: HanlinHostEffectState = !approved ? .notDispatched : nativeOutcome == .succeeded ? .confirmedCommitted
                : nativeOutcome == .rejectedByCapability ? .confirmedNoEffect : .uncertain
            #expect(first.result.effectState == expected)
            #expect(first.call.session == identity && first.call.step == 2)
            #expect(adapter.sdkOutcomeHandlers.isEmpty && adapter.sdkProgressHandlers.isEmpty && adapter.sdkPreDispatchHandlers.isEmpty)
        }
    }
}
