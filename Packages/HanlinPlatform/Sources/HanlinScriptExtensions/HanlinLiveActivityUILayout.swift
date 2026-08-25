import HanlinScriptUI

public enum HanlinLiveActivityUILayoutError: Error, Equatable, Sendable {
    case invalidRoot
    case missingRegion(HanlinScriptUIPrimitive)
    case duplicateRegion(HanlinScriptUIPrimitive)
    case unexpectedRegion(HanlinScriptUIPrimitive)
}

public struct HanlinLiveActivityUILayout: Hashable, Sendable {
    public let content: HanlinScriptUINode
    public let compactLeading: HanlinScriptUINode
    public let compactTrailing: HanlinScriptUINode
    public let minimal: HanlinScriptUINode
    public let expandedLeading: HanlinScriptUINode?
    public let expandedTrailing: HanlinScriptUINode?
    public let expandedCenter: HanlinScriptUINode?
    public let expandedBottom: HanlinScriptUINode?

    public init(root: HanlinScriptUINode) throws {
        guard root.kind == .liveActivityUI else {
            throw HanlinLiveActivityUILayoutError.invalidRoot
        }
        var regions: [HanlinScriptUIPrimitive: HanlinScriptUINode] = [:]
        let allowed: Set<HanlinScriptUIPrimitive> = [
            .liveActivityContent, .liveActivityCompactLeading, .liveActivityCompactTrailing,
            .liveActivityMinimal, .liveActivityExpandedLeading, .liveActivityExpandedTrailing,
            .liveActivityExpandedCenter, .liveActivityExpandedBottom,
        ]
        for region in root.children {
            guard allowed.contains(region.kind) else {
                throw HanlinLiveActivityUILayoutError.unexpectedRegion(region.kind)
            }
            guard regions.updateValue(Self.contentNode(for: region), forKey: region.kind) == nil else {
                throw HanlinLiveActivityUILayoutError.duplicateRegion(region.kind)
            }
        }
        func required(_ kind: HanlinScriptUIPrimitive) throws -> HanlinScriptUINode {
            guard let region = regions[kind] else {
                throw HanlinLiveActivityUILayoutError.missingRegion(kind)
            }
            return region
        }
        content = try required(.liveActivityContent)
        compactLeading = try required(.liveActivityCompactLeading)
        compactTrailing = try required(.liveActivityCompactTrailing)
        minimal = try required(.liveActivityMinimal)
        expandedLeading = regions[.liveActivityExpandedLeading]
        expandedTrailing = regions[.liveActivityExpandedTrailing]
        expandedCenter = regions[.liveActivityExpandedCenter]
        expandedBottom = regions[.liveActivityExpandedBottom]
    }

    private static func contentNode(for region: HanlinScriptUINode) -> HanlinScriptUINode {
        if region.children.count == 1, let child = region.children.first { return child }
        return HanlinScriptUINode(kind: .fragment, children: region.children)
    }
}
