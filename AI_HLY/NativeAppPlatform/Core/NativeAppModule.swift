import Foundation
import HanlinPlatformContracts
import SwiftUI

@MainActor
protocol NativeAppModule {
    var manifest: NativeAppManifest { get }

    /// Optional canonical registration providing package-safe descriptor and identity.
    var canonicalRegistration: (any HanlinStaticMiniAppRegistration)? { get }

    /// Full, user-facing app screen shown directly from the Apps grid.
    func makeRootView(context: NativeAppContext) -> AnyView

    func makeRootView(context: NativeAppContext, route: NativeAppRoute?) -> AnyView

    /// Thin AI adapters. These must reuse the same Core services as the full app.
    func assistantTools(context: NativeAppContext) -> [NativeTool]

    /// Compact UI providers that can render app data inside chat.
    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider]

    /// Full capability projection preserving both supported requests and diagnostics.
    func capabilityProjection(context: NativeAppContext) -> NativeCapabilityProjection

    /// Declared system capabilities required by this app.
    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest]
}

extension NativeAppModule {
    func makeRootView(context: NativeAppContext, route: NativeAppRoute?) -> AnyView {
        var routedContext = context
        routedContext.initialRoute = route ?? context.initialRoute
        return makeRootView(context: routedContext)
    }

    func assistantTools(context: NativeAppContext) -> [NativeTool] { [] }
    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider] { [] }

    func capabilityProjection(context: NativeAppContext) -> NativeCapabilityProjection {
        if let canonical = canonicalRegistration {
            return NativeCapabilityProjection(declarations: canonical.descriptor.capabilities)
        }
        return NativeCapabilityProjection(supportedRequests: [])
    }

    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest] {
        capabilityProjection(context: context).supportedRequests
    }

    var canonicalRegistration: (any HanlinStaticMiniAppRegistration)? { nil }
}

@MainActor
protocol NativeChatCardProvider {
    var id: String { get }
    var title: String { get }
}
