import SwiftUI
import UIKit

struct AgentDiagnosticsView: View {
    @AppStorage(AgentDiagnosticsConfiguration.levelKey) private var levelRaw = AgentDiagnosticsLevel.fullLocalDebug.rawValue
    @AppStorage(AgentDiagnosticsConfiguration.retentionKey) private var retention = 0
    @State private var sessions: [AgentDiagnosticsSessionFile] = []
    @State private var confirmsDeleteAll = false
    @State private var proposedRetention: Int?
    @State private var storageBytes: Int64 = 0

    private var directoryURL: URL? { NativeToolTraceLogger.shared.diagnosticsDirectoryURL }
    private static let interruptedSessionThreshold: TimeInterval = 10 * 60

    var body: some View {
        List {
            Section(String(localized: "Detailed Agent Logs")) {
                Picker(String(localized: "Recording level"), selection: $levelRaw) {
                    Text(String(localized: "Off")).tag(AgentDiagnosticsLevel.off.rawValue)
                    Text(String(localized: "Metadata only")).tag(AgentDiagnosticsLevel.metadataOnly.rawValue)
                    Text(String(localized: "Full detailed logs")).tag(AgentDiagnosticsLevel.fullLocalDebug.rawValue)
                }
                Text(String(localized: "Complete chat diagnostics are saved automatically on this device, including after upgrading. Readable logs include conversation text, prompts and tool content with credentials redacted. Exact source bytes are encrypted with a device-only key. Nothing is uploaded automatically. You can reduce or turn off recording here."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(String(localized: "Keep sessions"), selection: Binding(get: { retention }, set: { value in
                    if value > 0 { proposedRetention = value } else { retention = 0 }
                })) {
                    Text("10").tag(10)
                    Text("25").tag(25)
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text(String(localized: "No automatic deletion")).tag(0)
                }
                Text(String(localized: "Sessions are kept until you delete them. Choosing a session limit automatically deletes older sessions and all their companion files when a new session starts."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(String(localized: "Log folder")) {
                LabeledContent(String(localized: "Storage used"), value: ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                if storageBytes > 512 * 1024 * 1024 {
                    Label(String(localized: "Diagnostic files use substantial storage. Review and delete sessions you no longer need."), systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                if let directoryURL {
                    Text(directoryURL.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button(String(localized: "Open in Files")) {
                        UIApplication.shared.open(directoryURL)
                    }
                    Button(String(localized: "Copy log folder path")) {
                        UIPasteboard.general.string = directoryURL.path
                    }
                }
            }

            Section(String(localized: "Sessions")) {
                if sessions.isEmpty {
                    Text(String(localized: "No detailed agent logs"))
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions) { file in
                    NavigationLink {
                        AgentDiagnosticsSessionView(file: file)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.session.modelID)
                            Text("\(file.session.startedAt.formatted()) · \(file.session.rounds.count) rounds · \(file.session.status)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("hanlin-diagnostics-session-\(file.session.runID.uuidString)")
                    .swipeActions {
                        Button(role: .destructive) { delete(file) } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                    }
                }
                Button(String(localized: "Delete all detailed agent logs"), role: .destructive) {
                    confirmsDeleteAll = true
                }
            }
        }
        .navigationTitle(String(localized: "Agent Diagnostics"))
        .task { _ = AgentDiagnosticsConfiguration.level; _ = AgentDiagnosticsConfiguration.retentionLimit; reload() }
        .confirmationDialog(String(localized: "Automatically delete older diagnostic sessions?"), isPresented: Binding(get: { proposedRetention != nil }, set: { if !$0 { proposedRetention = nil } }), titleVisibility: .visible) {
            Button(String(localized: "Enable automatic deletion"), role: .destructive) {
                if let value = proposedRetention { retention = value }
                proposedRetention = nil
            }
        } message: {
            Text(String(localized: "This deletes older conversations and their encrypted source files when the selected session limit is exceeded. Export anything you want to keep first."))
        }
        .confirmationDialog(
            String(localized: "Delete all detailed agent logs?"),
            isPresented: $confirmsDeleteAll,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete all"), role: .destructive) { deleteAll() }
        }
    }

    private func reload() {
        guard let directoryURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            sessions = []
            return
        }
        storageBytes = urls.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        sessions = urls.filter { $0.lastPathComponent.hasPrefix("agent-session-") && $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      var session = try? AgentDiagnosticsSession.decodeStoredFile(data) else { return nil }
                if !session.isComplete,
                   session.status == "running",
                   Date().timeIntervalSince(session.lastUpdatedAt) > Self.interruptedSessionThreshold {
                    session.status = "interrupted"
                }
                return AgentDiagnosticsSessionFile(session: session, jsonURL: url, textURL: url.deletingPathExtension().appendingPathExtension("txt"))
            }
            .sorted { $0.session.startedAt > $1.session.startedAt }
    }

    private func delete(_ file: AgentDiagnosticsSessionFile) {
        AgentDiagnosticsRecorder.deleteSessionFiles(jsonURL: file.jsonURL)
        reload()
    }

    private func deleteAll() {
        for file in sessions { delete(file) }
        reload()
    }
}

private struct AgentDiagnosticsSessionFile: Identifiable {
    var id: UUID { session.id }
    var session: AgentDiagnosticsSession
    var jsonURL: URL
    var textURL: URL
}

private struct AgentDiagnosticsSessionView: View {
    let file: AgentDiagnosticsSessionFile
    @State private var preparedExport: AgentDiagnosticsExport?
    @State private var exportDirectory: URL?
    @State private var exportTask: Task<Void, Never>?
    @State private var exportError: String?
    @State private var isExporting = false
    @State private var showsRawConfirmation = false
    @State private var replayAPIType = "OpenAI"
    @State private var rawReview: AgentDiagnosticsRawReview?

    var body: some View {
        List {
            Section(String(localized: "Overview")) {
                LabeledContent(String(localized: "Provider"), value: file.session.providerID)
                LabeledContent(String(localized: "Model"), value: file.session.modelID)
                LabeledContent(String(localized: "Status"), value: file.session.status)
                LabeledContent(String(localized: "Rounds"), value: "\(file.session.rounds.count)")
                LabeledContent(String(localized: "Tools"), value: "\(file.session.efficiency.toolCallCount)")
                LabeledContent(String(localized: "Tokens"), value: file.session.totals.totalTokens.map(String.init) ?? String(localized: "Unavailable"))
            }
            Section(String(localized: "Model rounds")) {
                ForEach(file.session.rounds.sorted(by: { $0.index < $1.index })) { round in
                    DisclosureGroup("Round \(round.index) — \(round.trigger)") {
                        Text("Input: \(round.usage.inputTokens.map(String.init) ?? "—") · Output: \(round.usage.outputTokens.map(String.init) ?? "—") · \(round.usage.source.rawValue)")
                            .font(.caption)
                        if let request = round.request.sanitizedJSON {
                            diagnosticsBlock(String(localized: "Request"), request)
                        }
                        if let response = round.response.visibleContent {
                            diagnosticsBlock(String(localized: "Response"), response)
                        }
                        ForEach(round.toolCalls) { tool in
                            diagnosticsBlock(tool.toolName, tool.resultForModel ?? tool.status)
                        }
                    }
                }
            }
            Section(String(localized: "Files")) {
                Picker(String(localized: "Offline replay API format"), selection: $replayAPIType) {
                    ForEach(["OpenAI", "Anthropic", "Gemini"], id: \.self) { Text($0).tag($0) }
                }
                Text(String(localized: "Choose the format actually used by the recorded provider. This response-only replay does not recreate the original request or timing."))
                    .font(.caption).foregroundStyle(.secondary)
                Button { showsRawConfirmation = true } label: {
                    Label(String(localized: "Review encrypted capture"), systemImage: "lock.doc")
                }
                .accessibilityIdentifier("hanlin-diagnostics-review-encrypted")
                .disabled(isExporting)
                Button {
                    let input = file.jsonURL
                    isExporting = true
                    exportTask = Task {
                        defer { isExporting = false }
                        do {
                            let result = try await AgentDiagnosticsExporter.prepareLocally(sessionJSON: input)
                            if Task.isCancelled { result.discard() } else {
                                exportDirectory = result.directory
                                preparedExport = result
                            }
                        } catch is CancellationError { } catch {
                            exportError = String(localized: "The local archive could not be created. No files were shared. Check available storage and try again after the session finishes.")
                        }
                    }
                } label: {
                    Label(String(localized: "Prepare sanitized ZIP"), systemImage: "archivebox")
                }
                .disabled(isExporting)
                if isExporting { ProgressView() }
                if let exportError {
                    Text(exportError).foregroundStyle(.red).accessibilityIdentifier("hanlin-diagnostics-export-error")
                }
                ShareLink(item: file.jsonURL) { Label(String(localized: "Open JSON"), systemImage: "curlybraces") }
                ShareLink(item: file.textURL) { Label(String(localized: "Open readable log"), systemImage: "doc.text") }
            }
            if !file.session.efficiency.warnings.isEmpty {
                Section(String(localized: "Warnings")) {
                    ForEach(file.session.efficiency.warnings, id: \.self) { warning in
                        Text(warning)
                    }
                }
            }
        }
        .navigationTitle(file.session.modelID)
        .onDisappear { exportTask?.cancel() }
        .confirmationDialog(String(localized: "Open encrypted capture locally?"), isPresented: $showsRawConfirmation) {
            Button(String(localized: "Open local review")) {
                let input = file.jsonURL, runID = file.session.runID, modelID = file.session.modelID, apiType = replayAPIType
                isExporting = true
                exportError = nil
                exportTask = Task {
                    defer { isExporting = false }
                    do {
                        let review = try await AgentDiagnosticsRawReviewer.reviewLocally(
                            sessionJSON: input, runID: runID, modelID: modelID, apiType: apiType)
                        if !Task.isCancelled { rawReview = review }
                    } catch is CancellationError { } catch {
                        exportError = String(localized: "The capture could not be authenticated or exceeds the local review budget. The original files remain unchanged.")
                    }
                }
            }
            .accessibilityIdentifier("hanlin-diagnostics-confirm-local-review")
        } message: {
            Text(String(localized: "Only this run will be decrypted in memory with this device's key. Requests and conversation text may contain private information. Nothing is uploaded or executed. Credentials are masked before review; sharing the reviewed report is optional."))
        }
        .sheet(item: $preparedExport, onDismiss: {
            if let exportDirectory { try? FileManager.default.removeItem(at: exportDirectory) }
            exportDirectory = nil
            preparedExport = nil
        }) { export in
            NavigationStack {
                List {
                    Section(String(localized: "Review before sharing")) {
                        Text(export.preview).font(.caption).textSelection(.enabled)
                    }
                    Section(String(localized: "Conversation preview")) {
                        Text(String(localized: "Preview shows up to 65,536 characters from the readable log. The archive may contain additional conversation content."))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(export.conversationPreview).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    Section(String(localized: "Files")) {
                        ForEach(export.includedFiles, id: \.self) { Text($0).font(.caption) }
                        ForEach(export.missingFiles, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    }
                    ShareLink(item: export.archive) {
                        Label(String(localized: "Share reviewed archive"), systemImage: "square.and.arrow.up")
                    }
                }
                .navigationTitle(String(localized: "Diagnostic export"))
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { export.discard(); preparedExport = nil }
                } }
            }
        }
        .sheet(item: $rawReview) { review in
            NavigationStack {
                List {
                    Section(String(localized: "Review before sharing")) {
                        Text(String(localized: "Preview shows up to 65,536 characters. Sharing includes the full redacted report, not the encrypted source or device key."))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(String(review.text.prefix(65_536))).font(.caption.monospaced()).textSelection(.enabled)
                            .accessibilityIdentifier("hanlin-diagnostics-local-review-text")
                    }
                    ShareLink(item: review.text) {
                        Label(String(localized: "Share reviewed report"), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("hanlin-diagnostics-share-reviewed-report")
                }
                .navigationTitle(String(localized: "Local capture review"))
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { rawReview = nil }
                } }
            }
        }
    }

    private func diagnosticsBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced()).textSelection(.enabled)
        }
    }
}
