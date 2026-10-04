import Foundation

public enum HanlinSwiftUIDeclarationKind: String, Codable, Sendable {
    case view
    case modifier
    case type
    case protocolDeclaration = "protocol"
}

public enum HanlinSwiftUIBridgeTier: String, Codable, Sendable {
    case t1Mechanical = "T1"
    case t2Content = "T2"
    case t3Binding = "T3"
    case t4Semantic = "T4"
}

public enum HanlinSwiftUIBridgeStatus: String, Codable, Sendable, CaseIterable {
    case expoUpstream = "expo-upstream"
    case generated
    case manual
    case unsupported
    case internalPrivate = "internal-private"
    case deprecated
    case superseded
    case unavailable
    case hostLifecycleOnly = "host-lifecycle-only"
    case companionFramework = "companion-framework"
    case needsInvestigation = "needs-investigation"
}

public enum HanlinSwiftUISignatureStatus: String, Codable, Sendable, CaseIterable {
    case directGenerated = "direct-generated"
    case coveredBySharedTSSurface = "covered-by-shared-TS-surface"
    case coveredByManualAdapter = "covered-by-manual-adapter"
    case expoUpstream = "expo-upstream"
    case redundantOverload = "redundant-overload"
    case unsupported
    case internalPrivate = "internal-private"
    case deprecated
    case superseded
    case unavailable
    case hostLifecycle = "host-lifecycle"
    case needsInvestigation = "needs-investigation"

    public var isCovered: Bool {
        switch self {
        case .directGenerated, .coveredBySharedTSSurface, .coveredByManualAdapter, .expoUpstream, .redundantOverload:
            true
        case .unsupported, .internalPrivate, .deprecated, .superseded, .unavailable, .hostLifecycle, .needsInvestigation:
            false
        }
    }
}

public enum HanlinSwiftUIAggregateStatus: String, Codable, Sendable, CaseIterable {
    case full
    case partial
    case unsupported
    case internalPrivate = "internal-private"
    case deprecated
    case superseded
    case unavailable
    case lifecycleOnly = "lifecycle-only"
    case needsInvestigation = "needs-investigation"
}

public enum HanlinSwiftUIExpoParity: String, Codable, Sendable {
    case verified
    case partial
    case unknown
}

public enum HanlinSwiftUISDKVisibility: String, Codable, Sendable {
    case `public`
    case underscored
    case spi
}

public enum HanlinSwiftUIPublicSurface: String, Codable, Sendable, CaseIterable {
    case supported
    case partial
    case unsupported
    case internalPrivate = "internal-private"
    case deprecated
    case superseded
    case unavailable
    case hostLifecycleOnly = "host-lifecycle-only"
    case needsInvestigation = "needs-investigation"
    case companionFramework = "companion-framework"
}

public struct HanlinSwiftUIParameter: Codable, Hashable, Sendable {
    public var externalName: String?
    public var localName: String
    public var type: String
    public var defaultValue: String?
    public var attributes: [String]
    public var isBinding: Bool
    public var isViewBuilder: Bool
    public var isClosure: Bool

    public init(
        externalName: String?,
        localName: String,
        type: String,
        defaultValue: String?,
        attributes: [String],
        isBinding: Bool,
        isViewBuilder: Bool,
        isClosure: Bool
    ) {
        self.externalName = externalName
        self.localName = localName
        self.type = type
        self.defaultValue = defaultValue
        self.attributes = attributes
        self.isBinding = isBinding
        self.isViewBuilder = isViewBuilder
        self.isClosure = isClosure
    }
}

public struct HanlinSwiftUISignature: Codable, Hashable, Sendable {
    public var parameters: [HanlinSwiftUIParameter]
    public var returnType: String?
    public var genericParameters: [String]
    public var isAsync: Bool
    public var isThrowing: Bool
    public var availability: [String]
    public var attributes: [String]
    public var isDeprecated: Bool
    public var isUnavailable: Bool
    public var status: HanlinSwiftUISignatureStatus?
    public var reason: String?
    public var bridgeStrategy: String?
    public var sharedSurface: String?
    public var publicSurface: HanlinSwiftUIPublicSurface?
    public var exportedToHanlin: Bool

    public init(
        parameters: [HanlinSwiftUIParameter] = [],
        returnType: String? = nil,
        genericParameters: [String] = [],
        isAsync: Bool = false,
        isThrowing: Bool = false,
        availability: [String] = [],
        attributes: [String] = [],
        isDeprecated: Bool = false,
        isUnavailable: Bool = false,
        status: HanlinSwiftUISignatureStatus? = nil,
        reason: String? = nil,
        bridgeStrategy: String? = nil,
        sharedSurface: String? = nil,
        publicSurface: HanlinSwiftUIPublicSurface? = nil,
        exportedToHanlin: Bool = false
    ) {
        self.parameters = parameters
        self.returnType = returnType
        self.genericParameters = genericParameters
        self.isAsync = isAsync
        self.isThrowing = isThrowing
        self.availability = availability
        self.attributes = attributes
        self.isDeprecated = isDeprecated
        self.isUnavailable = isUnavailable
        self.status = status
        self.reason = reason
        self.bridgeStrategy = bridgeStrategy
        self.sharedSurface = sharedSurface
        self.publicSurface = publicSurface
        self.exportedToHanlin = exportedToHanlin
    }
}

public struct HanlinSwiftUIDeclaration: Codable, Hashable, Sendable {
    public var module: String
    public var symbol: String
    public var kind: HanlinSwiftUIDeclarationKind
    public var sourceModule: String
    public var genericParameters: [String]
    public var conformances: [String]
    public var availability: [String]
    public var attributes: [String]
    public var signatures: [HanlinSwiftUISignature]
    public var enumCases: [String]
    public var optionSetCases: [String]
    public var isDeprecated: Bool
    public var isUnavailable: Bool
    public var tier: HanlinSwiftUIBridgeTier?
    public var status: HanlinSwiftUIBridgeStatus?
    public var reason: String?
    public var manualAdapter: String?
    public var aggregateStatus: HanlinSwiftUIAggregateStatus?
    public var expoSymbolExists: Bool
    public var expoParity: HanlinSwiftUIExpoParity?
    public var sdkVisibility: HanlinSwiftUISDKVisibility
    public var publicSurface: HanlinSwiftUIPublicSurface?
    public var replacement: [String]
    public var exportedToHanlin: Bool

    public init(
        module: String,
        symbol: String,
        kind: HanlinSwiftUIDeclarationKind,
        sourceModule: String,
        genericParameters: [String] = [],
        conformances: [String] = [],
        availability: [String] = [],
        attributes: [String] = [],
        signatures: [HanlinSwiftUISignature] = [],
        enumCases: [String] = [],
        optionSetCases: [String] = [],
        isDeprecated: Bool = false,
        isUnavailable: Bool = false,
        tier: HanlinSwiftUIBridgeTier? = nil,
        status: HanlinSwiftUIBridgeStatus? = nil,
        reason: String? = nil,
        manualAdapter: String? = nil,
        aggregateStatus: HanlinSwiftUIAggregateStatus? = nil,
        expoSymbolExists: Bool = false,
        expoParity: HanlinSwiftUIExpoParity? = nil,
        sdkVisibility: HanlinSwiftUISDKVisibility = .public,
        publicSurface: HanlinSwiftUIPublicSurface? = nil,
        replacement: [String] = [],
        exportedToHanlin: Bool = false
    ) {
        self.module = module
        self.symbol = symbol
        self.kind = kind
        self.sourceModule = sourceModule
        self.genericParameters = genericParameters
        self.conformances = conformances
        self.availability = availability
        self.attributes = attributes
        self.signatures = signatures
        self.enumCases = enumCases
        self.optionSetCases = optionSetCases
        self.isDeprecated = isDeprecated
        self.isUnavailable = isUnavailable
        self.tier = tier
        self.status = status
        self.reason = reason
        self.manualAdapter = manualAdapter
        self.aggregateStatus = aggregateStatus
        self.expoSymbolExists = expoSymbolExists
        self.expoParity = expoParity
        self.sdkVisibility = sdkVisibility
        self.publicSurface = publicSurface
        self.replacement = replacement
        self.exportedToHanlin = exportedToHanlin
    }
}

public struct HanlinSwiftUIInterfaceIdentity: Codable, Hashable, Sendable {
    public var module: String
    public var fileName: String
    public var sha256: String

    public init(module: String, fileName: String, sha256: String) {
        self.module = module
        self.fileName = fileName
        self.sha256 = sha256
    }
}

public struct HanlinSwiftUISDKModuleMetadata: Codable, Hashable, Sendable {
    public var sourceFile: String
    public var artifactFile: String
    public var sha256: String
}

public struct HanlinSwiftUISDKMetadata: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var xcodeVersion: String
    public var developerDir: String
    public var sdk: String
    public var sdkRoot: String
    public var sdkVersion: String
    public var target: String
    public var modules: [String: HanlinSwiftUISDKModuleMetadata]
}

public struct HanlinSwiftUIInventory: Codable, Sendable {
    public var schemaVersion: Int
    public var generatorVersion: String
    public var sdkIdentity: String
    public var sdkMetadata: HanlinSwiftUISDKMetadata?
    public var interfaces: [HanlinSwiftUIInterfaceIdentity]
    public var declarations: [HanlinSwiftUIDeclaration]

    public init(
        schemaVersion: Int = 1,
        generatorVersion: String,
        sdkIdentity: String,
        sdkMetadata: HanlinSwiftUISDKMetadata? = nil,
        interfaces: [HanlinSwiftUIInterfaceIdentity],
        declarations: [HanlinSwiftUIDeclaration]
    ) {
        self.schemaVersion = schemaVersion
        self.generatorVersion = generatorVersion
        self.sdkIdentity = sdkIdentity
        self.sdkMetadata = sdkMetadata
        self.interfaces = interfaces.sorted { $0.module < $1.module }
        self.declarations = declarations.sorted {
            ($0.module, $0.symbol, $0.kind.rawValue) < ($1.module, $1.symbol, $1.kind.rawValue)
        }
    }
}

public struct HanlinSwiftUIManualRule: Codable, Hashable, Sendable {
    public var status: HanlinSwiftUIBridgeStatus
    public var reason: String
    public var adapter: String?
    public var coveredParameterLabelSets: [[String]]?
    public var uncoveredReason: String?

    public init(
        status: HanlinSwiftUIBridgeStatus,
        reason: String,
        adapter: String? = nil,
        coveredParameterLabelSets: [[String]]? = nil,
        uncoveredReason: String? = nil
    ) {
        self.status = status
        self.reason = reason
        self.adapter = adapter
        self.coveredParameterLabelSets = coveredParameterLabelSets
        self.uncoveredReason = uncoveredReason
    }
}

public struct HanlinSwiftUISupersededRule: Codable, Hashable, Sendable {
    public var reason: String
    public var replacement: [String]
}

public struct HanlinSwiftUIBridgeConfiguration: Codable, Sendable {
    public var runtimeVersion: String
    public var bridgeVersion: String
    public var expoUIVersion: String
    public var expoViews: [String]
    public var expoModifiers: [String]
    public var expoReviewedViews: [String]
    public var expoReviewedModifiers: [String]
    public var underscoredAllowlist: [String: String]
    public var supersededSymbols: [String: HanlinSwiftUISupersededRule]
    public var rules: [String: HanlinSwiftUIManualRule]

    public init(
        runtimeVersion: String,
        bridgeVersion: String,
        expoUIVersion: String,
        expoViews: [String],
        expoModifiers: [String],
        expoReviewedViews: [String] = [],
        expoReviewedModifiers: [String] = [],
        underscoredAllowlist: [String: String] = [:],
        supersededSymbols: [String: HanlinSwiftUISupersededRule] = [:],
        rules: [String: HanlinSwiftUIManualRule]
    ) {
        self.runtimeVersion = runtimeVersion
        self.bridgeVersion = bridgeVersion
        self.expoUIVersion = expoUIVersion
        self.expoViews = expoViews.sorted()
        self.expoModifiers = expoModifiers.sorted()
        self.expoReviewedViews = expoReviewedViews.sorted()
        self.expoReviewedModifiers = expoReviewedModifiers.sorted()
        self.underscoredAllowlist = underscoredAllowlist
        self.supersededSymbols = supersededSymbols
        self.rules = rules
    }
}

public struct HanlinSwiftUICoverage: Codable, Sendable {
    public var sdkIdentity: String
    public var sdkMetadata: HanlinSwiftUISDKMetadata?
    public var generatorVersion: String
    public var bridgeVersion: String
    public var expoUIVersion: String
    public var interfaceHashes: [String: String]
    public var counts: [String: Int]
    public var aggregateCounts: [String: Int]
    public var kindCounts: [String: Int]
    public var signatureCounts: [String: Int]
    public var inventoryCounts: [String: Int]
    public var publicSurfaceCounts: [String: Int]
    public var symbols: [HanlinSwiftUIDeclaration]
}
