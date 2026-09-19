// TranslationProviderRootView.swift
// ChavrusaChatTranslationProvider

import HanlinPlatformContracts
import HanlinScriptExtensions
import SwiftUI
@preconcurrency import TranslationUIProvider

struct TranslationProviderRootView: View {
    let context: any TranslationUIProviderContext
    @State private var session: TranslationProviderSession

    init(context: any TranslationUIProviderContext) {
        self.context = context
        _session = State(initialValue: TranslationProviderSession(context: context))
    }

    private var currentSourceText: String {
        context.inputText.map { String($0.characters) } ?? ""
    }

    var body: some View {
        NavigationStack(path: $session.path) {
            TranslationProviderHomeView(session: session)
                .navigationDestination(for: TranslationRoute.self) { route in
                    switch route {
                    case .apps:
                        TranslationProviderAppsView(session: session)
                    case let .miniApp(app):
                        TranslationProviderMiniAppView(session: session, app: app)
                    case .chat:
                        TranslationProviderMiniChatView(session: session)
                    }
                }
        }
        .onAppear {
            session.updateSourceTextIfNeeded(currentSourceText)
        }
        .task(id: currentSourceText) {
            session.updateSourceTextIfNeeded(currentSourceText)
        }
    }
}
