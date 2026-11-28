import HanlinLocalization
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
        case .knowledge: return String(localized: "Knowledge", bundle: HanlinLocalization.bundle)
        case .productivity: return String(localized: "Productivity", bundle: HanlinLocalization.bundle)
        case .utility: return String(localized: "Utilities", bundle: HanlinLocalization.bundle)
        case .text: return String(localized: "Text", bundle: HanlinLocalization.bundle)
        case .media: return String(localized: "Media", bundle: HanlinLocalization.bundle)
        case .automation: return String(localized: "Automation", bundle: HanlinLocalization.bundle)
        case .developer: return String(localized: "Developer", bundle: HanlinLocalization.bundle)
        }
    }
}
