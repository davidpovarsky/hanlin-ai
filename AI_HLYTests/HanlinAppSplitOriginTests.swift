import AISDKProvider
import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinMiniAppCore
import HanlinParityMiniApp
import HanlinPlatformContracts
import HanlinProductSplit
import SwiftData
import Testing
@testable import AI_Hanlin

private actor SplitModelCounter { var value = 0; func next() -> Int { value += 1; return value } }
private struct SplitComponentModel: LanguageModelV3 {
    let provider = "split-app-component", modelId = "split-app-component"
    let counter = SplitModelCounter()
    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult { throw HanlinHostError.unsupportedProviderCapability }
    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let index = await counter.next()
        return .init(stream: AsyncThrowingStream { c in
            if index == 1 {
                c.yield(.toolCall(.init(toolCallId: "original-split-call", toolName: "open_mini_app",
                    input: #"{"target":"hanlin.demo.swift-parity","action":"share.value","payload":null}"#)))
                c.yield(.finish(finishReason: .init(unified: .toolCalls), usage: .init(), providerMetadata: nil))
            } else {
                c.yield(.textStart(id: "original", providerMetadata: nil))
                c.yield(.textDelta(id: "original", delta: "Actual original tool continuation", providerMetadata: nil))
                c.yield(.textEnd(id: "original", providerMetadata: nil))
                c.yield(.finish(finishReason: .init(unified: .stop), usage: .init(), providerMetadata: nil))
            }
            c.finish()
        })
    }
}

private enum SplitComponentError: Error { case timeout, cancelled, missing }
@MainActor private final class SplitOpenProbe {
    var request: SplitBridgeRequest?
    var count = 0
    var waiter: CheckedContinuation<SplitBridgeRequest, Error>?
    func receive(_ request: SplitBridgeRequest) { self.request = request; count += 1; waiter?.resume(returning: request); waiter = nil }
    func wait() async throws -> SplitBridgeRequest {
        if let request { return request }
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { waiter = $0 }
        }, onCancel: { Task { @MainActor in self.waiter?.resume(throwing: SplitComponentError.cancelled); self.waiter = nil } })
    }
}
@MainActor private final class SplitOwnerBox { weak var value: HanlinAppAgentSessionOwner? }
@MainActor private final class SplitTestClock { var now = Date() }

@MainActor private func splitBounded<T: Sendable>(_ operation: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await Task.sleep(for: .seconds(8)); throw SplitComponentError.timeout }
        defer { group.cancelAll() }
        guard let value = try await group.next() else { throw SplitComponentError.missing }
        return value
    }
}

@MainActor private final class SplitAppHarness {
    let container: ModelContainer
    let row: ChatRecords
    let assistant: ChatMessages
    let mailbox: HanlinSplitMailbox
    let coordinator: HanlinAppSplitOriginCoordinator
    let owner: HanlinAppAgentSessionOwner
    let probe: SplitOpenProbe
    let group: URL
    let model = SplitComponentModel()
    let uiRun = UUID(), scene = UUID(), receivingWindowID = UUID()
    var streamTask: Task<Bool, Never>?
    var engineConstructions = 0
    var failure: String?

    init(cancelWhileOpening: Bool = false,
         now: (@MainActor () -> Date)? = nil,
         onTargetContext: (@MainActor (SplitBridgeRequest, HanlinAppAgentSessionOwner?) async throws -> Void)? = nil) throws {
        let container = try ModelContainer(for: ChatRecords.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let row = ChatRecords(name: "Original persisted Split conversation", type: "chat")
        let assistant = ChatMessages(role: "assistant", text: "", record: row)
        row.messages = [assistant]
        context.insert(row); context.insert(assistant); try context.save()
        let group = FileManager.default.temporaryDirectory.appending(path: "sdk-split-component-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath().standardizedFileURL
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: false)
        let mailbox = try HanlinSplitMailbox(trustedGroupContainer: group)
        let descriptor = SwiftParityMiniAppRegistration().descriptor
        let registration = try SplitTargetRegistration(descriptor: descriptor,
            installedPackage: .init(validating: "compiled.hanlin.demo.swift-parity"), generation: 0)
        try mailbox.publishCatalog([registration])
        let probe = SplitOpenProbe(), box = SplitOwnerBox()
        let coordinator = HanlinAppSplitOriginCoordinator(mailbox: mailbox, openURL: { url in
            do {
                let id = try SplitForegroundRoute.openMiniApps.reference(in: url)
                let request = try mailbox.original(id)
                let data = try #require(row.agentSDKRecordData)
                let record = try JSONDecoder().decode(HanlinConversationRecord.self, from: data)
                #expect(record.entries.contains { if case .presentationReference(1, let ref) = $0.payload { return ref.hasPrefix("hanlin.split.origin.v1:" + id.uuidString.lowercased() + ":") }; return false })
                let bindings = try HanlinAppAgentSessionOwner.historicalBindings(in: record)
                #expect(bindings.contains { $0.reference.rowID == assistant.id && $0.session.id.uuidString.lowercased() == request.session.rawValue })
                probe.receive(request)
                if cancelWhileOpening { box.value?.cancel() }
                return true
            } catch { Issue.record("Original dispatch lacked its committed canonical association: \(error)"); return false }
        }, targetContext: { request in
            try await onTargetContext?(request, box.value)
            _ = try request.launchPlan(descriptor: descriptor, installedPackageID: registration.installedPackage, currentGeneration: registration.generation)
            return Self.context(request)
        }, now: now ?? { Date() })
        let owner = HanlinAppAgentSessionOwner(splitCoordinator: coordinator)
        let priorApproval = owner.consent.onChange
        owner.consent.onChange = { [weak owner] request, choice in
            priorApproval?(request, choice)
            if choice == nil {
                Task { @MainActor [weak owner] in owner?.consent.answer(id: request.id, allowed: true) }
            }
        }
        box.value = owner
        self.container = container; self.row = row; self.assistant = assistant; self.group = group
        self.mailbox = mailbox; self.probe = probe; self.coordinator = coordinator; self.owner = owner
    }

    static func context(_ request: SplitBridgeRequest) -> SplitReceiverContext {
        .init(caller: request.caller, target: request.target, package: request.installedPackage, session: request.session,
              chat: request.chat, generation: request.generation, authorized: true, routeAvailable: true, online: true)
    }
    func start() throws {
        let id = try #require(row.id), context = container.mainContext
        let adapter = HanlinAISDKToolAdapter(session: .init(chatID: id.uuidString, isTemporaryChat: false),
            preparedTools: .init(authority: try HanlinCanonicalToolAuthority.build(nativeSources: [], mcpTools: []),
                executors: .init(executeNative: { _, _, _, _ in Issue.record("Unexpected general native executor"); return .init(modelText: "Unexpected", outcome: .failed) },
                    executeScripting: { _, _ in Issue.record("Unexpected script executor"); return .init(modelText: "Unexpected", outcome: .failed) })))
        let config = HanlinChatModelConfiguration(modelID: model.modelId, endpoint: URL(filePath: "/fixture"), apiKey: "", supportsToolUse: true)
        streamTask = Task { @MainActor in
            do {
                let stream = try await owner.stream(request: .init(conversation: row, conversationID: id, sceneID: scene,
                    rowID: assistant.id, uiRunID: uiRun, temporary: false, interaction: nil), modelContext: context,
                    configuration: config, engineFactory: { self.engineConstructions += 1; return HanlinAISDKAgentEngine(configuration: config, model: .v3(self.model)) },
                    toolAdapter: adapter, messages: [.init(role: .user, text: "Open original Swift Parity")], systemPrompt: nil)
                for try await event in stream { try owner.receive(event, uiRunID: uiRun) }
                try owner.producerStreamDrained(uiRunID: uiRun)
                return true
            } catch { failure = String(describing: error); return false }
        }
    }
    func opened() async throws -> SplitBridgeRequest { try await splitBounded { try await self.probe.wait() } }
    func complete(_ request: SplitBridgeRequest) async throws {
        let receiver = SplitDurableReceiver(persistence: mailbox, source: mailbox), context = Self.context(request)
        _ = try await receiver.receive(reference: request.id, context: context, now: .now)
        let started = try await receiver.start(reference: request.id, context: context, now: .now)
        let attempt = try #require(started.attempt)
        // This is the actual durable receiver with a fixture operation result, NOT a live broker effect.
        _ = try await receiver.complete(reference: request.id, attempt: attempt, outcome: .result(.integer(9_007_199_254_740_993)), context: context)
    }
    func returnToAI(_ request: SplitBridgeRequest) async {
        let url = SplitForegroundRoute.returnToAI.url(reference: request.id)
        guard let claim = coordinator.claimReturn(url, receivingWindowID: receivingWindowID) else { return }
        await coordinator.receiveReturn(url, modelContext: container.mainContext, receivingWindowID: receivingWindowID, claimID: claim)
    }

    func stop() {
        owner.cancel(); streamTask?.cancel()
        // This is a uniquely created test-only directory under the resolved temporary root.
        try? FileManager.default.removeItem(at: group)
    }
}

@Suite @MainActor struct HanlinAppSplitOriginTests {
    private func sharingFixture() throws -> (URL, HanlinMiniAppStorageContext) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "split-real-sharing-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        let store = try HanlinMiniAppDataStore(root: root)
        return (root, HanlinMiniAppStorageContext(appID: SwiftParityMiniAppRegistration().appID, store: store))
    }

    private func sharingRequest(caller: String, capability: String = "inter-app.share") throws -> HanlinMiniAppRequest {
        .init(caller: try .init(validating: caller), target: SwiftParityMiniAppRegistration().appID,
              action: try .init(validating: "share.value"), capability: try .init(validating: capability), payload: .null)
    }

    @Test func canonicalSharingSurvivesViewRegistrationAndReadsActualPrivateState() async throws {
        let (root, storage) = try sharingFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let broker = HanlinMiniAppRequestBroker(limits: .personalHost) { _ in true }
        try await storage.write(Data(#"{"counter":42,"name":"Original private value"}"#.utf8), area: .state, path: "parity.json")
        for _ in 0..<2 {
            // The Host fallback and mounted Swift view use the same registration.
            await SwiftParityMiniAppSharing.register(on: broker, storage: storage)
            for caller in ["hanlin.host", "hanlin.demo.script-parity"] {
                let request = try sharingRequest(caller: caller)
                let response = try await broker.request(request)
                #expect(response.requestID == request.id)
                #expect(response.value == .object(["name": .string("Original private value"), "counter": .integer(42)]))
            }
        }
    }

    @Test func canonicalSharingStillRejectsUnrelatedCallerAndWrongCapability() async throws {
        let (root, storage) = try sharingFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let broker = HanlinMiniAppRequestBroker(limits: .personalHost) { _ in true }
        await SwiftParityMiniAppSharing.register(on: broker, storage: storage)
        do { _ = try await broker.request(sharingRequest(caller: "unrelated.application")); Issue.record("Unrelated caller received private state") }
        catch { #expect(error as? HanlinMiniAppRequestError == .unauthorized) }
        do { _ = try await broker.request(sharingRequest(caller: "hanlin.host", capability: "storage")); Issue.record("Wrong capability reached the route") }
        catch { #expect(error as? HanlinMiniAppRequestError == .capabilityMismatch) }
    }

    @Test func canonicalSharingDoesNotBypassTheHostAuthorizer() async throws {
        let (root, storage) = try sharingFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let broker = HanlinMiniAppRequestBroker(limits: .personalHost) { _ in false }
        await SwiftParityMiniAppSharing.register(on: broker, storage: storage)
        do { _ = try await broker.request(sharingRequest(caller: "hanlin.host")); Issue.record("Denied Host reached private storage") }
        catch { #expect(error as? HanlinMiniAppRequestError == .unauthorized) }
        let events = await broker.auditEvents()
        #expect(events.count == 1 && events.first?.allowed == false && events.first?.outcome == "unauthorized")
    }

    @Test func canonicalSharingNeverRecastsCorruptPersistedStateAsAnEmptySuccess() async throws {
        let (root, storage) = try sharingFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let broker = HanlinMiniAppRequestBroker(limits: .personalHost) { _ in true }
        await SwiftParityMiniAppSharing.register(on: broker, storage: storage)
        try await storage.write(Data("invalid persisted JSON".utf8), area: .state, path: "parity.json")
        do { _ = try await broker.request(sharingRequest(caller: "hanlin.host")); Issue.record("Corrupt data became a successful default result") }
        catch { #expect(error is DecodingError) }
        #expect(try await storage.read(area: .state, path: "parity.json") == Data("invalid persisted JSON".utf8))
    }

    @Test func actualSessionDispatchSavesBeforeOpenAndReceiptBeforeOneTimeAccept() async throws {
        let harness = try SplitAppHarness(); defer { harness.stop() }
        try harness.start()
        let original = try await harness.opened()
        let lifetime = original.expiresAt.timeIntervalSince(original.issuedAt)
        #expect(lifetime > 60 && lifetime <= 120)
        #expect(original.chat == harness.row.id && original.session.rawValue == harness.owner.session?.identity.id.uuidString.lowercased())
        try await harness.complete(original)
        await harness.returnToAI(original)
        #expect(harness.coordinator.acceptedOrigin(forReceivingWindowID: harness.receivingWindowID) == original && harness.coordinator.lastFailure == nil)
        let data = try #require(harness.row.agentSDKRecordData), record = try JSONDecoder().decode(HanlinConversationRecord.self, from: data)
        #expect(record.entries.contains { if case .toolResult(_, let receipt) = $0.payload { return receipt.effectState == .confirmedCommitted && receipt.reconciliationReference?.hasPrefix("hanlin.split.return.v1:" + original.id.uuidString.lowercased()) == true }; return false })
        let task = try #require(harness.streamTask)
        let completed = try await splitBounded { await task.value }
        let modelCalls = await harness.model.counter.value
        #expect(completed && harness.failure == nil)
        #expect(harness.probe.count == 1 && modelCalls == 2 && harness.engineConstructions == 1)
        harness.coordinator.acknowledgeAcceptedOrigin(requestID: original.id, receivingWindowID: harness.receivingWindowID)
        await harness.returnToAI(original)
        #expect(harness.coordinator.acceptedOrigin(forReceivingWindowID: harness.receivingWindowID) == nil && harness.coordinator.lastFailure != nil)
        #expect(try harness.container.mainContext.fetch(FetchDescriptor<ChatRecords>()).count == 1)
    }

    @Test func cancellationWhileOSOpenAwaitsCannotLeaveAnUnresumableHostWaiter() async throws {
        let harness = try SplitAppHarness(cancelWhileOpening: true); defer { harness.stop() }
        try harness.start()
        _ = try await harness.opened()
        let task = try #require(harness.streamTask)
        let completed = try await splitBounded { await task.value }
        #expect(!completed)
        #expect(harness.coordinator.acceptedOrigin(forReceivingWindowID: harness.receivingWindowID) == nil && harness.probe.count == 1)
    }

    @Test func cancellationAfterReceiverStartKeepsOutcomeUnknownAndNeverNavigates() async throws {
        let harness = try SplitAppHarness(); defer { harness.stop() }
        try harness.start()
        let original = try await harness.opened(), receiver = SplitDurableReceiver(persistence: harness.mailbox, source: harness.mailbox)
        _ = try await receiver.receive(reference: original.id, context: SplitAppHarness.context(original), now: .now)
        _ = try await receiver.start(reference: original.id, context: SplitAppHarness.context(original), now: .now)
        harness.owner.cancel()
        let record = try harness.mailbox.transaction { state in
            guard let record = state.records[original.id] else { throw SplitComponentError.missing }; return record
        }
        #expect(record.phase == .outcomeUnknown)
        await harness.returnToAI(original)
        #expect(harness.coordinator.acceptedOrigin(forReceivingWindowID: harness.receivingWindowID) == nil)
        let task = try #require(harness.streamTask)
        _ = try await splitBounded { await task.value }
        #expect(harness.probe.count == 1)
    }

    @Test func deletedOriginalCannotSaveAcceptNavigateOrRecreateAConversation() async throws {
        let harness = try SplitAppHarness(); defer { harness.stop() }
        try harness.start()
        let original = try await harness.opened()
        try await harness.complete(original)
        let context = harness.container.mainContext
        context.delete(harness.row); try context.save()
        await harness.returnToAI(original)
        #expect(harness.coordinator.acceptedOrigin(forReceivingWindowID: harness.receivingWindowID) == nil && harness.coordinator.lastFailure != nil)
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
        #expect(try harness.mailbox.original(original.id) == original) // No mailbox acceptance on failed save/context.
    }

    @Test func deletedOriginalAssistantRowCannotRetargetAnExistingConversation() async throws {
        let harness = try SplitAppHarness(); defer { harness.stop() }
        try harness.start()
        let original = try await harness.opened()
        try await harness.complete(original)
        let context = harness.container.mainContext
        context.delete(harness.assistant); try context.save()
        await harness.returnToAI(original)
        #expect(harness.coordinator.acceptedOrigin(forReceivingWindowID: harness.receivingWindowID) == nil && harness.coordinator.lastFailure != nil)
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ChatMessages>()).isEmpty)
        #expect(try harness.mailbox.original(original.id) == original)
    }

    @Test func anotherIdleOrFailedOwnerCannotHideTheOriginalActiveCanonicalWriter() async throws {
        let harness = try SplitAppHarness(); defer { harness.stop() }
        try harness.start()
        let original = try await harness.opened()
        let context = harness.container.mainContext
        let secondRow = ChatMessages(role: "assistant", text: "", record: harness.row)
        context.insert(secondRow); try context.save()
        let secondOwner = HanlinAppAgentSessionOwner(splitCoordinator: harness.coordinator)
        defer { secondOwner.cancel() }
        let model = SplitComponentModel()
        let config = HanlinChatModelConfiguration(modelID: "second-owner", endpoint: URL(filePath: "/fixture"), apiKey: "", supportsToolUse: false)
        var attemptedEngineCreation = false
        do {
            _ = try await secondOwner.stream(request: .init(conversation: harness.row, conversationID: original.chat,
                sceneID: UUID(), rowID: secondRow.id, uiRunID: UUID(), temporary: false, interaction: nil),
                modelContext: context, configuration: config,
                engineFactory: {
                    attemptedEngineCreation = true
                    return HanlinAISDKAgentEngine(configuration: config, model: .v3(model))
                },
                toolAdapter: nil, messages: [.init(role: .user, text: "Do not conceal the pending original writer")], systemPrompt: nil)
            Issue.record("Unreconciled original operation allowed another model turn")
        } catch { #expect(error as? HanlinHostError == .unresolvedWrite) }
        #expect(!attemptedEngineCreation)
        #expect(harness.coordinator.hasRunningSession(for: original.chat))
        #expect(harness.owner.session?.isRunning == true)
        #expect(secondOwner.session == nil)
        #expect(harness.probe.count == 1)
    }

    @Test func receptionClaimRequiresAnExplicitWindowAndRejectsDuplicatesBeforeAwait() throws {
        let coordinator = HanlinAppSplitOriginCoordinator(), window = UUID(), other = UUID()
        let url = SplitForegroundRoute.returnToAI.url(reference: UUID())
        #expect(coordinator.claimReturn(url, receivingWindowID: nil) == nil)
        #expect(coordinator.lastFailure == .transportUnavailable)
        _ = try #require(coordinator.claimReturn(url, receivingWindowID: window))
        #expect(coordinator.claimReturn(url, receivingWindowID: window) == nil)
        #expect(coordinator.claimReturn(url, receivingWindowID: other) == nil)
        #expect(coordinator.acceptedOrigin(forReceivingWindowID: window) == nil)
        #expect(coordinator.acceptedOrigin(forReceivingWindowID: other) == nil)
        #expect(coordinator.acceptedOrigin(forReceivingWindowID: nil) == nil)
        coordinator.revokeReceivingWindow(other)
        #expect(coordinator.claimReturn(url, receivingWindowID: other) == nil)
        coordinator.revokeReceivingWindow(window)
        _ = try #require(coordinator.claimReturn(url, receivingWindowID: other))
    }

    @Test func expiredOriginalFailsBeforeAnyTargetAuthorityOrStoreLookup() async throws {
        var targetCalls = 0
        let group = FileManager.default.temporaryDirectory.appending(path: "sdk-split-expired-\(UUID().uuidString)", directoryHint: .isDirectory).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: group) }
        let mailbox = try HanlinSplitMailbox(trustedGroupContainer: group)
        let coordinator = HanlinAppSplitOriginCoordinator(mailbox: mailbox, openURL: { _ in Issue.record("Expired OS open"); return false }, targetContext: { request in targetCalls += 1; return SplitAppHarness.context(request) })
        let request = SplitBridgeRequest(caller: try .init(validating: "hanlin.host"), target: try .init(validating: "hanlin.demo.swift-parity"),
            installedPackage: try .init(validating: "compiled.hanlin.demo.swift-parity"), session: try .init(validating: UUID().uuidString.lowercased()),
            chat: UUID(), generation: 0, action: try .init(validating: "share.value"), capability: try .init(validating: "inter-app.share"),
            issuedAt: .now.addingTimeInterval(-60), expiresAt: .now.addingTimeInterval(-1), payload: .null)
        do { _ = try await coordinator.currentContext(for: request); Issue.record("Expired original accepted") }
        catch { #expect(error as? SplitBridgeFailure == .expired) }
        #expect(targetCalls == 0 && coordinator.acceptedOrigin(forReceivingWindowID: nil) == nil)
    }

    @Test func expiredHostAdmissionDeadlineStillRejectsBeforeDispatch() async throws {
        let harness = try SplitAppHarness(); defer { harness.stop() }
        let id = try #require(harness.row.id)
        let namespace = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library", workspace: "swiftdata", space: id.uuidString)
        let context = HanlinHostContext(namespace: namespace, sceneID: harness.scene, generation: UUID(),
            objectReference: id.uuidString, localeIdentifier: Locale.current.identifier)
        let identity = HanlinHostSession(conversationID: id, context: context)
        let store = HanlinAppConversationStore(context: harness.container.mainContext, conversation: harness.row,
            namespace: namespace, conversationID: id, temporary: false)
        let host = HanlinAppHostIntegration(identity: identity, store: store, isCurrent: { true })
        let config = HanlinChatModelConfiguration(modelID: harness.model.modelId, endpoint: URL(filePath: "/fixture"), apiKey: "", supportsToolUse: true)
        let engine = HanlinAISDKAgentEngine(configuration: config, model: .v3(harness.model))
        let session = HanlinAgentSession(identity: identity, host: host, engine: engine, store: store, capabilities: host, interactions: host)
        let invocationID = try HanlinToolInvocationID(validating: UUID().uuidString.lowercased())
        let logicalToolID = HanlinLogicalToolID(providerInstanceID: try .init(validating: "hanlin.host"),
            localToolID: try .init(validating: "open_mini_app"))
        let request = HanlinToolInvocationRequest(id: invocationID, logicalToolID: logicalToolID, aliasUsed: "open_mini_app",
            descriptorRevision: try .init(1), routingTableRevision: .init(1),
            arguments: .object(["target": .string("hanlin.demo.swift-parity"), "action": .string("share.value"), "payload": .null]),
            origin: .assistantModel, idempotencyKey: invocationID.rawValue,
            deadline: Date().addingTimeInterval(-1), limits: try HanlinToolInvocationLimits())
        let invocation = HanlinHostInvocation(request: request, session: identity, runID: UUID(), step: 0,
            providerCallID: "expired-admission-call", writeGuarantee: .hostManagedMutation,
            originalArgumentsJSON: Data(#"{"target":"hanlin.demo.swift-parity","action":"share.value","payload":null}"#.utf8))
        let rowRef = HanlinAppAgentRowReference(rowID: harness.assistant.id, uiRunID: harness.uiRun, messageID: harness.assistant.id)
        do {
            _ = try await harness.coordinator.execute(invocation, host: host, session: session, row: rowRef)
            Issue.record("Expired Host invocation deadline was dispatched")
        } catch {
            #expect(error as? SplitBridgeFailure == .denied)
        }
        #expect(harness.probe.count == 0)
    }

    @Test func preDispatchDeadlineExpiryDuringTargetContextBlocksMailboxAndOSOpen() async throws {
        let clock = SplitTestClock()
        var capturedRequestID: UUID?
        let harness = try SplitAppHarness(now: { clock.now }, onTargetContext: { request, _ in
            capturedRequestID = request.id
            // Advance past the 30s SDK admission deadline while still within the 120s split lifetime.
            clock.now = request.issuedAt.addingTimeInterval(35)
        })
        defer { harness.stop() }
        try harness.start()
        let task = try #require(harness.streamTask)
        let completed = try await splitBounded { await task.value }
        let requestID = try #require(capturedRequestID)
        #expect(completed && harness.failure == nil)
        #expect(harness.probe.count == 0)
        #expect(harness.coordinator.lastFailure == .expired)
        #expect(harness.coordinator.acceptedOrigin(forReceivingWindowID: harness.receivingWindowID) == nil)
        do { _ = try harness.mailbox.original(requestID); Issue.record("Expired pre-dispatch request entered mailbox") }
        catch { #expect(error as? SplitBridgeFailure == .correlationMismatch) }
        let data = try #require(harness.row.agentSDKRecordData)
        let record = try JSONDecoder().decode(HanlinConversationRecord.self, from: data)
        #expect(record.entries.contains {
            if case .toolResult(_, let receipt) = $0.payload { return receipt.effectState == .notDispatched }
            return false
        })
    }

    @Test func consentedReturnSucceedsPastOriginalAdmissionDeadlineWithinSplitLifetime() async throws {
        let clock = SplitTestClock()
        let harness = try SplitAppHarness(now: { clock.now })
        defer { harness.stop() }
        try harness.start()
        let original = try await harness.opened()
        #expect(original.expiresAt.timeIntervalSince(original.issuedAt) == 120)
        try await harness.complete(original)
        // Advance past the original 30s SDK admission deadline but within the minted 120s split lifetime.
        clock.now = original.issuedAt.addingTimeInterval(45)
        await harness.returnToAI(original)
        #expect(harness.coordinator.acceptedOrigin(forReceivingWindowID: harness.receivingWindowID) == original)
        #expect(harness.coordinator.lastFailure == nil)
        let task = try #require(harness.streamTask)
        let completed = try await splitBounded { await task.value }
        #expect(completed && harness.failure == nil)
    }

    @Test func cancellationDuringTargetContextReturnsNotDispatchedWithoutMailboxWrite() async throws {
        var capturedRequestID: UUID?
        let harness = try SplitAppHarness(onTargetContext: { request, owner in
            capturedRequestID = request.id
            owner?.cancel()
        })
        defer { harness.stop() }
        try harness.start()
        let task = try #require(harness.streamTask)
        let completed = try await splitBounded { await task.value }
        let requestID = try #require(capturedRequestID)
        #expect(!completed)
        #expect(harness.probe.count == 0)
        #expect(harness.coordinator.lastFailure == .cancelled)
        #expect(harness.coordinator.acceptedOrigin(forReceivingWindowID: harness.receivingWindowID) == nil)
        do { _ = try harness.mailbox.original(requestID); Issue.record("Cancelled pre-dispatch request entered mailbox") }
        catch { #expect(error as? SplitBridgeFailure == .correlationMismatch) }
    }
}
