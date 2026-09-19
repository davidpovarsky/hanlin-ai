// TranslationProviderAppsView.swift
// ChavrusaChatTranslationProvider

import HanlinPlatformContracts
import HanlinScriptExtensions
import SwiftUI

struct TranslationProviderAppsView: View {
    @Bindable var session: TranslationProviderSession
    @State private var apps: [HanlinScriptTranslationUISnapshot] = []
    @State private var isLoading: Bool = true

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            if apps.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Mini Apps Available",
                    systemImage: "square.grid.2x2",
                    description: Text("Install Script Mini Apps in Hanlin to use them here.")
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(apps) { app in
                        Button {
                            session.path.append(.miniApp(app))
                        } label: {
                            HanlinMiniAppCardView(
                                title: app.displayName,
                                subtitle: app.summary ?? "",
                                accentHex: app.accentHex,
                                isBeta: app.isBeta,
                                iconSymbol: app.iconSymbol,
                                style: .compact
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Mini Apps")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadApps()
        }
    }

    private func loadApps() {
        isLoading = true
        defer { isLoading = false }
        if let snapshot = try? HanlinScriptExtensionStore().load() {
            apps = snapshot.translationApps
        }
    }
}
