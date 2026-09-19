// TranslationProviderMiniAppView.swift
// ChavrusaChatTranslationProvider

import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinScriptUI
import SwiftUI

struct TranslationProviderMiniAppView: View {
    @Bindable var session: TranslationProviderSession
    let app: HanlinScriptTranslationUISnapshot

    var body: some View {
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
                        Text("BETA")
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
                        "No UI Defined",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This app does not provide a declarative Translation UI.")
                    )
                    .padding(.top, 30)
                }
            }
        }
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
