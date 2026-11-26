import AI_Hanlin
import AppIntents
import ExpoWidgets
import HanlinTranslationUI
import SwiftUI

#if HANLIN_NATIVESCRIPT_POC
@main
struct HanlinNativeScriptPOCApp: App {
    var body: some Scene {
        WindowGroup { HanlinNativeScriptAcceptanceView() }
    }
}
#else
@main
@MainActor
struct MyApp: App {
    @UIApplicationDelegateAdaptor(HanlinNotificationApplicationDelegate.self) private var notificationDelegate
    private let context: HanlinApplicationContext

    init() {
        do { context = try HanlinApplicationContext(configuration: .hanlin) }
        catch { fatalError("Unable to initialize Hanlin: \(error)") }
    }

    var body: some Scene {
        HanlinApplicationScene(context: context)
    }
}
#endif

/// Register the original SDK's system actions with this application's metadata.
struct HanlinAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [HanlinApplicationIntentsPackage.self, HanlinNativePresentationIntentsPackage.self, HanlinExpoWidgetsIntentsPackage.self]
    }
}
