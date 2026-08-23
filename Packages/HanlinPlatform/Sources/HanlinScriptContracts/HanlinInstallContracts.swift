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

public struct HanlinPackageEntrypointDescriptor: Codable, Hashable, Sendable {
    public let id: String
    public let kind: HanlinPackageEntrypointKind
    public let sourcePath: String
    public let exportedSymbol: String?
    public let supportedContexts: Set<HanlinExecutionContext>
    public let requiredCapabilities: [HanlinCapabilityRequest]
    public let runtimePolicyID: String
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
        self.artifactDigest = artifactDigest
        self.compatibility = compatibility
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
    public let manifest: HanlinScriptingManifest?

    public init(
        installedPackageID: HanlinInstalledPackageID,
        packageID: HanlinPackageID,
        version: HanlinPackageVersion,
        sourceDigest: String,
        entrypoints: [HanlinPackageEntrypointDescriptor],
        requestedCapabilities: [HanlinCapabilityRequest],
        manifest: HanlinScriptingManifest? = nil
    ) {
        self.installedPackageID = installedPackageID
        self.packageID = packageID
        self.version = version
        self.sourceDigest = sourceDigest
        self.entrypoints = entrypoints
        self.requestedCapabilities = requestedCapabilities
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
