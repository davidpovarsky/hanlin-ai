import Observation
import SwiftUI

@MainActor
@Observable
private final class NodePackagesModel {
    var packageName = ""
    var version = ""
    var installed: [NodePackageDetails] = []
    var preview: NodePackageDetails?
    var message: String?
    var isBusy = false
    private var operation: Task<Void, Never>?

    func reload() async {
        do { installed = try await AppRuntimeCore.shared.nodePackages.installed() }
        catch { message = error.localizedDescription }
    }

    func inspect() { run { self.preview = try await AppRuntimeCore.shared.nodePackages.preview(name: self.packageName, version: self.version.nilIfEmpty) } }
    func install() { run { self.preview = try await AppRuntimeCore.shared.nodePackages.install(name: self.packageName, version: self.version.nilIfEmpty); await self.reload() } }
    func update(_ item: NodePackageDetails) { packageName = item.name; version = ""; install() }
    func uninstall(_ item: NodePackageDetails) { run { try await AppRuntimeCore.shared.nodePackages.uninstall(name: item.name); await self.reload() } }
    func cancel() { operation?.cancel(); operation = nil; isBusy = false; message = RuntimeL10n.string("Cancelled") }

    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        operation?.cancel()
        isBusy = true
        message = nil
        operation = Task {
            defer { self.isBusy = false }
            do { try await body(); self.message = RuntimeL10n.string("Completed") }
            catch is CancellationError { self.message = RuntimeL10n.string("Cancelled") }
            catch { self.message = error.localizedDescription }
        }
    }
}

struct NodePackagesView: View {
    @State private var model = NodePackagesModel()

    var body: some View {
        List {
            Section(RuntimeL10n.string("npm package")) {
                TextField(RuntimeL10n.string("Package name"), text: $model.packageName)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField(RuntimeL10n.string("Version or tag (optional)"), text: $model.version)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    Button(RuntimeL10n.string("Preview")) { model.inspect() }
                    Button(RuntimeL10n.string("Install")) { model.install() }
                    if model.isBusy { Button(RuntimeL10n.string("Cancel"), role: .cancel) { model.cancel() } }
                }
                .disabled(model.packageName.isEmpty && !model.isBusy)
                if model.isBusy { ProgressView(RuntimeL10n.string("Resolving and verifying package")) }
                if let message = model.message { Text(message).font(.caption).textSelection(.enabled) }
            }

            if let item = model.preview { NodePackageDetailsView(item: item) }

            Section(RuntimeL10n.string("Installed global packages")) {
                if model.installed.isEmpty { ContentUnavailableView(RuntimeL10n.string("No global Node packages"), systemImage: "shippingbox") }
                ForEach(model.installed) { item in
                    NavigationLink { List { NodePackageDetailsView(item: item) }.navigationTitle(item.name) } label: {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(item.version).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(RuntimeL10n.string("Uninstall"), role: .destructive) { model.uninstall(item) }
                        Button(RuntimeL10n.string("Update")) { model.update(item) }.tint(.blue)
                    }
                }
            }

            Section { Text(RuntimeL10n.string("Packages are installed transactionally with npm lifecycle scripts disabled. Compatibility is reported per package; TypeScript packages with published JavaScript output are supported.")) .font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle(RuntimeL10n.string("Node Packages"))
        .task { await model.reload() }
        .refreshable { await model.reload() }
    }
}

private struct NodePackageDetailsView: View {
    let item: NodePackageDetails

    var body: some View {
        Section(RuntimeL10n.string("Package details")) {
            LabeledContent(RuntimeL10n.string("Package"), value: item.name)
            LabeledContent(RuntimeL10n.string("Version"), value: item.version)
            if let summary = item.summary { Text(summary) }
            LabeledContent(RuntimeL10n.string("Node requirement"), value: item.nodeRequirement ?? RuntimeL10n.string("Not specified"))
            LabeledContent(RuntimeL10n.string("Storage"), value: item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? RuntimeL10n.string("Calculated after installation"))
            if let integrity = item.integrity { LabeledContent(RuntimeL10n.string("Integrity"), value: integrity).lineLimit(2).textSelection(.enabled) }
            if !item.dependencies.isEmpty { LabeledContent(RuntimeL10n.string("Dependencies"), value: item.dependencies.joined(separator: ", ")) }
            if let lifecycle = item.lifecycle {
                LabeledContent(RuntimeL10n.string("Lifecycle scripts"), value: lifecycle.actions.isEmpty ? RuntimeL10n.string("None") : RuntimeL10n.format("%d planned actions", lifecycle.actions.count))
                if lifecycle.requiresApproval { Text(RuntimeL10n.string("Lifecycle actions require explicit approval and are not run during the package transaction.")) .font(.caption).foregroundStyle(.orange) }
            }
            ForEach(item.findings ?? []) { finding in
                Label(finding.message, systemImage: finding.severity == "unsupported" ? "xmark.octagon" : "exclamationmark.triangle")
                    .font(.caption)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
