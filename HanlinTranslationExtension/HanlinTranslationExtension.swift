import SwiftUI
import TranslationUIProvider

@main
@MainActor
final class HanlinTranslationExtension: TranslationUIProviderExtension {
    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            HanlinTranslationProviderView(context: context)
        }
    }
}
