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
    let isExperimental: Bool

    init(
        id: String,
        title: String,
        subtitle: String,
        description: String,
        systemImage: String,
        category: NativeAppCategory,
        entryPoints: Set<NativeAppEntryPointKind>,
        requiredCapabilities: [String] = [],
        isExperimental: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.systemImage = systemImage
        self.category = category
        self.entryPoints = entryPoints
        self.requiredCapabilities = requiredCapabilities
        self.isExperimental = isExperimental
    }
}
