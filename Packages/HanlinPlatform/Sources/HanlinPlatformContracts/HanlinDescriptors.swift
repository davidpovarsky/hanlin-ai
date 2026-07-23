import Foundation

public struct LocalizedValue: Codable, Hashable, Sendable {
    public let values: [String: String]
    public let fallbackLocale: String

    public init(
        _ values: [String: String],
        fallbackLocale: String = "en"
    ) throws {
        guard !values.isEmpty else {
            throw HanlinContractError.invalidLocalizedValue(
                reason: "at least one localization is required"
            )
        }
        guard values[fallbackLocale]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw HanlinContractError.invalidLocalizedValue(
                reason: "fallback locale '\(fallbackLocale)' is missing or empty"
            )
        }
        for (locale, value) in values {
            guard Self.isCanonicalLocale(locale) else {
                throw HanlinContractError.invalidLocalizedValue(
                    reason: "locale '\(locale)' is not canonical"
                )
            }
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HanlinContractError.invalidLocalizedValue(
                    reason: "locale '\(locale)' has an empty value"
                )
            }
        }
        self.values = values
        self.fallbackLocale = fallbackLocale
    }

    public func resolved(locale: Locale) -> String {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if let exact = values[identifier] {
            return exact
        }
        if let language = locale.language.languageCode?.identifier,
           let languageValue = values[language]
        {
            return languageValue
        }
        return values[fallbackLocale] ?? values.values.sorted().first ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case values
        case fallbackLocale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            container.decode([String: String].self, forKey: .values),
            fallbackLocale: container.decode(
                String.self,
                forKey: .fallbackLocale
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(values, forKey: .values)
        try container.encode(fallbackLocale, forKey: .fallbackLocale)
    }

    private static func isCanonicalLocale(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 35 else {
            return false
        }
        let components = value.split(separator: "-", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0.isEmpty }) else {
            return false
        }
        return components.allSatisfy { component in
            component.unicodeScalars.allSatisfy { scalar in
                scalar.value < 128 && CharacterSet.alphanumerics.contains(scalar)
            }
        }
    }
}

public enum HanlinExecutionOrigin: String, Codable, CaseIterable, Hashable, Sendable {
    case system
    case nativeModule
    case scriptPackage
    case assistantModel
    case mcpServer
    case userAutomation
    case appExtension
}

public enum HanlinRiskLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case passive
    case read
    case sensitiveRead
    case write
    case destructive
    case privileged
}

public enum HanlinExecutionContext: String, Codable, CaseIterable, Hashable, Sendable {
    case mainApplication
    case widget
    case liveActivity
    case controlWidget
    case appIntent
    case notificationUI
    case keyboard
    case translationUI
    case backgroundTask
}

public enum HanlinDistributionMode: String, Codable, CaseIterable, Hashable, Sendable {
    case personalDevelopment
    case enterprise
    case testFlight
    case appStoreRestricted
}

public enum HanlinAppImplementation: Codable, Hashable, Sendable {
    case native(moduleID: HanlinModuleID)
    case script(packageID: HanlinPackageID)
    case hybrid(moduleID: HanlinModuleID, packageID: HanlinPackageID)
}

extension HanlinAppImplementation {
    private enum CodingKeys: String, CodingKey {
        case type
        case moduleID
        case packageID
    }

    private enum ImplementationType: String, Codable {
        case native
        case script
        case hybrid
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ImplementationType.self, forKey: .type) {
        case .native:
            self = try .native(
                moduleID: container.decode(HanlinModuleID.self, forKey: .moduleID)
            )
        case .script:
            self = try .script(
                packageID: container.decode(
                    HanlinPackageID.self,
                    forKey: .packageID
                )
            )
        case .hybrid:
            self = try .hybrid(
                moduleID: container.decode(HanlinModuleID.self, forKey: .moduleID),
                packageID: container.decode(
                    HanlinPackageID.self,
                    forKey: .packageID
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .native(moduleID):
            try container.encode(ImplementationType.native, forKey: .type)
            try container.encode(moduleID, forKey: .moduleID)
        case let .script(packageID):
            try container.encode(ImplementationType.script, forKey: .type)
            try container.encode(packageID, forKey: .packageID)
        case let .hybrid(moduleID, packageID):
            try container.encode(ImplementationType.hybrid, forKey: .type)
            try container.encode(moduleID, forKey: .moduleID)
            try container.encode(packageID, forKey: .packageID)
        }
    }
}

public enum HanlinIconDescriptor: Codable, Hashable, Sendable {
    case systemSymbol(name: String)
    case asset(name: String)
    case packageResource(path: String)
}

extension HanlinIconDescriptor {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum IconType: String, Codable {
        case systemSymbol
        case asset
        case packageResource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .value)
        switch try container.decode(IconType.self, forKey: .type) {
        case .systemSymbol:
            self = .systemSymbol(name: value)
        case .asset:
            self = .asset(name: value)
        case .packageResource:
            self = .packageResource(path: value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .systemSymbol(name):
            try container.encode(IconType.systemSymbol, forKey: .type)
            try container.encode(name, forKey: .value)
        case let .asset(name):
            try container.encode(IconType.asset, forKey: .type)
            try container.encode(name, forKey: .value)
        case let .packageResource(path):
            try container.encode(IconType.packageResource, forKey: .type)
            try container.encode(path, forKey: .value)
        }
    }
}

public struct HanlinAppearanceDescriptor: Codable, Hashable, Sendable {
    public let accentHex: String?
    public let preferredColorScheme: HanlinPreferredColorScheme?

    public init(
        accentHex: String? = nil,
        preferredColorScheme: HanlinPreferredColorScheme? = nil
    ) {
        self.accentHex = accentHex
        self.preferredColorScheme = preferredColorScheme
    }
}

public enum HanlinPreferredColorScheme: String, Codable, Hashable, Sendable {
    case system
    case light
    case dark
}

public enum HanlinAppCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case assistant
    case developer
    case education
    case health
    case knowledge
    case media
    case productivity
    case reference
    case utilities
    case other
}

public enum HanlinEntryPointKind: String, Codable, CaseIterable, Hashable, Sendable {
    case app
    case assistantTool
    case widget
    case liveActivity
    case controlWidget
    case appIntentBridge
    case notificationUI
    case keyboard
    case translationUI
    case backgroundTask
}

public struct HanlinEntryPointDescriptor: Codable, Hashable, Sendable {
    public let kind: HanlinEntryPointKind
    public let handler: String
    public let allowedContexts: [HanlinExecutionContext]

    public init(
        kind: HanlinEntryPointKind,
        handler: String,
        allowedContexts: [HanlinExecutionContext]
    ) {
        self.kind = kind
        self.handler = handler
        self.allowedContexts = allowedContexts
    }
}

public struct HanlinRouteDescriptor: Codable, Hashable, Sendable {
    public let id: HanlinRouteID
    public let title: LocalizedValue
    public let parameterSchema: HanlinJSONSchema
    public let requiredCapabilities: [HanlinCapabilityID]

    public init(
        id: HanlinRouteID,
        title: LocalizedValue,
        parameterSchema: HanlinJSONSchema,
        requiredCapabilities: [HanlinCapabilityID] = []
    ) {
        self.id = id
        self.title = title
        self.parameterSchema = parameterSchema
        self.requiredCapabilities = requiredCapabilities
    }
}

public struct HanlinActionDescriptor: Codable, Hashable, Sendable {
    public let id: HanlinActionID
    public let title: LocalizedValue
    public let inputSchema: HanlinJSONSchema
    public let outputSchema: HanlinJSONSchema?
    public let capabilities: [HanlinCapabilityID]
    public let risk: HanlinRiskLevel

    public init(
        id: HanlinActionID,
        title: LocalizedValue,
        inputSchema: HanlinJSONSchema,
        outputSchema: HanlinJSONSchema? = nil,
        capabilities: [HanlinCapabilityID] = [],
        risk: HanlinRiskLevel
    ) {
        self.id = id
        self.title = title
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.capabilities = capabilities
        self.risk = risk
    }
}

public enum HanlinToolOwner: Codable, Hashable, Sendable {
    case system
    case app(HanlinAppID)
    case module(HanlinModuleID)
    case `package`(HanlinPackageID)
    case mcpServer(HanlinMCPServerID)
}

extension HanlinToolOwner {
    private enum CodingKeys: String, CodingKey {
        case type
        case identifier
    }

    private enum OwnerType: String, Codable {
        case system
        case app
        case module
        case `package`
        case mcpServer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(OwnerType.self, forKey: .type) {
        case .system:
            self = .system
        case .app:
            self = try .app(
                container.decode(HanlinAppID.self, forKey: .identifier)
            )
        case .module:
            self = try .module(
                container.decode(HanlinModuleID.self, forKey: .identifier)
            )
        case .package:
            self = try .package(
                container.decode(HanlinPackageID.self, forKey: .identifier)
            )
        case .mcpServer:
            self = try .mcpServer(
                container.decode(HanlinMCPServerID.self, forKey: .identifier)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .system:
            try container.encode(OwnerType.system, forKey: .type)
        case let .app(identifier):
            try container.encode(OwnerType.app, forKey: .type)
            try container.encode(identifier, forKey: .identifier)
        case let .module(identifier):
            try container.encode(OwnerType.module, forKey: .type)
            try container.encode(identifier, forKey: .identifier)
        case let .package(identifier):
            try container.encode(OwnerType.package, forKey: .type)
            try container.encode(identifier, forKey: .identifier)
        case let .mcpServer(identifier):
            try container.encode(OwnerType.mcpServer, forKey: .type)
            try container.encode(identifier, forKey: .identifier)
        }
    }
}

public struct HanlinToolPresentationDescriptor: Codable, Hashable, Sendable {
    public let compactStyle: HanlinToolCompactStyle
    public let supportsExpandedPresentation: Bool

    public init(
        compactStyle: HanlinToolCompactStyle,
        supportsExpandedPresentation: Bool = false
    ) {
        self.compactStyle = compactStyle
        self.supportsExpandedPresentation = supportsExpandedPresentation
    }
}

public enum HanlinToolCompactStyle: String, Codable, Hashable, Sendable {
    case automatic
    case text
    case entity
    case search
    case error
}

public struct HanlinToolDescriptor: Codable, Hashable, Sendable {
    public let id: HanlinToolID
    public let owner: HanlinToolOwner
    public let title: LocalizedValue
    public let summary: LocalizedValue
    public let inputSchema: HanlinJSONSchema
    public let outputSchema: HanlinJSONSchema?
    public let capabilities: [HanlinCapabilityID]
    public let risk: HanlinRiskLevel
    public let presentation: HanlinToolPresentationDescriptor

    public init(
        id: HanlinToolID,
        owner: HanlinToolOwner,
        title: LocalizedValue,
        summary: LocalizedValue,
        inputSchema: HanlinJSONSchema,
        outputSchema: HanlinJSONSchema? = nil,
        capabilities: [HanlinCapabilityID] = [],
        risk: HanlinRiskLevel,
        presentation: HanlinToolPresentationDescriptor
    ) {
        self.id = id
        self.owner = owner
        self.title = title
        self.summary = summary
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.capabilities = capabilities
        self.risk = risk
        self.presentation = presentation
    }
}

public struct HanlinCapabilityDeclaration: Codable, Hashable, Sendable {
    public let id: HanlinCapabilityID
    public let reason: LocalizedValue
    public let constraints: HanlinValue
    public let optional: Bool

    public init(
        id: HanlinCapabilityID,
        reason: LocalizedValue,
        constraints: HanlinValue = .object([:]),
        optional: Bool = false
    ) {
        self.id = id
        self.reason = reason
        self.constraints = constraints
        self.optional = optional
    }
}

public struct HanlinDependencyDeclaration: Codable, Hashable, Sendable {
    public let packageID: HanlinPackageID
    public let versions: HanlinHostVersionRange
    public let optional: Bool

    public init(
        packageID: HanlinPackageID,
        versions: HanlinHostVersionRange,
        optional: Bool = false
    ) {
        self.packageID = packageID
        self.versions = versions
        self.optional = optional
    }
}

public struct HanlinExtensionDeclaration: Codable, Hashable, Sendable {
    public let kind: HanlinEntryPointKind
    public let entryPoint: String
    public let requiredCapabilities: [HanlinCapabilityID]

    public init(
        kind: HanlinEntryPointKind,
        entryPoint: String,
        requiredCapabilities: [HanlinCapabilityID] = []
    ) {
        self.kind = kind
        self.entryPoint = entryPoint
        self.requiredCapabilities = requiredCapabilities
    }
}

public struct HanlinAuthor: Codable, Hashable, Sendable {
    public let name: String
    public let identifier: HanlinPublisherID?
    public let website: URL?

    public init(
        name: String,
        identifier: HanlinPublisherID? = nil,
        website: URL? = nil
    ) {
        self.name = name
        self.identifier = identifier
        self.website = website
    }
}

public struct HanlinDistributionDeclaration: Codable, Hashable, Sendable {
    public let sourceVisible: Bool
    public let sourceEditable: Bool
    public let remoteUpdates: Bool
    public let allowedModes: [HanlinDistributionMode]

    public init(
        sourceVisible: Bool,
        sourceEditable: Bool,
        remoteUpdates: Bool,
        allowedModes: [HanlinDistributionMode]
    ) {
        self.sourceVisible = sourceVisible
        self.sourceEditable = sourceEditable
        self.remoteUpdates = remoteUpdates
        self.allowedModes = allowedModes
    }
}

public enum HanlinIntegrityAlgorithm: String, Codable, Hashable, Sendable {
    case sha256
}

public struct HanlinIntegrityDeclaration: Codable, Hashable, Sendable {
    public let algorithm: HanlinIntegrityAlgorithm
    public let digest: String
    public let signer: HanlinPublisherID?

    public init(
        algorithm: HanlinIntegrityAlgorithm,
        digest: String,
        signer: HanlinPublisherID? = nil
    ) {
        self.algorithm = algorithm
        self.digest = digest
        self.signer = signer
    }
}

public struct HanlinAppDescriptor: Codable, Identifiable, Hashable, Sendable {
    public let schemaVersion: HanlinManifestVersion
    public let id: HanlinAppID
    public let name: LocalizedValue
    public let summary: LocalizedValue
    public let description: LocalizedValue
    public let version: HanlinPackageVersion
    public let minimumHostVersion: HanlinPackageVersion?
    public let apiVersion: HanlinAPIVersion
    public let icon: HanlinIconDescriptor
    public let appearance: HanlinAppearanceDescriptor
    public let category: HanlinAppCategory
    public let implementation: HanlinAppImplementation
    public let entryPoints: [HanlinEntryPointDescriptor]
    public let routes: [HanlinRouteDescriptor]
    public let actions: [HanlinActionDescriptor]
    public let tools: [HanlinToolDescriptor]
    public let capabilities: [HanlinCapabilityDeclaration]
    public let dependencies: [HanlinDependencyDeclaration]
    public let extensions: [HanlinExtensionDeclaration]
    public let authors: [HanlinAuthor]
    public let distribution: HanlinDistributionDeclaration
    public let integrity: HanlinIntegrityDeclaration?

    public init(
        schemaVersion: HanlinManifestVersion,
        id: HanlinAppID,
        name: LocalizedValue,
        summary: LocalizedValue,
        description: LocalizedValue,
        version: HanlinPackageVersion,
        minimumHostVersion: HanlinPackageVersion? = nil,
        apiVersion: HanlinAPIVersion,
        icon: HanlinIconDescriptor,
        appearance: HanlinAppearanceDescriptor = .init(),
        category: HanlinAppCategory,
        implementation: HanlinAppImplementation,
        entryPoints: [HanlinEntryPointDescriptor],
        routes: [HanlinRouteDescriptor] = [],
        actions: [HanlinActionDescriptor] = [],
        tools: [HanlinToolDescriptor] = [],
        capabilities: [HanlinCapabilityDeclaration] = [],
        dependencies: [HanlinDependencyDeclaration] = [],
        extensions: [HanlinExtensionDeclaration] = [],
        authors: [HanlinAuthor],
        distribution: HanlinDistributionDeclaration,
        integrity: HanlinIntegrityDeclaration? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.summary = summary
        self.description = description
        self.version = version
        self.minimumHostVersion = minimumHostVersion
        self.apiVersion = apiVersion
        self.icon = icon
        self.appearance = appearance
        self.category = category
        self.implementation = implementation
        self.entryPoints = entryPoints
        self.routes = routes
        self.actions = actions
        self.tools = tools
        self.capabilities = capabilities
        self.dependencies = dependencies
        self.extensions = extensions
        self.authors = authors
        self.distribution = distribution
        self.integrity = integrity
    }

    public func canonicalJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decodeAndValidate(
        _ data: Data,
        support: HanlinVersionSupport = .version1
    ) throws -> HanlinAppDescriptor {
        let descriptor = try JSONDecoder().decode(Self.self, from: data)
        try descriptor.validate(support: support)
        return descriptor
    }

    public func validate(
        support: HanlinVersionSupport = .version1
    ) throws {
        var issues: [HanlinManifestIssue] = []
        do {
            try support.validate(schemaVersion)
        } catch {
            issues.append(.init(
                code: .unsupportedManifestVersion,
                path: "schemaVersion",
                message: error.localizedDescription
            ))
        }
        do {
            try support.validate(apiVersion)
        } catch {
            issues.append(.init(
                code: .unsupportedAPIVersion,
                path: "apiVersion",
                message: error.localizedDescription
            ))
        }
        if entryPoints.isEmpty {
            issues.append(.init(
                code: .missingEntryPoint,
                path: "entryPoints",
                message: "At least one entry point is required."
            ))
        }
        for (index, entryPoint) in entryPoints.enumerated() {
            if !Self.isSafeRelativePath(entryPoint.handler) {
                issues.append(.init(
                    code: .unsafeEntryPoint,
                    path: "entryPoints[\(index)].handler",
                    message: "Entry-point handlers must be normalized relative paths."
                ))
            }
            if entryPoint.allowedContexts.isEmpty {
                issues.append(.init(
                    code: .missingExecutionContext,
                    path: "entryPoints[\(index)].allowedContexts",
                    message: "Entry points require at least one execution context."
                ))
            }
            Self.appendDuplicateIssues(
                values: entryPoint.allowedContexts,
                code: .duplicateExecutionContext,
                path: "entryPoints[\(index)].allowedContexts",
                into: &issues
            )
        }
        Self.appendDuplicateIssues(
            values: entryPoints.map(\.kind),
            code: .duplicateEntryPoint,
            path: "entryPoints",
            into: &issues
        )
        Self.appendDuplicateIssues(
            values: routes.map(\.id),
            code: .duplicateRoute,
            path: "routes",
            into: &issues
        )
        Self.appendDuplicateIssues(
            values: actions.map(\.id),
            code: .duplicateAction,
            path: "actions",
            into: &issues
        )
        Self.appendDuplicateIssues(
            values: tools.map(\.id),
            code: .duplicateTool,
            path: "tools",
            into: &issues
        )
        Self.appendDuplicateIssues(
            values: capabilities.map(\.id),
            code: .duplicateCapability,
            path: "capabilities",
            into: &issues
        )
        Self.appendDuplicateIssues(
            values: dependencies.map(\.packageID),
            code: .duplicateDependency,
            path: "dependencies",
            into: &issues
        )
        if authors.isEmpty || authors.contains(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            issues.append(.init(
                code: .invalidAuthor,
                path: "authors",
                message: "At least one non-empty author name is required."
            ))
        }
        if distribution.allowedModes.isEmpty {
            issues.append(.init(
                code: .missingDistributionMode,
                path: "distribution.allowedModes",
                message: "At least one distribution mode is required."
            ))
        }
        Self.appendDuplicateIssues(
            values: distribution.allowedModes,
            code: .duplicateDistributionMode,
            path: "distribution.allowedModes",
            into: &issues
        )
        if let integrity,
           integrity.algorithm == .sha256,
           !Self.isCanonicalSHA256(integrity.digest)
        {
            issues.append(.init(
                code: .invalidIntegrity,
                path: "integrity.digest",
                message: "SHA-256 digests must be 64 lowercase hexadecimal characters."
            ))
        }
        for (index, route) in routes.enumerated() {
            do {
                try route.parameterSchema.validateDefinition()
            } catch {
                issues.append(.init(
                    code: .invalidSchema,
                    path: "routes[\(index)].parameterSchema",
                    message: error.localizedDescription
                ))
            }
        }
        for (index, action) in actions.enumerated() {
            Self.validate(
                action.inputSchema,
                path: "actions[\(index)].inputSchema",
                into: &issues
            )
            if let outputSchema = action.outputSchema {
                Self.validate(
                    outputSchema,
                    path: "actions[\(index)].outputSchema",
                    into: &issues
                )
            }
        }
        for (index, tool) in tools.enumerated() {
            Self.validate(
                tool.inputSchema,
                path: "tools[\(index)].inputSchema",
                into: &issues
            )
            if let outputSchema = tool.outputSchema {
                Self.validate(
                    outputSchema,
                    path: "tools[\(index)].outputSchema",
                    into: &issues
                )
            }
        }
        guard issues.isEmpty else {
            throw HanlinContractError.invalidManifest(issues)
        }
    }

    private static func validate(
        _ schema: HanlinJSONSchema,
        path: String,
        into issues: inout [HanlinManifestIssue]
    ) {
        do {
            try schema.validateDefinition()
        } catch {
            issues.append(.init(
                code: .invalidSchema,
                path: path,
                message: error.localizedDescription
            ))
        }
    }

    private static func appendDuplicateIssues<Value: Hashable>(
        values: [Value],
        code: HanlinManifestIssueCode,
        path: String,
        into issues: inout [HanlinManifestIssue]
    ) {
        var seen: Set<Value> = []
        if values.contains(where: { !seen.insert($0).inserted }) {
            issues.append(.init(
                code: code,
                path: path,
                message: "Duplicate canonical identifiers are not allowed."
            ))
        }
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        guard
            !value.isEmpty,
            !value.hasPrefix("/"),
            !value.hasPrefix("\\"),
            !value.contains("\\"),
            !value.contains("\0")
        else {
            return false
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
        }
    }
}

public enum HanlinManifestIssueCode: String, Codable, Hashable, Sendable {
    case unsupportedManifestVersion
    case unsupportedAPIVersion
    case missingEntryPoint
    case unsafeEntryPoint
    case missingExecutionContext
    case duplicateExecutionContext
    case duplicateEntryPoint
    case duplicateRoute
    case duplicateAction
    case duplicateTool
    case duplicateCapability
    case duplicateDependency
    case invalidAuthor
    case missingDistributionMode
    case duplicateDistributionMode
    case invalidIntegrity
    case invalidSchema
}

public struct HanlinManifestIssue: Codable, Hashable, Sendable {
    public let code: HanlinManifestIssueCode
    public let path: String
    public let message: String

    public init(code: HanlinManifestIssueCode, path: String, message: String) {
        self.code = code
        self.path = path
        self.message = message
    }
}
