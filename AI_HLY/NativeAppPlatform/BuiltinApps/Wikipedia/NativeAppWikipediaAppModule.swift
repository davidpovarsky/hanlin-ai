import SwiftUI

@MainActor
struct NativeAppWikipediaAppModule: NativeAppModule {
    let manifest = NativeAppManifest(
        id: NativeAppWikipediaIndex.id,
        title: "Wikipedia",
        subtitle: "Explore, save and revisit knowledge",
        description: "A multi-screen encyclopedia client with search, article pages, related results, saved articles, recent searches, language settings, chat cards and Assistant entry points.",
        systemImage: "globe.americas.fill",
        category: .knowledge,
        entryPoints: [.fullApp, .assistantTool, .chatCard],
        requiredCapabilities: NativeAppWikipediaImports.capabilities.map(\.id),
        keywords: ["encyclopedia", "articles", "knowledge", "wiki", "ויקיפדיה"],
        appearance: NativeAppAppearance(startHex: "4C83E8", endHex: "3452A4"),
        isExperimental: true
    )

    func makeRootView(context: NativeAppContext) -> AnyView {
        NativeAppWikipediaExports.rootView(context: context)
    }

    func assistantTools(context: NativeAppContext) -> [NativeTool] {
        NativeAppWikipediaExports.assistantTools(context: context)
    }

    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider] {
        [NativeAppWikipediaChatCardProvider()]
    }

    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest] {
        NativeAppWikipediaImports.capabilities
    }
}
