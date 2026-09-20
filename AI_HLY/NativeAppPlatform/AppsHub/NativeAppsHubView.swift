import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinScriptStore
import SwiftData
import SwiftUI

struct NativeAppsHubView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var isEditingApps = false
    @State private var showsAddSheet = false
    @State private var scriptingPlatform = HanlinScriptingPlatform.shared
    @State private var miniAppHost = HanlinMiniAppHost.shared
    @State private var swiftDestination: HanlinMiniAppHost.SwiftDestination?
    @State private var informationItem: HanlinMiniAppCatalogItem?
    @State private var scriptingPackageID: HanlinInstalledPackageID?
    @State private var pendingPackageLaunchID: HanlinInstalledPackageID?
    @State private var launchError: String?

    private let columns = [
        GridItem(.adaptive(minimum: 205, maximum: 320), spacing: 20)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    engineSection(.swift, title: "Swift")
                    engineSection(.nativeScript, title: "NativeScript")
                    engineSection(.expo, title: "Expo")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(localized: "Apps"))
            .searchable(text: $searchText, prompt: "Search Apps")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsAddSheet = true } label: {
                        Label("Add App", systemImage: "plus")
                    }
                    .accessibilityIdentifier("hanlin-apps-add")
                    .accessibilityLabel("hanlin-apps-add")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(isEditingApps ? "Done" : "Edit") { isEditingApps.toggle() }
                }
            }
            .overlay {
                if !searchText.isEmpty && filteredItems.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .sheet(isPresented: $showsAddSheet, onDismiss: {
                refreshCatalog()
                if let packageID = pendingPackageLaunchID {
                    pendingPackageLaunchID = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        await scriptingPlatform.launch(packageID)
                    }
                }
            }) {
                NativeAppsAddSheet(
                    items: miniAppHost.items,
                    host: miniAppHost,
                    scriptingPlatform: scriptingPlatform,
                    onLaunchPackage: { packageID in
                        pendingPackageLaunchID = packageID
                    }
                )
            }
            .sheet(item: $informationItem) { item in
                MiniAppDescriptorDetailView(item: item)
            }
            .sheet(isPresented: Binding(
                get: { scriptingPackageID != nil },
                set: { if !$0 { scriptingPackageID = nil } }
            )) {
                if let packageID = scriptingPackageID {
                    NavigationStack {
                        ScriptingInstalledPackageDetailView(
                            packageID: packageID,
                            platform: scriptingPlatform
                        )
                    }
                }
            }
            .fullScreenCover(item: $swiftDestination) { destination in
                destination.view
            }
            .fullScreenCover(isPresented: Binding(
                get: {
                    scriptingPlatform.activeApplicationModel != nil
                        || scriptingPlatform.activeNativeScriptController != nil
                        || scriptingPlatform.activeExpoController != nil
                },
                set: { if !$0 { scriptingPlatform.dismissActiveApplication() } }
            )) {
                ScriptingApplicationContainerView(platform: scriptingPlatform)
            }
            .alert("Script App Error", isPresented: Binding(
                get: { launchError != nil || scriptingPlatform.activity.isFailure },
                set: {
                    if !$0 {
                        launchError = nil
                        scriptingPlatform.clearFailure()
                    }
                }
            )) {
                Button("OK") {
                    launchError = nil
                    scriptingPlatform.clearFailure()
                }
            } message: {
                Text(launchError ?? scriptingPlatform.activity.failureMessage ?? "The app could not be opened.")
            }
            .task {
                scriptingPlatform.configure(modelContext: modelContext)
                await scriptingPlatform.restore()
                await miniAppHost.refresh(installedPackages: scriptingPlatform.installedPackages)
            }
            .onChange(of: scriptingPlatform.installedPackages) { _, packages in
                Task { await miniAppHost.refresh(installedPackages: packages) }
            }
        }
    }

    private var filteredItems: [HanlinMiniAppCatalogItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return miniAppHost.visibleItems.filter { item in
            guard !query.isEmpty else { return true }
            let descriptor = item.descriptor
            return [
                descriptor.id.rawValue,
                descriptor.name.preferredValue(forLocale: Locale.current.identifier),
                descriptor.summary.preferredValue(forLocale: Locale.current.identifier),
                descriptor.description.preferredValue(forLocale: Locale.current.identifier),
                descriptor.category.rawValue
            ].joined(separator: " ").localizedStandardContains(query)
        }
    }

    @ViewBuilder
    private func engineSection(_ engine: HanlinMiniAppEngine, title: String) -> some View {
        let values = filteredItems.filter { $0.engine == engine }
        if !values.isEmpty {
            Section {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(values) { item in miniAppCard(item) }
                }
            } header: {
                Text(title)
                    .font(.title2.bold())
                    .accessibilityIdentifier("hanlin-miniapps-section-\(engine.rawValue)")
            }
        }
    }

    private func miniAppCard(_ item: HanlinMiniAppCatalogItem) -> some View {
        let appName = item.descriptor.name.preferredValue(forLocale: Locale.current.identifier)
        return ZStack(alignment: .topLeading) {
            Button { launch(item) } label: {
                MiniAppCardView(descriptor: item.descriptor, isEditing: isEditingApps)
            }
            .buttonStyle(.plain)
            .disabled(isEditingApps)
            .contextMenu { commonActions(for: item) }
            .accessibilityIdentifier("hanlin-package-card-\(appName)")
            .accessibilityLabel(appName)

            if isEditingApps {
                Button { miniAppHost.setHidden(true, appID: item.id) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .padding(10)
                .accessibilityLabel("Hide \(item.descriptor.name.preferredValue(forLocale: Locale.current.identifier))")
            } else {
                Menu { commonActions(for: item) } label: {
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

    @ViewBuilder
    private func commonActions(for item: HanlinMiniAppCatalogItem) -> some View {
        Button { launch(item) } label: { Label("Open", systemImage: "play.fill") }
        if let pkg = scriptingPlatform.installedPackages.first(where: { $0.appID == item.id || $0.record.packageID.rawValue == item.id.rawValue }) {
            Button { scriptingPackageID = pkg.record.installedPackageID } label: {
                Label("Package Information", systemImage: "info.circle")
            }
        }
        Button { informationItem = item } label: { Label("App Information", systemImage: "info.circle") }
        Divider()
        Button { miniAppHost.setHidden(true, appID: item.id) } label: {
            Label("Hide App", systemImage: "eye.slash")
        }
    }

    private func launch(_ item: HanlinMiniAppCatalogItem) {
        Task {
            do {
                switch item.engine {
                case .swift:
                    swiftDestination = try miniAppHost.swiftDestination(for: item)
                case .nativeScript:
                    try await miniAppHost.launchNativeScript(item, platform: scriptingPlatform)
                case .expo:
                    try await miniAppHost.launchExpo(item, platform: scriptingPlatform)
                }
            } catch {
                launchError = error.localizedDescription
            }
        }
    }

    private func refreshCatalog() {
        Task { await miniAppHost.refresh(installedPackages: scriptingPlatform.installedPackages) }
    }
}

private struct MiniAppDescriptorDetailView: View {
    let item: HanlinMiniAppCatalogItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Mini App") {
                    LabeledContent("Name", value: item.descriptor.name.preferredValue(forLocale: Locale.current.identifier))
                    LabeledContent("ID", value: item.id.rawValue)
                    LabeledContent("Engine", value: item.engine.displayName)
                    LabeledContent("Version", value: item.descriptor.version.rawValue)
                }
                Section("Canonical entrypoints") {
                    ForEach(Array(item.descriptor.entryPoints.enumerated()), id: \.offset) { _, entrypoint in
                        LabeledContent(entrypoint.kind.rawValue, value: entrypoint.runtimeProfile?.rawValue ?? "compiled-swift")
                    }
                }
                Section("Capabilities") {
                    ForEach(item.descriptor.capabilities, id: \.id) { capability in
                        Text(capability.id.rawValue)
                    }
                }
            }
            .navigationTitle("App Information")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private extension HanlinScriptingPlatform.Activity {
    var isFailure: Bool { if case .failed = self { true } else { false } }
    var failureMessage: String? { if case let .failed(message) = self { message } else { nil } }
}
