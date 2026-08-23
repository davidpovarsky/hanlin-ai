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
}

public enum HanlinScriptUIError: Error, Equatable, Sendable {
    case invalidPath(HanlinScriptUIPath)
    case duplicateKey(String)
    case keySetMismatch
    case patchLimit
}
