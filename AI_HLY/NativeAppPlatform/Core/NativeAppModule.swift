import Foundation
import SwiftUI

@MainActor
protocol NativeAppModule {
    var manifest: NativeAppManifest { get }

    /// Full, user-facing app screen shown in the Apps tab.
    func makeRootView(context: NativeAppContext) -> AnyView

    /// Thin AI adapters. These must reuse the same Core services as the full app.
    func assistantTools(context: NativeAppContext) -> [NativeTool]

    /// Compact UI providers that can render app data inside chat.
    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider]

    /// Declared system capabilities required by this app.
    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest]
}

extension NativeAppModule {
    func assistantTools(context: NativeAppContext) -> [NativeTool] { [] }
    func chatCards(context: NativeAppContext) -> [NativeChatCardProvider] { [] }
    func capabilities(context: NativeAppContext) -> [NativeCapabilityRequest] { [] }
}

@MainActor
protocol NativeChatCardProvider {
    var id: String { get }
    var title: String { get }
}
