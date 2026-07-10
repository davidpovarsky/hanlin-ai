import SwiftUI
import SwiftData

struct NativeAppsHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var searchText = ""
    @State private var isEditingApps = false
    @State private var showsAddSheet = false
    @State private var infoModuleID: String?

    private var context: NativeAppContext {
        NativeAppContext(
            localeIdentifier: Locale.current.identifier,
            modelContext: modelContext,
            openURL: { url in openURL(url) }
        )
    }

    private var modules: [NativeAppModule] {
        NativeAppRegistry.shared.allModules()
    }

    private var visibleModules: [NativeAppModule] {
        modules.filter { $0.manifest.matches(searchText: searchText) }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 205, maximum: 320), spacing: 20)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(visibleModules, id: \.manifest.id) { module in
                        ZStack(alignment: .topLeading) {
                            NavigationLink {
                                module.makeRootView(context: context)
                            } label: {
                                NativeAppCardView(
                                    manifest: module.manifest,
                                    isEditing: isEditingApps
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditingApps)

                            Menu {
                                Button {
                                    infoModuleID = module.manifest.id
                                } label: {
                                    Label("App Information", systemImage: "info.circle")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(.white.opacity(0.18), in: Circle())
                            }
                            .padding(12)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(localized: "Apps"))
            .searchable(text: $searchText, prompt: "Search Apps")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(isEditingApps ? "Done" : "Edit") {
                        isEditingApps.toggle()
                    }
                    Button {
                        showsAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if visibleModules.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .sheet(isPresented: $showsAddSheet) {
                NativeAppsAddSheet(modules: modules)
            }
            .sheet(isPresented: Binding(
                get: { infoModuleID != nil },
                set: { if !$0 { infoModuleID = nil } }
            )) {
                if let id = infoModuleID, let module = NativeAppRegistry.shared.module(id: id) {
                    NativeAppDetailView(module: module, context: context)
                }
            }
        }
    }
}
