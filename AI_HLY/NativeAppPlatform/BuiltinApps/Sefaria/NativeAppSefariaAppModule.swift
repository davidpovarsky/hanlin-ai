import SwiftUI

@MainActor
struct NativeAppSefariaAppModule: NativeAppModule {
    let manifest = NativeAppManifest(
        id: NativeAppSefariaIndex.id,
        title: "Sefaria",
        subtitle: "Search, read, save and revisit sources",
        description: String(localized: "Search and read Jewish texts and sources"),
        systemImage: "books.vertical.fill",
        category: .knowledge,
        entryPoints: [.fullApp, .assistantTool, .chatCard],
        requiredCapabilities: NativeAppSefariaImports.capabilities.map(\.id),
        keywords: ["Torah", "Talmud", "Tanakh", "Halacha", "Jewish texts", "מקורות", "ספריא"],
        appearance: NativeAppAppearance(startHex: "5CB88A", endHex: "2E7D68"),
        isExperimental: true
    )

    func makeRootView(context: NativeAppContext) -> AnyView {
        NativeAppSefariaExports.rootView(context: context)
    }

    func assistantTools(context: NativeAppContext) -> [NativeTool] {
        NativeAppSefariaExports.assistantTools(context: context)
    }

    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider] {
        [NativeAppSefariaChatCardProvider()]
    }

    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest] {
        NativeAppSefariaImports.capabilities
    }
}
