import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
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
                Text("Choose a .scripting or .zip package. Hanlin copies it into private staging and performs Import Preview without executing package code.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let preview = platform.preview {
                ScriptingImportPreviewSections(preview: preview)
                Section {
                    Button("Install") { Task { await platform.installPreview() } }
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
                ForEach(preview.requestedCapabilities, id: \.capabilityID) {
                    Label($0.capabilityID.rawValue, systemImage: "hand.raised")
                }
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
                List {
                    Section("Package") {
                        LabeledContent("Name", value: package.manifest?.name ?? package.record.packageID.rawValue)
                        LabeledContent("Version", value: package.record.version.rawValue)
                        LabeledContent("Generation", value: String(package.record.activeGeneration))
                        Toggle("Enabled", isOn: Binding(
                            get: { package.enabled },
                            set: { value in Task { await platform.setEnabled(value, for: packageID) } }
                        ))
                    }
                    Section("Entry Points") {
                        ForEach(package.entrypoints, id: \.id) {
                            VStack(alignment: .leading) {
                                LabeledContent($0.kind.rawValue, value: $0.sourcePath)
                                LabeledContent("Runtime", value: $0.runtimeProfile.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
            } else {
                ContentUnavailableView("Package Not Installed", systemImage: "shippingbox")
            }
        }
        .navigationTitle(package?.manifest?.name ?? "Script Package")
    }

    private var package: HanlinStoredPackageSnapshot? {
        platform.installedPackages.first { $0.record.installedPackageID == packageID }
    }
}
