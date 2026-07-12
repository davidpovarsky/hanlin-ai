import Foundation
import SwiftData
import SwiftUI

typealias NativeOpenURLAction = @MainActor (URL) -> Void

@MainActor
struct NativeAppContext {
    var localeIdentifier: String
    var modelContext: ModelContext?
    var openURL: NativeOpenURLAction?
    var capabilityRegistry: NativeCapabilityRegistry
    var session: NativeAppSession?
    var initialRoute: NativeAppRoute?
    var platform: NativeAppPlatformServices

    init(
        localeIdentifier: String = Locale.current.identifier,
        modelContext: ModelContext? = nil,
        openURL: NativeOpenURLAction? = nil,
        capabilityRegistry: NativeCapabilityRegistry? = nil,
        session: NativeAppSession? = nil,
        initialRoute: NativeAppRoute? = nil,
        platform: NativeAppPlatformServices? = nil
    ) {
        self.localeIdentifier = localeIdentifier
        self.modelContext = modelContext
        self.openURL = openURL
        let capabilityRegistry = capabilityRegistry ?? .shared
        self.capabilityRegistry = capabilityRegistry
        self.session = session
        self.initialRoute = initialRoute ?? session?.initialRoute
        self.platform = platform ?? NativeAppPlatformServices.default(
            appID: session?.appID,
            modelContext: modelContext,
            openURL: openURL,
            capabilityRegistry: capabilityRegistry
        )
    }

    var isHebrew: Bool { localeIdentifier.hasPrefix("he") }
    var isChinese: Bool { localeIdentifier.hasPrefix("zh") }
}
