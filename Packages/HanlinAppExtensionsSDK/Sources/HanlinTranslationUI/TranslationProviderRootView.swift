#if canImport(TranslationUIProvider)
import HanlinLocalization
// TranslationProviderRootView.swift
// ChavrusaChatTranslationProvider

import HanlinPlatformContracts
import HanlinScriptExtensions
import SwiftUI
@preconcurrency import TranslationUIProvider

public struct TranslationProviderRootView: View {
    public let context: any TranslationUIProviderContext
    @State private var session: TranslationProviderSession

    public init(context: any TranslationUIProviderContext, services: HanlinTranslationHostServices) {
        self.context = context
        _session = State(initialValue: TranslationProviderSession(context: context, services: services))
    }

    public init(session: TranslationProviderSession) {
        self.context = session.context
        _session = State(initialValue: session)
    }

    private var currentSourceText: String {
        context.inputText.map { String($0.characters) } ?? ""
    }

    public var body: some View {
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

#endif
