import Foundation
import HanlinScriptExtensions
import SwiftData

/// A provider's original request dialect; no alternate transport is introduced.
public enum HanlinApplicationProviderAPI: String, Codable, CaseIterable, Sendable {
    case openAI = "OpenAI"
    case openAIResponses = "OpenAI-Response"
    case gemini = "Gemini"
    case anthropic = "Anthropic"

    var original: APIType {
        switch self {
        case .openAI: .openAI
        case .openAIResponses: .openAIResponse
        case .gemini: .gemini
        case .anthropic: .anthropic
        }
    }
}

/// The identifier is the original APIKeys.company routing identity. It remains
/// stable when changing a display name, endpoint or credential.
public struct HanlinApplicationProviderConfiguration: Equatable, Sendable {
    public var identifier: String
    public var displayName: String
    public var endpoint: URL?
    public var api: HanlinApplicationProviderAPI
    public var isEnabled: Bool
    public var autoProbeCapabilities: Bool

    public init(identifier: String, displayName: String, endpoint: URL? = nil,
                api: HanlinApplicationProviderAPI = .openAI, isEnabled: Bool = true,
                autoProbeCapabilities: Bool = true) {
        self.identifier = identifier; self.displayName = displayName
        self.endpoint = endpoint; self.api = api; self.isEnabled = isEnabled
        self.autoProbeCapabilities = autoProbeCapabilities
    }
}

public struct HanlinApplicationProvider: Identifiable, Sendable {
    public var id: String { configuration.identifier }
    public let configuration: HanlinApplicationProviderConfiguration
    public let isBuiltIn: Bool
    /// Describes storage representation, not current Keychain availability.
    public let usesProtectedCredentialStorage: Bool

    @MainActor init(_ row: APIKeys) {
        configuration = .init(identifier: row.company ?? "", displayName: row.name ?? "",
            endpoint: row.requestURL.flatMap(URL.init(string:)),
            api: HanlinApplicationProviderAPI(rawValue: row.apiType.rawValue) ?? .openAI,
            isEnabled: !row.isHidden, autoProbeCapabilities: row.autoProbeCapabilities)
        isBuiltIn = row.from == .system
        usesProtectedCredentialStorage = row.key.map(HanlinKeychainCredentialStore.isReference) ?? false
    }
}

public struct HanlinApplicationModelCapabilities: Equatable, Sendable {
    public var text: Bool
    public var tools: Bool
    public var search: Bool
    public var reasoning: Bool
    public var adjustableReasoning: Bool
    public var imageInput: Bool
    public var imageGeneration: Bool
    public var voice: Bool

    public init(text: Bool = true, tools: Bool = false, search: Bool = false,
                reasoning: Bool = false, adjustableReasoning: Bool = false,
                imageInput: Bool = false, imageGeneration: Bool = false, voice: Bool = false) {
        self.text = text; self.tools = tools; self.search = search
        self.reasoning = reasoning; self.adjustableReasoning = adjustableReasoning
        self.imageInput = imageInput; self.imageGeneration = imageGeneration; self.voice = voice
    }

    var original: ModelCapabilities {
        .init(supportsTextGen: text, supportsMultimodal: imageInput,
              supportsReasoning: reasoning, supportReasoningChange: adjustableReasoning,
              supportsImageGen: imageGeneration, supportsVoiceGen: voice, supportsToolUse: tools)
    }

    @MainActor init(_ row: AllModels) {
        self.init(text: row.supportsTextGen, tools: row.supportsToolUse, search: row.supportsSearch,
            reasoning: row.supportsReasoning, adjustableReasoning: row.supportReasoningChange,
            imageInput: row.supportsMultimodal, imageGeneration: row.supportsImageGen, voice: row.supportsVoiceGen)
    }
}

public enum HanlinApplicationModelConfigurationError: LocalizedError, Sendable {
    case invalidProvider, invalidEndpoint, duplicateProvider(String), providerNotFound(String)
    case invalidModel, modelNotFound(UUID), ambiguousModel(UUID)
    case builtInProviderCannotBeDeleted

    public var errorDescription: String? {
        switch self {
        case .invalidProvider: "A provider requires a nonempty routing identifier and display name."
        case .invalidEndpoint: "A custom provider requires an HTTP or HTTPS endpoint with a host."
        case .duplicateProvider: "More than one provider uses this routing identifier, or it already exists."
        case .providerNotFound: "The provider is not present in this application context."
        case .invalidModel: "A model requires a nonempty provider model identifier and display name."
        case .modelNotFound: "The model is not present in this application context."
        case .ambiguousModel: "More than one original model uses this identifier."
        case .builtInProviderCannotBeDeleted: "Disable a built-in provider instead of deleting its catalog definition."
        }
    }
}

public extension HanlinApplicationContext {
    func providers() throws -> [HanlinApplicationProvider] { try modelAccess.providers() }

    /// Uses the original protected credential writer and this container's
    /// credential registry. The secret never enters the public metadata DTO.
    @discardableResult
    func createProvider(_ configuration: HanlinApplicationProviderConfiguration,
                        credential: String = "") throws -> HanlinApplicationProvider {
        try modelAccess.createProvider(configuration, credential: credential)
    }

    @discardableResult
    func updateProvider(_ configuration: HanlinApplicationProviderConfiguration) throws -> HanlinApplicationProvider {
        try modelAccess.updateProvider(configuration)
    }

    /// Removes a custom provider row. Disable built-in providers instead.
    /// Model definitions and historical
    /// immutable Keychain generations are retained, as in the original store.
    func deleteProvider(_ identifier: String) throws { try modelAccess.deleteProvider(identifier) }

    /// Explicit secret access for a host's own settings. This is never part of
    /// provider/model listing, diagnostics or message snapshots.
    func providerCredential(_ identifier: String) throws -> String? {
        try modelAccess.providerCredential(identifier)
    }

    func setProviderCredential(_ value: String, provider identifier: String) throws {
        try modelAccess.setProviderCredential(value, provider: identifier)
    }

    /// Clears the currently selected credential using the original versioned
    /// writer; it does not erase retained recovery generations.
    func clearProviderCredential(_ identifier: String) throws {
        try setProviderCredential("", provider: identifier)
    }

    @discardableResult
    func createModel(modelID: String, displayName: String, provider identifier: String,
                     capabilities: HanlinApplicationModelCapabilities = .init(),
                     isHidden: Bool = false) throws -> HanlinApplicationModel {
        try modelAccess.createModel(modelID: modelID, displayName: displayName, provider: identifier,
                                   capabilities: capabilities, isHidden: isHidden)
    }

    /// Applies the original editable model metadata to the same UUID. Routing
    /// identifiers stay stable; create another model to select a different wire ID.
    @discardableResult
    func updateModel(_ id: UUID, displayName: String? = nil,
                     capabilities: HanlinApplicationModelCapabilities? = nil,
                     isHidden: Bool? = nil, position: Int? = nil) throws -> HanlinApplicationModel {
        try modelAccess.updateModel(id, displayName: displayName, capabilities: capabilities,
                                    isHidden: isHidden, position: position)
    }

    func deleteModel(_ id: UUID) throws { try modelAccess.deleteModel(id) }

    private var modelAccess: HanlinApplicationModelAccess {
        .init(context: modelContainer.mainContext)
    }
}

/// A narrow access adapter to the original rows/writers. It owns no persistent
/// store, alternate model catalog, credentials or process-global configuration.
@MainActor
struct HanlinApplicationModelAccess {
    let context: ModelContext

    func providers() throws -> [HanlinApplicationProvider] {
        try context.fetch(FetchDescriptor<APIKeys>(sortBy: [SortDescriptor(\APIKeys.timestamp)]))
            .filter { !($0.company ?? "").isEmpty }.map(HanlinApplicationProvider.init)
    }

    func provider(_ identifier: String) throws -> APIKeys {
        let company: String? = identifier
        let rows = try context.fetch(FetchDescriptor<APIKeys>(predicate: #Predicate { $0.company == company }))
        guard let row = rows.first else { throw HanlinApplicationModelConfigurationError.providerNotFound(identifier) }
        guard rows.count == 1 else { throw HanlinApplicationModelConfigurationError.duplicateProvider(identifier) }
        return row
    }

    private func validate(_ value: HanlinApplicationProviderConfiguration, isNew: Bool) throws {
        guard !value.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HanlinApplicationModelConfigurationError.invalidProvider
        }
        if let endpoint = value.endpoint {
            guard ["http", "https"].contains(endpoint.scheme ?? ""), endpoint.host != nil else {
                throw HanlinApplicationModelConfigurationError.invalidEndpoint
            }
        } else if isNew { throw HanlinApplicationModelConfigurationError.invalidEndpoint }
    }

    func createProvider(_ value: HanlinApplicationProviderConfiguration, credential: String) throws -> HanlinApplicationProvider {
        try validate(value, isNew: true)
        let company: String? = value.identifier
        guard try context.fetch(FetchDescriptor<APIKeys>(predicate: #Predicate { $0.company == company })).isEmpty else {
            throw HanlinApplicationModelConfigurationError.duplicateProvider(value.identifier)
        }
        let row = APIKeys(name: value.displayName, company: value.identifier,
            requestURL: value.endpoint?.absoluteString, isHidden: !value.isEnabled,
            apiType: value.api.original, from: .custom, autoProbeCapabilities: value.autoProbeCapabilities)
        try HanlinAppProviderCredentials.shared.insert(row, value: credential, in: context)
        return .init(row)
    }

    func updateProvider(_ value: HanlinApplicationProviderConfiguration) throws -> HanlinApplicationProvider {
        let row = try provider(value.identifier)
        try validate(value, isNew: row.from == .custom)
        try HanlinAppProviderCredentials.shared.saveMetadata(for: row, expectedStoredValue: row.key, in: context) { row in
            row.name = value.displayName; row.requestURL = value.endpoint?.absoluteString
            row.isHidden = !value.isEnabled; row.apiType = value.api.original
            row.autoProbeCapabilities = value.autoProbeCapabilities
        }
        return .init(row)
    }

    func deleteProvider(_ identifier: String) throws {
        let row = try provider(identifier)
        guard row.from == .custom else { throw HanlinApplicationModelConfigurationError.builtInProviderCannotBeDeleted }
        if context.hasChanges { try context.save() }
        context.delete(row)
        do { try context.save() } catch { context.rollback(); throw error }
    }

    func providerCredential(_ identifier: String) throws -> String? {
        try HanlinAppProviderCredentials.shared.resolve(provider(identifier))
    }

    func setProviderCredential(_ value: String, provider identifier: String) throws {
        let row = try provider(identifier)
        try HanlinAppProviderCredentials.shared.save(value, for: row, expectedStoredValue: row.key, in: context)
    }

    func model(_ id: UUID) throws -> AllModels {
        let rows = try context.fetch(FetchDescriptor<AllModels>(predicate: #Predicate { $0.id == id }))
        guard let row = rows.first else { throw HanlinApplicationModelConfigurationError.modelNotFound(id) }
        guard rows.count == 1 else { throw HanlinApplicationModelConfigurationError.ambiguousModel(id) }
        return row
    }

    func createModel(modelID: String, displayName: String, provider identifier: String,
                     capabilities: HanlinApplicationModelCapabilities, isHidden: Bool) throws -> HanlinApplicationModel {
        _ = try provider(identifier)
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HanlinApplicationModelConfigurationError.invalidModel
        }
        let row = try ModelRefreshService.addModelToDatabase(modelId: modelID, displayName: displayName,
            company: identifier, context: context, capabilities: capabilities.original,
            isHidden: isHidden, supportsSearch: capabilities.search)
        return .init(row)
    }

    func updateModel(_ id: UUID, displayName: String?, capabilities: HanlinApplicationModelCapabilities?,
                     isHidden: Bool?, position: Int?) throws -> HanlinApplicationModel {
        let row = try model(id)
        if let displayName, displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw HanlinApplicationModelConfigurationError.invalidModel
        }
        if context.hasChanges { try context.save() }
        if let displayName { row.displayName = displayName }
        if let isHidden { row.isHidden = isHidden }
        if let position { row.position = position }
        if let capabilities {
            row.supportsTextGen = capabilities.text; row.supportsToolUse = capabilities.tools
            row.supportsSearch = capabilities.search; row.supportsReasoning = capabilities.reasoning
            row.supportReasoningChange = capabilities.adjustableReasoning; row.supportsMultimodal = capabilities.imageInput
            row.supportsImageGen = capabilities.imageGeneration; row.supportsVoiceGen = capabilities.voice
        }
        do { try context.save() } catch { context.rollback(); throw error }
        return .init(row)
    }

    func deleteModel(_ id: UUID) throws {
        let row = try model(id)
        try ModelRefreshService.removeModelFromDatabase(model: row, context: context)
    }
}
