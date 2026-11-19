import Foundation
import HanlinScriptExtensions
import HanlinScriptingApplicationRuntime
import SwiftData

/// AI-target composition. MiniApps compiles the runtime without this file or
/// its model, default-policy and credential dependencies.
@MainActor
final class HanlinScriptingPlatformAIIntegration: HanlinScriptingApplicationServices {
    private let modelContext: ModelContext
    private let compactConfigStore: HanlinCompactAgentConfigStore?

    init(modelContext: ModelContext, compactConfigStore: HanlinCompactAgentConfigStore? = nil) {
        self.modelContext = modelContext
        self.compactConfigStore = compactConfigStore
    }

    func loadAssistant(
        _ request: HanlinScriptingAssistantRequest
    ) async throws -> AsyncThrowingStream<HanlinScriptingAssistantChunk, Error> {
        try await HanlinScriptingAssistantProviderAdapter(context: modelContext).load(request)
    }

    func publishCompactAgentConfig() throws {
        let keys = try modelContext.fetch(FetchDescriptor<APIKeys>())
        let models = try modelContext.fetch(FetchDescriptor<AllModels>())

        let validKeys = keys.filter { key in
            guard let k = key.storedCredential, key.preservesCredentialSelection, k.uppercased() != "LOCAL",
                  let company = key.company, !company.isEmpty, company.uppercased() != "LOCAL",
                  let urlStr = key.requestURL, !urlStr.isEmpty, URL(string: urlStr) != nil else {
                return false
            }
            return true
        }

        var keyByCompany: [String: APIKeys] = [:]
        for key in validKeys {
            let company = key.company ?? ""
            if let existing = keyByCompany[company] {
                if existing.isHidden && !key.isHidden {
                    keyByCompany[company] = key
                }
            } else {
                keyByCompany[company] = key
            }
        }

        let eligibleModels = models.filter { model in
            guard !model.isHidden,
                  model.supportsTextGen,
                  let name = model.name, !name.isEmpty,
                  let company = model.company,
                  company.uppercased() != "LOCAL",
                  keyByCompany[company] != nil else {
                return false
            }
            return true
        }

        guard let selectedModel = HanlinDefaultChatPolicy.defaultModel(in: eligibleModels),
              let selectedKey = keyByCompany[selectedModel.company ?? ""],
              let apiKey = selectedKey.key,
              let endpointStr = selectedKey.requestURL,
              let endpoint = URL(string: endpointStr) else {
            let store = try compactConfigStore ?? HanlinCompactAgentConfigStore()
            try store.clear()
            return
        }

        let config = HanlinCompactAgentConfiguration(
            endpoint: endpoint,
            // Legacy records retain compatibility until explicitly saved.
            // A secured record exports only its handle, never the resolved secret.
            apiKey: HanlinKeychainCredentialStore.isReference(apiKey) ? "" : apiKey,
            credentialReference: HanlinKeychainCredentialStore.isReference(apiKey) ? apiKey : nil,
            modelID: selectedModel.name ?? "gpt-4o-mini",
            company: selectedKey.company,
            displayName: selectedModel.displayName ?? selectedModel.name,
            systemPrompt: "You are Hanlin, an intelligent AI assistant. Provide concise, helpful answers directly relating to the user's selected text and query.",
            apiType: selectedKey.apiType.rawValue,
            temperature: HanlinDefaultChatPolicy.temperature,
            topP: HanlinDefaultChatPolicy.topP,
            maxTokens: HanlinDefaultChatPolicy.maxTokens,
            supportsReasoning: selectedModel.supportsReasoning && !selectedModel.supportReasoningChange,
            supportReasoningChange: selectedModel.supportReasoningChange,
            thinkingLength: HanlinDefaultChatPolicy.thinkingLength,
            supportsToolUse: false,
            updatedAt: .now
        )
        let store = try compactConfigStore ?? HanlinCompactAgentConfigStore()
        try store.save(config)
    }
}

extension HanlinScriptingPlatform {
    /// Preserve existing AI callers while keeping ModelContext out of runtime.
    func configure(modelContext: ModelContext) {
        configure(applicationServices: HanlinScriptingPlatformAIIntegration(modelContext: modelContext))
    }
}
