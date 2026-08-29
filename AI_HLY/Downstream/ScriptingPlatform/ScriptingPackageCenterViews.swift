import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
import HanlinScriptUI
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let hanlinScriptingPackage = UTType(importedAs: "com.hanlin.scripting-package")
}

struct ScriptingPackageImportView: View {
    let platform: HanlinScriptingPlatform
    @Environment(\.dismiss) private var dismiss
    @State private var showsImporter = false

    var body: some View {
        List {
            Section {
                Button {
                    showsImporter = true
                } label: {
                    Label("Import Script Package", systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("hanlin-file-importer")
                Text("Choose a .scripting or .zip package. Hanlin copies it into private staging and performs Import Preview without executing package code.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let preview = platform.preview {
                ScriptingImportPreviewSections(preview: preview, platform: platform)
                Section {
                    Button("Install") { Task { await platform.installPreview() } }
                        .accessibilityIdentifier("hanlin-package-install")
                        .disabled(!preview.canInstall || platform.activity == .installing)
                    Button("Discard", role: .destructive) { platform.discardPreview() }
                }
            }

            if case let .failed(message) = platform.activity {
                Section("Import Error") {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Script Package")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if platform.activity == .importing || platform.activity == .installing {
                ProgressView(platform.activity == .importing ? "Inspecting…" : "Installing…")
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.hanlinScriptingPackage, .zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { Task { await platform.importPackage(from: url) } }
            case let .failure(error):
                Task { @MainActor in
                    platform.reportImportFailure(error)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}

private struct ScriptingImportPreviewSections: View {
    let preview: HanlinImportPreview
    let platform: HanlinScriptingPlatform

    var body: some View {
        Section("Package") {
            LabeledContent("Name", value: preview.manifest?.name ?? preview.source.originalFileName)
            if let version = preview.manifest?.version { LabeledContent("Version", value: version) }
            LabeledContent("Trust", value: preview.source.trust.rawValue)
            LabeledContent("SHA-256", value: String(preview.source.contentSHA256.prefix(16)) + "…")
        }
        Section("Entry Points") {
            ForEach(preview.entrypoints, id: \.id) { entrypoint in
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(entrypoint.kind.rawValue, value: entrypoint.sourcePath)
                    LabeledContent("Runtime", value: entrypoint.runtimeProfile.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(runtimeReason(entrypoint.runtimeProfile))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if !preview.requestedCapabilities.isEmpty {
            Section("Permissions") {
                ForEach(preview.requestedCapabilities, id: \.capabilityID) { request in
                    Toggle(
                        request.capabilityID.rawValue,
                        isOn: Binding(
                            get: { platform.approvedCapabilities.contains(request.capabilityID) },
                            set: { platform.setCapabilityApproved($0, capability: request.capabilityID) }
                        )
                    )
                }
                Text("Required capabilities must be approved explicitly. They remain package-scoped and can be revoked from package details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if !preview.findings.isEmpty {
            Section("Compatibility") {
                ForEach(Array(preview.findings.enumerated()), id: \.offset) { _, finding in
                    Label(
                        finding.message,
                        systemImage: finding.severity == .error ? "xmark.octagon" : "info.circle"
                    )
                    .foregroundStyle(finding.severity == .error ? Color.red : Color.secondary)
                }
            }
        }
    }

    private func runtimeReason(_ profile: HanlinRuntimeProfile) -> String {
        switch profile {
        case .scriptingJSC: return "Original Scripting JavaScript and TypeScript use the compatibility runtime."
        case .hanlinQuickJS: return "Hanlin manifest selected constrained JavaScript."
        case .hanlinNode: return "Hanlin manifest selected a trusted Node worker."
        case .hanlinPython: return "Python entrypoint requires trusted local execution."
        case .hanlinNativeScript: return "NativeScript 9.1 provides trusted Apple-native interop and Core UI."
        }
    }
}

struct ScriptingInstalledPackageDetailView: View {
    let packageID: HanlinInstalledPackageID
    let platform: HanlinScriptingPlatform
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let package {
                installedPackageList(package)
            } else {
                ContentUnavailableView("Package Not Installed", systemImage: "shippingbox")
            }
        }
        .navigationTitle(package?.manifest?.name ?? "Script Package")
    }

    private var package: HanlinStoredPackageSnapshot? {
        platform.installedPackages.first { $0.record.installedPackageID == packageID }
    }

    private func installedPackageList(_ package: HanlinStoredPackageSnapshot) -> some View {
        List {
            Section("Package") {
                LabeledContent("Name", value: package.manifest?.name ?? package.record.packageID.rawValue)
                LabeledContent("Version", value: package.record.version.rawValue)
                LabeledContent("Generation", value: String(package.record.activeGeneration))
                Toggle("Enabled", isOn: enabledBinding(for: package))
            }
            Section("Entry Points") {
                ForEach(package.entrypoints, id: \.id) { entrypoint in
                    VStack(alignment: .leading) {
                        LabeledContent(entrypoint.kind.rawValue, value: entrypoint.sourcePath)
                        LabeledContent("Runtime", value: entrypoint.runtimeProfile.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            let capabilities = Set(
                package.entrypoints
                    .flatMap(\.requiredCapabilities)
                    .map(\.capabilityID)
            )
            if !capabilities.isEmpty {
                Section("Permissions") {
                    ForEach(capabilities.sorted { $0.rawValue < $1.rawValue }, id: \.self) { capability in
                        Toggle(
                            capability.rawValue,
                            isOn: Binding(
                                get: { package.grantedCapabilities.contains(capability) },
                                set: { granted in
                                    Task {
                                        await platform.setCapabilityGranted(
                                            granted,
                                            capability: capability,
                                            for: packageID
                                        )
                                    }
                                }
                            )
                        )
                    }
                    Text("Revoking a capability takes effect for new package operations and tool invocations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if package.availableGenerations.count > 1 {
                Section("Versions") {
                    ForEach(package.availableGenerations.reversed(), id: \.self) { generation in
                        Button {
                            Task { await platform.rollback(packageID, to: generation) }
                        } label: {
                            HStack {
                                Text("Generation \(generation)")
                                Spacer()
                                if generation == package.record.activeGeneration {
                                    Label("Active", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(generation == package.record.activeGeneration)
                    }
                }
            }
            Section {
                Button("Uninstall", role: .destructive) {
                    Task {
                        await platform.uninstall(packageID)
                        dismiss()
                    }
                }
            }
        }
    }

    private func enabledBinding(for package: HanlinStoredPackageSnapshot) -> Binding<Bool> {
        Binding(
            get: { package.enabled },
            set: { value in
                Task { await platform.setEnabled(value, for: packageID) }
            }
        )
    }
}

struct ScriptingApplicationContainerView: View {
    let platform: HanlinScriptingPlatform
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let model = platform.activeApplicationModel {
                    HanlinScriptUIView(model: model)
                } else if let controller = platform.activeNativeScriptController {
                    HanlinHostedViewController(controller: controller)
                } else {
                    ContentUnavailableView("Script App Unavailable", systemImage: "exclamationmark.triangle")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        platform.dismissActiveApplication()
                        dismiss()
                    }
                    .accessibilityIdentifier("hanlin-script-app-close")
                }
            }
        }
        .sheet(item: Binding(
            get: { platform.systemUIPresentation },
            set: { value in if value == nil { platform.cancelSystemUI() } }
        )) { presentation in
            HanlinScriptingSystemUIPresentationView(presentation: presentation) { result in
                platform.completeSystemUI(id: presentation.id, result: result)
            }
            .interactiveDismissDisabled()
        }
        .onDisappear { platform.dismissActiveApplication() }
    }
}

private struct HanlinHostedViewController: UIViewControllerRepresentable {
    let controller: UIViewController

    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
