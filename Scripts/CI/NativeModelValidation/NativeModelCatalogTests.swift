import Foundation
import SwiftData
import Testing
import HanlinAgentCore
import HanlinChatCore
@testable import HanlinNativeModelCatalog

@Suite @MainActor struct NativeModelCatalogTests {
    private func store() throws -> ModelContainer {
        try ModelContainer(for: AllModels.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func registrationIsIdempotentAndAppendsWithoutReorderingExistingRows() throws {
        let container = try store()
        let context = container.mainContext
        let first = AllModels(name: "first", displayName: "First", position: 3, company: "OPENAI")
        let second = AllModels(name: "second", displayName: "Second", position: 8, company: "CUSTOM")
        context.insert(first); context.insert(second); try context.save()
        let original = try context.fetch(FetchDescriptor<AllModels>(sortBy: [SortDescriptor(\.position)]))
        let row = try HanlinAppleModelCatalogAdapter.register(in: context)
        let repeated = try HanlinAppleModelCatalogAdapter.register(in: context)
        let all = try context.fetch(FetchDescriptor<AllModels>(sortBy: [SortDescriptor(\.position)]))
        #expect(all.count == 3 && all.prefix(2).map(\.id) == original.map(\.id))
        #expect(row.id == repeated.id && row.id == HanlinAppleModelCatalogAdapter.catalogID)
        #expect(row.position == 9 && first.position == 3 && second.position == 8)
        #expect(!row.isHidden && !row.systemProvision && row.supportsTextGen)
        #expect(HanlinDefaultChatPolicy.defaultModelIndex(in: [row]) == nil)
        #expect(HanlinDefaultChatPolicy.defaultModel(in: [row]) == nil)
        #expect(HanlinDefaultChatPolicy.defaultModelIndex(in: all) == 0)
        #expect(!row.supportsToolUse && !row.supportsReasoning && !row.supportsMultimodal)
        #expect(!row.supportsSearch && !row.supportsVoiceGen && !row.supportsImageGen)
    }

    @Test func reservedNameConflictPreservesOriginalCatalog() throws {
        let container = try store(); let context = container.mainContext
        let custom = AllModels(name: HanlinAppleOnDeviceProvider.modelID, displayName: "User row", position: 0, company: "CUSTOM", systemProvision: false)
        context.insert(custom); try context.save()
        #expect(throws: HanlinAISDKError.self) { try HanlinAppleModelCatalogAdapter.register(in: context) }
        let all = try context.fetch(FetchDescriptor<AllModels>())
        #expect(all.count == 1 && all.first?.id == custom.id && custom.company == "CUSTOM")
    }

    @Test func nativeConfigurationUsesActualAvailabilityWithoutCredentialsOrFallback() throws {
        let container = try store(); let context = container.mainContext
        let row = try HanlinAppleModelCatalogAdapter.register(in: context)
        #expect(HanlinAppleModelCatalogAdapter.isNative(row))
        if HanlinAppleOnDeviceProvider.availability == .available {
            let configuration = try HanlinAppleModelCatalogAdapter.configuration(for: row)
            #expect(configuration.apiKey.isEmpty && configuration.endpoint.isFileURL)
            #expect(!configuration.supportsToolUse && !configuration.supportsReasoning)
            let engine = try HanlinAppleOnDeviceProvider.makeEngine(configuration: configuration)
            _ = engine // Compilation/composition only; no model generation is claimed.
        } else {
            #expect(throws: HanlinAppleProviderError.unavailable) { try HanlinAppleModelCatalogAdapter.configuration(for: row) }
        }
        row.supportsToolUse = true
        #expect(throws: HanlinAISDKError.self) { try HanlinAppleModelCatalogAdapter.configuration(for: row) }
    }
}
