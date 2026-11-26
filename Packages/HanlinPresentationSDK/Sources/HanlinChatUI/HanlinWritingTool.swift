import Foundation
import HanlinLocalization

public enum HanlinWritingTool: String, CaseIterable {
        case translation, polish, summary
        public var title: String {
            switch self {
            case .translation: String(localized: "即时翻译", bundle: HanlinLocalization.bundle)
            case .polish: String(localized: "即时润色", bundle: HanlinLocalization.bundle)
            case .summary: String(localized: "即时摘要", bundle: HanlinLocalization.bundle)
            }
        }
    }
