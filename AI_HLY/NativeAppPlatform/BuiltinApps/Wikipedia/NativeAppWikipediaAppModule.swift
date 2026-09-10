import HanlinPlatformContracts
import SwiftUI

@MainActor
struct NativeAppWikipediaAppModule: NativeAppModule {
    private let registration = WikipediaCanonicalRegistration()

    var canonicalRegistration: (any HanlinStaticMiniAppRegistration)? {
        registration
    }

    var manifest: NativeAppManifest {
        NativeAppManifest(
            descriptor: registration.descriptor,
            keywords: ["encyclopedia", "articles", "knowledge", "wiki", "ויקיפדיה"],
            isExperimental: true
        )
    }

    func makeRootView(context: NativeAppContext) -> AnyView {
        NativeAppWikipediaExports.rootView(context: context)
    }

    func assistantTools(context: NativeAppContext) -> [NativeTool] {
        NativeAppWikipediaExports.assistantTools(context: context)
    }

    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider] {
        [NativeAppWikipediaChatCardProvider()]
    }

    var capabilityProjection: NativeCapabilityProjection {
        NativeCapabilityProjection(declarations: registration.descriptor.capabilities)
    }

    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest] {
        capabilityProjection.supportedRequests
    }
}
