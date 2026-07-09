import SwiftUI

@MainActor
struct TextToolkitAppModule: NativeAppModule {
    let manifest = NativeAppManifest(
        id: TextToolkitIndex.id,
        title: "Text Toolkit",
        subtitle: "Analyze and transform text",
        description: "A small native text utility app that counts words, extracts links, and transforms text. It exposes the same logic to the assistant.",
        systemImage: "textformat",
        category: .text,
        entryPoints: [.fullApp, .assistantTool, .chatCard],
        requiredCapabilities: TextToolkitImports.capabilities.map(\.id),
        isExperimental: false
    )

    func makeRootView(context: NativeAppContext) -> AnyView { TextToolkitExports.rootView(context: context) }
    func assistantTools(context: NativeAppContext) -> [NativeTool] { TextToolkitExports.assistantTools(context: context) }
    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider] { [TextToolkitChatCardProvider()] }
    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest] { TextToolkitImports.capabilities }
}
