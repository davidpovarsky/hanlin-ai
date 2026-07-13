import SwiftUI

@MainActor
struct NativeAppTextStudioAppModule: NativeAppModule {
    let manifest = NativeAppManifest(
        id: NativeAppTextStudioIndex.id,
        title: "Text Studio",
        subtitle: "Write, inspect, transform and keep history",
        description: String(localized: "Analyze, transform and continue working with text"),
        systemImage: "textformat.alt",
        category: .text,
        entryPoints: [.fullApp, .assistantTool, .chatCard],
        requiredCapabilities: NativeAppTextStudioImports.capabilities.map(\.id),
        keywords: ["text", "editor", "analysis", "transform", "word count", "clipboard"],
        appearance: NativeAppAppearance(startHex: "F06FB5", endHex: "A84FDB"),
        isExperimental: true
    )

    func makeRootView(context: NativeAppContext) -> AnyView {
        NativeAppTextStudioExports.rootView(context: context)
    }

    func assistantTools(context: NativeAppContext) -> [NativeTool] {
        NativeAppTextStudioExports.assistantTools(context: context)
    }

    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider] {
        [NativeAppTextStudioChatCardProvider()]
    }

    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest] {
        NativeAppTextStudioImports.capabilities
    }
}
