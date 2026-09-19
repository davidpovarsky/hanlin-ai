// TranslationProviderRootView.swift
// ChavrusaChatTranslationProvider

import HanlinPlatformContracts
import HanlinScriptExtensions
import SwiftUI
@preconcurrency import TranslationUIProvider

struct TranslationProviderRootView: View {
    @State private var session: TranslationProviderSession

    init(context: any TranslationUIProviderContext) {
        _session = State(initialValue: TranslationProviderSession(context: context))
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
    }
}
