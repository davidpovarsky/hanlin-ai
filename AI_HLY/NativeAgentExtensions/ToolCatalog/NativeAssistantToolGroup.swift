import Foundation

struct NativeAssistantToolGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let summary: String
    let systemImage: String
    let category: NativeAppCategory
    let isExperimental: Bool
    let isEnabledByDefault: Bool
    let toolEntries: [NativeToolCatalogEntry]
}
