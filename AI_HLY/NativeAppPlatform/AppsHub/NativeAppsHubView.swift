import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct NativeAppsHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    @State private var searchText = ""
    @State private var isEditingApps = false
    @State private var showsAddSheet = false
    @State private var fullScreenRequest: NativeAppLaunchRequest?
    @State private var largeSheetRequest: NativeAppLaunchRequest?
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
                            Button {
                                openFullScreen(module)
                            } label: {
                                NativeAppCardView(
                                    manifest: module.manifest,
                                    isEditing: isEditingApps
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditingApps)
                            .contextMenu {
                                nativeAppActions(for: module)
                            }

                            Menu {
                                nativeAppActions(for: module)
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
            .fullScreenCover(item: $fullScreenRequest) { request in
                NativeAppSessionContainerView(request: request)
            }
            .sheet(item: $largeSheetRequest) { request in
                NativeAppSessionContainerView(request: request)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
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

    private func launchRequest(
        for module: NativeAppModule,
        style: NativeAppPresentationStyle
    ) -> NativeAppLaunchRequest {
        NativeAppLaunchRequest(
            appID: module.manifest.id,
            presentationStyle: style
        )
    }

    private func openFullScreen(_ module: NativeAppModule) {
        fullScreenRequest = launchRequest(for: module, style: .fullScreen)
    }

    private func openLargeSheet(_ module: NativeAppModule) {
        largeSheetRequest = launchRequest(for: module, style: .largeSheet)
    }

    private func openNewWindow(_ module: NativeAppModule) {
        let request = launchRequest(for: module, style: .newWindow)

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            fullScreenRequest = NativeAppLaunchRequest(
                id: request.id,
                appID: request.appID,
                presentationStyle: .fullScreen,
                initialRoute: request.initialRoute
            )
            return
        }
        #endif

        openWindow(value: request)
    }

    @ViewBuilder
    private func nativeAppActions(for module: NativeAppModule) -> some View {
        Button {
            openFullScreen(module)
        } label: {
            Label("Open Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
        }

        Button {
            openLargeSheet(module)
        } label: {
            Label("Open in Large Sheet", systemImage: "rectangle.inset.filled")
        }

        Button {
            openNewWindow(module)
        } label: {
            Label("Open in New Window", systemImage: "macwindow.badge.plus")
        }

        Divider()

        Button {
            infoModuleID = module.manifest.id
        } label: {
            Label("App Information", systemImage: "info.circle")
        }
    }
}
