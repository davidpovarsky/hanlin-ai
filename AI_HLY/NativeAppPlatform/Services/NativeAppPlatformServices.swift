import Foundation
import SwiftData
import HanlinPlatformContracts
import HanlinMiniAppCore

@MainActor
struct NativeAppPlatformServices {
    let appID: String?
    let modelContext: ModelContext?
    let router: NativeAppRouter
    let storage: NativeAppStorageBroker
    let pasteboard: NativeAppPasteboardBroker
    let openURL: NativeAppOpenURLBroker
    let network: NativeAppNetworkBroker
    let actionBus: NativeAppActionBus
    let capabilityRegistry: NativeCapabilityRegistry
    let hostServices: SwiftMiniAppHostServicesAdapter

    static func `default`(
        appID: String?, modelContext: ModelContext?, openURL: NativeOpenURLAction?,
        capabilityRegistry: NativeCapabilityRegistry
    ) -> NativeAppPlatformServices {
        let router = NativeAppRouter()
        let storage = NativeAppStorageBroker(appID: appID)
        let pasteboard = NativeAppPasteboardBroker(appID: appID, capabilityRegistry: capabilityRegistry)
        let openURLBroker = NativeAppOpenURLBroker(appID: appID, openURL: openURL, capabilityRegistry: capabilityRegistry)
        let network = NativeAppNetworkBroker(appID: appID, capabilityRegistry: capabilityRegistry)
        let actionBus = NativeAppActionBus(router: router, storage: storage, pasteboard: pasteboard,
                                           openURL: openURLBroker, network: network,
                                           capabilityRegistry: capabilityRegistry)
        let validAppID = (try? HanlinAppID(validating: appID ?? "hanlin.swift.app"))
            ?? (try! HanlinAppID(validating: "hanlin.swift.app"))
        let hostServices = SwiftMiniAppHostServicesAdapter(appID: validAppID)
        return NativeAppPlatformServices(appID: appID, modelContext: modelContext,
                                         router: router, storage: storage,
                                         pasteboard: pasteboard, openURL: openURLBroker,
                                         network: network, actionBus: actionBus,
                                         capabilityRegistry: capabilityRegistry,
                                         hostServices: hostServices)
    }
}
