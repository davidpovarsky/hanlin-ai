import Foundation
import SwiftData
import HanlinAgentCore
import HanlinChatCore

/// The one app catalog row for the system provider. The existing picker owns visibility.
enum HanlinAppleModelCatalogAdapter {
    static let catalogID = UUID(uuid: (0x76, 0x29, 0x8a, 0x03, 0x22, 0x51, 0x4d, 0x79,
                                       0x8e, 0x19, 0x5e, 0x29, 0x30, 0x9c, 0x5d, 0xa1))

    static func isNative(_ model: AllModels) -> Bool { model.id == catalogID }

    static var isAvailable: Bool { HanlinAppleOnDeviceProvider.availability == .available }

    /// Append once after existing rows. Never remove/reorder rows or rewrite saved useModel indices.
    /// Remains in the catalog when unavailable so a saved selection cannot shift to another model.
    @discardableResult
    @MainActor
    static func register(in context: ModelContext) throws -> AllModels {
        let models = try context.fetch(FetchDescriptor<AllModels>())
        let native = models.filter { $0.id == catalogID }
        guard native.count <= 1 else { throw HanlinAISDKError.invalidConversation("Duplicate native model identity.") }
        guard !models.contains(where: { $0.id != catalogID && $0.name == HanlinAppleOnDeviceProvider.modelID }) else {
            throw HanlinAISDKError.invalidConversation("The reserved native model name conflicts with another catalog row.")
        }
        if let existing = native.first {
            try validate(existing)
            return existing
        }
        guard let maximum = models.compactMap(\.position).max(), maximum < Int.max else {
            if models.isEmpty { return try insert(position: 0, in: context) }
            throw HanlinAISDKError.invalidConversation("Cannot append a unique native model without changing the catalog order.")
        }
        return try insert(position: maximum + 1, in: context)
    }

    @MainActor private static func insert(position: Int, in context: ModelContext) throws -> AllModels {
        let model = AllModels(id: catalogID, name: HanlinAppleOnDeviceProvider.modelID,
            displayName: HanlinAppleOnDeviceProvider.displayName, position: position, company: "APPLE",
            isHidden: false, systemProvision: false, icon: "apple.intelligence")
        context.insert(model)
        try context.save()
        return model
    }

    private static func validate(_ model: AllModels) throws {
        guard model.id == catalogID, model.name == HanlinAppleOnDeviceProvider.modelID,
              model.company == "APPLE", model.identity == "model", model.supportsTextGen,
              !model.supportsToolUse, !model.supportsMultimodal, !model.supportsReasoning,
              !model.supportsImageGen, !model.supportsVoiceGen, !model.supportsSearch else {
            throw HanlinAISDKError.invalidConversation("The native model catalog entry is invalid.")
        }
    }

    static func configuration(
        for model: AllModels,
        temperature: Double = HanlinChatGenerationDefaults.temperature,
        topP: Double = HanlinChatGenerationDefaults.topP,
        maxTokens: Int = HanlinChatGenerationDefaults.maxTokens
    ) throws -> HanlinChatModelConfiguration {
        try validate(model)
        guard HanlinAppleOnDeviceProvider.availability == .available else { throw HanlinAppleProviderError.unavailable }
        return generationConfiguration(temperature: temperature, topP: topP, maxTokens: maxTokens)
    }

    // Keep the original native identity while forwarding the caller's settings to
    // the shared engine and provider, including settings the provider must reject.
    static func generationConfiguration(
        temperature: Double = HanlinChatGenerationDefaults.temperature,
        topP: Double = HanlinChatGenerationDefaults.topP,
        maxTokens: Int = HanlinChatGenerationDefaults.maxTokens
    ) -> HanlinChatModelConfiguration {
        let native = HanlinAppleOnDeviceProvider.configuration()
        return .init(
            modelID: native.modelID, baseModelID: native.baseModelID,
            displayName: native.displayName, company: native.company, apiType: native.apiType,
            endpoint: native.endpoint, apiKey: native.apiKey,
            temperature: temperature, topP: topP, maxTokens: maxTokens,
            supportsReasoning: native.supportsReasoning,
            supportReasoningChange: native.supportReasoningChange,
            thinkingLength: native.thinkingLength, reasoningEffort: native.reasoningEffort,
            supportsToolUse: native.supportsToolUse, supportsTextGen: native.supportsTextGen,
            systemPrompt: native.systemPrompt, updatedAt: native.updatedAt
        )
    }
}
