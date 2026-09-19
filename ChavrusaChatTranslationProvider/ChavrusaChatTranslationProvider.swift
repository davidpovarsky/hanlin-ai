import SwiftUI
@preconcurrency import Translation
@preconcurrency import TranslationUIProvider

@main
final class ChavrusaChatTranslationProvider: TranslationUIProviderExtension {
    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            TranslationProviderRootView(context: context)
        }
    }
}
