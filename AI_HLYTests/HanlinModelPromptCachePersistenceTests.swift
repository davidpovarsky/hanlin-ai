import Foundation
import HanlinChatCore
import HanlinScriptExtensions
import SwiftData
import Testing
@testable import AI_Hanlin

@Suite("Original model prompt-cache persistence")
@MainActor
struct HanlinModelPromptCachePersistenceTests {
    @Test func oldRowsAndOriginalSwiftDataRoundTrip() throws {
        let container = try ModelContainer(for: AllModels.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let row = AllModels(name: "claude", displayName: "Claude", position: 0, company: "ANTHROPIC")
        #expect(row.promptCachePolicy == nil)
        context.insert(row)
        let policy = HanlinPromptCachePolicy(anthropicTTL: .oneHour)
        try row.setPromptCachePolicy(policy)
        try context.save()
        let reloaded = try #require(ModelContext(container).fetch(FetchDescriptor<AllModels>()).first)
        #expect(reloaded.promptCachePolicy == policy)
        #expect(HanlinApplicationModel(reloaded).promptCachePolicy == policy)
        try reloaded.setPromptCachePolicy(nil)
        #expect(reloaded.promptCachePolicyJSON == nil)
    }

    @Test func scopedResourcesCannotReplaceGlobalPreferences() throws {
        let row = AllModels(name: "gemini-2.5-flash", displayName: "Gemini", position: 0, company: "GOOGLE")
        try row.setPromptCachePolicy(.providerDefault)
        let before = row.promptCachePolicyJSON
        let scoped = HanlinGoogleCachedContentReference(name: "cachedContents/test", modelID: "gemini-2.5-flash",
            expiresAt: .distantFuture, scopeKey: "conversation-a")
        #expect(throws: HanlinModelPromptCachePreferenceError.self) {
            try row.setPromptCachePolicy(.init(googleCachedContent: scoped))
        }
        #expect(row.promptCachePolicyJSON == before)
        #expect(throws: HanlinModelPromptCachePreferenceError.self) {
            try row.setPromptCachePolicy(.init(openAI: .init(comparisonResponseID: "resp_other_conversation")))
        }
        #expect(row.promptCachePolicyJSON == before)
    }

    @Test func compactConfigurationPreservesPreferencesAndLegacyDecoding() throws {
        let policy = HanlinPromptCachePolicy(openAI: .init(retention: .twentyFourHours))
        let original = HanlinCompactAgentConfiguration(endpoint: URL(string: "https://api.openai.com/v1")!,
            apiKey: "", credentialReference: "protected-test-handle", modelID: "gpt-test",
            promptCachePolicy: policy)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(HanlinCompactAgentConfiguration.self, from: data)
        #expect(restored.promptCachePolicy == policy)
        #expect(try restored.resolvedChatModelConfiguration(using: { _ in "test-only-secret" }).promptCachePolicy == policy)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "promptCachePolicy")
        let older = try JSONDecoder().decode(HanlinCompactAgentConfiguration.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        #expect(older.promptCachePolicy == nil)
        #expect(older.credentialReference == original.credentialReference)
    }
}
