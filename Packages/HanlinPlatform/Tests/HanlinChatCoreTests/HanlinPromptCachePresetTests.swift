import Foundation
import Testing
@testable import HanlinChatCore

@Suite("Prompt cache settings presets")
struct HanlinPromptCachePresetTests {
    private let native = URL(string: "https://api.openai.com/v1/responses")!

    @Test
    func defaultsAndCustomPoliciesPreserveMigrationSemantics() {
        #expect(HanlinPromptCachePreset.automatic.policy == nil)
        #expect(HanlinPromptCachePreset.matching(nil) == .automatic)
        #expect(HanlinPromptCachePreset.matching(.automatic) == .automatic)
        #expect(HanlinPromptCachePreset.matching(.providerDefault) == .providerDefault)
        #expect(HanlinPromptCachePreset.matching(.noExplicitCaching) == .noExplicitCaching)
        let custom = HanlinPromptCachePolicy(openAI: .init(mode: .implicit, ttl: .thirtyMinutes))
        #expect(HanlinPromptCachePreset.matching(custom) == nil)
        let scopedDiagnostic = HanlinPromptCachePolicy(openAI: .init(comparisonResponseID: "resp_scoped"))
        #expect(HanlinPromptCachePreset.matching(scopedDiagnostic) == nil)
        for preset in HanlinPromptCachePreset.allCases {
            #expect(preset.policy?.googleCachedContent == nil)
            #expect(preset.policy?.openAI?.comparisonResponseID == nil)
        }
    }

    @Test
    func nativeLegacyRetentionAndModernExplicitLifetimeAreDistinct() {
        let legacy = HanlinPromptCachePreset.available(
            company: "OPENAI", apiType: "OpenAI-Response", endpoint: native, modelID: "gpt-5.5"
        )
        #expect(legacy.contains(.openAITwentyFourHours))
        #expect(!legacy.contains(.openAIExplicitThirtyMinutes))
        let modern = HanlinPromptCachePreset.available(
            company: "OPENAI", apiType: "OpenAI-Response", endpoint: native, modelID: "gpt-6.2-sol"
        )
        #expect(!modern.contains(.openAITwentyFourHours))
        #expect(modern.contains(.openAIExplicitThirtyMinutes))
        #expect(modern.contains(.openAIExplicitTwelveHours))
        #expect(HanlinPromptCachePreset.available(
            company: "OPENAI", apiType: "openAIResponse", endpoint: native, modelID: "gpt-6.2-sol"
        ) == modern)
        #expect(HanlinPromptCachePreset.openAIExplicitTwelveHours.policy?.openAI?.ttl == .twelveHours)
        #expect(HanlinPromptCachePreset.openAITwentyFourHours.policy?.openAI?.retention == .twentyFourHours)
    }

    @Test
    func nativeChatDoesNotOfferResponsesOnlyExplicitPresets() {
        let presets = HanlinPromptCachePreset.available(
            company: "OPENAI", apiType: "OpenAI", endpoint: native, modelID: "gpt-6.2-sol"
        )
        #expect(presets == [.automatic, .providerDefault, .noExplicitCaching])
        let legacy = HanlinPromptCachePreset.available(
            company: "OPENAI", apiType: "OpenAI", endpoint: native, modelID: "gpt-4.1-2025-04-14"
        )
        #expect(legacy.contains(.openAITwentyFourHours))
        let unsupportedVariant = HanlinPromptCachePreset.available(
            company: "OPENAI", apiType: "OpenAI", endpoint: native, modelID: "gpt-4.1-mini"
        )
        #expect(!unsupportedVariant.contains(.openAITwentyFourHours))
        for model in ["", "gpt-.", "gpt-6.", "gpt--6", "gpt-6x", "gpt-6.2.1", "gpt-7"] {
            #expect(HanlinPromptCachePreset.available(
                company: "OPENAI", apiType: "OpenAI-Response", endpoint: native, modelID: model
            ) == [.automatic, .providerDefault, .noExplicitCaching])
        }
    }

    @Test
    func proxiesPlanTransportAndOtherProvidersDoNotInheritOpenAIPresets() {
        for endpoint in [
            "https://gateway.example/v1/responses",
            "https://api.openai.com.example/v1/responses",
            "http://api.openai.com/v1/responses",
            "https://api.openai.com:9443/v1/responses",
            "https://user@api.openai.com/v1/responses"
        ] {
            let presets = HanlinPromptCachePreset.available(
                company: "OPENAI", apiType: "OpenAI-Response",
                endpoint: URL(string: endpoint), modelID: "gpt-6.2-sol"
            )
            #expect(presets == [.automatic, .providerDefault, .noExplicitCaching])
        }
        for (company, dialect) in [("CUSTOM", "OpenAI-Response"), ("OPENAI", "openai-chatgpt-plan")] {
            #expect(HanlinPromptCachePreset.available(
                company: company, apiType: dialect, endpoint: native, modelID: "gpt-5.5"
            ) == [.automatic, .providerDefault, .noExplicitCaching])
        }
    }

    @Test
    func anthropicAndLocalAvailabilityReflectNativeProvider() {
        let anthropic = HanlinPromptCachePreset.available(
            company: "ANTHROPIC", apiType: "Anthropic",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages"), modelID: "claude-sonnet-4"
        )
        #expect(anthropic == [.automatic, .providerDefault, .noExplicitCaching, .anthropicOneHour])
        #expect(HanlinPromptCachePreset.anthropicOneHour.policy?.anthropicTTL == .oneHour)
        for company in ["APPLE", "LOCAL"] {
            #expect(HanlinPromptCachePreset.available(
                company: company, apiType: "OpenAI", endpoint: native, modelID: "gpt-5.5"
            ).isEmpty)
        }
    }
}
