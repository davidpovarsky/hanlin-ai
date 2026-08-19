import SwiftUI
import Translation
import TranslationUIProvider

@MainActor
struct HanlinTranslationProviderView: View {
    @State private var context: any TranslationUIProviderContext
    @State private var configuration: TranslationSession.Configuration?
    @State private var translatedText: AttributedString?
    @State private var translationError: String?
    @State private var isTranslating = false

    private let registry = HanlinTranslationActionRegistry.standard

    init(context: any TranslationUIProviderContext) {
        _context = State(initialValue: context)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sourceSection
                actionSection

                if isTranslating {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Translating…")
                            .foregroundStyle(.secondary)
                    }
                }

                if let translatedText {
                    translationSection(translatedText)
                }

                if let translationError {
                    ContentUnavailableView(
                        "Translation unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(translationError)
                    )
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .translationTask(configuration) { @Sendable session in
            let sourceText: String? = await MainActor.run {
                guard let inputText = context.inputText, !inputText.characters.isEmpty else {
                    return nil
                }
                return String(inputText.characters)
            }

            guard let sourceText else {
                await MainActor.run {
                    translatedText = nil
                    translationError = nil
                    isTranslating = false
                }
                return
            }

            await MainActor.run {
                isTranslating = true
            }

            do {
                let response = try await session.translate(sourceText)
                let result = AttributedString(response.targetText)

                await MainActor.run {
                    translatedText = result
                    translationError = nil
                    isTranslating = false
                }
            } catch {
                let message = error.localizedDescription

                await MainActor.run {
                    translatedText = nil
                    translationError = message
                    isTranslating = false
                }
            }
        }
        .onChange(of: context.inputText) { _, _ in
            configuration = nil
            translatedText = nil
            translationError = nil
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Selected text", systemImage: "text.quote")
                .font(.headline)

            if let inputText = context.inputText, !inputText.characters.isEmpty {
                Text(inputText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No text was provided by the host app.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        let actions = registry.actions(for: context.inputText)

        if !actions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Hanlin")
                    .font(.headline)

                ForEach(actions) { action in
                    Button {
                        perform(action)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: action.systemImage)
                                .frame(width: 24)
                            Text(action.title)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func translationSection(_ translation: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Translation", systemImage: "globe")
                .font(.headline)
            Text(translation)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Done") {
                context.finish(translation: nil)
            }
            .buttonStyle(.bordered)

            Spacer()

            if context.allowsReplacement, let translatedText {
                Button("Replace") {
                    context.finish(translation: translatedText)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func perform(_ action: HanlinTranslationActionDescriptor) {
        guard action.id == "translate" else { return }

        context.expandSheet()
        translatedText = nil
        translationError = nil

        if configuration == nil {
            configuration = TranslationSession.Configuration(source: nil, target: nil)
        } else {
            configuration?.invalidate()
        }
    }
}
