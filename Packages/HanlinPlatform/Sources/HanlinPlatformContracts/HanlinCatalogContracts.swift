import Foundation

public struct HanlinPackageDescriptor: Codable, Hashable, Sendable {
    public let id: HanlinPackageID
    public let version: HanlinPackageVersion
    public let descriptorRevision: HanlinDescriptorRevision
    public let displayName: LocalizedValue
    public let appIDs: [HanlinAppID]
    public let dependencies: [HanlinDependencyDeclaration]
    public let authors: [HanlinAuthor]
    public let distribution: HanlinDistributionDeclaration
    public let integrity: HanlinIntegrityDeclaration?

    public init(
        id: HanlinPackageID,
        version: HanlinPackageVersion,
        descriptorRevision: HanlinDescriptorRevision,
        displayName: LocalizedValue,
        appIDs: [HanlinAppID],
        dependencies: [HanlinDependencyDeclaration] = [],
        authors: [HanlinAuthor],
        distribution: HanlinDistributionDeclaration,
        integrity: HanlinIntegrityDeclaration? = nil
    ) {
        self.id = id
        self.version = version
        self.descriptorRevision = descriptorRevision
        self.displayName = displayName
        self.appIDs = appIDs
        self.dependencies = dependencies
        self.authors = authors
        self.distribution = distribution
        self.integrity = integrity
    }
}

public enum HanlinRegistrationSource: Codable, Hashable, Sendable {
    case nativeHost
    case installedPackage(HanlinInstalledPackageID)
    case provider(HanlinProviderInstanceID)
}

public struct HanlinCatalogRegistration: Codable, Hashable, Sendable {
    public let id: HanlinCatalogRegistrationID
    public let source: HanlinRegistrationSource
    public let descriptorRevision: HanlinDescriptorRevision
    public let registeredAt: Date
    public let enabled: Bool

    public init(
        id: HanlinCatalogRegistrationID,
        source: HanlinRegistrationSource,
        descriptorRevision: HanlinDescriptorRevision,
        registeredAt: Date,
        enabled: Bool
    ) {
        self.id = id
        self.source = source
        self.descriptorRevision = descriptorRevision
        self.registeredAt = registeredAt
        self.enabled = enabled
    }
}

public enum HanlinCatalogRegistrationResult: Codable, Hashable, Sendable {
    case accepted(HanlinCatalogRegistration)
    case rejected(HanlinPlatformError)
}

public struct HanlinCatalogSnapshot: Codable, Hashable, Sendable {
    public let revision: HanlinCatalogRevision
    public let generatedAt: Date
    public let apps: [HanlinAppDescriptor]
    public let packages: [HanlinPackageDescriptor]
    public let providerInstances: [HanlinProviderInstance]
    public let registrations: [HanlinCatalogRegistration]

    public init(
        revision: HanlinCatalogRevision,
        generatedAt: Date,
        apps: [HanlinAppDescriptor],
        packages: [HanlinPackageDescriptor] = [],
        providerInstances: [HanlinProviderInstance] = [],
        registrations: [HanlinCatalogRegistration] = []
    ) {
        self.revision = revision
        self.generatedAt = generatedAt
        self.apps = apps
        self.packages = packages
        self.providerInstances = providerInstances
        self.registrations = registrations
    }
}

public enum HanlinInstallationState: String, Codable, Hashable, Sendable {
    case staging
    case verified
    case committed
    case enabled
    case disabled
    case updating
    case uninstalling
    case removed
    case failed
}

public struct HanlinInstalledPackage: Codable, Hashable, Sendable {
    public let id: HanlinInstalledPackageID
    public let packageID: HanlinPackageID
    public let version: HanlinPackageVersion
    public let integrity: HanlinIntegrityDeclaration?
    public let logicalEntryPoint: String
    public let state: HanlinInstallationState
    public let installedAt: Date
    public let updatedAt: Date

    public init(
        id: HanlinInstalledPackageID,
        packageID: HanlinPackageID,
        version: HanlinPackageVersion,
        integrity: HanlinIntegrityDeclaration? = nil,
        logicalEntryPoint: String,
        state: HanlinInstallationState,
        installedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.packageID = packageID
        self.version = version
        self.integrity = integrity
        self.logicalEntryPoint = logicalEntryPoint
        self.state = state
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }
}

public enum HanlinProviderKind: String, Codable, Hashable, Sendable {
    case native
    case mcp
    case runtime
    case script
}

public struct HanlinProviderDescriptor: Codable, Hashable, Sendable {
    public let id: HanlinProviderID
    public let kind: HanlinProviderKind
    public let displayName: LocalizedValue
    public let contractVersion: HanlinContractVersion

    public init(
        id: HanlinProviderID,
        kind: HanlinProviderKind,
        displayName: LocalizedValue,
        contractVersion: HanlinContractVersion
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.contractVersion = contractVersion
    }
}

public struct HanlinProviderConfiguration: Codable, Hashable, Sendable {
    public let enabled: Bool
    public let values: [String: HanlinValue]
    public let secretReferences: [String: String]

    public init(
        enabled: Bool,
        values: [String: HanlinValue] = [:],
        secretReferences: [String: String] = [:]
    ) {
        self.enabled = enabled
        self.values = values
        self.secretReferences = secretReferences
    }
}

public struct HanlinProviderInstance: Codable, Hashable, Sendable {
    public let id: HanlinProviderInstanceID
    public let providerID: HanlinProviderID
    public let installedPackageID: HanlinInstalledPackageID?
    public let externalReference: String?
    public let configuration: HanlinProviderConfiguration

    public init(
        id: HanlinProviderInstanceID,
        providerID: HanlinProviderID,
        installedPackageID: HanlinInstalledPackageID? = nil,
        externalReference: String? = nil,
        configuration: HanlinProviderConfiguration
    ) {
        self.id = id
        self.providerID = providerID
        self.installedPackageID = installedPackageID
        self.externalReference = externalReference
        self.configuration = configuration
    }
}

public struct HanlinRouteRequest: Codable, Hashable, Sendable {
    public let requestID: HanlinRequestID
    public let appID: HanlinAppID
    public let routeID: HanlinRouteID
    public let parameters: HanlinJSONValue

    public init(
        requestID: HanlinRequestID,
        appID: HanlinAppID,
        routeID: HanlinRouteID,
        parameters: HanlinJSONValue = .object([:])
    ) {
        self.requestID = requestID
        self.appID = appID
        self.routeID = routeID
        self.parameters = parameters
    }
}

public enum HanlinPresentationIntent: String, Codable, Hashable, Sendable {
    case fullScreen
    case largeSheet
    case newWindow
}

public struct HanlinLaunchTarget: Codable, Hashable, Sendable {
    public let appID: HanlinAppID
    public let installedPackageID: HanlinInstalledPackageID?

    public init(
        appID: HanlinAppID,
        installedPackageID: HanlinInstalledPackageID? = nil
    ) {
        self.appID = appID
        self.installedPackageID = installedPackageID
    }
}

public struct HanlinLaunchRequest: Codable, Hashable, Sendable {
    public let id: HanlinLaunchID
    public let requestID: HanlinRequestID
    public let target: HanlinLaunchTarget
    public let presentation: HanlinPresentationIntent
    public let initialRoute: HanlinRouteRequest?
    public let origin: HanlinExecutionOrigin

    public init(
        id: HanlinLaunchID,
        requestID: HanlinRequestID,
        target: HanlinLaunchTarget,
        presentation: HanlinPresentationIntent,
        initialRoute: HanlinRouteRequest? = nil,
        origin: HanlinExecutionOrigin
    ) {
        self.id = id
        self.requestID = requestID
        self.target = target
        self.presentation = presentation
        self.initialRoute = initialRoute
        self.origin = origin
    }
}

public enum HanlinLaunchResult: Codable, Hashable, Sendable {
    case launched(HanlinAppSessionID)
    case denied(HanlinPolicyEvaluationID, String)
    case failed(HanlinPlatformError)
    case cancelled(HanlinCancellationID)
}

public struct HanlinActionRequest: Codable, Hashable, Sendable {
    public let requestID: HanlinRequestID
    public let appID: HanlinAppID
    public let actionID: HanlinActionID
    public let input: HanlinJSONValue
    public let origin: HanlinExecutionOrigin
    public let userGesturePresent: Bool

    public init(
        requestID: HanlinRequestID,
        appID: HanlinAppID,
        actionID: HanlinActionID,
        input: HanlinJSONValue = .object([:]),
        origin: HanlinExecutionOrigin,
        userGesturePresent: Bool
    ) {
        self.requestID = requestID
        self.appID = appID
        self.actionID = actionID
        self.input = input
        self.origin = origin
        self.userGesturePresent = userGesturePresent
    }
}

public enum HanlinActionResult: Codable, Hashable, Sendable {
    case completed(HanlinValue?)
    case denied(HanlinPolicyEvaluationID, String)
    case failed(HanlinPlatformError)
    case cancelled(HanlinCancellationID)
}
