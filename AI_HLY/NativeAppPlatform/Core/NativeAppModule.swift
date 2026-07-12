import Foundation
import SwiftUI

@MainActor
protocol NativeAppModule {
    var manifest: NativeAppManifest { get }

    /// Full, user-facing app screen shown directly from the Apps grid.
    func makeRootView(context: NativeAppContext) -> AnyView

    func makeRootView(context: NativeAppContext, route: NativeAppRoute?) -> AnyView

    /// Thin AI adapters. These must reuse the same Core services as the full app.
    func assistantTools(context: NativeAppContext) -> [NativeTool]

    /// Compact UI providers that can render app data inside chat.
    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider]

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
    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest] { [] }
}

@MainActor
protocol NativeChatCardProvider {
    var id: String { get }
    var title: String { get }
}
