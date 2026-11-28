import AppIntents
import ExtensionKit
import HanlinExtensionContracts
import HanlinScriptExtensions
import HanlinTranslationUI
import SwiftUI
@preconcurrency import Translation
@preconcurrency import TranslationUIProvider

@main
final class HanlinMiniAppsTranslationProvider: TranslationUIProviderExtension {
    private static let services = HanlinTranslationHostServices(configuration: .miniapps)

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            TranslationProviderRootView(context: context, services: Self.services)
        }
    }
}

struct HanlinMiniAppsTranslationIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [HanlinScriptExtensionIntentsPackage.self]
    }
}
