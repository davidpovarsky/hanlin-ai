import SwiftUI

@MainActor
struct WikipediaAppModule: NativeAppModule {
    let manifest = NativeAppManifest(
        id: WikipediaIndex.id,
        title: "Wikipedia",
        subtitle: "Search and summarize articles",
        description: "Search Wikipedia, open article summaries, and expose Wikipedia search to the assistant.",
        systemImage: "globe",
        category: .knowledge,
        entryPoints: [.fullApp, .assistantTool, .chatCard],
        requiredCapabilities: WikipediaImports.capabilities.map(\.id),
        isExperimental: true
    )

    func makeRootView(context: NativeAppContext) -> AnyView { WikipediaExports.rootView(context: context) }
    func assistantTools(context: NativeAppContext) -> [NativeTool] { WikipediaExports.assistantTools(context: context) }
    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider] { [WikipediaChatCardProvider()] }
    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest] { WikipediaImports.capabilities }
}
