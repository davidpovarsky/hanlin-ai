import SwiftUI
import Translation
import TranslationUIProvider

@main
final class ChavrusaChatTranslationProvider: TranslationUIProviderExtension {
    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            TranslationProviderView(context: context)
        }
    }
}

private struct TranslationProviderView<Context: TranslationUIProviderContext>: View {
    let context: Context
    @State private var translatedText = ""

    private var sourceText: String {
        context.inputText.map { String($0.characters) } ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Selected text") { Text(sourceText) }
                Section("Translation") {
                    if translatedText.isEmpty {
                        ContentUnavailableView("Ready to translate", systemImage: "translate")
                    } else {
                        Text(translatedText).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("ChavrusaChat")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(context.allowsReplacement ? "Replace" : "Done") {
                        context.finish(translation: translatedText.isEmpty ? nil : AttributedString(translatedText))
                    }
                    .disabled(translatedText.isEmpty)
                }
            }
            .translationTask(source: nil, target: nil) { session in
                guard !sourceText.isEmpty else { return }
                if let response = try? await session.translate(sourceText) {
                    translatedText = response.targetText
                }
            }
        }
    }
}
