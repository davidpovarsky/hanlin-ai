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
    public let profile: HanlinRuntimeProfile
    public let engine: String
    public let engineVersion: String
    public let abiVersion: HanlinScriptABIVersion
    public let cancellation: HanlinScriptCancellationCapabilities
    public let capabilities: HanlinRuntimeCapabilities
    public let minimumTrust: HanlinPackageTrust

    public init(
        kind: HanlinRuntimeKind,
        profile: HanlinRuntimeProfile? = nil,
        engine: String,
        engineVersion: String,
        abiVersion: HanlinScriptABIVersion,
        cancellation: HanlinScriptCancellationCapabilities,
        capabilities: HanlinRuntimeCapabilities? = nil,
        minimumTrust: HanlinPackageTrust? = nil
    ) {
        self.kind = kind
        let resolvedProfile = profile ?? Self.legacyProfile(for: kind)
        self.profile = resolvedProfile
        self.engine = engine
        self.engineVersion = engineVersion
        self.abiVersion = abiVersion
        self.cancellation = cancellation
        self.capabilities = capabilities ?? .canonical(for: resolvedProfile)
        self.minimumTrust = minimumTrust ?? Self.defaultMinimumTrust(for: resolvedProfile)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, profile, engine, engineVersion, abiVersion, cancellation, capabilities, minimumTrust
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(HanlinRuntimeKind.self, forKey: .kind)
        profile = try container.decodeIfPresent(HanlinRuntimeProfile.self, forKey: .profile)
            ?? Self.legacyProfile(for: kind)
        engine = try container.decode(String.self, forKey: .engine)
        engineVersion = try container.decode(String.self, forKey: .engineVersion)
        abiVersion = try container.decode(HanlinScriptABIVersion.self, forKey: .abiVersion)
        cancellation = try container.decode(HanlinScriptCancellationCapabilities.self, forKey: .cancellation)
        capabilities = try container.decodeIfPresent(HanlinRuntimeCapabilities.self, forKey: .capabilities)
            ?? .canonical(for: profile)
        minimumTrust = try container.decodeIfPresent(HanlinPackageTrust.self, forKey: .minimumTrust)
            ?? Self.defaultMinimumTrust(for: profile)
    }

    private static func legacyProfile(for kind: HanlinRuntimeKind) -> HanlinRuntimeProfile {
        switch kind {
        case .javaScriptCore: .scriptingJSC
        case .node, .mcp: .hanlinNode
        case .localPython: .hanlinPython
        default: .hanlinQuickJS
        }
    }

    private static func defaultMinimumTrust(for profile: HanlinRuntimeProfile) -> HanlinPackageTrust {
        switch profile {
        case .scriptingJSC, .hanlinQuickJS: .localUnverified
        case .hanlinNode: .publisherVerified
        case .hanlinPython: .integrityVerified
        }
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
    public let compilerProvenance: HanlinCompilerProvenance?
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
        compilerProvenance: HanlinCompilerProvenance? = nil,
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
        self.compilerProvenance = compilerProvenance
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
        if runtime.kind != runtime.profile.runtimeKind {
            issues.append(.init(
                code: .invalidRuntime,
                path: "runtime",
                message: "The runtime kind does not match its typed runtime profile."
            ))
        }
        if runtime.capabilities != .canonical(for: runtime.profile) {
            issues.append(.init(
                code: .invalidRuntime,
                path: "runtime.capabilities",
                message: "Runtime capabilities must match the canonical profile declaration."
            ))
        }
        guard let acceptedRuntime = support.runtimes[runtime.profile] else {
            issues.append(.init(
                code: .invalidRuntime,
                path: "runtime.profile",
                message: "Unsupported runtime profile '\(runtime.profile.rawValue)'."
            ))
            throw HanlinContractError.invalidManifest(issues)
        }
        if runtime.engine != acceptedRuntime.engine || runtime.engineVersion != acceptedRuntime.version {
            issues.append(.init(
                code: .invalidRuntime,
                path: "runtime.engineVersion",
                message: "Unsupported engine or engine version for '\(runtime.profile.rawValue)'."
            ))
        }
        if runtime.capabilities.hardInterruption
            && (!runtime.cancellation.interruptibleExecution || !runtime.cancellation.deadlineEnforcement) {
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
        let sourceExtension = URL(filePath: entrypoint.sourcePath).pathExtension.lowercased()
        let compiledExtension = URL(filePath: entrypoint.compiledPath).pathExtension.lowercased()
        let validEntrypointMapping = switch runtime.profile {
        case .hanlinPython:
            sourceExtension == "py" && compiledExtension == "py"
                && entrypoint.sourcePath == entrypoint.compiledPath
        case .scriptingJSC, .hanlinQuickJS, .hanlinNode:
            ["ts", "tsx", "js", "jsx"].contains(sourceExtension)
                && compiledExtension == "js"
                && entrypoint.sourcePath != entrypoint.compiledPath
        }
        if !validEntrypointMapping {
            issues.append(.init(
                code: .invalidCompiler,
                path: "entrypoint",
                message: runtime.profile == .hanlinPython
                    ? "A Python worker entrypoint must reference one integrity-checked Python source artifact."
                    : "A JavaScript worker entrypoint must map a supported source module to a distinct JavaScript artifact."
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
    public struct Runtime: Hashable, Sendable {
        public let engine: String
        public let version: String

        public init(engine: String, version: String) {
            self.engine = engine
            self.version = version
        }
    }

    public let manifestVersion: HanlinManifestVersion
    public let abiVersion: HanlinScriptABIVersion
    public let engine: String
    public let engineVersion: String
    public let compilerLane: String
    public let compilerVersion: String
    public let runtimes: [HanlinRuntimeProfile: Runtime]

    public init(
        manifestVersion: HanlinManifestVersion,
        abiVersion: HanlinScriptABIVersion,
        engine: String,
        engineVersion: String,
        compilerLane: String,
        compilerVersion: String,
        runtimes: [HanlinRuntimeProfile: Runtime]? = nil
    ) {
        self.manifestVersion = manifestVersion
        self.abiVersion = abiVersion
        self.engine = engine
        self.engineVersion = engineVersion
        self.compilerLane = compilerLane
        self.compilerVersion = compilerVersion
        self.runtimes = runtimes ?? [
            .hanlinQuickJS: .init(engine: engine, version: engineVersion)
        ]
    }

    public static let multiRuntime = Self(
        manifestVersion: .init(major: 1, minor: 0),
        abiVersion: .init(major: 1, minor: 0),
        engine: "JavaScriptCore", engineVersion: "Apple",
        compilerLane: "scripting-original", compilerVersion: "7.0.2",
        runtimes: [
            .scriptingJSC: .init(engine: "JavaScriptCore", version: "Apple"),
            .hanlinQuickJS: .init(engine: "quickjs-ng", version: "0.16.1"),
            .hanlinNode: .init(engine: "NodeMobile", version: "24.5.0"),
            .hanlinPython: .init(engine: "CPython", version: "3.14.6")
        ]
    )
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
