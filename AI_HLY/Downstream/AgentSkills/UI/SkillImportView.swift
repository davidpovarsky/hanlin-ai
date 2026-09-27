import SwiftUI
import UniformTypeIdentifiers
import HanlinPlatformContracts

@MainActor
struct SkillImportView: View {
    let onImported: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int = 0
    @State private var urlString: String = ""
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var showFileImporter: Bool = false

    var body: some View {
        NavigationStack {
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
            .navigationTitle(SkillL10n.string("Import Skill"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SkillL10n.string("Cancel")) {
                        dismiss()
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

            if isProcessing {
                ProgressView(SkillL10n.string("Installing..."))
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
                downloadAndInstall()
            } label: {
                Label(SkillL10n.string("Download & Install"), systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("hanlin-skill-import-url-button")
            .padding(.horizontal, 40)

            if isProcessing {
                ProgressView(SkillL10n.string("Installing..."))
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
                    let descriptor = try SkillImporter.shared.importSkill(fromArchiveAt: fileURL)
                    successMessage = "Successfully imported skill '\(descriptor.title.preferredValue())' [\(descriptor.id.rawValue)]."
                    isProcessing = false
                    onImported()
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func downloadAndInstall() {
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
                let descriptor = try await SkillImporter.shared.installFromHTTPSURL(url)
                successMessage = "Successfully downloaded and installed skill '\(descriptor.title.preferredValue())' [\(descriptor.id.rawValue)]."
                isProcessing = false
                onImported()
                try? await Task.sleep(nanoseconds: 800_000_000)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }
}
