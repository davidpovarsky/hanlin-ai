import Observation
import SwiftUI

@MainActor
@Observable
private final class PythonPackagesModel {
    var packageName = ""
    var version = ""
    var installed: [PythonPackageRecord] = []
    var preview: PythonPackagePreview?
    var probeOutput: String?
    var installProgress: PythonPackageInstallProgress?
    var message: String?
    var isBusy = false
    private var operation: Task<Void, Never>?

    func reload() async {
        do { installed = try await AppRuntimeCore.shared.pythonPackages.installed() }
        catch { message = error.localizedDescription }
    }

    func inspect() { run { self.preview = try await AppRuntimeCore.shared.pythonPackages.preview(name: self.packageName, version: self.version.isEmpty ? nil : self.version) } }
    func install() {
        run {
            _ = try await AppRuntimeCore.shared.pythonPackages.install(
                name: self.packageName,
                version: self.version.isEmpty ? nil : self.version
            ) { update in
                self.installProgress = update
            }
            await self.reload()
        }
    }
    func update(_ item: PythonPackageRecord) { packageName = item.name; version = ""; install() }
    func uninstall(_ item: PythonPackageRecord) { run { try await AppRuntimeCore.shared.pythonPackages.uninstall(item); await self.reload() } }
    func probe(_ item: PythonPackageRecord) { run { let result = try await AppRuntimeCore.shared.pythonPackages.probe(item); self.probeOutput = result.stdout + result.stderr } }
    func cancel() { operation?.cancel(); operation = nil; isBusy = false; message = RuntimeL10n.string("Cancelled") }

    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        operation?.cancel()
        isBusy = true
        installProgress = nil
        message = nil
        operation = Task {
            defer { self.isBusy = false }
            do { try await body(); self.message = RuntimeL10n.string("Completed") }
            catch is CancellationError { self.message = RuntimeL10n.string("Cancelled") }
            catch { self.message = error.localizedDescription }
        }
    }
}

struct PythonPackagesView: View {
    @State private var model = PythonPackagesModel()

    var body: some View {
        List {
            Section(RuntimeL10n.string("PyPI package")) {
                TextField(RuntimeL10n.string("Package name"), text: $model.packageName).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField(RuntimeL10n.string("Version (optional)"), text: $model.version).textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    Button(RuntimeL10n.string("Preview")) { model.inspect() }
                    Button(RuntimeL10n.string("Install")) { model.install() }
                    if model.isBusy { Button(RuntimeL10n.string("Cancel"), role: .cancel) { model.cancel() } }
                }
                if model.isBusy {
                    if let progress = model.installProgress {
                        ProgressView(
                            value: Double(progress.completedUnits),
                            total: Double(max(1, progress.totalUnits))
                        ) {
                            Text(RuntimeL10n.string("Python package installation progress"))
                        } currentValueLabel: {
                            Text("\(progress.phase.rawValue.capitalized): \(progress.packageName)")
                        }
                    } else {
                        ProgressView(RuntimeL10n.string("Downloading and verifying wheel"))
                    }
                }
                if let message = model.message { Text(message).font(.caption).textSelection(.enabled) }
            }

            if let preview = model.preview {
                Section(RuntimeL10n.string("Package details")) {
                    LabeledContent(RuntimeL10n.string("Package"), value: preview.name)
                    LabeledContent(RuntimeL10n.string("Version"), value: preview.version)
                    if let summary = preview.summary { Text(summary) }
                    LabeledContent(RuntimeL10n.string("Classification"), value: preview.isPurePython ? RuntimeL10n.string("Universal pure-Python wheel") : RuntimeL10n.string("Native or source distribution"))
                    Text(preview.compatibilityExplanation).font(.caption)
                }
            }

            Section(RuntimeL10n.string("Installed Python packages")) {
                if model.installed.isEmpty { ContentUnavailableView(RuntimeL10n.string("No local Python packages"), systemImage: "shippingbox") }
                ForEach(model.installed) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(item.name); Spacer(); Text(item.version).foregroundStyle(.secondary) }
                        Text(ByteCountFormatter.string(fromByteCount: item.storageBytes, countStyle: .file)).font(.caption)
                        if !item.dependencyRequirements.isEmpty { Text(item.dependencyRequirements.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary) }
                        if let dependencies = item.resolvedDependencies, !dependencies.isEmpty {
                            Text(dependencies.map { "\($0.name) \($0.version)" }.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button(RuntimeL10n.string("Import Probe")) { model.probe(item) }.buttonStyle(.borderless)
                    }
                    .swipeActions {
                        Button(RuntimeL10n.string("Uninstall"), role: .destructive) { model.uninstall(item) }
                        Button(RuntimeL10n.string("Update")) { model.update(item) }.tint(.blue)
                    }
                }
                if let probeOutput = model.probeOutput { Text(probeOutput).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            }

            Section { Text(RuntimeL10n.string("Universal pure-Python wheels can be installed. Source builds and arbitrary native extensions cannot be installed dynamically on iOS; a future release may add prebundled native modules.")) .font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle(RuntimeL10n.string("Python Packages"))
        .task { await model.reload() }
        .refreshable { await model.reload() }
    }
}
