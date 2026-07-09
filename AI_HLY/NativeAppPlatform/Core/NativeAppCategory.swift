import Foundation

enum NativeAppCategory: String, Codable, Hashable, CaseIterable {
    case knowledge
    case productivity
    case utility
    case text
    case media
    case automation
    case developer

    var title: String {
        switch self {
        case .knowledge: return String(localized: "Knowledge")
        case .productivity: return String(localized: "Productivity")
        case .utility: return String(localized: "Utilities")
        case .text: return String(localized: "Text")
        case .media: return String(localized: "Media")
        case .automation: return String(localized: "Automation")
        case .developer: return String(localized: "Developer")
        }
    }
}
