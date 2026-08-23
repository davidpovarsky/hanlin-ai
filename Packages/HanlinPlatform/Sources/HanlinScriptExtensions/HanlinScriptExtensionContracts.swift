import Foundation
import HanlinPlatformContracts
import HanlinScriptUI

public enum HanlinScriptExtensionContext: String, Codable, CaseIterable, Hashable, Sendable {
    case widget
    case appIntent
    case liveActivity
}

public struct HanlinScriptExtensionIdentity: Codable, Hashable, Sendable {
    public let installedPackageID: HanlinInstalledPackageID
    public let packageID: HanlinPackageID
    public let generation: UInt64
    public let entrypointID: String

    public init(
        installedPackageID: HanlinInstalledPackageID,
        packageID: HanlinPackageID,
        generation: UInt64,
        entrypointID: String
    ) {
        self.installedPackageID = installedPackageID
        self.packageID = packageID
        self.generation = generation
        self.entrypointID = entrypointID
    }
}

public struct HanlinScriptWidgetSnapshot: Codable, Hashable, Sendable {
    public let identity: HanlinScriptExtensionIdentity
    public let displayName: String
    public let validUntil: Date
    public let relevance: Double
    public let root: HanlinScriptUINode
    public let deepLink: URL?

    public init(
        identity: HanlinScriptExtensionIdentity,
        displayName: String,
        validUntil: Date,
        relevance: Double = 0,
        root: HanlinScriptUINode,
        deepLink: URL? = nil
    ) {
        self.identity = identity
        self.displayName = displayName
        self.validUntil = validUntil
        self.relevance = relevance
        self.root = root
        self.deepLink = deepLink
    }
}

public struct HanlinScriptIntentEntityRecord: Codable, Hashable, Sendable {
    public let identity: HanlinScriptExtensionIdentity
    public let id: String
    public let displayName: String
    public let subtitle: String?

    public init(
        identity: HanlinScriptExtensionIdentity,
        id: String,
        displayName: String,
        subtitle: String? = nil
    ) {
        self.identity = identity
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
    }
}

public struct HanlinScriptIntentInvocation: Codable, Hashable, Sendable {
    public let identity: HanlinScriptExtensionIdentity
    public let entityID: String?
    public let parameters: HanlinValue
    public let continueInForeground: Bool

    public init(
        identity: HanlinScriptExtensionIdentity,
        entityID: String? = nil,
        parameters: HanlinValue = .null,
        continueInForeground: Bool = false
    ) {
        self.identity = identity
        self.entityID = entityID
        self.parameters = parameters
        self.continueInForeground = continueInForeground
    }
}

public struct HanlinScriptResumeCommand: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let invocation: HanlinScriptIntentInvocation

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        invocation: HanlinScriptIntentInvocation
    ) {
        self.id = id
        self.createdAt = createdAt
        self.invocation = invocation
    }
}

public struct HanlinGenericLiveActivityAttributes: Codable, Hashable, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public let revision: UInt64
        public let title: String
        public let state: HanlinValue
        public let root: HanlinScriptUINode

        public init(revision: UInt64, title: String, state: HanlinValue, root: HanlinScriptUINode) {
            self.revision = revision
            self.title = title
            self.state = state
            self.root = root
        }
    }

    public let installedPackageID: String
    public let activityID: String

    public init(installedPackageID: String, activityID: String) {
        self.installedPackageID = installedPackageID
        self.activityID = activityID
    }
}

public struct HanlinScriptLiveActivityDescriptor: Codable, Hashable, Sendable {
    public let identity: HanlinScriptExtensionIdentity
    public let activityID: String
    public let title: String
    public let state: HanlinValue
    public let root: HanlinScriptUINode
    public let staleDate: Date?

    public init(
        identity: HanlinScriptExtensionIdentity,
        activityID: String,
        title: String,
        state: HanlinValue,
        root: HanlinScriptUINode,
        staleDate: Date? = nil
    ) {
        self.identity = identity
        self.activityID = activityID
        self.title = title
        self.state = state
        self.root = root
        self.staleDate = staleDate
    }
}

public struct HanlinScriptExtensionSnapshot: Codable, Hashable, Sendable {
    public let schemaVersion: UInt32
    public let generatedAt: Date
    public let widgets: [HanlinScriptWidgetSnapshot]
    public let intentEntities: [HanlinScriptIntentEntityRecord]
    public let liveActivities: [HanlinScriptLiveActivityDescriptor]

    public init(
        schemaVersion: UInt32 = 1,
        generatedAt: Date,
        widgets: [HanlinScriptWidgetSnapshot] = [],
        intentEntities: [HanlinScriptIntentEntityRecord] = [],
        liveActivities: [HanlinScriptLiveActivityDescriptor] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.widgets = widgets
        self.intentEntities = intentEntities
        self.liveActivities = liveActivities
    }
}
