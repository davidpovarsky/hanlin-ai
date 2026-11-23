#if canImport(SwiftUI)
import SwiftUI

/// Per-view overrides for the original Hanlin surfaces. Nil retains that
/// component's original light/dark color, material, geometry and animation.
/// Environment scoping lets independent embeds use different appearances.
public struct HanlinChatAppearance: Sendable {
    public var composerAccent: Color?
    public var composerHighlight: Color?
    public var capabilityAccent: Color?
    public var toolAccent: Color?
    public var toolInk: Color?
    public var toolSurface: Color?
    public var activeTitle: Color?
    public var shimmerColors: [Color]?
    public var userMessageBackground: Color?
    public var userMessageForeground: Color?
    public var temporaryMessageBackground: Color?
    public var temporaryMessageForeground: Color?

    public init(composerAccent: Color? = nil, composerHighlight: Color? = nil,
                capabilityAccent: Color? = nil, toolAccent: Color? = nil,
                toolInk: Color? = nil, toolSurface: Color? = nil,
                activeTitle: Color? = nil, shimmerColors: [Color]? = nil,
                userMessageBackground: Color? = nil, userMessageForeground: Color? = nil,
                temporaryMessageBackground: Color? = nil, temporaryMessageForeground: Color? = nil) {
        self.composerAccent = composerAccent; self.composerHighlight = composerHighlight
        self.capabilityAccent = capabilityAccent; self.toolAccent = toolAccent
        self.toolInk = toolInk; self.toolSurface = toolSurface
        self.activeTitle = activeTitle; self.shimmerColors = shimmerColors
        self.userMessageBackground = userMessageBackground; self.userMessageForeground = userMessageForeground
        self.temporaryMessageBackground = temporaryMessageBackground
        self.temporaryMessageForeground = temporaryMessageForeground
    }

    public static let original = Self()
}

private struct HanlinChatAppearanceKey: EnvironmentKey {
    static let defaultValue = HanlinChatAppearance.original
}

public extension EnvironmentValues {
    var hanlinChatAppearance: HanlinChatAppearance {
        get { self[HanlinChatAppearanceKey.self] }
        set { self[HanlinChatAppearanceKey.self] = newValue }
    }
}

public extension View {
    /// Applies to the full original conversation or any selected SDK component.
    /// It does not mutate global appearance or another host's configuration.
    func hanlinChatAppearance(_ appearance: HanlinChatAppearance) -> some View {
        environment(\.hanlinChatAppearance, appearance)
    }
}
#endif
