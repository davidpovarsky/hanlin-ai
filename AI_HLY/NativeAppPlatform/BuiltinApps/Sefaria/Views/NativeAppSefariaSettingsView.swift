import SwiftUI

struct NativeAppSefariaSettingsView: View {
    @ObservedObject var store: NativeAppSefariaStore

    var body: some View {
        Form {
            Section("Reading") {
                Picker("Text Language", selection: $store.preferredLanguage) {
                    ForEach(NativeAppSefariaLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
            }

            Section("Data") {
                LabeledContent("Recent Searches", value: "\(store.recentQueries.count)")
                LabeledContent("Saved Sources", value: "\(store.savedSources.count)")
                Button("Clear Recent Searches", role: .destructive) {
                    store.clearRecentQueries()
                }
                Button("Clear Saved Sources", role: .destructive) {
                    store.clearSavedSources()
                }
            }

            Section("Architecture") {
                Text("Views, Assistant tools and chat cards all consume NativeAppSefariaSearchService and NativeAppSefariaSourceService from Core.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
