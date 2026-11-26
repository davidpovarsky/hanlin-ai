import Foundation

/// Original ScriptWidget $dynamic_island regions, frozen before leaving the
/// JavaScript owner queue. The native ActivityKit extension renders these nodes.
public struct HanlinScriptWidgetDynamicIsland: Codable, Hashable, Sendable {
    public let expandedLeading: HanlinScriptWidgetPreparedNode?
    public let expandedTrailing: HanlinScriptWidgetPreparedNode?
    public let expandedCenter: HanlinScriptWidgetPreparedNode?
    public let expandedBottom: HanlinScriptWidgetPreparedNode?
    public let compactLeading: HanlinScriptWidgetPreparedNode?
    public let compactTrailing: HanlinScriptWidgetPreparedNode?
    public let minimal: HanlinScriptWidgetPreparedNode?

    public init(expandedLeading: HanlinScriptWidgetPreparedNode? = nil,
                expandedTrailing: HanlinScriptWidgetPreparedNode? = nil,
                expandedCenter: HanlinScriptWidgetPreparedNode? = nil,
                expandedBottom: HanlinScriptWidgetPreparedNode? = nil,
                compactLeading: HanlinScriptWidgetPreparedNode? = nil,
                compactTrailing: HanlinScriptWidgetPreparedNode? = nil,
                minimal: HanlinScriptWidgetPreparedNode? = nil) {
        self.expandedLeading = expandedLeading
        self.expandedTrailing = expandedTrailing
        self.expandedCenter = expandedCenter
        self.expandedBottom = expandedBottom
        self.compactLeading = compactLeading
        self.compactTrailing = compactTrailing
        self.minimal = minimal
    }
}
