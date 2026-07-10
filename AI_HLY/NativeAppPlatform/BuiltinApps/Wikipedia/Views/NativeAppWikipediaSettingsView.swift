import SwiftUI

struct NativeAppWikipediaSettingsView: View {
    @ObservedObject var store: NativeAppWikipediaStore

    var body: some View {
        Form {
            Section("Language") {
                Picker("Wikipedia Language", selection: $store.language) {
                    ForEach(NativeAppWikipediaLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
            }

            Section("Data") {
                LabeledContent("Recent Searches", value: "\(store.recentQueries.count)")
                LabeledContent("Saved Articles", value: "\(store.savedArticles.count)")
                Button("Clear Recent Searches", role: .destructive) {
                    store.clearRecentQueries()
                }
                Button("Clear Saved Articles", role: .destructive) {
                    store.clearSavedArticles()
                }
            }

            Section("Architecture") {
                Text("The app UI and Assistant tools both call NativeAppWikipediaSearchService and NativeAppWikipediaSummaryService from Core.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
