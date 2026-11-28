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

    private var providedPlatform: NativeAppPlatformServices?

    /// Lazily resolves platform services. Constructing a lightweight context for
    /// assistant-tool registration no longer creates router/storage/pasteboard/network services.
    var platform: NativeAppPlatformServices {
        providedPlatform ?? NativeAppPlatformServices.default(
            appID: session?.appID,
            modelContext: modelContext,
            openURL: openURL,
            capabilityRegistry: capabilityRegistry
        )
    }

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
        self.capabilityRegistry = capabilityRegistry ?? .shared
        self.session = session
        self.initialRoute = initialRoute ?? session?.initialRoute
        self.providedPlatform = platform
    }

    var isHebrew: Bool { localeIdentifier.hasPrefix("he") }
    var isChinese: Bool { localeIdentifier.hasPrefix("zh") }
}
