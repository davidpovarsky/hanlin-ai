import Foundation

public enum OpenUIRenderTarget: String, Codable, CaseIterable, Hashable, Sendable {
    case react, swiftui
}

public enum PresentationAnswerMode: String, Codable, Hashable, Sendable {
    case mixedMarkdownOpenUI, fullOpenUI
}

public enum SourcePresentation: String, Codable, Hashable, Sendable {
    case sentenceAndAnswer, sidebar
}

/// Every reference is pinned. Registering v2 does not rewrite a v1 conversation.
public struct PresentationReference: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let version: Int
    public init(_ id: String, version: Int = 1) { self.id = id; self.version = version }
    public var key: String { "\(id)@\(version)" }
}

public struct PresentationProfile: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let version: Int
    public let shellID: String
    public let catalogIDs: [PresentationReference]
    public let themeID: String
    public let motionPresetID: String
    public let answerMode: PresentationAnswerMode
    public let capabilities: Set<String>
    public let renderTargets: Set<OpenUIRenderTarget>
    public let sourcePresentation: SourcePresentation

    public init(id: String, version: Int = 1, shellID: String,
                catalogIDs: [PresentationReference], themeID: String = "system",
                motionPresetID: String = "v1.relaxed", answerMode: PresentationAnswerMode = .mixedMarkdownOpenUI,
                capabilities: Set<String> = [], renderTargets: Set<OpenUIRenderTarget> = [.react, .swiftui],
                sourcePresentation: SourcePresentation = .sentenceAndAnswer) {
        self.id = id; self.version = version; self.shellID = shellID; self.catalogIDs = catalogIDs
        self.themeID = themeID; self.motionPresetID = motionPresetID; self.answerMode = answerMode
        self.capabilities = capabilities; self.renderTargets = renderTargets
        self.sourcePresentation = sourcePresentation
    }
    public var reference: PresentationReference { .init(id, version: version) }
}

public struct ConversationPresentationAssignment: Codable, Hashable, Sendable {
    public let conversationID: UUID
    public let profile: PresentationReference
    public init(conversationID: UUID, profile: PresentationReference) {
        self.conversationID = conversationID; self.profile = profile
    }
}

/// Schemas/examples are supplied by the catalog's actual implementation. A shell
/// controls layout; the catalog controls what the model can put inside a part.
public struct ComponentCatalogDescriptor: Codable, Hashable, Sendable {
    public let reference: PresentationReference
    public let renderTargets: Set<OpenUIRenderTarget>
    public let componentNames: [String]
    public let modelInstructions: String
    public init(reference: PresentationReference, renderTargets: Set<OpenUIRenderTarget>,
                componentNames: [String], modelInstructions: String) {
        self.reference = reference; self.renderTargets = renderTargets
        self.componentNames = componentNames; self.modelInstructions = modelInstructions
    }
}

public struct ShellDescriptor: Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let usesSourcesSidebar: Bool
    public init(id: String, title: String, usesSourcesSidebar: Bool = false) {
        self.id = id; self.title = title; self.usesSourcesSidebar = usesSourcesSidebar
    }
}

public struct HostPresentationDescriptor: Codable, Hashable, Sendable {
    public let appID: String
    public let defaultProfile: PresentationReference
    public let availableProfiles: [PresentationProfile]
    public let catalogProviders: [ComponentCatalogDescriptor]
    public let shells: [ShellDescriptor]
    public let hostCapabilities: Set<String>
    public let renderTargets: Set<OpenUIRenderTarget>
    public init(appID: String, defaultProfile: PresentationReference,
                availableProfiles: [PresentationProfile], catalogProviders: [ComponentCatalogDescriptor],
                shells: [ShellDescriptor], hostCapabilities: Set<String>,
                renderTargets: Set<OpenUIRenderTarget> = [.react, .swiftui]) {
        self.appID = appID; self.defaultProfile = defaultProfile; self.availableProfiles = availableProfiles
        self.catalogProviders = catalogProviders; self.shells = shells
        self.hostCapabilities = hostCapabilities; self.renderTargets = renderTargets
    }
}

/// Persist this snapshot with each message. Displaying historical content never
/// reauthorizes an action; the original Host must check live authority each time.
public struct ResolvedPresentationProfile: Codable, Hashable, Sendable {
    public let appID: String
    public let profile: PresentationProfile
    public let shell: ShellDescriptor
    public let catalogs: [ComponentCatalogDescriptor]
    public let capabilities: Set<String>
    public let renderTargets: Set<OpenUIRenderTarget>
}

public enum PresentationResolutionError: Error, Equatable, Sendable {
    case conversationMismatch, profileUnavailable, shellUnavailable, catalogUnavailable(String)
    case duplicateRegistration(String), unsupportedRenderTarget
}

public struct ComponentCatalogRegistry: Sendable {
    private var catalogs: [PresentationReference: ComponentCatalogDescriptor] = [:]
    public init(_ descriptors: [ComponentCatalogDescriptor] = []) throws {
        for descriptor in descriptors { try register(descriptor) }
    }
    public mutating func register(_ descriptor: ComponentCatalogDescriptor) throws {
        if let old = catalogs[descriptor.reference], old != descriptor {
            throw PresentationResolutionError.duplicateRegistration(descriptor.reference.key)
        }
        catalogs[descriptor.reference] = descriptor
    }
    public func catalog(_ reference: PresentationReference) throws -> ComponentCatalogDescriptor {
        guard let result = catalogs[reference] else { throw PresentationResolutionError.catalogUnavailable(reference.key) }
        return result
    }
}

public struct ShellRegistry: Sendable {
    private var shells: [String: ShellDescriptor] = [:]
    public init(_ descriptors: [ShellDescriptor] = []) throws {
        for descriptor in descriptors {
            if let old = shells[descriptor.id], old != descriptor {
                throw PresentationResolutionError.duplicateRegistration(descriptor.id)
            }
            shells[descriptor.id] = descriptor
        }
    }
    public func shell(_ id: String) throws -> ShellDescriptor {
        guard let value = shells[id] else { throw PresentationResolutionError.shellUnavailable }
        return value
    }
}

public enum ProfileResolver {
    public static func resolve(host: HostPresentationDescriptor, conversationID: UUID,
                               assignment: ConversationPresentationAssignment? = nil) throws -> ResolvedPresentationProfile {
        if let assignment, assignment.conversationID != conversationID {
            throw PresentationResolutionError.conversationMismatch
        }
        let reference = assignment?.profile ?? host.defaultProfile
        guard let profile = host.availableProfiles.first(where: { $0.reference == reference }) else {
            throw PresentationResolutionError.profileUnavailable
        }
        let shell = try ShellRegistry(host.shells).shell(profile.shellID)
        let registry = try ComponentCatalogRegistry(host.catalogProviders)
        let catalogs = try profile.catalogIDs.map { try registry.catalog($0) }
        let catalogTargets = catalogs.reduce(into: Set<OpenUIRenderTarget>()) { $0.formUnion($1.renderTargets) }
        let targets = profile.renderTargets.intersection(host.renderTargets).intersection(catalogTargets)
        return .init(appID: host.appID, profile: profile, shell: shell, catalogs: catalogs,
                     capabilities: profile.capabilities.intersection(host.hostCapabilities), renderTargets: targets)
    }
}
