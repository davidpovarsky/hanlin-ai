#if canImport(TranslationUIProvider)
import HanlinLocalization
// TranslationProviderMiniAppView.swift
// ChavrusaChatTranslationProvider

import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinScriptUI
import SwiftUI

public struct TranslationProviderMiniAppView: View {
    @Bindable public var session: TranslationProviderSession
    public let app: HanlinScriptTranslationUISnapshot

    public init(session: TranslationProviderSession, app: HanlinScriptTranslationUISnapshot) {
        self.session = session
        self.app = app
    }

    @ViewBuilder public var body: some View {
        if app.nativePresentation != nil {
            TranslationProviderNativePresentationView(session: session, app: app)
        } else {
            legacyBody
        }
    }

    private var legacyBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header badge
                HStack {
                    Image(systemName: app.iconSymbol ?? "doc.text.magnifyingglass")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                    Text(app.displayName)
                        .font(.headline)
                    Spacer()
                    if app.isBeta {
                        Text("BETA", bundle: HanlinLocalization.bundle)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Divider()
                    .padding(.horizontal, 16)

                // Substituted Declarative Node Tree
                if let root = app.rootNode {
                    let substitutedRoot = root.substituting(sessionContext: session.sessionContext)
                    HanlinExtensionNodeView(node: substitutedRoot, identity: app.identity)
                        .padding(.horizontal, 16)
                } else {
                    ContentUnavailableView(
                        hanlin: "No UI Defined",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This app does not provide a declarative Translation UI.", bundle: HanlinLocalization.bundle)
                    )
                    .padding(.top, 30)
                }
            }
        }
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#endif
