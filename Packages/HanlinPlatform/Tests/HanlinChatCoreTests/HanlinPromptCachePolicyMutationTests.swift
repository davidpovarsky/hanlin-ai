import Testing
@testable import HanlinChatCore

@Suite("Agent prompt cache policy inheritance")
struct HanlinPromptCachePolicyMutationTests {
    private let custom = HanlinPromptCachePolicy(
        openAI: .init(mode: .implicit, ttl: .thirtyMinutes)
    )

    @Test
    func unchangedWireModelAndProviderPreserveSavedCustomPolicy() {
        // Internal duplicate/agent identifiers must not count as a base change.
        // Preserve means the caller leaves even unknown serialized fields intact.
        let mutation = HanlinPromptCachePolicyMutation.resolve(
            originalModelID: "gpt-6.2-sol_hanlin_repeat_duplicate_agent_original",
            originalCompany: "openai",
            selectedBaseModelID: "gpt-6.2-sol_hanlin",
            selectedBaseCompany: "OPENAI",
            selectedBasePolicy: .providerDefault,
            selection: nil
        )
        #expect(mutation == .preserve)
        #expect(HanlinPromptCachePreset.matching(custom) == nil)
        #expect(resolve(baseID: nil, basePolicy: .providerDefault) == .preserve)
    }

    @Test
    func changedModelOrProviderInheritsSelectedBasePolicyIncludingAutomatic() {
        #expect(resolve(baseID: "gpt-5.5", basePolicy: custom) == .replace(custom))
        #expect(resolve(baseID: "gpt-5.5", basePolicy: nil) == .replace(nil))
        #expect(resolve(baseCompany: "CUSTOM", basePolicy: .noExplicitCaching)
            == .replace(.noExplicitCaching))
    }

    @Test
    func explicitPresetOverridesBaseInheritanceAndAutomaticClearsSavedOverride() {
        #expect(resolve(
            baseID: "gpt-5.5", basePolicy: custom, selection: .preset(.providerDefault)
        ) == .replace(.providerDefault))
        #expect(resolve(
            baseID: "gpt-5.5", basePolicy: custom, selection: .preset(.automatic)
        ) == .replace(nil))
        #expect(resolve(
            baseID: nil, basePolicy: nil, selection: .preset(.noExplicitCaching)
        ) == .replace(.noExplicitCaching))
    }

    @Test
    func explicitPreserveOverridesRebindAndExplicitInheritanceCanRefreshUnchangedBase() {
        #expect(resolve(
            baseID: "gpt-5.5", basePolicy: .providerDefault, selection: .preserveSaved
        ) == .preserve)
        #expect(resolve(basePolicy: custom, selection: .inheritBase) == .replace(custom))
        #expect(resolve(basePolicy: nil, selection: .inheritBase) == .replace(nil))
        #expect(resolve(baseID: nil, basePolicy: custom, selection: .inheritBase) == .preserve)
    }

    private func resolve(
        baseID: String? = "gpt-6.2-sol",
        baseCompany: String? = "OPENAI",
        basePolicy: HanlinPromptCachePolicy?,
        selection: HanlinPromptCachePolicySelection? = nil
    ) -> HanlinPromptCachePolicyMutation {
        HanlinPromptCachePolicyMutation.resolve(
            originalModelID: "gpt-6.2-sol_agent_existing",
            originalCompany: "OPENAI",
            selectedBaseModelID: baseID,
            selectedBaseCompany: baseCompany,
            selectedBasePolicy: basePolicy,
            selection: selection
        )
    }
}
