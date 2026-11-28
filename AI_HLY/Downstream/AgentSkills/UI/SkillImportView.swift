import HanlinLocalization
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
    @State private var presentation = SkillImportPresentationState()
    @State private var showFileImporter: Bool = false
    @State private var importTask: Task<Void, Never>?

    private var isProcessing: Bool { presentation.isProcessing }
    private var errorMessage: String? { presentation.errorMessage }
    private var successMessage: String? { presentation.successMessage }
    private var downloadedBytes: Int64 { presentation.downloadedBytes }
    private var expectedDownloadBytes: Int64? { presentation.expectedDownloadBytes }

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
                        presentation.invalidate()
                        importTask?.cancel()
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
                allowedContentTypes: [.zip, UTType(filenameExtension: "md") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImportResult(result)
            }
        }
        .onDisappear {
            presentation.invalidate()
            importTask?.cancel()
            if case .preview(let staged) = step { staged.cleanup() }
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
            Picker(hanlin: "", selection: $selectedTab) {
                Text(SkillL10n.string("Import File")).tag(0)
                    .accessibilityIdentifier("hanlin-skill-import-tab-zip")
                Text(SkillL10n.string("Install from HTTPS URL")).tag(1)
                    .accessibilityIdentifier("hanlin-skill-import-tab-url")
            }
            .pickerStyle(.segmented)
            .padding()

            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(HanlinTypography.footnote)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }

            if let succ = successMessage {
                Text(succ)
                    .foregroundColor(.green)
                    .font(HanlinTypography.footnote)
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
            Section(header: Text("Skill Metadata", bundle: HanlinLocalization.bundle)) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(staged.parsedMarkdown.name)
                            .font(HanlinTypography.headline)
                            .accessibilityIdentifier("hanlin-skill-import-preview-title")
                        Spacer()
                        Text(staged.skillID.rawValue)
                            .font(HanlinTypography.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }

                    if !staged.parsedMarkdown.description.isEmpty {
                        Text(staged.parsedMarkdown.description)
                            .font(HanlinTypography.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            SkillCompatibilityUnknownSection(identifierScope: "import")

            if !staged.metadata.preferredToolIDs.isEmpty {
                Section(header: Text("Preferred Tools", bundle: HanlinLocalization.bundle)) {
                    ForEach(staged.metadata.preferredToolIDs, id: \.self) { tool in
                        HStack {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(HanlinTypography.caption)
                                .foregroundColor(.secondary)
                            Text(tool)
                                .font(HanlinTypography.subheadline.monospaced())
                        }
                    }
                }
            }

            if !staged.metadata.triggerHints.isEmpty {
                Section(header: Text("Trigger Hints", bundle: HanlinLocalization.bundle)) {
                    ForEach(staged.metadata.triggerHints, id: \.self) { hint in
                        Text(hint)
                            .font(HanlinTypography.footnote)
                    }
                }
            }

            Section(header: Text("Included Resources (\(staged.resources.count))", bundle: HanlinLocalization.bundle)) {
                if staged.resources.isEmpty {
                    Text("No additional resources.", bundle: HanlinLocalization.bundle)
                        .font(HanlinTypography.footnote)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("hanlin-skill-import-preview-resources-empty")
                } else {
                    ForEach(staged.resources) { res in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(res.relativePath)
                                    .font(HanlinTypography.footnote.monospaced())
                                Text(ByteCountFormatter.string(fromByteCount: res.byteCount, countStyle: .file))
                                    .font(HanlinTypography.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if res.isBinary {
                                Text("Binary", bundle: HanlinLocalization.bundle)
                                    .font(HanlinTypography.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section(header: Text("Package Origin & Integrity", bundle: HanlinLocalization.bundle)) {
                if let origin = staged.originURL {
                    LabeledContent(hanlin: "Origin URL", value: origin)
                        .accessibilityIdentifier("hanlin-skill-import-origin-url")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("SHA-256", bundle: HanlinLocalization.bundle)
                        .font(HanlinTypography.caption)
                        .foregroundColor(.secondary)
                    Text(staged.sha256)
                        .font(HanlinTypography.caption2.monospaced())
                        .foregroundColor(.primary)
                }
                .accessibilityIdentifier("hanlin-skill-import-sha256")
            }

            Section {
                VStack(spacing: 12) {
                    if let err = errorMessage {
                        Text(err)
                            .foregroundColor(.red)
                            .font(HanlinTypography.footnote)
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
                        .accessibilityIdentifier("hanlin-skill-import-install-button")

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
        .accessibilityIdentifier("hanlin-skill-import-preview-list")
    }

    private var zipImportSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.zipper")
                .font(HanlinTypography.fixed(size: 48))
                .foregroundColor(.accentColor)
                .padding(.top, 30)

            Text(SkillL10n.string("Select a ZIP package or a SKILL.md file. Previewing does not run scripts."))
                .font(HanlinTypography.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                showFileImporter = true
            } label: {
                Label(SkillL10n.string("Select ZIP or SKILL.md"), systemImage: "folder")
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
                Label(hanlin: "Load Test Fixture ZIP", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)
            .accessibilityIdentifier("hanlin-skill-import-fixture-button")
            .padding(.horizontal, 40)
            if ProcessInfo.processInfo.environment["HANLIN_AGENT_SKILLS_EMBEDDED_ACCEPTANCE"] == "1" {
                Button {
                    loadTestFixtureMarkdown()
                } label: {
                    Label(hanlin: "Load Markdown Acceptance Fixture", systemImage: "doc.text")
                }
                .disabled(isProcessing)
                .accessibilityIdentifier("hanlin-skill-import-markdown-fixture-button")
            }
            #endif

            if isProcessing {
                ProgressView(SkillL10n.string("Inspecting..."))
            }
        }
    }

    private var urlImportSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(HanlinTypography.fixed(size: 48))
                .foregroundColor(.accentColor)
                .padding(.top, 30)

            VStack(alignment: .leading, spacing: 6) {
                Text(SkillL10n.string("Skill Archive URL"))
                    .font(HanlinTypography.caption)
                    .foregroundColor(.secondary)

                TextField(hanlin: "https://example.com/skill-bundle.zip", text: $urlString)
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
                Text(downloadProgressDescription)
                    .font(HanlinTypography.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("hanlin-skill-download-progress")
            }
        }
    }

    private func beginInspection() -> UUID {
        importTask?.cancel()
        return presentation.beginInspection()
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            let attempt = beginInspection()
            importTask = Task {
                do {
                    let staged = try await SkillImporter.shared.stageAndInspectInBackground(fileURL: fileURL)
                    try presentPreview(staged, attempt: attempt)
                } catch is CancellationError {
                    presentation.inspectionCancelled(attempt: attempt)
                } catch {
                    presentation.inspectionFailed(attempt: attempt, message: error.localizedDescription)
                }
            }
        case .failure(let error):
            let attempt = beginInspection()
            presentation.inspectionFailed(attempt: attempt, message: error.localizedDescription)
        }
    }

    private func downloadAndInspect() {
        let attempt = beginInspection()
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else {
            presentation.inspectionFailed(attempt: attempt, message: "Please enter a valid HTTPS URL.")
            return
        }
        importTask = Task { @MainActor in
            do {
                let staged = try await SkillImporter.shared.downloadAndStage(from: url, downloadProgress: { received, expected in
                    Task { @MainActor in
                        presentation.recordProgress(attempt: attempt, received: received, expected: expected)
                    }
                })
                try presentPreview(staged, attempt: attempt)
            } catch is CancellationError {
                presentation.inspectionCancelled(attempt: attempt)
            } catch {
                presentation.inspectionFailed(attempt: attempt, message: error.localizedDescription)
            }
        }
    }

    private var downloadProgressDescription: String {
        let received = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        guard let expected = expectedDownloadBytes else { return received }
        return "\(received) / \(ByteCountFormatter.string(fromByteCount: expected, countStyle: .file))"
    }

    private func loadTestFixtureZip() {
        let attempt = beginInspection()
        importTask = Task { @MainActor in
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let tempZip = tempDir.appendingPathComponent("ui-import-skill-\(UUID().uuidString).zip")
                defer { try? FileManager.default.removeItem(at: tempZip) }
                guard let archive = try? Archive(url: tempZip, accessMode: .create) else {
                    presentation.inspectionFailed(attempt: attempt, message: "Failed to create test fixture zip.")
                    return
                }
                let requestedID = ProcessInfo.processInfo.environment["HANLIN_SKILL_ZIP_FIXTURE_ID"]
                let fixtureID = requestedID.flatMap { $0.hasPrefix("ui-exec-") && $0.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) ? $0 : nil } ?? "ui-import-skill"
                let policyMetadata: String
                #if targetEnvironment(simulator) || DEBUG
                policyMetadata = ProcessInfo.processInfo.environment["HANLIN_SKILL_OPENCLAW_FIXTURE"] == "1" ? """
                user-invocable: false
                disable-model-invocation: true
                metadata:
                  openclaw:
                    requires:
                      bins: node
                    install:
                      - kind: node
                        package: "@hanlin-fixture/policy@1.0.0"
                      - kind: node
                        package: "file:../unsupported"

                """ : ""
                #else
                policyMetadata = ""
                #endif
                let skillMD = """
                ---
                name: \(fixtureID)
                description: Deterministic UI imported skill for acceptance testing.
                \(policyMetadata)---

                # UI Import Skill Instructions
                Execute tools as needed.
                """
                let skillMDData = Data(skillMD.utf8)
                try archive.addEntry(with: "SKILL.md", type: .file, uncompressedSize: UInt32(skillMDData.count), provider: { position, size in
                    skillMDData.subdata(in: position..<(position + size))
                })
                let refData = Data("Reference documentation content.\n".utf8)
                try archive.addEntry(with: "references/guide.md", type: .file, uncompressedSize: UInt32(refData.count), provider: { position, size in
                    refData.subdata(in: position..<(position + size))
                })
                let scriptData = Data("print('test script')\n".utf8)
                try archive.addEntry(with: "scripts/run.py", type: .file, uncompressedSize: UInt32(scriptData.count), provider: { position, size in
                    scriptData.subdata(in: position..<(position + size))
                })

                if fixtureID != "ui-import-skill" {
                    let slow = Data("console.log('STARTED_\(fixtureID)'); await new Promise(resolve=>setTimeout(resolve,30000)); console.log('UNEXPECTED_LATE');".utf8)
                    try archive.addEntry(with: "scripts/slow.mjs", type: .file, uncompressedSize: UInt32(slow.count)) { position, size in
                        slow.subdata(in: position..<(position + size))
                    }
                }
                let staged = try await SkillImporter.shared.stageAndInspectInBackground(fileURL: tempZip)
                try presentPreview(staged, attempt: attempt)
            } catch is CancellationError {
                presentation.inspectionCancelled(attempt: attempt)
            } catch {
                presentation.inspectionFailed(attempt: attempt, message: error.localizedDescription)
            }
        }
    }

    #if targetEnvironment(simulator) || DEBUG
    private func loadTestFixtureMarkdown() {
        let attempt = beginInspection()
        importTask = Task { @MainActor in
            let temporaryFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("ui-markdown-\(UUID().uuidString).md")
            defer { try? FileManager.default.removeItem(at: temporaryFile) }
            do {
                let suppliedID = ProcessInfo.processInfo.environment["HANLIN_SKILL_MARKDOWN_FIXTURE_ID"]
                    ?? "ui-md-\(UUID().uuidString.lowercased())"
                let id = try HanlinSkillID(validating: suppliedID)
                let markdown = """
                ---
                name: \(id.rawValue)
                description: Instruction-only Markdown acceptance fixture.
                ---

                # Instruction-only Skill
                Summarize the question using these instructions. No script is included.
                """
                try markdown.write(to: temporaryFile, atomically: true, encoding: .utf8)
                let staged = try await SkillImporter.shared.stageAndInspectInBackground(fileURL: temporaryFile)
                try presentPreview(staged, attempt: attempt)
            } catch is CancellationError {
                presentation.inspectionCancelled(attempt: attempt)
            } catch {
                presentation.inspectionFailed(attempt: attempt, message: error.localizedDescription)
            }
        }
    }
    #endif

    private func presentPreview(_ staged: StagedSkillPackage, attempt: UUID) throws {
        guard !Task.isCancelled, presentation.preparePreview(attempt: attempt) else {
            staged.cleanup()
            throw CancellationError()
        }
        step = .preview(staged)
    }

    private func installStaged(_ staged: StagedSkillPackage) {
        guard let attempt = presentation.beginInstallation() else { return }
        importTask?.cancel()
        importTask = Task { @MainActor in
            guard !Task.isCancelled, presentation.isInstalling(attempt: attempt) else {
                presentation.installationCancelled(attempt: attempt)
                return
            }
            do {
                let descriptor = try SkillImporter.shared.install(staged: staged)
                // The store committed: notify its existing consumer even if this
                // presentation has been superseded. Do not replay or roll it back.
                onImported()
                if presentation.finishInstallation(attempt: attempt,
                    message: "Successfully installed skill '\(descriptor.title.preferredValue())' [\(descriptor.id.rawValue)].") {
                    dismiss()
                }
            } catch is CancellationError {
                presentation.installationCancelled(attempt: attempt)
            } catch {
                presentation.installationFailed(attempt: attempt, message: error.localizedDescription)
            }
        }
    }
}
