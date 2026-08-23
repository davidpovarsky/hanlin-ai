import Foundation
import HanlinPlatformContracts

public enum HanlinScriptUIPrimitive: String, Codable, CaseIterable, Hashable, Sendable {
    case fragment
    case text
    case image
    case button
    case textField
    case hStack
    case vStack
    case zStack
    case scrollView
    case group
    case spacer
    case divider
    case progress
    case navigationStack
    case navigationLink
    case tabView
    case tab
}

public struct HanlinScriptUINode: Codable, Hashable, Sendable {
    public let kind: HanlinScriptUIPrimitive
    public let key: String?
    public let properties: [String: HanlinValue]
    public let children: [HanlinScriptUINode]

    public init(
        kind: HanlinScriptUIPrimitive,
        key: String? = nil,
        properties: [String: HanlinValue] = [:],
        children: [HanlinScriptUINode] = []
    ) {
        self.kind = kind
        self.key = key
        self.properties = properties
        self.children = children
    }

}

public struct HanlinScriptUIPath: Codable, Hashable, Sendable {
    public let indices: [Int]
    public init(_ indices: [Int] = []) { self.indices = indices }
    public func appending(_ index: Int) -> Self { .init(indices + [index]) }
}

public enum HanlinScriptUIPatch: Codable, Hashable, Sendable {
    case replace(path: HanlinScriptUIPath, node: HanlinScriptUINode)
    case setProperties(path: HanlinScriptUIPath, properties: [String: HanlinValue])
    case insert(parent: HanlinScriptUIPath, index: Int, node: HanlinScriptUINode)
    case remove(path: HanlinScriptUIPath)
    case reorder(parent: HanlinScriptUIPath, keys: [String])
}

public struct HanlinScriptUIEffect: Codable, Hashable, Sendable {
    public let id: String
    public let dependencies: [HanlinValue]
    public init(id: String, dependencies: [HanlinValue]) {
        self.id = id
        self.dependencies = dependencies
    }
}

public enum HanlinScriptUICommand: Codable, Hashable, Sendable {
    case render(HanlinScriptUINode)
    case patches([HanlinScriptUIPatch])
    case event(handlerID: String, payload: HanlinValue)
    case state(hookID: String, value: HanlinValue)
    case registerEffect(HanlinScriptUIEffect)
    case releaseEffect(id: String)
    case registerRoute(HanlinScriptUIRoute, destination: HanlinScriptUINode)
    case navigate(HanlinScriptUIRoute)
    case pop(count: Int)
    case selectTab(String)
    case present(HanlinScriptUIPresentation)
    case dismissPresentation(id: String)
    case scenePhase(HanlinScriptUIScenePhase)
    case resume(HanlinScriptResumePayload)
}

public struct HanlinScriptUIRoute: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let payload: HanlinValue
    public init(id: String, payload: HanlinValue = .null) {
        self.id = id
        self.payload = payload
    }
}

public enum HanlinScriptUIPresentationStyle: String, Codable, Hashable, Sendable {
    case sheet
    case fullScreen
    case dialog
}

public struct HanlinScriptUIPresentation: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let style: HanlinScriptUIPresentationStyle
    public let title: String?
    public let message: String?
    public let content: HanlinScriptUINode?

    public init(
        id: String,
        style: HanlinScriptUIPresentationStyle,
        title: String? = nil,
        message: String? = nil,
        content: HanlinScriptUINode? = nil
    ) {
        self.id = id
        self.style = style
        self.title = title
        self.message = message
        self.content = content
    }
}

public enum HanlinScriptUIScenePhase: String, Codable, Hashable, Sendable {
    case active
    case inactive
    case background
}

public struct HanlinScriptResumePayload: Codable, Hashable, Sendable {
    public let source: String
    public let queryParameters: [String: HanlinValue]
    public let widgetParameter: String?
    public let action: HanlinValue?

    public init(
        source: String,
        queryParameters: [String: HanlinValue] = [:],
        widgetParameter: String? = nil,
        action: HanlinValue? = nil
    ) {
        self.source = source
        self.queryParameters = queryParameters
        self.widgetParameter = widgetParameter
        self.action = action
    }
}

public struct HanlinScriptUISceneDescriptor: Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let supportsMultipleWindows: Bool
    public let minimumWidth: Double?
    public let minimumHeight: Double?

    public init(
        id: String,
        title: String,
        supportsMultipleWindows: Bool,
        minimumWidth: Double? = nil,
        minimumHeight: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.supportsMultipleWindows = supportsMultipleWindows
        self.minimumWidth = minimumWidth
        self.minimumHeight = minimumHeight
    }
}

public enum HanlinScriptUIError: Error, Equatable, Sendable {
    case invalidPath(HanlinScriptUIPath)
    case duplicateKey(String)
    case keySetMismatch
    case patchLimit
    case unknownRoute(String)
    case invalidPopCount(Int)
}
