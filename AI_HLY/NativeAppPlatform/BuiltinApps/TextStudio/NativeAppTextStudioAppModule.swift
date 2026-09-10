import HanlinPlatformContracts
import SwiftUI

@MainActor
struct NativeAppTextStudioAppModule: NativeAppModule {
    private let registration = TextStudioCanonicalRegistration()

    var canonicalRegistration: (any HanlinStaticMiniAppRegistration)? {
        registration
    }

    var manifest: NativeAppManifest {
        NativeAppManifest(
            descriptor: registration.descriptor,
            keywords: ["text", "editor", "analysis", "transform", "word count", "clipboard"],
            isExperimental: true
        )
    }

    func makeRootView(context: NativeAppContext) -> AnyView {
        NativeAppTextStudioExports.rootView(context: context)
    }

    func assistantTools(context: NativeAppContext) -> [NativeTool] {
        NativeAppTextStudioExports.assistantTools(context: context)
    }

    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider] {
        [NativeAppTextStudioChatCardProvider()]
    }

    var capabilityProjection: NativeCapabilityProjection {
        NativeCapabilityProjection(declarations: registration.descriptor.capabilities)
    }

    func capabilityProjection(context: NativeAppContext) -> NativeCapabilityProjection {
        capabilityProjection
    }

    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest] {
        capabilityProjection.supportedRequests
    }
}
