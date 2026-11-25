import HanlinLocalization
import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinPresentationKit
import HanlinScriptStore
import SwiftUI

/// Original Hanlin catalog with host-supplied preparation, launch and toolbar actions.
/// Prepare the canonical Hanlin application runtime before presenting this surface.
@MainActor
public struct NativeAppsCatalogView<AdditionalToolbar: ToolbarContent>: View {
    var prepareCatalog: (() async -> Void)?
    let refreshCatalog: () async -> Void
    let onLaunch: (HanlinMiniAppCatalogItem) -> Void
    let onLaunchPackage: (HanlinInstalledPackageID) -> Void
    var presentsSourceReader = false
    @ToolbarContentBuilder let additionalToolbar: () -> AdditionalToolbar

    public init(prepareCatalog: (() async -> Void)? = nil,
                refreshCatalog: @escaping () async -> Void,
                onLaunch: @escaping (HanlinMiniAppCatalogItem) -> Void,
                onLaunchPackage: @escaping (HanlinInstalledPackageID) -> Void,
                presentsSourceReader: Bool = false,
                @ToolbarContentBuilder additionalToolbar: @escaping () -> AdditionalToolbar) {
        self.prepareCatalog = prepareCatalog
        self.refreshCatalog = refreshCatalog
        self.onLaunch = onLaunch
        self.onLaunchPackage = onLaunchPackage
        self.presentsSourceReader = presentsSourceReader
        self.additionalToolbar = additionalToolbar
    }

    @State private var searchText = ""
    @State private var isEditingApps = false
    @State private var showsAddSheet = false
    @State private var showsTorahCapture = false
    @State private var scriptingPlatform = HanlinScriptingPlatform.shared
    @State private var miniAppHost = HanlinMiniAppHost.shared
    @State private var informationItem: HanlinMiniAppCatalogItem?
    @State private var scriptingPackageID: HanlinInstalledPackageID?
    @State private var pendingPackageLaunchID: HanlinInstalledPackageID?

    private let columns = [
        GridItem(.adaptive(minimum: 205, maximum: 320), spacing: 20)
    ]

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    engineSection(.swift, title: "Swift")
                    engineSection(.scriptingJSC, title: "ScriptUI")
                    engineSection(.nativeScript, title: "NativeScript")
                    engineSection(.expo, title: "Expo")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .accessibilityIdentifier("hanlin-apps-catalog")
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(localized: "Apps", bundle: HanlinLocalization.bundle))
            .searchable(text: $searchText, prompt: Text("hanlin.apps.search", bundle: HanlinLocalization.bundle))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsAddSheet = true } label: {
                        Label(hanlin: "Add App", systemImage: "plus")
                    }
                    .accessibilityIdentifier("hanlin-apps-add")
                    .accessibilityLabel(Text("hanlin-apps-add", bundle: HanlinLocalization.bundle))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(isEditingApps ? "Done" : "Edit") { isEditingApps.toggle() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsTorahCapture = true } label: {
                        Label(hanlin: "לימוד מצילום", systemImage: "camera.viewfinder")
                    }
                    .accessibilityIdentifier("hanlin-apps-torah-capture")
                }
                additionalToolbar()
            }
            .sheet(isPresented: $showsTorahCapture) {
                TorahPhotoStudyCaptureView(presentsSourceReader: presentsSourceReader)
            }
            .overlay {
                if !searchText.isEmpty && filteredItems.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .sheet(isPresented: $showsAddSheet, onDismiss: {
                let packageID = pendingPackageLaunchID
                pendingPackageLaunchID = nil
                Task {
                    await refreshCatalog()
                    if let packageID {
                        if let package = scriptingPlatform.installedPackages.first(where: {
                            $0.record.installedPackageID == packageID
                        }), !package.hasLaunchableApp {
                            scriptingPackageID = packageID
                        } else {
                            onLaunchPackage(packageID)
                        }
                    }
                }
            }) {
                NativeAppsAddSheet(
                    items: miniAppHost.items,
                    host: miniAppHost,
                    scriptingPlatform: scriptingPlatform,
                    onLaunchPackage: { pendingPackageLaunchID = $0 }
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
            .task { await prepareCatalog?() }
            .onChange(of: scriptingPlatform.installedPackages) { _, _ in
                Task { await refreshCatalog() }
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
                    .font(HanlinTypography.title2.bold())
                    .accessibilityIdentifier("hanlin-miniapps-section-\(engine.rawValue)")
            }
        }
    }

    private func miniAppCard(_ item: HanlinMiniAppCatalogItem) -> some View {
        let appName = item.descriptor.name.preferredValue(forLocale: Locale.current.identifier)
        return ZStack(alignment: .topLeading) {
            Button { onLaunch(item) } label: {
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
                        .font(HanlinTypography.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .padding(10)
                .accessibilityLabel(Text("Hide \(item.descriptor.name.preferredValue(forLocale: Locale.current.identifier))", bundle: HanlinLocalization.bundle))
            } else {
                Menu { commonActions(for: item) } label: {
                    Image(systemName: "ellipsis")
                        .font(HanlinTypography.headline)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .padding(12)
                .accessibilityLabel(Text("App Actions", bundle: HanlinLocalization.bundle))
                .accessibilityIdentifier("hanlin-app-actions-\(item.id.rawValue)")
            }
        }
    }

    @ViewBuilder
    private func commonActions(for item: HanlinMiniAppCatalogItem) -> some View {
        Button { onLaunch(item) } label: { Label(hanlin: "Open", systemImage: "play.fill") }
        if let pkg = scriptingPlatform.installedPackages.first(where: { $0.appID == item.id || $0.record.packageID.rawValue == item.id.rawValue }) {
            Button { scriptingPackageID = pkg.record.installedPackageID } label: {
                Label(hanlin: "Package Information", systemImage: "info.circle")
            }
            .accessibilityIdentifier("hanlin-package-information-menu-item")
        }
        Button { informationItem = item } label: { Label(hanlin: "App Information", systemImage: "info.circle") }
        Divider()
        Button { miniAppHost.setHidden(true, appID: item.id) } label: {
            Label(hanlin: "Hide App", systemImage: "eye.slash")
        }
    }
}

private struct MiniAppDescriptorDetailView: View {
    let item: HanlinMiniAppCatalogItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(hanlin: "Mini App") {
                    LabeledContent(hanlin: "Name", value: item.descriptor.name.preferredValue(forLocale: Locale.current.identifier))
                    LabeledContent(hanlin: "ID", value: item.id.rawValue)
                    LabeledContent(hanlin: "Engine", value: item.engine.displayName)
                    LabeledContent(hanlin: "Version", value: item.descriptor.version.rawValue)
                }
                Section(hanlin: "Canonical entrypoints") {
                    ForEach(Array(item.descriptor.entryPoints.enumerated()), id: \.offset) { _, entrypoint in
                        LabeledContent(entrypoint.kind.rawValue, value: entrypoint.runtimeProfile?.rawValue ?? "compiled-swift")
                    }
                }
                Section(hanlin: "Capabilities") {
                    ForEach(item.descriptor.capabilities, id: \.id) { capability in
                        Text(capability.id.rawValue)
                    }
                }
            }
            .navigationTitle(Text("App Information", bundle: HanlinLocalization.bundle))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(hanlin: "Done") { dismiss() } } }
        }
    }
}
