import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinScriptStore
import SwiftUI

struct NativeAppsAddSheet: View {
    let items: [HanlinMiniAppCatalogItem]
    let host: HanlinMiniAppHost
    let scriptingPlatform: HanlinScriptingPlatform
    var onLaunchPackage: ((HanlinInstalledPackageID) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPackageID: HanlinInstalledPackageID?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Swift apps are compiled into Hanlin. NativeScript packages are dynamically importable.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        ScriptingPackageImportView(platform: scriptingPlatform)
                    } label: {
                        Label("Import NativeScript Package", systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("hanlin-import-script-package")
                }

                let hidden = items.filter { host.isHidden($0.id) }
                if !hidden.isEmpty {
                    Section("Hidden Apps") {
                        ForEach(hidden) { item in
                            Button {
                                host.setHidden(false, appID: item.id)
                            } label: {
                                Label(
                                    item.descriptor.name.preferredValue(forLocale: Locale.current.identifier),
                                    systemImage: "eye"
                                )
                            }
                        }
                    }
                }

                let canonicalAppIDs = Set(items.map(\.id))
                let legacyPackages = scriptingPlatform.installedPackages.filter { !canonicalAppIDs.contains($0.appID) }
                if !legacyPackages.isEmpty {
                    Section("Scripting Packages") {
                        ForEach(legacyPackages, id: \.record.installedPackageID) { package in
                            let name = package.manifest?.name ?? package.record.packageID.rawValue
                            Button {
                                guard package.enabled else { return }
                                let required = Set(package.entrypoints.first(where: { $0.kind == .app })?.requiredCapabilities.filter(\.required).map(\.capabilityID) ?? [])
                                guard required.isSubset(of: Set(package.grantedCapabilities)) else {
                                    return
                                }
                                if let onLaunchPackage {
                                    onLaunchPackage(package.record.installedPackageID)
                                    dismiss()
                                } else {
                                    dismiss()
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(500))
                                        await scriptingPlatform.launch(package.record.installedPackageID)
                                    }
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(package.record.packageID.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if !package.enabled {
                                        Text("Disabled")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("hanlin-package-card-\(name)")
                            .accessibilityLabel(name)
                            .contextMenu {
                                Button {
                                    guard package.enabled else { return }
                                    if let onLaunchPackage {
                                        onLaunchPackage(package.record.installedPackageID)
                                        dismiss()
                                    } else {
                                        dismiss()
                                        Task {
                                            try? await Task.sleep(for: .milliseconds(500))
                                            await scriptingPlatform.launch(package.record.installedPackageID)
                                        }
                                    }
                                } label: {
                                    Label("Open", systemImage: "play.fill")
                                }
                                .disabled(!package.enabled)

                                Button {
                                    selectedPackageID = package.record.installedPackageID
                                } label: {
                                    Label("Package Information", systemImage: "info.circle")
                                }
                            }
                        }
                    }
                }

                Section("Bundled Swift Apps") {
                    ForEach(items.filter({ $0.engine == .swift })) { item in
                        Label(
                            item.descriptor.name.preferredValue(forLocale: Locale.current.identifier),
                            systemImage: "swift"
                        )
                    }
                }
            }
            .navigationTitle("Add Apps")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: Binding(
                get: { selectedPackageID.map { IdentifiablePackageID(id: $0) } },
                set: { selectedPackageID = $0?.id }
            )) { wrapper in
                NavigationStack {
                    ScriptingInstalledPackageDetailView(
                        packageID: wrapper.id,
                        platform: scriptingPlatform
                    )
                }
            }
        }
    }
}

private struct IdentifiablePackageID: Identifiable {
    let id: HanlinInstalledPackageID
}
