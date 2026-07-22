import SwiftUI

struct MCPServerInstallView: View {
    @State private var provider = MCPRuntimeProvider.shared
    @State private var packageInput = ""
    @State private var spec: MCPPackageSpec?
    @State private var preview: MCPPackageManifestPreview?
    @State private var selectedEntryPoint = ""
    @State private var errorMessage: String?
    @State private var importing = false
    @State private var working = false

    var body: some View {
        Form {
            Section(MCPL10n.string("Package source")) {
                TextField(MCPL10n.string("Package name or .tgz URL"), text: $packageInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button(MCPL10n.string("Preview")) { Task { await loadPreview() } }
                        .disabled(packageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
                    Button(MCPL10n.string("Import .tgz file")) { importing = true }
                        .disabled(working)
                }
            }

            Section {
                Label(
                    MCPL10n.string("This package contains executable JavaScript and will run inside Hanlin's application sandbox. Install only packages you trust."),
                    systemImage: "exclamationmark.shield"
                )
                .font(.callout)
            }

            if let preview {
                Section(MCPL10n.string("Preview")) {
                    LabeledContent(MCPL10n.string("Package"), value: preview.packageName)
                    LabeledContent(MCPL10n.string("Version"), value: preview.version)
                    if let summary = preview.summary { Text(summary) }
                    LabeledContent(MCPL10n.string("Node requirement"), value: preview.nodeRequirement ?? MCPL10n.string("Not specified"))
                    LabeledContent(MCPL10n.string("Dependencies"), value: "\(preview.dependencyCount)")
                    if preview.entryPoints.count > 1 {
                        Picker(MCPL10n.string("Entry point"), selection: $selectedEntryPoint) {
                            ForEach(preview.entryPoints, id: \.self) { entryPoint in
                                Text(entryPoint).tag(entryPoint)
                            }
                        }
                    } else if let entryPoint = preview.entryPoints.first {
                        LabeledContent(MCPL10n.string("Entry point"), value: entryPoint)
                    }
                    ForEach(preview.compatibility.findings) { finding in
                        Label(finding.localizedMessage, systemImage: findingIcon(finding.severity))
                            .foregroundStyle(findingColor(finding.severity))
                    }
                    Button(MCPL10n.string("Install")) { Task { await install() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(preview.compatibility.verdict == .unsupported || working || spec == nil)
                }
            }

            Section {
                MCPInstallProgressView(state: provider.installState)
                if case .installing = provider.installState {
                    Button(MCPL10n.string("Cancel"), role: .cancel) {
                        Task { await provider.cancelInstall() }
                    }
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle(MCPL10n.string("Add MCP Server"))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.mcpTGZ, .gzip]) { result in
            switch result {
            case .success(let url): Task { await loadLocalPreview(url) }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private func loadPreview() async {
        working = true
        defer { working = false }
        do {
            let parsed = try MCPPackageSpec(packageInput)
            spec = parsed
            preview = try await provider.preview(spec: parsed)
            selectedEntryPoint = preview?.entryPoints.first ?? ""
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription; preview = nil }
    }

    private func loadLocalPreview(_ url: URL) async {
        working = true
        defer { working = false }
        do {
            let parsed = try MCPPackageSpec(localArchive: url)
            spec = parsed
            preview = try await provider.preview(spec: parsed)
            selectedEntryPoint = preview?.entryPoints.first ?? ""
            packageInput = url.lastPathComponent
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription; preview = nil }
    }

    private func install() async {
        guard let spec else { return }
        working = true
        await provider.install(
            spec: spec,
            entryPointOverride: preview?.entryPoints.count == 1 ? nil : selectedEntryPoint
        )
        if case .failed = provider.installState {
            // The operation-scoped progress card owns terminal install failures.
            errorMessage = nil
        } else {
            errorMessage = provider.lastError
        }
        working = false
    }

    private func findingIcon(_ severity: MCPCompatibilityFinding.Severity) -> String {
        switch severity {
        case .info: "checkmark.shield"
        case .warning: "exclamationmark.triangle"
        case .unsupported: "xmark.octagon"
        }
    }

    private func findingColor(_ severity: MCPCompatibilityFinding.Severity) -> Color {
        switch severity {
        case .info: .blue
        case .warning: .orange
        case .unsupported: .red
        }
    }
}
