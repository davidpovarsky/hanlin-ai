import HanlinPlatformContracts
import SwiftUI

@MainActor
struct NativeAppSefariaAppModule: NativeAppModule {
    private let registration = SefariaCanonicalRegistration()

    var canonicalRegistration: (any HanlinStaticMiniAppRegistration)? {
        registration
    }

    var manifest: NativeAppManifest {
        NativeAppManifest(
            descriptor: registration.descriptor,
            keywords: ["Torah", "Talmud", "Tanakh", "Halacha", "Jewish texts", "מקורות", "ספריא"],
            isExperimental: true
        )
    }

    func makeRootView(context: NativeAppContext) -> AnyView {
        NativeAppSefariaExports.rootView(context: context)
    }

    func assistantTools(context: NativeAppContext) -> [NativeTool] {
        NativeAppSefariaExports.assistantTools(context: context)
    }

    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider] {
        [NativeAppSefariaChatCardProvider()]
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
