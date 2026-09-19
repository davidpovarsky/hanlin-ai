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
    public let family: String
    public let actionIdentity: HanlinScriptExtensionIdentity?
    public let validUntil: Date
    public let relevance: Double
    public let root: HanlinScriptUINode
    public let deepLink: URL?

    public init(
        identity: HanlinScriptExtensionIdentity,
        displayName: String,
        family: String = "systemMedium",
        actionIdentity: HanlinScriptExtensionIdentity? = nil,
        validUntil: Date,
        relevance: Double = 0,
        root: HanlinScriptUINode,
        deepLink: URL? = nil
    ) {
        self.identity = identity
        self.displayName = displayName
        self.family = family
        self.actionIdentity = actionIdentity
        self.validUntil = validUntil
        self.relevance = relevance
        self.root = root
        self.deepLink = deepLink
    }

    private enum CodingKeys: String, CodingKey {
        case identity, displayName, family, actionIdentity, validUntil, relevance, root, deepLink
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identity = try container.decode(HanlinScriptExtensionIdentity.self, forKey: .identity)
        displayName = try container.decode(String.self, forKey: .displayName)
        family = try container.decodeIfPresent(String.self, forKey: .family) ?? "systemMedium"
        actionIdentity = try container.decodeIfPresent(HanlinScriptExtensionIdentity.self, forKey: .actionIdentity)
        validUntil = try container.decode(Date.self, forKey: .validUntil)
        relevance = try container.decode(Double.self, forKey: .relevance)
        root = try container.decode(HanlinScriptUINode.self, forKey: .root)
        deepLink = try container.decodeIfPresent(URL.self, forKey: .deepLink)
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

public struct HanlinTranslationSessionContext: Codable, Hashable, Sendable {
    public let sourceText: String
    public let origin: HanlinExecutionContext
    public let presentation: String
    public let createdAt: Date

    public init(
        sourceText: String,
        origin: HanlinExecutionContext = .translationUI,
        presentation: String = "compact",
        createdAt: Date = .now
    ) {
        self.sourceText = sourceText
        self.origin = origin
        self.presentation = presentation
        self.createdAt = createdAt
    }
}

public struct HanlinScriptTranslationUISnapshot: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(identity.packageID.rawValue)|\(identity.entrypointID)" }
    public let identity: HanlinScriptExtensionIdentity
    public let appID: String
    public let displayName: String
    public let summary: String?
    public let iconSymbol: String?
    public let accentHex: String?
    public let isBeta: Bool
    public let entrypointID: String
    public let rootNode: HanlinScriptUINode?

    public init(
        identity: HanlinScriptExtensionIdentity,
        appID: String,
        displayName: String,
        summary: String? = nil,
        iconSymbol: String? = nil,
        accentHex: String? = nil,
        isBeta: Bool = false,
        entrypointID: String,
        rootNode: HanlinScriptUINode? = nil
    ) {
        self.identity = identity
        self.appID = appID
        self.displayName = displayName
        self.summary = summary
        self.iconSymbol = iconSymbol
        self.accentHex = accentHex
        self.isBeta = isBeta
        self.entrypointID = entrypointID
        self.rootNode = rootNode
    }
}

public struct HanlinScriptExtensionSnapshot: Codable, Hashable, Sendable {
    public let schemaVersion: UInt32
    public let generatedAt: Date
    public let widgets: [HanlinScriptWidgetSnapshot]
    public let intentEntities: [HanlinScriptIntentEntityRecord]
    public let liveActivities: [HanlinScriptLiveActivityDescriptor]
    public let translationApps: [HanlinScriptTranslationUISnapshot]

    public init(
        schemaVersion: UInt32 = 1,
        generatedAt: Date,
        widgets: [HanlinScriptWidgetSnapshot] = [],
        intentEntities: [HanlinScriptIntentEntityRecord] = [],
        liveActivities: [HanlinScriptLiveActivityDescriptor] = [],
        translationApps: [HanlinScriptTranslationUISnapshot] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.widgets = widgets
        self.intentEntities = intentEntities
        self.liveActivities = liveActivities
        self.translationApps = translationApps
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, widgets, intentEntities, liveActivities, translationApps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(UInt32.self, forKey: .schemaVersion) ?? 1
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        widgets = try container.decodeIfPresent([HanlinScriptWidgetSnapshot].self, forKey: .widgets) ?? []
        intentEntities = try container.decodeIfPresent([HanlinScriptIntentEntityRecord].self, forKey: .intentEntities) ?? []
        liveActivities = try container.decodeIfPresent([HanlinScriptLiveActivityDescriptor].self, forKey: .liveActivities) ?? []
        translationApps = try container.decodeIfPresent([HanlinScriptTranslationUISnapshot].self, forKey: .translationApps) ?? []
    }
}

extension HanlinScriptUINode {
    public func substituting(context: [String: String]) -> HanlinScriptUINode {
        var updatedProps = properties
        for (k, v) in properties {
            if case let .string(s) = v {
                var substituted = s
                for (placeholder, replacement) in context {
                    substituted = substituted.replacingOccurrences(of: "{{\(placeholder)}}", with: replacement)
                }
                updatedProps[k] = .string(substituted)
            }
        }
        let updatedChildren = children.map { $0.substituting(context: context) }
        return HanlinScriptUINode(
            kind: kind,
            key: key,
            properties: updatedProps,
            children: updatedChildren
        )
    }

    public func substituting(sessionContext: HanlinTranslationSessionContext) -> HanlinScriptUINode {
        substituting(context: [
            "selectedText": sessionContext.sourceText,
            "selectedTextLength": String(sessionContext.sourceText.count),
            "origin": sessionContext.origin,
            "presentation": sessionContext.presentation
        ])
    }
}
