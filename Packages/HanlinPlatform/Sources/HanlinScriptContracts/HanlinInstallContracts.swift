import Foundation
import HanlinPlatformContracts

public enum HanlinPackageEntrypointKind: String, Codable, CaseIterable, Hashable, Sendable {
    case app
    case assistantTool
    case widget
    case appIntent
    case liveActivity
    case spotlight
    case quickLook
    case share
    case capture
    case safariExtension
}

public enum HanlinCompatibilityState: String, Codable, Hashable, Sendable {
    case supported
    case partial
    case unsupported
}

public struct HanlinCompatibilityFinding: Codable, Hashable, Sendable {
    public let state: HanlinCompatibilityState
    public let severity: HanlinDiagnosticSeverity
    public let symbol: String?
    public let sourcePath: String?
    public let message: String
    public let rationale: String?

    public init(
        state: HanlinCompatibilityState,
        severity: HanlinDiagnosticSeverity,
        symbol: String? = nil,
        sourcePath: String? = nil,
        message: String,
        rationale: String? = nil
    ) {
        self.state = state
        self.severity = severity
        self.symbol = symbol
        self.sourcePath = sourcePath
        self.message = message
        self.rationale = rationale
    }
}

public struct HanlinCapabilityRequest: Codable, Hashable, Sendable {
    public let capabilityID: HanlinCapabilityID
    public let required: Bool
    public let scope: HanlinJSONValue
    public let purpose: String

    public init(
        capabilityID: HanlinCapabilityID,
        required: Bool,
        scope: HanlinJSONValue = .object([:]),
        purpose: String
    ) {
        self.capabilityID = capabilityID
        self.required = required
        self.scope = scope
        self.purpose = purpose
    }
}

public struct HanlinCapabilityApprovalState: Codable, Hashable, Sendable {
    public let requests: [HanlinCapabilityRequest]
    public private(set) var approvedCapabilities: Set<HanlinCapabilityID>

    public init(
        requests: [HanlinCapabilityRequest],
        approvedCapabilities: Set<HanlinCapabilityID> = []
    ) {
        var normalized: [HanlinCapabilityID: HanlinCapabilityRequest] = [:]
        for request in requests {
            if let current = normalized[request.capabilityID], current.required, !request.required {
                continue
            }
            normalized[request.capabilityID] = request
        }
        self.requests = normalized.values.sorted {
            $0.capabilityID.rawValue < $1.capabilityID.rawValue
        }
        let requested = Set(normalized.keys)
        self.approvedCapabilities = approvedCapabilities.intersection(requested)
    }

    public var requiredCapabilities: Set<HanlinCapabilityID> {
        Set(requests.filter(\.required).map(\.capabilityID))
    }

    public var missingRequiredCapabilities: [HanlinCapabilityID] {
        requiredCapabilities.subtracting(approvedCapabilities).sorted {
            $0.rawValue < $1.rawValue
        }
    }

    public var hasApprovedEveryRequiredCapability: Bool {
        missingRequiredCapabilities.isEmpty
    }

    public mutating func setApproved(_ approved: Bool, capability: HanlinCapabilityID) {
        guard requests.contains(where: { $0.capabilityID == capability }) else { return }
        if approved {
            approvedCapabilities.insert(capability)
        } else {
            approvedCapabilities.remove(capability)
        }
    }
}

public struct HanlinPackageEntrypointDescriptor: Codable, Hashable, Sendable {
    public let id: String
    public let kind: HanlinPackageEntrypointKind
    public let sourcePath: String
    public let exportedSymbol: String?
    public let supportedContexts: Set<HanlinExecutionContext>
    public let requiredCapabilities: [HanlinCapabilityRequest]
    public let runtimePolicyID: String
    public let runtimeProfile: HanlinRuntimeProfile
    public let artifactDigest: String?
    public let compatibility: HanlinCompatibilityState

    public init(
        id: String,
        kind: HanlinPackageEntrypointKind,
        sourcePath: String,
        exportedSymbol: String? = nil,
        supportedContexts: Set<HanlinExecutionContext>,
        requiredCapabilities: [HanlinCapabilityRequest] = [],
        runtimePolicyID: String,
        runtimeProfile: HanlinRuntimeProfile = .scriptingJSC,
        artifactDigest: String? = nil,
        compatibility: HanlinCompatibilityState
    ) {
        self.id = id
        self.kind = kind
        self.sourcePath = sourcePath
        self.exportedSymbol = exportedSymbol
        self.supportedContexts = supportedContexts
        self.requiredCapabilities = requiredCapabilities
        self.runtimePolicyID = runtimePolicyID
        self.runtimeProfile = runtimeProfile
        self.artifactDigest = artifactDigest
        self.compatibility = compatibility
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, sourcePath, exportedSymbol, supportedContexts, requiredCapabilities
        case runtimePolicyID, runtimeProfile, artifactDigest, compatibility
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(HanlinPackageEntrypointKind.self, forKey: .kind)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        exportedSymbol = try container.decodeIfPresent(String.self, forKey: .exportedSymbol)
        supportedContexts = try container.decode(Set<HanlinExecutionContext>.self, forKey: .supportedContexts)
        requiredCapabilities = try container.decodeIfPresent([HanlinCapabilityRequest].self, forKey: .requiredCapabilities) ?? []
        runtimePolicyID = try container.decode(String.self, forKey: .runtimePolicyID)
        runtimeProfile = try container.decodeIfPresent(HanlinRuntimeProfile.self, forKey: .runtimeProfile)
            ?? (sourcePath.lowercased().hasSuffix(".py") ? .hanlinPython : .hanlinQuickJS)
        artifactDigest = try container.decodeIfPresent(String.self, forKey: .artifactDigest)
        compatibility = try container.decode(HanlinCompatibilityState.self, forKey: .compatibility)
    }
}

public struct HanlinPackageResourceDescriptor: Codable, Hashable, Sendable {
    public let logicalPath: String
    public let byteCount: Int64
    public let sha256: String
    public let mediaType: String?

    public init(logicalPath: String, byteCount: Int64, sha256: String, mediaType: String? = nil) {
        self.logicalPath = logicalPath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.mediaType = mediaType
    }
}

public struct HanlinPackageDependencyEdge: Codable, Hashable, Sendable {
    public let importer: String
    public let specifier: String
    public let resolvedPath: String?

    public init(importer: String, specifier: String, resolvedPath: String?) {
        self.importer = importer
        self.specifier = specifier
        self.resolvedPath = resolvedPath
    }
}

public struct HanlinPackageDependencyGraph: Codable, Hashable, Sendable {
    public let modules: [String]
    public let edges: [HanlinPackageDependencyEdge]
    public let unresolvedSpecifiers: [String]

    public init(
        modules: [String],
        edges: [HanlinPackageDependencyEdge],
        unresolvedSpecifiers: [String] = []
    ) {
        self.modules = modules
        self.edges = edges
        self.unresolvedSpecifiers = unresolvedSpecifiers
    }
}

public struct HanlinImportPreview: Codable, Hashable, Sendable {
    public let source: HanlinImportedPackageSource
    public let archive: HanlinArchiveInspection
    public let manifest: HanlinScriptingManifest?
    public let entrypoints: [HanlinPackageEntrypointDescriptor]
    public let dependencyGraph: HanlinPackageDependencyGraph
    public let requestedCapabilities: [HanlinCapabilityRequest]
    public let findings: [HanlinCompatibilityFinding]
    public let sourceBytes: Int64
    public let extractedBytes: Int64

    public init(
        source: HanlinImportedPackageSource,
        archive: HanlinArchiveInspection,
        manifest: HanlinScriptingManifest?,
        entrypoints: [HanlinPackageEntrypointDescriptor],
        dependencyGraph: HanlinPackageDependencyGraph,
        requestedCapabilities: [HanlinCapabilityRequest],
        findings: [HanlinCompatibilityFinding],
        sourceBytes: Int64,
        extractedBytes: Int64
    ) {
        self.source = source
        self.archive = archive
        self.manifest = manifest
        self.entrypoints = entrypoints
        self.dependencyGraph = dependencyGraph
        self.requestedCapabilities = requestedCapabilities
        self.findings = findings
        self.sourceBytes = sourceBytes
        self.extractedBytes = extractedBytes
    }

    public var canInstall: Bool {
        archive.isInstallable && !findings.contains { $0.severity == .error }
    }
}

public struct HanlinInstallPlan: Codable, Hashable, Sendable {
    public let installedPackageID: HanlinInstalledPackageID
    public let packageID: HanlinPackageID
    public let version: HanlinPackageVersion
    public let sourceDigest: String
    public let entrypoints: [HanlinPackageEntrypointDescriptor]
    public let requestedCapabilities: [HanlinCapabilityRequest]
    public let grantedCapabilities: [HanlinCapabilityID]
    public let manifest: HanlinScriptingManifest?

    public init(
        installedPackageID: HanlinInstalledPackageID,
        packageID: HanlinPackageID,
        version: HanlinPackageVersion,
        sourceDigest: String,
        entrypoints: [HanlinPackageEntrypointDescriptor],
        requestedCapabilities: [HanlinCapabilityRequest],
        grantedCapabilities: [HanlinCapabilityID] = [],
        manifest: HanlinScriptingManifest? = nil
    ) {
        self.installedPackageID = installedPackageID
        self.packageID = packageID
        self.version = version
        self.sourceDigest = sourceDigest
        self.entrypoints = entrypoints
        self.requestedCapabilities = requestedCapabilities
        self.grantedCapabilities = grantedCapabilities.sorted { $0.rawValue < $1.rawValue }
        self.manifest = manifest
    }
}

public struct HanlinInstalledPackageRecord: Codable, Hashable, Sendable {
    public let schemaVersion: UInt32
    public let installedPackageID: HanlinInstalledPackageID
    public let packageID: HanlinPackageID
    public let version: HanlinPackageVersion
    public let sourceDigest: String
    public let artifactDigest: String
    public let activeGeneration: UInt64
    public let installedAt: Date
    public let updatedAt: Date

    public init(
        schemaVersion: UInt32 = 1,
        installedPackageID: HanlinInstalledPackageID,
        packageID: HanlinPackageID,
        version: HanlinPackageVersion,
        sourceDigest: String,
        artifactDigest: String,
        activeGeneration: UInt64,
        installedAt: Date,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.installedPackageID = installedPackageID
        self.packageID = packageID
        self.version = version
        self.sourceDigest = sourceDigest
        self.artifactDigest = artifactDigest
        self.activeGeneration = activeGeneration
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }
}

public struct HanlinArtifactFile: Codable, Hashable, Sendable {
    public let logicalPath: String
    public let sha256: String
    public let byteCount: Int64
    public let context: HanlinPackageEntrypointKind

    public init(logicalPath: String, sha256: String, byteCount: Int64, context: HanlinPackageEntrypointKind) {
        self.logicalPath = logicalPath
        self.sha256 = sha256
        self.byteCount = byteCount
        self.context = context
    }
}

public struct HanlinPackageArtifactManifest: Codable, Hashable, Sendable {
    public let schemaVersion: UInt32
    public let compilerVersion: String
    public let compilerIntegrity: String
    public let compilerOptionsHash: String
    public let baselineID: String
    public let baselineDigest: String
    public let hanlinABIVersion: String
    public let packageContentDigest: String
    public let cacheFingerprint: String
    public let files: [HanlinArtifactFile]

    public init(
        schemaVersion: UInt32 = 1,
        compilerVersion: String,
        compilerIntegrity: String,
        compilerOptionsHash: String,
        baselineID: String,
        baselineDigest: String,
        hanlinABIVersion: String,
        packageContentDigest: String,
        cacheFingerprint: String,
        files: [HanlinArtifactFile]
    ) {
        self.schemaVersion = schemaVersion
        self.compilerVersion = compilerVersion
        self.compilerIntegrity = compilerIntegrity
        self.compilerOptionsHash = compilerOptionsHash
        self.baselineID = baselineID
        self.baselineDigest = baselineDigest
        self.hanlinABIVersion = hanlinABIVersion
        self.packageContentDigest = packageContentDigest
        self.cacheFingerprint = cacheFingerprint
        self.files = files
    }
}

public struct HanlinPackageUpdatePlan: Codable, Hashable, Sendable {
    public let installedPackageID: HanlinInstalledPackageID
    public let currentVersion: HanlinPackageVersion
    public let proposedVersion: HanlinPackageVersion
    public let currentDigest: String
    public let proposedDigest: String
    public let addedCapabilities: [HanlinCapabilityRequest]
    public let removedCapabilities: [HanlinCapabilityRequest]
    public let rollbackGeneration: UInt64

    public init(
        installedPackageID: HanlinInstalledPackageID,
        currentVersion: HanlinPackageVersion,
        proposedVersion: HanlinPackageVersion,
        currentDigest: String,
        proposedDigest: String,
        addedCapabilities: [HanlinCapabilityRequest],
        removedCapabilities: [HanlinCapabilityRequest],
        rollbackGeneration: UInt64
    ) {
        self.installedPackageID = installedPackageID
        self.currentVersion = currentVersion
        self.proposedVersion = proposedVersion
        self.currentDigest = currentDigest
        self.proposedDigest = proposedDigest
        self.addedCapabilities = addedCapabilities
        self.removedCapabilities = removedCapabilities
        self.rollbackGeneration = rollbackGeneration
    }
}
