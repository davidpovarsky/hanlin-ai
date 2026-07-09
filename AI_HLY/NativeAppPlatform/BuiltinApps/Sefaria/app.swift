import SwiftUI

@MainActor
struct SefariaAppModule: NativeAppModule {
    let manifest = NativeAppManifest(
        id: SefariaIndex.id,
        title: "Sefaria",
        subtitle: "Jewish texts and sources",
        description: "Search Jewish sources, open references, copy text, and expose source search to the assistant.",
        systemImage: "book.closed",
        category: .knowledge,
        entryPoints: [.fullApp, .assistantTool, .chatCard],
        requiredCapabilities: SefariaImports.capabilities.map(\.id),
        isExperimental: true
    )

    func makeRootView(context: NativeAppContext) -> AnyView {
        SefariaExports.rootView(context: context)
    }

    func assistantTools(context: NativeAppContext) -> [NativeTool] {
        SefariaExports.assistantTools(context: context)
    }

    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider] {
        [SefariaChatCardProvider()]
    }

    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest] {
        SefariaImports.capabilities
    }
}
