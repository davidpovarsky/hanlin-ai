import Foundation
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
}
