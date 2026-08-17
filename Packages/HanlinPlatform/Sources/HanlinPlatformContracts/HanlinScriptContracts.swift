import Foundation

public enum HanlinScriptDocumentKind: String, Codable, Hashable, Sendable {
    case assistantTool
}

public struct HanlinScriptCancellationCapabilities: Codable, Hashable, Sendable {
    public let interruptibleExecution: Bool
    public let deadlineEnforcement: Bool

    public init(
        interruptibleExecution: Bool,
        deadlineEnforcement: Bool
    ) {
        self.interruptibleExecution = interruptibleExecution
        self.deadlineEnforcement = deadlineEnforcement
    }
}

public struct HanlinScriptRuntimeDescriptor: Codable, Hashable, Sendable {
    public let kind: HanlinRuntimeKind
    public let engine: String
    public let engineVersion: String
    public let abiVersion: HanlinScriptABIVersion
    public let cancellation: HanlinScriptCancellationCapabilities

    public init(
        kind: HanlinRuntimeKind,
        engine: String,
        engineVersion: String,
        abiVersion: HanlinScriptABIVersion,
        cancellation: HanlinScriptCancellationCapabilities
    ) {
        self.kind = kind
        self.engine = engine
        self.engineVersion = engineVersion
        self.abiVersion = abiVersion
        self.cancellation = cancellation
    }
}

public struct HanlinScriptExportedTool: Codable, Hashable, Sendable {
    public let id: HanlinToolID
    public let title: LocalizedValue
    public let summary: LocalizedValue
    public let inputSchema: HanlinJSONSchemaDocument
    public let outputSchema: HanlinJSONSchemaDocument?
    public let requiredCapabilities: [HanlinCapabilityID]
    public let risk: HanlinRiskLevel
    public let requiresApproval: Bool

    public init(
        id: HanlinToolID,
        title: LocalizedValue,
        summary: LocalizedValue,
        inputSchema: HanlinJSONSchemaDocument,
        outputSchema: HanlinJSONSchemaDocument? = nil,
        requiredCapabilities: [HanlinCapabilityID] = [],
        risk: HanlinRiskLevel = .passive,
        requiresApproval: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.requiredCapabilities = requiredCapabilities
        self.risk = risk
        self.requiresApproval = requiresApproval
    }
}

public struct HanlinScriptEntrypoint: Codable, Hashable, Sendable {
    public let documentKind: HanlinScriptDocumentKind
    public let sourcePath: String
    public let compiledPath: String
    public let compilerLane: String
    public let compilerVersion: String
    public let compilerConfigurationHash: String
    public let sourceIntegrity: HanlinIntegrityDeclaration
    public let compiledIntegrity: HanlinIntegrityDeclaration
    public let exportedTools: [HanlinScriptExportedTool]

    public init(
        documentKind: HanlinScriptDocumentKind,
        sourcePath: String,
        compiledPath: String,
        compilerLane: String,
        compilerVersion: String,
        compilerConfigurationHash: String,
        sourceIntegrity: HanlinIntegrityDeclaration,
        compiledIntegrity: HanlinIntegrityDeclaration,
        exportedTools: [HanlinScriptExportedTool]
    ) {
        self.documentKind = documentKind
        self.sourcePath = sourcePath
        self.compiledPath = compiledPath
        self.compilerLane = compilerLane
        self.compilerVersion = compilerVersion
        self.compilerConfigurationHash = compilerConfigurationHash
        self.sourceIntegrity = sourceIntegrity
        self.compiledIntegrity = compiledIntegrity
        self.exportedTools = exportedTools
    }
}

public struct HanlinScriptPackageManifest: Codable, Hashable, Sendable {
    public let schemaVersion: HanlinManifestVersion
    public let descriptorRevision: HanlinDescriptorRevision
    public let packageID: HanlinPackageID
    public let version: HanlinPackageVersion
    public let displayName: LocalizedValue
    public let runtime: HanlinScriptRuntimeDescriptor
    public let entrypoint: HanlinScriptEntrypoint
    public let integrity: HanlinIntegrityDeclaration

    public init(
        schemaVersion: HanlinManifestVersion,
        descriptorRevision: HanlinDescriptorRevision,
        packageID: HanlinPackageID,
        version: HanlinPackageVersion,
        displayName: LocalizedValue,
        runtime: HanlinScriptRuntimeDescriptor,
        entrypoint: HanlinScriptEntrypoint,
        integrity: HanlinIntegrityDeclaration
    ) {
        self.schemaVersion = schemaVersion
        self.descriptorRevision = descriptorRevision
        self.packageID = packageID
        self.version = version
        self.displayName = displayName
        self.runtime = runtime
        self.entrypoint = entrypoint
        self.integrity = integrity
    }

    public func canonicalJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Deterministic package authorization material. The declared digest is
    /// deliberately excluded so callers can hash this representation.
    public func integrityMaterialJSONData() throws -> Data {
        let material = IntegrityMaterial(
            schemaVersion: schemaVersion,
            descriptorRevision: descriptorRevision,
            packageID: packageID,
            version: version,
            displayName: displayName,
            runtime: runtime,
            entrypoint: entrypoint
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(material)
    }

    public static func decodeAndValidate(
        _ data: Data,
        support: HanlinScriptContractSupport
    ) throws -> Self {
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        try manifest.validate(support: support)
        return manifest
    }

    public func validate(support: HanlinScriptContractSupport) throws {
        var issues: [HanlinManifestIssue] = []
        if schemaVersion != support.manifestVersion {
            issues.append(.init(
                code: .unsupportedManifestVersion,
                path: "schemaVersion",
                message: "Unsupported Script manifest version '\(schemaVersion.rawValue)'."
            ))
        }
        if runtime.kind != .quickJS || runtime.engine != support.engine {
            issues.append(.init(
                code: .invalidRuntime,
                path: "runtime",
                message: "The Script runtime must use the configured isolated engine."
            ))
        }
        if runtime.engineVersion != support.engineVersion {
            issues.append(.init(
                code: .invalidRuntime,
                path: "runtime.engineVersion",
                message: "Unsupported Script engine version '\(runtime.engineVersion)'."
            ))
        }
        if !runtime.cancellation.interruptibleExecution
            || !runtime.cancellation.deadlineEnforcement {
            issues.append(.init(
                code: .invalidRuntime,
                path: "runtime.cancellation",
                message: "The Script runtime declaration must require interruption and deadlines."
            ))
        }
        if runtime.abiVersion != support.abiVersion {
            issues.append(.init(
                code: .unsupportedScriptABI,
                path: "runtime.abiVersion",
                message: "Unsupported Script ABI version '\(runtime.abiVersion.rawValue)'."
            ))
        }
        if entrypoint.compilerLane != support.compilerLane
            || entrypoint.compilerVersion != support.compilerVersion {
            issues.append(.init(
                code: .invalidCompiler,
                path: "entrypoint.compilerVersion",
                message: "The Script compiler lane or version is unsupported."
            ))
        }
        if !Self.isCanonicalSHA256(entrypoint.compilerConfigurationHash) {
            issues.append(.init(
                code: .invalidCompiler,
                path: "entrypoint.compilerConfigurationHash",
                message: "The Script compiler configuration hash is invalid."
            ))
        }
        for (path, value) in [
            ("entrypoint.sourcePath", entrypoint.sourcePath),
            ("entrypoint.compiledPath", entrypoint.compiledPath)
        ] where !Self.isSafeRelativePath(value) {
            issues.append(.init(
                code: .unsafeEntryPoint,
                path: path,
                message: "Script entry paths must be normalized package-local relative paths."
            ))
        }
        if !entrypoint.sourcePath.hasSuffix(".ts")
            || !entrypoint.compiledPath.hasSuffix(".js")
            || entrypoint.sourcePath == entrypoint.compiledPath {
            issues.append(.init(
                code: .invalidCompiler,
                path: "entrypoint",
                message: "A Script entrypoint must map a TypeScript source to a distinct JavaScript artifact."
            ))
        }
        if entrypoint.exportedTools.isEmpty {
            issues.append(.init(
                code: .missingScriptTool,
                path: "entrypoint.exportedTools",
                message: "A Script entrypoint must export at least one tool."
            ))
        }
        var toolIDs: Set<HanlinToolID> = []
        do {
            _ = try LocalizedValue(
                displayName.values,
                fallbackLocale: displayName.fallbackLocale
            )
        } catch {
            issues.append(.init(
                code: .invalidSchema,
                path: "displayName",
                message: error.localizedDescription
            ))
        }
        for (index, tool) in entrypoint.exportedTools.enumerated() {
            if !toolIDs.insert(tool.id).inserted {
                issues.append(.init(
                    code: .duplicateTool,
                    path: "entrypoint.exportedTools[\(index)].id",
                    message: "Duplicate Script local tool identifiers are not allowed."
                ))
            }
            if tool.inputSchema.findings.contains(where: { $0.severity == .error })
                || tool.outputSchema?.findings.contains(where: {
                    $0.severity == .error
                }) == true {
                issues.append(.init(
                    code: .invalidSchema,
                    path: "entrypoint.exportedTools[\(index)]",
                    message: "Script tool schemas cannot contain error findings."
                ))
            }
            do {
                _ = try LocalizedValue(
                    tool.title.values,
                    fallbackLocale: tool.title.fallbackLocale
                )
                _ = try LocalizedValue(
                    tool.summary.values,
                    fallbackLocale: tool.summary.fallbackLocale
                )
                _ = try HanlinJSONSchemaDocument(
                    dialect: tool.inputSchema.dialect,
                    root: tool.inputSchema.root,
                    contentHash: tool.inputSchema.contentHash,
                    sourceProviderInstanceID: tool.inputSchema.sourceProviderInstanceID,
                    findings: tool.inputSchema.findings
                )
                _ = try tool.inputSchema.canonicalJSONData()
                if let outputSchema = tool.outputSchema {
                    _ = try HanlinJSONSchemaDocument(
                        dialect: outputSchema.dialect,
                        root: outputSchema.root,
                        contentHash: outputSchema.contentHash,
                        sourceProviderInstanceID: outputSchema.sourceProviderInstanceID,
                        findings: outputSchema.findings
                    )
                    _ = try outputSchema.canonicalJSONData()
                }
            } catch {
                issues.append(.init(
                    code: .invalidSchema,
                    path: "entrypoint.exportedTools[\(index)]",
                    message: error.localizedDescription
                ))
            }
        }
        for (path, declaration) in [
            ("integrity", integrity),
            ("entrypoint.sourceIntegrity", entrypoint.sourceIntegrity),
            ("entrypoint.compiledIntegrity", entrypoint.compiledIntegrity)
        ] where !Self.isCanonicalSHA256(declaration) {
            issues.append(.init(
                code: .invalidIntegrity,
                path: path,
                message: "Script SHA-256 digests must be lowercase hexadecimal."
            ))
        }
        guard issues.isEmpty else {
            throw HanlinContractError.invalidManifest(issues)
        }
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.hasPrefix("\\"),
              !value.contains("\\"),
              !value.contains(":"),
              !value.contains("\0")
        else {
            return false
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }

    private static func isCanonicalSHA256(
        _ declaration: HanlinIntegrityDeclaration
    ) -> Bool {
        declaration.algorithm == .sha256
            && isCanonicalSHA256(declaration.digest)
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy { byte in
                (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
            }
    }

    private struct IntegrityMaterial: Encodable {
        let schemaVersion: HanlinManifestVersion
        let descriptorRevision: HanlinDescriptorRevision
        let packageID: HanlinPackageID
        let version: HanlinPackageVersion
        let displayName: LocalizedValue
        let runtime: HanlinScriptRuntimeDescriptor
        let entrypoint: HanlinScriptEntrypoint
    }
}

public struct HanlinScriptContractSupport: Hashable, Sendable {
    public let manifestVersion: HanlinManifestVersion
    public let abiVersion: HanlinScriptABIVersion
    public let engine: String
    public let engineVersion: String
    public let compilerLane: String
    public let compilerVersion: String

    public init(
        manifestVersion: HanlinManifestVersion,
        abiVersion: HanlinScriptABIVersion,
        engine: String,
        engineVersion: String,
        compilerLane: String,
        compilerVersion: String
    ) {
        self.manifestVersion = manifestVersion
        self.abiVersion = abiVersion
        self.engine = engine
        self.engineVersion = engineVersion
        self.compilerLane = compilerLane
        self.compilerVersion = compilerVersion
    }
}

public struct HanlinScriptExecutionLimits: Codable, Hashable, Sendable {
    public let timeoutMilliseconds: Int64
    public let maximumOutputBytes: Int
    public let maximumMemoryBytes: Int64?

    public init(
        timeoutMilliseconds: Int64,
        maximumOutputBytes: Int,
        maximumMemoryBytes: Int64? = nil
    ) throws {
        guard timeoutMilliseconds > 0,
              maximumOutputBytes > 0,
              maximumOutputBytes <= 8 * 1_048_576,
              maximumMemoryBytes.map({ $0 > 0 }) ?? true
        else {
            throw HanlinContractError.invalidSchema(reason: "invalid script execution limits")
        }
        self.timeoutMilliseconds = timeoutMilliseconds
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumMemoryBytes = maximumMemoryBytes
    }
}

public struct HanlinScriptExecutionRequest: Codable, Hashable, Sendable {
    public let id: HanlinScriptExecutionID
    public let runtimeSessionID: HanlinRuntimeSessionID
    public let installedPackageID: HanlinInstalledPackageID
    public let appID: HanlinAppID?
    public let logicalEntryPoint: String
    public let compilerLane: String
    public let compilerVersion: String
    public let compilerConfigurationHash: String
    public let parameters: HanlinValue
    public let grantIDs: [HanlinGrantID]
    public let limits: HanlinScriptExecutionLimits

    public init(
        id: HanlinScriptExecutionID,
        runtimeSessionID: HanlinRuntimeSessionID,
        installedPackageID: HanlinInstalledPackageID,
        appID: HanlinAppID? = nil,
        logicalEntryPoint: String,
        compilerLane: String,
        compilerVersion: String,
        compilerConfigurationHash: String,
        parameters: HanlinValue,
        grantIDs: [HanlinGrantID] = [],
        limits: HanlinScriptExecutionLimits
    ) {
        self.id = id
        self.runtimeSessionID = runtimeSessionID
        self.installedPackageID = installedPackageID
        self.appID = appID
        self.logicalEntryPoint = logicalEntryPoint
        self.compilerLane = compilerLane
        self.compilerVersion = compilerVersion
        self.compilerConfigurationHash = compilerConfigurationHash
        self.parameters = parameters
        self.grantIDs = grantIDs
        self.limits = limits
    }
}

public enum HanlinScriptExecutionOutcome: Codable, Hashable, Sendable {
    case completed(HanlinValue?)
    case compileOnly(diagnostics: [String])
    case failed(HanlinPlatformError)
    case cancelled(HanlinCancellationID)
    case timedOut
}

public struct HanlinScriptExecutionResult: Codable, Hashable, Sendable {
    public let executionID: HanlinScriptExecutionID
    public let outcome: HanlinScriptExecutionOutcome
    public let startedAt: Date?
    public let completedAt: Date

    public init(
        executionID: HanlinScriptExecutionID,
        outcome: HanlinScriptExecutionOutcome,
        startedAt: Date? = nil,
        completedAt: Date
    ) {
        self.executionID = executionID
        self.outcome = outcome
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public enum HanlinScriptStreamKind: String, Codable, Hashable, Sendable {
    case standardOutput
    case standardError
    case progress
    case value
    case terminal
}

public struct HanlinScriptStreamEvent: Codable, Hashable, Sendable {
    public let executionID: HanlinScriptExecutionID
    public let sequence: UInt64
    public let timestamp: Date
    public let kind: HanlinScriptStreamKind
    public let payload: HanlinValue

    public init(
        executionID: HanlinScriptExecutionID,
        sequence: UInt64,
        timestamp: Date,
        kind: HanlinScriptStreamKind,
        payload: HanlinValue
    ) {
        self.executionID = executionID
        self.sequence = sequence
        self.timestamp = timestamp
        self.kind = kind
        self.payload = payload
    }
}
