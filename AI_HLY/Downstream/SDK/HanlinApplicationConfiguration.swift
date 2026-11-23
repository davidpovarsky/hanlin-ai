import CryptoKit
import Foundation
import HanlinAgentCore
import HanlinHostContracts
import HanlinPlatformContracts
import HanlinScriptExtensions
import SwiftData

/// The original engine's live host ports. A host can supply its own business
/// implementation without replacing the Hanlin conversation owner or renderer.
public struct HanlinApplicationHostServices: Sendable {
    public let host: any HanlinHostIntegration
    public let capabilities: (any HanlinHostCapabilitySource)?
    public let interactions: (any HanlinHostInteractionSource)?
    /// Observers receive the original committed Session events. They do not
    /// replace the app's presentation/store callbacks.
    public let onHostResult: (@MainActor @Sendable (HanlinHostResultEvent) -> Void)?
    public let onHostProgress: (@MainActor @Sendable (HanlinHostProgressEvent) -> Void)?
    public let onRunCompletion: (@MainActor @Sendable (HanlinAgentRunCompletion) -> Void)?
    public let onSessionInvalidated: (@MainActor @Sendable (HanlinHostSession) -> Void)?

    public init(host: any HanlinHostIntegration,
                capabilities: (any HanlinHostCapabilitySource)? = nil,
                interactions: (any HanlinHostInteractionSource)? = nil,
                onHostResult: (@MainActor @Sendable (HanlinHostResultEvent) -> Void)? = nil,
                onHostProgress: (@MainActor @Sendable (HanlinHostProgressEvent) -> Void)? = nil,
                onRunCompletion: (@MainActor @Sendable (HanlinAgentRunCompletion) -> Void)? = nil,
                onSessionInvalidated: (@MainActor @Sendable (HanlinHostSession) -> Void)? = nil) {
        self.onHostResult = onHostResult
        self.onHostProgress = onHostProgress
        self.onRunCompletion = onRunCompletion
        self.onSessionInvalidated = onSessionInvalidated
        self.host = host
        self.capabilities = capabilities
        self.interactions = interactions
    }
}

/// Called for the actual original session, after its conversation and storage
/// owner are bound. Return the supplied services to retain all Hanlin tools, or
/// supply the host's existing authority. The original services remain available
/// to a host adapter that composes its business tools with Hanlin's tools.
public typealias HanlinApplicationHostServicesFactory =
    @MainActor @Sendable (HanlinHostSession, HanlinApplicationHostServices) async throws
    -> HanlinApplicationHostServices

/// Keychain policy belongs to the embedding application, never the SDK package.
public struct HanlinApplicationCredentials: Hashable, Sendable {
    public enum Accessibility: Hashable, Sendable {
        case whenUnlocked, afterFirstUnlock
    }

    public let service: String
    public let accessGroup: String?
    public let synchronizable: Bool
    public let accessibility: Accessibility

    public init(service: String, accessGroup: String? = nil, synchronizable: Bool = false,
                accessibility: Accessibility = .afterFirstUnlock) {
        self.service = service
        self.accessGroup = accessGroup
        self.synchronizable = synchronizable
        self.accessibility = accessibility
    }

    var store: HanlinKeychainCredentialStore {
        .init(service: service, accessGroup: accessGroup, synchronizable: synchronizable,
              accessibility: accessibility == .whenUnlocked ? .whenUnlocked : .afterFirstUnlock)
    }

    static var currentHost: Self {
        .init(service: (Bundle.main.bundleIdentifier ?? "HanlinHost") + ".provider-credentials")
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

/// Configuration for one original Hanlin model container and its conversation
/// namespace. A host chooses storage and service scopes explicitly; importing
/// the package does not opt into Hanlin's CloudKit container or Keychain group.
@MainActor
public struct HanlinApplicationConfiguration {
    public enum Storage {
        /// An isolated SDK store under Application Support, scoped by the exact
        /// app/account/workspace identifiers. CloudKit is disabled.
        case applicationSupport
        case file(URL)
        case inMemory
        /// The original Hanlin app's existing store and CloudKit/test policy.
        /// Use the explicit `.hanlin` configuration when launching Hanlin itself.
        case hanlin
    }

    public let appIdentifier: String
    public let accountIdentifier: String
    public let workspaceIdentifier: String
    public let storage: Storage
    public let credentials: HanlinApplicationCredentials
    public let runtime: HanlinApplicationRuntimeConfiguration
    public let hostServices: HanlinApplicationHostServicesFactory?

    public init(appIdentifier: String, accountIdentifier: String = "default",
                workspaceIdentifier: String = "default", storage: Storage = .applicationSupport,
                credentials: HanlinApplicationCredentials? = nil,
                runtime: HanlinApplicationRuntimeConfiguration? = nil,
                hostServices: HanlinApplicationHostServicesFactory? = nil) {
        self.appIdentifier = appIdentifier
        self.accountIdentifier = accountIdentifier
        self.workspaceIdentifier = workspaceIdentifier
        self.storage = storage
        let credentialScope = SHA256.hash(data: Data((accountIdentifier + "\u{0}" + workspaceIdentifier).utf8))
            .map { String(format: "%02x", $0) }.joined()
        self.credentials = credentials ?? .init(service: appIdentifier + ".provider-credentials." + credentialScope)
        self.runtime = runtime ?? .applicationSupport(appIdentifier: appIdentifier)
        self.hostServices = hostServices
    }

    /// Preserves the original app's durable namespace, credentials and runtime.
    public static var hanlin: Self {
        .init(appIdentifier: "hanlin", accountIdentifier: "local-personal-library",
              workspaceIdentifier: "swiftdata", storage: .hanlin,
              credentials: .init(service: "com.itorah.chavrusachat.provider-credentials",
                  accessGroup: "group.com.itorah.chavrusachat", synchronizable: true),
              runtime: .applicationSupport(appIdentifier: "com.itorah.chavrusachat"))
    }

    func namespace(conversationID: UUID, temporary: Bool) throws -> HanlinConversationNamespace {
        let workspace = temporary
            ? (appIdentifier == "hanlin" && workspaceIdentifier == "swiftdata"
                ? "temporary" : workspaceIdentifier + ".temporary")
            : workspaceIdentifier
        return try .init(app: appIdentifier, account: accountIdentifier, workspace: workspace,
                         space: conversationID.uuidString)
    }

    func makeModelContainer() throws -> ModelContainer {
        let modelConfiguration: ModelConfiguration
        switch storage {
        case .hanlin:
            return try AppDataManager.makeDefaultModelContainer()
        case .inMemory:
            modelConfiguration = .init(schema: AppDataManager.schema,
                isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        case .file(let url):
            guard url.isFileURL else { throw HanlinApplicationError.invalidStorageURL }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            modelConfiguration = .init(schema: AppDataManager.schema, url: url, cloudKitDatabase: .none)
        case .applicationSupport:
            let identity = try JSONEncoder().encode([appIdentifier, accountIdentifier, workspaceIdentifier])
            let directoryName = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = support.appending(path: "HanlinSDK/" + directoryName, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            modelConfiguration = .init(schema: AppDataManager.schema,
                url: directory.appending(path: "Chat.store"), cloudKitDatabase: .none)
        }
        return try ModelContainer(for: AppDataManager.schema, configurations: [modelConfiguration])
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

/// Lock-protected metadata only. No ModelContext or secret is read under this
/// lock. Weak ownership prevents a released container's identity being reused.
final class HanlinApplicationCredentialRegistry: @unchecked Sendable {
    static let shared = HanlinApplicationCredentialRegistry()
    private final class Entry {
        weak var container: ModelContainer?
        let credentials: HanlinApplicationCredentials
        init(container: ModelContainer, credentials: HanlinApplicationCredentials) {
            self.container = container
            self.credentials = credentials
        }
    }
    private let lock = NSLock()
    private var entries: [ObjectIdentifier: Entry] = [:]

    func register(_ container: ModelContainer, credentials: HanlinApplicationCredentials) {
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { $0.value.container != nil }
        entries[ObjectIdentifier(container)] = Entry(container: container, credentials: credentials)
    }

    func credentials(for container: ModelContainer?) -> HanlinApplicationCredentials {
        lock.lock()
        defer { lock.unlock() }
        guard let container, let entry = entries[ObjectIdentifier(container)],
              entry.container === container else { return .currentHost }
        return entry.credentials
    }
}

/// The original native engines are singletons, so their configuration cannot be
/// replaced underneath existing jobs. Provider credentials and conversation
/// namespaces use the independent per-container registry above.
final class HanlinApplicationProcessRuntime: @unchecked Sendable {
    static let shared = HanlinApplicationProcessRuntime()
    private let lock = NSLock()
    private var installed: HanlinApplicationRuntimeConfiguration?
    private var modelContainer: ModelContainer?

    func install(_ configuration: HanlinApplicationRuntimeConfiguration, modelContainer: ModelContainer) throws {
        guard configuration.directory.isFileURL else { throw HanlinApplicationError.invalidStorageURL }
        lock.lock()
        defer { lock.unlock() }
        if let installed, installed != configuration {
            throw HanlinApplicationError.incompatibleRuntimeConfiguration
        }
        if let current = self.modelContainer, current !== modelContainer {
            throw HanlinApplicationError.incompatibleRuntimeContainer
        }
        installed = configuration
        self.modelContainer = modelContainer
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

@MainActor
enum HanlinApplicationContextRegistry {
    private final class Entry {
        weak var context: HanlinApplicationContext?
        init(_ context: HanlinApplicationContext) { self.context = context }
    }
    private static var entries: [ObjectIdentifier: Entry] = [:]
    /// Legacy internal callers in Hanlin itself continue to use its explicit
    /// application configuration after its context has been installed.
    private static var legacyConfiguration: HanlinApplicationConfiguration?

    static func register(_ context: HanlinApplicationContext) throws {
        entries = entries.filter { $0.value.context != nil }
        let id = ObjectIdentifier(context.modelContainer)
        guard entries[id]?.context == nil else { throw HanlinApplicationError.containerAlreadyRegistered }
        entries[id] = Entry(context)
        if case .hanlin = context.configuration.storage {
            legacyConfiguration = context.configuration
        }
    }

    static func configuration(for container: ModelContainer) -> HanlinApplicationConfiguration {
        if let context = entries[ObjectIdentifier(container)]?.context,
           context.modelContainer === container { return context.configuration }
        // Existing internal test/data contexts have no public facade. Preserve
        // the installed original app policy; unrelated hosts never inherit it.
        if let legacyConfiguration { return legacyConfiguration }
        return .init(appIdentifier: Bundle.main.bundleIdentifier ?? "HanlinHost")
    }
}
