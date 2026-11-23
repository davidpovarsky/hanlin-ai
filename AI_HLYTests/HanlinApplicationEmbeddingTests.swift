import Foundation
import HanlinHostContracts
import Security
import SwiftData
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Original application embedding")
struct HanlinApplicationEmbeddingTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: APIKeys.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func providerFixture() throws -> (ModelContainer, HanlinApplicationModelAccess, HanlinApplicationCredentials) {
        let container = try ModelContainer(for: APIKeys.self, AllModels.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let policy = HanlinApplicationCredentials(service: "hanlin.preload.tests." + UUID().uuidString)
        HanlinApplicationCredentialRegistry.shared.register(container, credentials: policy)
        return (container, .init(context: container.mainContext), policy)
    }

    private func removeFixtureCredentials(_ policy: HanlinApplicationCredentials) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: policy.service] as CFDictionary)
    }

    @Test
    func providerCredentialLookupUsesTheRecordsContainer() throws {
        let app = "hanlin.embedding.tests." + UUID().uuidString.lowercased()
        let firstPolicy = HanlinApplicationConfiguration(
            appIdentifier: app, accountIdentifier: "first").credentials
        let secondPolicy = HanlinApplicationConfiguration(
            appIdentifier: app, accountIdentifier: "second").credentials
        let first = try container()
        let second = try container()
        HanlinApplicationCredentialRegistry.shared.register(first, credentials: firstPolicy)
        HanlinApplicationCredentialRegistry.shared.register(second, credentials: secondPolicy)
        defer {
            for policy in [firstPolicy, secondPolicy] {
                SecItemDelete([
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: policy.service
                ] as CFDictionary)
            }
        }

        let reference = try firstPolicy.store.stage("synthetic-host-credential",
            kind: .model, previousStoredValue: nil)
        let firstRecord = APIKeys(company: "fixture", key: reference)
        let secondRecord = APIKeys(company: "fixture", key: reference)
        first.mainContext.insert(firstRecord)
        second.mainContext.insert(secondRecord)
        try first.mainContext.save()
        try second.mainContext.save()

        #expect(try HanlinAppProviderCredentials.shared.resolve(firstRecord) == "synthetic-host-credential")
        #expect(throws: (any Error).self) {
            try HanlinAppProviderCredentials.shared.resolve(secondRecord)
        }
        // Opening/reading the second container must not change the first one.
        #expect(try HanlinAppProviderCredentials.shared.resolve(firstRecord) == "synthetic-host-credential")
    }

    @Test
    func originalRuntimeCannotBeRedirectedToAnotherContainer() throws {
        let runtime = HanlinApplicationProcessRuntime()
        let first = try container()
        let second = try container()
        let configuration = HanlinApplicationRuntimeConfiguration(
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
            mcpSecretService: "fixture.mcp", environmentSecretService: "fixture.environment")
        try runtime.install(configuration, modelContainer: first)
        try runtime.install(configuration, modelContainer: first)
        #expect(throws: HanlinApplicationError.self) {
            try runtime.install(configuration, modelContainer: second)
        }
        #expect(runtime.configuration == configuration)
    }

    @Test
    func programmaticProviderAndModelUseOriginalRowsAndProtectedWriter() throws {
        let container = try ModelContainer(for: APIKeys.self, AllModels.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let policy = HanlinApplicationCredentials(service: "hanlin.model-api.tests." + UUID().uuidString)
        HanlinApplicationCredentialRegistry.shared.register(container, credentials: policy)
        defer {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: policy.service] as CFDictionary)
        }
        let access = HanlinApplicationModelAccess(context: container.mainContext)
        var configuration = HanlinApplicationProviderConfiguration(identifier: "CUSTOM_FIXTURE",
            displayName: "Host provider", endpoint: URL(string: "https://example.invalid/v1/chat/completions"))
        let provider = try access.createProvider(configuration, credential: "synthetic-first")
        #expect(provider.usesProtectedCredentialStorage)
        #expect(!provider.isBuiltIn)
        #expect(try access.providerCredential(provider.id) == "synthetic-first")
        let originalProvider = try access.provider(provider.id)
        let firstReference = originalProvider.key
        #expect(firstReference != "synthetic-first")
        configuration.displayName = "Renamed host provider"
        configuration.api = .anthropic
        let renamed = try access.updateProvider(configuration)
        #expect(renamed.id == provider.id)
        #expect(originalProvider.apiType == .anthropic)
        #expect(originalProvider.key == firstReference)
        try access.setProviderCredential("synthetic-rotated", provider: provider.id)
        #expect(originalProvider.key != firstReference)
        #expect(try access.providerCredential(provider.id) == "synthetic-rotated")
        try access.setProviderCredential("", provider: provider.id)
        #expect(try access.providerCredential(provider.id) == "")

        let capabilities = HanlinApplicationModelCapabilities(tools: true, search: true,
            reasoning: true, adjustableReasoning: true, imageInput: true)
        let created = try access.createModel(modelID: "fixture-model", displayName: "Host model",
            provider: provider.id, capabilities: capabilities, isHidden: false)
        #expect(created.baseModelID == "fixture-model")
        #expect(created.modelID == "fixture-model_repeat_CUSTOM_FIXTURE")
        #expect(created.capabilities == capabilities)
        #expect(!created.isBuiltIn)
        let changed = try access.updateModel(created.id, displayName: "Renamed model",
            capabilities: nil, isHidden: true, position: 12)
        #expect(changed.id == created.id)
        #expect(changed.modelID == created.modelID)
        #expect(changed.displayName == "Renamed model")
        #expect(changed.isHidden && changed.position == 12)
        let namesake = AllModels(name: created.modelID, displayName: "A distinct original row",
            position: 13, company: provider.id, systemProvision: false)
        container.mainContext.insert(namesake)
        try container.mainContext.save()
        try access.deleteModel(created.id)
        #expect(throws: HanlinApplicationModelConfigurationError.self) { try access.model(created.id) }
        #expect(try access.model(namesake.id).displayName == "A distinct original row")
        try access.deleteProvider(provider.id)
        #expect(try access.providers().isEmpty)
        #expect(try access.model(namesake.id).id == namesake.id)
    }

    @Test
    func hostConstructedActivitySnapshotPreservesIdentityAndOriginalPayloads() throws {
        let id = UUID()
        let group = UUID()
        let date = Date(timeIntervalSince1970: 1234)
        let images = [Data([0, 1, 255])]
        let snapshot = HanlinConversationMessageSnapshot(id: id, text: "Observed answer",
            reasoning: "Observed reasoning", toolContent: "Observed tool result", toolName: "host-tool",
            imageData: try JSONEncoder().encode(images), nativeUIBlocksJSON: "[]",
            agentRunJSON: "{\"hostFixture\":true}", presentationSnapshot: Data([3, 2, 1]),
            groupID: group, timestamp: date, finishReason: "stop")
        #expect(snapshot.id == id && snapshot.groupID == group && snapshot.timestamp == date)
        #expect(snapshot.toolContent == "Observed tool result")
        #expect(snapshot.agentRunJSON == "{\"hostFixture\":true}")
        #expect(snapshot.presentationSnapshot == Data([3, 2, 1]))
        #expect(try snapshot.decodedImageData() == images)
        #expect(HanlinConversationMessageSnapshot(id: id).groupID == id)
        _ = HanlinToolActivityView(message: snapshot)
    }

    @Test
    func providerPreloadingPreservesDistinctRoutingIdentitiesWithEqualNames() throws {
        let (container, access, policy) = try providerFixture()
        defer { removeFixtureCredentials(policy) }
        for identifier in ["HOST_FIRST", "HOST_SECOND"] {
            try access.createProvider(.init(identifier: identifier, displayName: "Same display name",
                endpoint: URL(string: "https://example.invalid/" + identifier)), credential: "synthetic-" + identifier)
        }
        let first = try access.provider("HOST_FIRST"), second = try access.provider("HOST_SECOND")
        let firstID = first.persistentModelID, secondID = second.persistentModelID
        let firstKey = first.key, secondKey = second.key
        preloadAPIKeysIfNeeded(context: container.mainContext)
        #expect(try access.provider("HOST_FIRST").persistentModelID == firstID)
        #expect(try access.provider("HOST_SECOND").persistentModelID == secondID)
        #expect(first.key == firstKey && second.key == secondKey)
        #expect(try access.providerCredential("HOST_FIRST") == "synthetic-HOST_FIRST")
        #expect(try access.providerCredential("HOST_SECOND") == "synthetic-HOST_SECOND")
    }

    @Test
    func providerPreloadingKeepsCustomBuiltinRoutingOverride() throws {
        let (container, access, policy) = try providerFixture()
        defer { removeFixtureCredentials(policy) }
        try access.createProvider(.init(identifier: "OPENAI", displayName: "Host-owned route",
            endpoint: URL(string: "https://example.invalid/messages"), api: .anthropic), credential: "synthetic-host-route")
        let original = try access.provider("OPENAI")
        let id = original.persistentModelID, reference = original.key
        preloadAPIKeysIfNeeded(context: container.mainContext)
        preloadAPIKeysIfNeeded(context: container.mainContext)
        let restored = try access.provider("OPENAI") // Exactly one original routing identity.
        #expect(restored.persistentModelID == id && restored.key == reference)
        #expect(restored.name == "Host-owned route" && restored.from == .custom)
        #expect(restored.requestURL == "https://example.invalid/messages" && restored.apiType == .anthropic)
        #expect(try access.providerCredential("OPENAI") == "synthetic-host-route")
    }

    @Test
    func providerPreloadingPreservesRenamedBuiltinCredentials() throws {
        let (container, access, policy) = try providerFixture()
        defer { removeFixtureCredentials(policy) }
        preloadAPIKeysIfNeeded(context: container.mainContext)
        try access.setProviderCredential("synthetic-builtin", provider: "OPENAI")
        let original = try access.provider("OPENAI")
        let id = original.persistentModelID, reference = original.key
        var configuration = HanlinApplicationProvider(original).configuration
        configuration.displayName = "Renamed by the host"
        try access.updateProvider(configuration)
        preloadAPIKeysIfNeeded(context: container.mainContext)
        let restored = try access.provider("OPENAI")
        #expect(restored.persistentModelID == id && restored.key == reference)
        #expect(restored.name == "Renamed by the host" && restored.from == .system)
        #expect(try access.providerCredential("OPENAI") == "synthetic-builtin")
    }

    @Test
    func explicitBuiltinRequestOverrideStaysHostOwnedDuringPreload() throws {
        let (container, access, policy) = try providerFixture()
        defer { removeFixtureCredentials(policy) }
        preloadAPIKeysIfNeeded(context: container.mainContext)
        try access.setProviderCredential("synthetic-custom-endpoint", provider: "OPENAI")
        let original = try access.provider("OPENAI")
        let id = original.persistentModelID, reference = original.key
        var configuration = HanlinApplicationProvider(original).configuration
        configuration.endpoint = URL(string: "https://example.invalid/v1/messages")
        configuration.api = .anthropic
        try access.updateProvider(configuration)
        preloadAPIKeysIfNeeded(context: container.mainContext)
        let restored = try access.provider("OPENAI")
        #expect(restored.persistentModelID == id && restored.key == reference)
        #expect(restored.from == .custom && restored.apiType == .anthropic)
        #expect(restored.requestURL == configuration.endpoint?.absoluteString)
        #expect(try access.providerCredential("OPENAI") == "synthetic-custom-endpoint")
    }

    @Test
    func providerPreloadingRetainsAmbiguousLegacyCredentialRows() throws {
        let (container, access, policy) = try providerFixture()
        defer { removeFixtureCredentials(policy) }
        let first = APIKeys(name: "Legacy first", company: "OPENAI", requestURL: "https://first.invalid")
        let second = APIKeys(name: "Legacy second", company: "OPENAI", requestURL: "https://second.invalid")
        try HanlinAppProviderCredentials.shared.insert(first, value: "synthetic-first", in: container.mainContext)
        try HanlinAppProviderCredentials.shared.insert(second, value: "synthetic-second", in: container.mainContext)
        let firstID = first.persistentModelID, secondID = second.persistentModelID
        let firstKey = first.key, secondKey = second.key
        preloadAPIKeysIfNeeded(context: container.mainContext)
        #expect(throws: HanlinApplicationModelConfigurationError.self) { try access.provider("OPENAI") }
        let rows = try container.mainContext.fetch(FetchDescriptor<APIKeys>()).filter { $0.company == "OPENAI" }
        #expect(Set(rows.map(\.persistentModelID)) == Set([firstID, secondID]))
        #expect(first.key == firstKey && second.key == secondKey)
        #expect(first.requestURL == "https://first.invalid" && second.requestURL == "https://second.invalid")
        #expect(try HanlinAppProviderCredentials.shared.resolve(first) == "synthetic-first")
        #expect(try HanlinAppProviderCredentials.shared.resolve(second) == "synthetic-second")
    }

    @Test
    func modelPreloadingKeepsCustomMetadataForMatchingCatalogName() throws {
        let (container, _, policy) = try providerFixture()
        defer { removeFixtureCredentials(policy) }
        let catalog = try #require(getModelList().first { $0.name?.isEmpty == false && $0.company != "LOCAL" })
        let model = AllModels(name: catalog.name, displayName: "Host-owned model",
            position: 900, company: "HOST_ROUTING_ID", price: -1, isHidden: true,
            supportsSearch: !catalog.supportsSearch, supportsTextGen: !catalog.supportsTextGen,
            supportsMultimodal: !catalog.supportsMultimodal, supportsReasoning: !catalog.supportsReasoning,
            supportReasoningChange: !catalog.supportReasoningChange, supportsImageGen: !catalog.supportsImageGen,
            supportsVoiceGen: !catalog.supportsVoiceGen, supportsToolUse: !catalog.supportsToolUse,
            systemProvision: false)
        container.mainContext.insert(model)
        try container.mainContext.save()
        let id = model.id, capabilities = HanlinApplicationModelCapabilities(model)
        preloadModelDataIfNeeded(context: container.mainContext)
        let rows = try container.mainContext.fetch(FetchDescriptor<AllModels>()).filter { $0.id == id }
        #expect(rows.count == 1)
        #expect(model.company == "HOST_ROUTING_ID" && model.displayName == "Host-owned model")
        #expect(model.position == 900 && model.price == -1 && model.isHidden)
        #expect(HanlinApplicationModelCapabilities(model) == capabilities)
    }
    @Test
    func modelPreloadingPreservesDistinctCustomRowsWithEqualNames() throws {
        let (container, _, policy) = try providerFixture()
        defer { removeFixtureCredentials(policy) }
        let first = AllModels(name: "legacy-shared-name", displayName: "First custom model",
            position: 900, company: "HOST_FIRST", supportsToolUse: true, systemProvision: false)
        let second = AllModels(name: "legacy-shared-name", displayName: "Second custom model",
            position: 901, company: "HOST_SECOND", supportsReasoning: true, systemProvision: false)
        let malformed = AllModels(name: nil, displayName: "Retained legacy custom metadata",
            position: 902, company: "HOST_LEGACY", systemProvision: false)
        for model in [first, second, malformed] { container.mainContext.insert(model) }
        try container.mainContext.save()
        let ids = Set([first.id, second.id, malformed.id])
        preloadModelDataIfNeeded(context: container.mainContext)
        let retained = try container.mainContext.fetch(FetchDescriptor<AllModels>()).filter { ids.contains($0.id) }
        #expect(Set(retained.map(\.id)) == ids)
        #expect(first.company == "HOST_FIRST" && first.supportsToolUse)
        #expect(second.company == "HOST_SECOND" && second.supportsReasoning)
        #expect(malformed.displayName == "Retained legacy custom metadata")
    }

    @Test
    func modelPreloadingRetainsBuiltinCustomNameCollision() throws {
        let (container, _, policy) = try providerFixture()
        defer { removeFixtureCredentials(policy) }
        let builtin = try #require(getModelList().first { $0.name?.isEmpty == false && $0.company != "LOCAL" })
        let custom = AllModels(name: builtin.name, displayName: "Host-owned collision",
            position: 900, company: "HOST_ROUTING_ID", price: -1, isHidden: true,
            supportsToolUse: !builtin.supportsToolUse, systemProvision: false)
        container.mainContext.insert(builtin)
        container.mainContext.insert(custom)
        try container.mainContext.save()
        let ids = Set([builtin.id, custom.id])
        let company = builtin.company, capabilities = HanlinApplicationModelCapabilities(custom)
        preloadModelDataIfNeeded(context: container.mainContext)
        let retained = try container.mainContext.fetch(FetchDescriptor<AllModels>()).filter { ids.contains($0.id) }
        #expect(Set(retained.map(\.id)) == ids)
        #expect(builtin.company == company && builtin.systemProvision)
        #expect(custom.company == "HOST_ROUTING_ID" && custom.price == -1 && custom.isHidden)
        #expect(!custom.systemProvision && HanlinApplicationModelCapabilities(custom) == capabilities)
    }

    @Test
    func conversationMetadataMutatesOnlyTheOriginalRowsAndPreservesAnnouncement() throws {
        let container = try ModelContainer(for: ChatRecords.self, ChatMessages.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let original = ChatRecords(name: "Equal original title", type: "chat", input: "Unsent original draft")
        let namesake = ChatRecords(name: "Equal original title", type: "chat")
        context.insert(original); context.insert(namesake)
        try context.save()
        let originalID = original.persistentModelID, namesakeID = namesake.persistentModelID
        let announcement = try #require(HanlinConversationMutation.rename(original, title: "Renamed שלום",
            announceChange: true, in: context))
        try HanlinConversationMutation.setPinned(original, isPinned: true, in: context)
        #expect(original.persistentModelID == originalID && original.isPinned)
        #expect(original.name == "Renamed שלום" && original.input == "Unsent original draft")
        #expect(namesake.persistentModelID == namesakeID && namesake.name == "Equal original title" && !namesake.isPinned)
        #expect(announcement.role == "information" && announcement.record === original)
        let chinese = (Locale.preferredLanguages.first ?? "zh-Hans").hasPrefix("zh")
        #expect(announcement.text == (chinese ? "群聊名称被修改为“Renamed שלום”"
            : "Group chat name has been changed to \"Renamed שלום\""))
        #expect(try HanlinConversationMutation.rename(original, title: "Renamed שלום",
            announceChange: true, in: context) == nil)
        #expect(try context.fetch(FetchDescriptor<ChatMessages>()).count == 1)
        #expect(throws: HanlinConversationMutationError.emptyTitle) {
            try HanlinConversationMutation.rename(original, title: "", announceChange: true, in: context)
        }
        let temporary = ChatRecords(name: "Detached temporary title", type: "chat")
        try HanlinConversationMutation.rename(temporary, title: "Renamed temporary title",
            announceChange: false, in: context, temporary: true)
        #expect(temporary.name == "Renamed temporary title" && temporary.modelContext == nil)
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<ChatMessages>()).count == 1)
    }

    @Test
    func conversationDeletionRevokesPreparationAndRejectsLateProjection() throws {
        let container = try ModelContainer(for: ChatRecords.self, ChatMessages.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let original = ChatRecords(name: "Original pending turn", type: "chat")
        let assistant = ChatMessages(role: "assistant", text: "Partial original answer", record: original)
        context.insert(original); context.insert(assistant); try context.save()
        let id = try #require(original.id), owner = HanlinAppAgentSessionOwner()
        let request = HanlinAppAgentSessionOwner.Request(conversation: original, conversationID: id,
            sceneID: UUID(), rowID: assistant.id, uiRunID: UUID(), temporary: false, interaction: nil)
        let access = try owner.prepareDataAccess(request: request, modelContext: context)
        let lease = try HanlinConversationRunLease.acquire(container: container, conversationID: id)
        let coordinator = AgentRunCoordinator(groupID: assistant.groupID, providerID: "fixture", modelID: "fixture")
        let projection = HanlinConversationStreamProjection(record: original, context: context,
            messages: [assistant], assistant: assistant, coordinator: coordinator, lease: lease)
        var revokedBeforeDelete = false
        lease.onRevoke {
            revokedBeforeDelete = lease.isRevoked && !original.isDeleted
            #expect(throws: HanlinHostError.staleContext) {
                try owner.requireDataAccess(access, request: request, modelContext: context)
            }
        }
        try HanlinConversationMutation.delete(original, in: context)
        #expect(revokedBeforeDelete)
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChatMessages>()).isEmpty)
        projection.consume(StreamData(content: "Late answer must not return"))
        #expect(throws: CancellationError.self) { try projection.finish() }
        projection.fail(HanlinHostError.cancelled)
        projection.cancel()
        #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChatMessages>()).isEmpty)

        let replacement = ChatRecords(id: id, name: "Distinct replacement row", type: "chat")
        context.insert(replacement); try context.save()
        let next = try HanlinConversationRunLease.acquire(container: container, conversationID: id)
        defer { next.release() }
        lease.release()
        #expect(throws: HanlinHostError.duplicateInvocation) {
            try HanlinConversationRunLease.acquire(container: container, conversationID: id)
        }
        #expect(replacement.agentSDKRecordData == nil)
    }

    @Test
    func conversationMutationRejectsAForeignContainerBeforeRevocation() throws {
        @MainActor func database() throws -> ModelContainer {
            try ModelContainer(for: ChatRecords.self, ChatMessages.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
        let first = try database(), second = try database(), id = UUID()
        let firstRow = ChatRecords(id: id, name: "First account row", type: "chat")
        let secondRow = ChatRecords(id: id, name: "Second account row", type: "chat")
        first.mainContext.insert(firstRow); second.mainContext.insert(secondRow)
        try first.mainContext.save(); try second.mainContext.save()
        let firstLease = try HanlinConversationRunLease.acquire(container: first, conversationID: id)
        let secondLease = try HanlinConversationRunLease.acquire(container: second, conversationID: id)
        defer { firstLease.release(); secondLease.release() }
        #expect(throws: HanlinHostError.staleContext) {
            try HanlinConversationMutation.delete(firstRow, in: second.mainContext)
        }
        #expect(!firstLease.isRevoked && !secondLease.isRevoked)
        try HanlinConversationMutation.delete(firstRow, in: first.mainContext)
        #expect(firstLease.isRevoked && !secondLease.isRevoked)
        #expect(try second.mainContext.fetch(FetchDescriptor<ChatRecords>()).first === secondRow)
    }

    @Test
    func conversationMetadataAndDeletionReturnSaveFailuresAndRollback() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "hanlin-mutation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Original.store")
        @MainActor func database(allowsSave: Bool) throws -> ModelContainer {
            try ModelContainer(for: ChatRecords.self, ChatMessages.self,
                configurations: ModelConfiguration(url: url, allowsSave: allowsSave, cloudKitDatabase: .none))
        }
        @MainActor func seed() throws {
            let container = try database(allowsSave: true)
            let row = ChatRecords(name: "Durable original title", type: "chat", input: "Durable unsent draft")
            let message = ChatMessages(role: "user", text: "Durable original history", record: row)
            container.mainContext.insert(row); container.mainContext.insert(message)
            try container.mainContext.save()
        }
        try seed()
        let container = try database(allowsSave: false), context = container.mainContext
        context.autosaveEnabled = false
        let row = try #require(context.fetch(FetchDescriptor<ChatRecords>()).first)
        let operations: [@MainActor () throws -> Void] = [
            { _ = try HanlinConversationMutation.rename(row, title: "Must not persist", announceChange: true, in: context) },
            { try HanlinConversationMutation.setPinned(row, isPinned: true, in: context) },
            { try HanlinConversationMutation.delete(row, in: context) }
        ]
        for operation in operations {
            do { try operation(); Issue.record("Read-only original store reported mutation success") }
            catch { #expect(!context.hasChanges) }
            #expect(row.name == "Durable original title" && row.input == "Durable unsent draft" && !row.isPinned)
            #expect(try context.fetch(FetchDescriptor<ChatRecords>()).count == 1)
            #expect(try context.fetch(FetchDescriptor<ChatMessages>()).map(\.text) == ["Durable original history"])
        }
    }

}
