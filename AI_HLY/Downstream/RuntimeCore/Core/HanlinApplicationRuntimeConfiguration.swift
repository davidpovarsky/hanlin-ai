import Foundation
import HanlinExtensionContracts

/// Optional operating-system hooks belong to the embedding application.
/// A plain host configuration does not read Hanlin's App Group or open Hanlin.
public struct HanlinApplicationSystemIntegrations: Hashable, Sendable {
    public let shareAppGroupIdentifier: String?
    public let notificationCategoryIdentifier: String?
    public let visionURL: URL?

    public init(shareAppGroupIdentifier: String? = nil,
                notificationCategoryIdentifier: String? = nil,
                visionURL: URL? = nil) {
        self.shareAppGroupIdentifier = shareAppGroupIdentifier
        self.notificationCategoryIdentifier = notificationCategoryIdentifier
        self.visionURL = visionURL
    }

    /// Uses the same immutable host policy as the extension SDK products.
    public init(extensionHost: HanlinExtensionHostConfiguration) {
        self.init(shareAppGroupIdentifier: extensionHost.appGroupIdentifier,
                  notificationCategoryIdentifier: extensionHost.notificationCategoryIdentifier,
                  visionURL: extensionHost.visionURL)
    }

    /// Retains the original app's existing extension and intent contracts.
    public static var hanlin: Self { .init(extensionHost: .hanlin) }

    /// Hosts using HanlinWorkspaceView can route the configured camera URL to
    /// its original vision destination without duplicating URL matching.
    public func isVisionURL(_ url: URL) -> Bool {
        guard let expected = visionURL else { return false }
        return url.scheme?.lowercased() == expected.scheme?.lowercased()
            && url.host?.lowercased() == expected.host?.lowercased()
            && url.port == expected.port && url.user == expected.user
            && url.password == expected.password && url.path == expected.path
            && url.query == expected.query && url.fragment == expected.fragment
    }

    static var currentHost: Self {
        guard let host = try? HanlinExtensionHostConfiguration.load() else { return .init() }
        return .init(extensionHost: host)
    }
}

public enum HanlinApplicationSystemIntegrationError: LocalizedError {
    case visionRouteNotConfigured
    case visionRouteUnavailable

    public var errorDescription: String? {
        switch self {
        case .visionRouteNotConfigured: "Configure the host application's Vision URL before using this intent."
        case .visionRouteUnavailable: "The host application could not open its configured Vision URL."
        }
    }
}

/// Native Node/Python/MCP engines retain their original process lifetime. Their
/// filesystem and secret services are selected once before first use. Separate
/// views share one original model container; standalone AgentCore sessions can
/// independently use host-owned stores and account scopes.
public struct HanlinApplicationRuntimeConfiguration: Hashable, Sendable {
    public let directory: URL
    public let mcpSecretService: String
    public let environmentSecretService: String

    public init(directory: URL, mcpSecretService: String, environmentSecretService: String) {
        self.directory = directory
        self.mcpSecretService = mcpSecretService
        self.environmentSecretService = environmentSecretService
    }

    public static func applicationSupport(appIdentifier: String) -> Self {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return .init(directory: support.appending(path: "HanlinRuntime/v1", directoryHint: .isDirectory),
                     mcpSecretService: appIdentifier + ".mcp",
                     environmentSecretService: appIdentifier + ".runtime")
    }

    static var currentHost: Self {
        applicationSupport(appIdentifier: Bundle.main.bundleIdentifier ?? "HanlinHost")
    }
}

public enum HanlinApplicationError: LocalizedError {
    case invalidStorageURL
    case incompatibleRuntimeConfiguration
    case incompatibleRuntimeContainer
    case incompatibleModelContainer
    case invalidConversation
    case containerAlreadyRegistered
    case conversationNotFound(UUID)
    case duplicateConversation(UUID)
    case noChatModelReady

    public var errorDescription: String? {
        switch self {
        case .invalidStorageURL:
            "The Hanlin store must use a file URL."
        case .incompatibleRuntimeConfiguration:
            "The process already owns a different native runtime configuration. Reuse its runtime configuration for additional Hanlin contexts."
        case .incompatibleRuntimeContainer:
            "The original native runtime already belongs to another model container. Reuse the same HanlinApplicationContext across windows and embedded views."
        case .incompatibleModelContainer:
            "The supplied model container does not include the original Hanlin application schema."
        case .invalidConversation:
            "The conversation has no stable identifier."
        case .containerAlreadyRegistered:
            "This model container already belongs to another live Hanlin application context."
        case .conversationNotFound:
            "This conversation is no longer available in the selected application context."
        case .duplicateConversation:
            "More than one stored conversation has the requested identifier."
        case .noChatModelReady:
            "No chat model is ready. Enable a provider or make an on-device model available in Settings."
        }
    }
}

/// The original native engines are singletons, so their configuration cannot be
/// replaced underneath existing jobs. Provider credentials and conversation
/// namespaces use the independent per-container registry above.
final class HanlinApplicationProcessRuntime: @unchecked Sendable {
    static let shared = HanlinApplicationProcessRuntime()
    private let lock = NSLock()
    private var installed: HanlinApplicationRuntimeConfiguration?
    private var modelContainer: AnyObject?
    private var installedSystemIntegrations: HanlinApplicationSystemIntegrations?

    func install(_ configuration: HanlinApplicationRuntimeConfiguration, modelContainer: AnyObject,
                 systemIntegrations: HanlinApplicationSystemIntegrations = .currentHost) throws {
        guard configuration.directory.isFileURL else { throw HanlinApplicationError.invalidStorageURL }
        lock.lock()
        defer { lock.unlock() }
        if let installed, installed != configuration {
            throw HanlinApplicationError.incompatibleRuntimeConfiguration
        }
        if let installedSystemIntegrations, installedSystemIntegrations != systemIntegrations {
            throw HanlinApplicationError.incompatibleRuntimeConfiguration
        }
        if let current = self.modelContainer, current !== modelContainer {
            throw HanlinApplicationError.incompatibleRuntimeContainer
        }
        installed = configuration
        installedSystemIntegrations = systemIntegrations
        self.modelContainer = modelContainer
    }

    var systemIntegrations: HanlinApplicationSystemIntegrations {
        lock.lock()
        defer { lock.unlock() }
        return installedSystemIntegrations ?? .currentHost
    }

    var configuration: HanlinApplicationRuntimeConfiguration {
        lock.lock()
        defer { lock.unlock() }
        if let installed { return installed }
        let current = HanlinApplicationRuntimeConfiguration.currentHost
        installed = current
        return current
    }
}

