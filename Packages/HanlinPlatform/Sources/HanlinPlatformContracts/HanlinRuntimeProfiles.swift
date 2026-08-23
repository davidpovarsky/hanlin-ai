import Foundation

public enum HanlinRuntimeProfile: String, Codable, CaseIterable, Hashable, Sendable {
    case scriptingJSC = "scripting-jsc"
    case hanlinQuickJS = "hanlin-quickjs"
    case hanlinNode = "hanlin-node"
    case hanlinPython = "hanlin-python"

    public var runtimeKind: HanlinRuntimeKind {
        switch self {
        case .scriptingJSC: .javaScriptCore
        case .hanlinQuickJS: .quickJS
        case .hanlinNode: .node
        case .hanlinPython: .localPython
        }
    }
}

public enum HanlinRuntimeFilesystemModel: String, Codable, Hashable, Sendable {
    case none
    case capabilityBroker
    case verifiedWorkspace
}

public enum HanlinRuntimeNetworkModel: String, Codable, Hashable, Sendable {
    case none
    case capabilityBroker
    case trustedWorkerPolicy
}

public enum HanlinPackageTrust: String, Codable, CaseIterable, Hashable, Sendable {
    case localUnverified
    case integrityVerified
    case publisherVerified
    case bundledTrusted

    public var rank: Int {
        switch self {
        case .localUnverified: 0
        case .integrityVerified: 1
        case .publisherVerified: 2
        case .bundledTrusted: 3
        }
    }

    public func satisfies(_ minimum: Self) -> Bool { rank >= minimum.rank }
}

public struct HanlinRuntimeCapabilities: Codable, Hashable, Sendable {
    public let persistentContext: Bool
    public let hardMemoryLimit: Bool
    public let hardStackLimit: Bool
    public let hardInterruption: Bool
    public let asyncHostCalls: Bool
    public let modules: Bool
    public let scriptUI: Bool
    public let extensionSafe: Bool
    public let trustedCodeOnly: Bool
    public let filesystem: HanlinRuntimeFilesystemModel
    public let network: HanlinRuntimeNetworkModel

    public static func canonical(for profile: HanlinRuntimeProfile) -> Self {
        switch profile {
        case .scriptingJSC:
            .init(persistentContext: true, hardMemoryLimit: false, hardStackLimit: false,
                  hardInterruption: false, asyncHostCalls: true, modules: true, scriptUI: true,
                  extensionSafe: true, trustedCodeOnly: false, filesystem: .capabilityBroker,
                  network: .capabilityBroker)
        case .hanlinQuickJS:
            .init(persistentContext: true, hardMemoryLimit: true, hardStackLimit: true,
                  hardInterruption: true, asyncHostCalls: true, modules: true, scriptUI: true,
                  extensionSafe: true, trustedCodeOnly: false, filesystem: .capabilityBroker,
                  network: .capabilityBroker)
        case .hanlinNode:
            .init(persistentContext: true, hardMemoryLimit: false, hardStackLimit: false,
                  hardInterruption: true, asyncHostCalls: true, modules: true, scriptUI: false,
                  extensionSafe: false, trustedCodeOnly: true, filesystem: .verifiedWorkspace,
                  network: .trustedWorkerPolicy)
        case .hanlinPython:
            .init(persistentContext: true, hardMemoryLimit: false, hardStackLimit: false,
                  hardInterruption: false, asyncHostCalls: true, modules: true, scriptUI: false,
                  extensionSafe: false, trustedCodeOnly: true, filesystem: .verifiedWorkspace,
                  network: .capabilityBroker)
        }
    }

    public init(
        persistentContext: Bool, hardMemoryLimit: Bool, hardStackLimit: Bool,
        hardInterruption: Bool, asyncHostCalls: Bool, modules: Bool, scriptUI: Bool,
        extensionSafe: Bool, trustedCodeOnly: Bool, filesystem: HanlinRuntimeFilesystemModel,
        network: HanlinRuntimeNetworkModel
    ) {
        self.persistentContext = persistentContext
        self.hardMemoryLimit = hardMemoryLimit
        self.hardStackLimit = hardStackLimit
        self.hardInterruption = hardInterruption
        self.asyncHostCalls = asyncHostCalls
        self.modules = modules
        self.scriptUI = scriptUI
        self.extensionSafe = extensionSafe
        self.trustedCodeOnly = trustedCodeOnly
        self.filesystem = filesystem
        self.network = network
    }
}

public struct HanlinCompilerProvenance: Codable, Hashable, Sendable {
    public let typecheckCompilerVersion: String
    public let emitterVersion: String
    public let bundlerVersion: String
    public let runtimeEngineVersion: String
    public let typecheckConfigurationHash: String
    public let emitterConfigurationHash: String
    public let bundlerConfigurationHash: String

    public init(
        typecheckCompilerVersion: String, emitterVersion: String, bundlerVersion: String,
        runtimeEngineVersion: String, typecheckConfigurationHash: String,
        emitterConfigurationHash: String, bundlerConfigurationHash: String
    ) {
        self.typecheckCompilerVersion = typecheckCompilerVersion
        self.emitterVersion = emitterVersion
        self.bundlerVersion = bundlerVersion
        self.runtimeEngineVersion = runtimeEngineVersion
        self.typecheckConfigurationHash = typecheckConfigurationHash
        self.emitterConfigurationHash = emitterConfigurationHash
        self.bundlerConfigurationHash = bundlerConfigurationHash
    }
}
