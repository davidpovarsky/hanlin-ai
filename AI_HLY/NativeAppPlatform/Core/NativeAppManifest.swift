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
