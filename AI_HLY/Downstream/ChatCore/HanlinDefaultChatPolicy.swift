import Foundation
import HanlinChatCore

/// The single model/generation policy used when Hanlin creates a conversation
/// without an existing per-chat selection (including compact extension chat).
enum HanlinDefaultChatPolicy {
    static func orderedModels(_ models: [AllModels]) -> [AllModels] {
        models.sorted {
            let lhsPosition = $0.position ?? Int.max
            let rhsPosition = $1.position ?? Int.max
            if lhsPosition != rhsPosition { return lhsPosition < rhsPosition }
            return ($0.name ?? "") < ($1.name ?? "")
        }
    }

    static func defaultModelIndex(in models: [AllModels]) -> Int? {
        models.enumerated()
            .filter { !$0.element.isHidden && !HanlinAppleModelCatalogAdapter.isNative($0.element) }
            .sorted {
                let lhsPosition = $0.element.position ?? Int.max
                let rhsPosition = $1.element.position ?? Int.max
                if lhsPosition != rhsPosition { return lhsPosition < rhsPosition }
                return ($0.element.name ?? "") < ($1.element.name ?? "")
            }
            .first?.offset
    }

    static func defaultModel(in models: [AllModels]) -> AllModels? {
        orderedModels(models).first { !$0.isHidden && !HanlinAppleModelCatalogAdapter.isNative($0) }
    }

    /// Resolve only a NEW conversation's initial selection. Existing useModel
    /// indices and explicit Composer selections are never rewritten by this policy.
    static func creationModelIndex(in models: [AllModels], providers: [APIKeys],
                                   nativeAvailable: Bool, downloadedLocalModels: Set<String>) -> Int? {
        let remoteConfigured = providers.contains {
            $0.company?.uppercased() != "LOCAL" && $0.company?.uppercased() != "APPLE"
                && !$0.isHidden && !($0.resolvedKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if remoteConfigured { return defaultModelIndex(in: models) }
        let localEnabled = providers.contains { $0.company?.uppercased() == "LOCAL" && !$0.isHidden }
        return models.indices.filter { index in
            let model = models[index]
            guard !model.isHidden, model.supportsTextGen else { return false }
            if HanlinAppleModelCatalogAdapter.isNative(model) { return nativeAvailable }
            return localEnabled && model.company?.uppercased() == "LOCAL"
                && downloadedLocalModels.contains(model.name ?? "")
        }.min {
            let lhs = models[$0].position ?? Int.max
            let rhs = models[$1].position ?? Int.max
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
    }

    @MainActor
    static func creationModelIndex(in models: [AllModels], providers: [APIKeys]) -> Int? {
        let downloaded = Set(models.compactMap { model -> String? in
            guard model.company?.uppercased() == "LOCAL", !model.isHidden,
                  let name = model.name, getLocalModelPath(for: name) != nil else { return nil }
            return name
        })
        return creationModelIndex(in: models, providers: providers,
            nativeAvailable: HanlinAppleModelCatalogAdapter.isAvailable, downloadedLocalModels: downloaded)
    }

    static let temperature = HanlinChatGenerationDefaults.temperature
    static let topP = HanlinChatGenerationDefaults.topP
    static let maxTokens = HanlinChatGenerationDefaults.maxTokens
    static let thinkingLength = HanlinChatGenerationDefaults.thinkingLength
}
