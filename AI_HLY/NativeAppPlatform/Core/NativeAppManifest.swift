import Foundation

struct NativeAppManifest: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let description: String
    let systemImage: String
    let category: NativeAppCategory
    let entryPoints: Set<NativeAppEntryPointKind>
    let requiredCapabilities: [String]
    let keywords: [String]
    let appearance: NativeAppAppearance
    let isExperimental: Bool
    let areAssistantToolsEnabledByDefault: Bool

    init(
        id: String,
        title: String,
        subtitle: String,
        description: String,
        systemImage: String,
        category: NativeAppCategory,
        entryPoints: Set<NativeAppEntryPointKind>,
        requiredCapabilities: [String] = [],
        keywords: [String] = [],
        appearance: NativeAppAppearance,
        isExperimental: Bool = false,
        areAssistantToolsEnabledByDefault: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.systemImage = systemImage
        self.category = category
        self.entryPoints = entryPoints
        self.requiredCapabilities = requiredCapabilities
        self.keywords = keywords
        self.appearance = appearance
        self.isExperimental = isExperimental
        self.areAssistantToolsEnabledByDefault = areAssistantToolsEnabledByDefault
    }

    func matches(searchText: String) -> Bool {
        let value = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return true }
        return ([title, subtitle, description, category.title] + keywords)
            .joined(separator: " ")
            .lowercased()
            .contains(value)
    }
}

import HanlinPlatformContracts

extension NativeAppManifest {
    init(
        descriptor: HanlinAppDescriptor,
        keywords: [String] = [],
        isExperimental: Bool = true,
        areAssistantToolsEnabledByDefault: Bool = true
    ) {
        let title = descriptor.name.preferredValue(forLocale: "en")
        let subtitle = descriptor.summary.preferredValue(forLocale: "en")
        let description = descriptor.description.preferredValue(forLocale: "en")

        let systemImage: String
        switch descriptor.icon {
        case let .systemSymbol(name):
            systemImage = name
        case let .asset(name):
            systemImage = name
        case let .packageResource(path):
            systemImage = path
        }

        var entryPoints: Set<NativeAppEntryPointKind> = []
        for ep in descriptor.entryPoints {
            switch ep.kind {
            case .app:
                entryPoints.insert(.fullApp)
            case .assistantTool:
                entryPoints.insert(.assistantTool)
            case .embeddedResult:
                entryPoints.insert(.chatCard)
            default:
                break
            }
        }

        let category: NativeAppCategory = switch descriptor.category {
        case .knowledge: .knowledge
        case .productivity: .text
        case .utilities: .utility
        default: .knowledge
        }

        let hex = descriptor.appearance.accentHex?.trimmingCharacters(in: CharacterSet(charactersIn: "#")) ?? "5CB88A"
        let appearance = NativeAppAppearance(startHex: hex, endHex: hex)
        let requiredCapabilities = descriptor.capabilities.map(\.id.rawValue)

        self.init(
            id: descriptor.id.rawValue,
            title: title,
            subtitle: subtitle,
            description: description,
            systemImage: systemImage,
            category: category,
            entryPoints: entryPoints,
            requiredCapabilities: requiredCapabilities,
            keywords: keywords,
            appearance: appearance,
            isExperimental: isExperimental,
            areAssistantToolsEnabledByDefault: areAssistantToolsEnabledByDefault
        )
    }
}
