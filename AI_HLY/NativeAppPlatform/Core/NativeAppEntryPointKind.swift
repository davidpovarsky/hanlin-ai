import Foundation

enum NativeAppEntryPointKind: String, Codable, Hashable, CaseIterable {
    case fullApp
    case assistantTool
    case chatCard
    case widget
    case liveActivity
    case shortcut
    case shareExtension
    case spotlight

    var title: String {
        switch self {
        case .fullApp: return "Full App"
        case .assistantTool: return "Assistant Tool"
        case .chatCard: return "Chat Card"
        case .widget: return "Widget"
        case .liveActivity: return "Live Activity"
        case .shortcut: return "Shortcut"
        case .shareExtension: return "Share Extension"
        case .spotlight: return "Spotlight"
        }
    }
}

enum NativePresentationMode: String, Codable, Hashable {
    case fullApp
    case chatCard
    case compact
}
