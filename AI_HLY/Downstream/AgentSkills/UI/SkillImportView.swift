import SwiftUI
import UniformTypeIdentifiers
import HanlinPlatformContracts
import ZIPFoundation

enum ImportStep {
    case input
    case preview(StagedSkillPackage)
}

@MainActor
struct SkillImportView: View {
    let initialTab: Int
    let onImported: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var step: ImportStep = .input
    @State private var selectedTab: Int = 0
    @State private var urlString: String = ""
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var showFileImporter: Bool = false

    init(initialTab: Int = 0, onImported: @escaping () -> Void = {}) {
        self.initialTab = initialTab
        self.onImported = onImported
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch step {
                case .input:
                    inputView
                case .preview(let staged):
                    previewView(staged)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SkillL10n.string("Cancel")) {
                        switch step {
                        case .input:
                            dismiss()
                        case .preview(let staged):
                            try? FileManager.default.removeItem(at: staged.stagingDirectoryURL)
                            step = .input
                        }
                    }
                    .accessibilityIdentifier("hanlin-skill-import-cancel-button")
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                handleFileImportResult(result)
            }
        }
    }

    private var navTitle: String {
        switch step {
        case .input:
            return SkillL10n.string("Import Skill")
        case .preview:
            return SkillL10n.string("Skill Preview")
        }
    }

    private var inputView: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text(SkillL10n.string("Import ZIP Archive")).tag(0)
                    .accessibilityIdentifier("hanlin-skill-import-tab-zip")
                Text(SkillL10n.string("Install from HTTPS URL")).tag(1)
                    .accessibilityIdentifier("hanlin-skill-import-tab-url")
            }
            .pickerStyle(.segmented)
            .padding()

            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }

            if let succ = successMessage {
                Text(succ)
                    .foregroundColor(.green)
                    .font(.footnote)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }

            if selectedTab == 0 {
                zipImportSection
            } else {
                urlImportSection
            }

            Spacer()
        }
    }

    private func previewView(_ staged: StagedSkillPackage) -> some View {
        List {
            Section(header: Text("Skill Metadata")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(staged.parsedMarkdown.name)
                            .font(.headline)
                        Spacer()
                        Text(staged.skillID.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }

                    if !staged.parsedMarkdown.description.isEmpty {
                        Text(staged.parsedMarkdown.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if !staged.metadata.preferredToolIDs.isEmpty {
                Section(header: Text("Preferred Tools")) {
                    ForEach(staged.metadata.preferredToolIDs, id: \.self) { tool in
                        HStack {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(tool)
                                .font(.system(.subheadline, design: .monospaced))
                        }
                    }
                }
            }

            if !staged.metadata.triggerHints.isEmpty {
                Section(header: Text("Trigger Hints")) {
                    ForEach(staged.metadata.triggerHints, id: \.self) { hint in
                        Text(hint)
                            .font(.footnote)
                    }
                }
            }

            Section(header: Text("Included Resources (\(staged.resources.count))")) {
                if staged.resources.isEmpty {
                    Text("No additional resources.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(staged.resources) { res in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(res.relativePath)
                                    .font(.system(.footnote, design: .monospaced))
                                Text(ByteCountFormatter.string(fromByteCount: res.byteCount, countStyle: .file))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if res.isBinary {
                                Text("Binary")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section(header: Text("Package Origin & Integrity")) {
                if let origin = staged.originURL {
                    LabeledContent("Origin URL", value: origin)
                        .accessibilityIdentifier("hanlin-skill-import-origin-url")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("SHA-256")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(staged.sha256)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .accessibilityIdentifier("hanlin-skill-import-sha256")
            }

            Section {
                VStack(spacing: 12) {
                    if let err = errorMessage {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }

                    if isProcessing {
                        ProgressView(SkillL10n.string("Installing..."))
                    } else {
                        Button {
                            installStaged(staged)
                        } label: {
                            Text(SkillL10n.string("Install Skill"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("hanlin-skill-import-confirm-install")

                        Button(role: .cancel) {
                            try? FileManager.default.removeItem(at: staged.stagingDirectoryURL)
                            step = .input
                        } label: {
                            Text(SkillL10n.string("Cancel"))
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("hanlin-skill-import-preview-cancel")
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var zipImportSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .padding(.top, 30)

            Text("Select a .zip archive containing a valid SKILL.md bundle and optional resources.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                showFileImporter = true
            } label: {
                Label(SkillL10n.string("Select ZIP File"), systemImage: "folder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing)
            .accessibilityIdentifier("hanlin-skill-import-select-file-button")
            .padding(.horizontal, 40)

            #if targetEnvironment(simulator) || DEBUG
            Button {
                loadTestFixtureZip()
            } label: {
                Label("Load Test Fixture ZIP", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)
            .accessibilityIdentifier("hanlin-skill-import-fixture-button")
            .padding(.horizontal, 40)
            #endif

            if isProcessing {
                ProgressView(SkillL10n.string("Inspecting..."))
            }
        }
    }

    private var urlImportSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .padding(.top, 30)

            VStack(alignment: .leading, spacing: 6) {
                Text(SkillL10n.string("Skill Archive URL"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("https://example.com/skill-bundle.zip", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .accessibilityIdentifier("hanlin-skill-import-url-input")
            }
            .padding(.horizontal)

            Button {
                downloadAndInspect()
            } label: {
                Label(SkillL10n.string("Download & Inspect"), systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("hanlin-skill-import-url-button")
            .padding(.horizontal, 40)

            if isProcessing {
                ProgressView(SkillL10n.string("Downloading & Inspecting..."))
            }
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            isProcessing = true
            errorMessage = nil
            successMessage = nil

            let isSecured = fileURL.startAccessingSecurityScopedResource()
            defer {
                if isSecured { fileURL.stopAccessingSecurityScopedResource() }
            }

            Task {
                do {
                    let staged = try SkillImporter.shared.stageAndInspect(fileURL: fileURL)
                    isProcessing = false
                    step = .preview(staged)
                } catch {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func downloadAndInspect() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else {
            errorMessage = "Please enter a valid HTTPS URL."
            return
        }

        isProcessing = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                let staged = try await SkillImporter.shared.downloadAndStage(from: url)
                isProcessing = false
                step = .preview(staged)
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }

    private func loadTestFixtureZip() {
        isProcessing = true
        errorMessage = nil
        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let tempZip = tempDir.appendingPathComponent("ui-import-skill-\(UUID().uuidString).zip")
                guard let archive = try? Archive(url: tempZip, accessMode: .create) else {
                    errorMessage = "Failed to create test fixture zip."
                    isProcessing = false
                    return
                }
                let skillMD = """
                ---
                name: ui-import-skill
                description: Deterministic UI imported skill for acceptance testing.
                ---

                # UI Import Skill Instructions
                Execute tools as needed.
                """
                let skillMDData = Data(skillMD.utf8)
                try archive.addEntry(with: "SKILL.md", type: .file, uncompressedSize: Int64(skillMDData.count), provider: { position, size in
                    skillMDData.subdata(in: position..<(position + size))
                })
                let refData = Data("Reference documentation content.\n".utf8)
                try archive.addEntry(with: "references/guide.md", type: .file, uncompressedSize: Int64(refData.count), provider: { position, size in
                    refData.subdata(in: position..<(position + size))
                })
                let scriptData = Data("print('test script')\n".utf8)
                try archive.addEntry(with: "scripts/run.py", type: .file, uncompressedSize: Int64(scriptData.count), provider: { position, size in
                    scriptData.subdata(in: position..<(position + size))
                })

                let staged = try SkillImporter.shared.stageAndInspect(fileURL: tempZip)
                isProcessing = false
                step = .preview(staged)
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }

    private func installStaged(_ staged: StagedSkillPackage) {
        isProcessing = true
        errorMessage = nil
        Task {
            do {
                let descriptor = try SkillImporter.shared.install(staged: staged)
                successMessage = "Successfully installed skill '\(descriptor.title.preferredValue())' [\(descriptor.id.rawValue)]."
                isProcessing = false
                onImported()
                try? await Task.sleep(nanoseconds: 600_000_000)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }
}
