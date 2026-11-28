import HanlinLocalization
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
            Section(String(localized: "Detailed Agent Logs", bundle: HanlinLocalization.bundle)) {
                Picker(String(localized: "Recording level", bundle: HanlinLocalization.bundle), selection: $levelRaw) {
                    Text(String(localized: "Off", bundle: HanlinLocalization.bundle)).tag(AgentDiagnosticsLevel.off.rawValue)
                    Text(String(localized: "Metadata only", bundle: HanlinLocalization.bundle)).tag(AgentDiagnosticsLevel.metadataOnly.rawValue)
                    Text(String(localized: "Full detailed logs", bundle: HanlinLocalization.bundle)).tag(AgentDiagnosticsLevel.fullLocalDebug.rawValue)
                }
                Text(String(localized: "Complete chat diagnostics are saved automatically on this device, including after upgrading. Readable logs include conversation text, prompts and tool content with credentials redacted. Exact source bytes are encrypted with a device-only key. Nothing is uploaded automatically. You can reduce or turn off recording here.", bundle: HanlinLocalization.bundle))
                    .font(HanlinTypography.caption)
                    .foregroundStyle(.secondary)

                Picker(String(localized: "Keep sessions", bundle: HanlinLocalization.bundle), selection: Binding(get: { retention }, set: { value in
                    if value > 0 { proposedRetention = value } else { retention = 0 }
                })) {
                    Text("10", bundle: HanlinLocalization.bundle).tag(10)
                    Text("25", bundle: HanlinLocalization.bundle).tag(25)
                    Text("50", bundle: HanlinLocalization.bundle).tag(50)
                    Text("100", bundle: HanlinLocalization.bundle).tag(100)
                    Text(String(localized: "No automatic deletion", bundle: HanlinLocalization.bundle)).tag(0)
                }
                Text(String(localized: "Sessions are kept until you delete them. Choosing a session limit automatically deletes older sessions and all their companion files when a new session starts.", bundle: HanlinLocalization.bundle))
                    .font(HanlinTypography.caption).foregroundStyle(.secondary)
            }

            Section(String(localized: "Log folder", bundle: HanlinLocalization.bundle)) {
                LabeledContent(String(localized: "Storage used", bundle: HanlinLocalization.bundle), value: ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                if storageBytes > 512 * 1024 * 1024 {
                    Label(String(localized: "Diagnostic files use substantial storage. Review and delete sessions you no longer need.", bundle: HanlinLocalization.bundle), systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                if let directoryURL {
                    Text(directoryURL.path)
                        .font(HanlinTypography.caption.monospaced())
                        .textSelection(.enabled)
                    Button(String(localized: "Open in Files", bundle: HanlinLocalization.bundle)) {
                        UIApplication.shared.open(directoryURL)
                    }
                    Button(String(localized: "Copy log folder path", bundle: HanlinLocalization.bundle)) {
                        UIPasteboard.general.string = directoryURL.path
                    }
                }
            }

            Section(String(localized: "Sessions", bundle: HanlinLocalization.bundle)) {
                if sessions.isEmpty {
                    Text(String(localized: "No detailed agent logs", bundle: HanlinLocalization.bundle))
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions) { file in
                    NavigationLink {
                        AgentDiagnosticsSessionView(file: file)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.session.modelID)
                            Text("\(file.session.startedAt.formatted()) · \(file.session.rounds.count) rounds · \(file.session.status)", bundle: HanlinLocalization.bundle)
                                .font(HanlinTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("hanlin-diagnostics-session-\(file.session.runID.uuidString)")
                    .swipeActions {
                        Button(role: .destructive) { delete(file) } label: {
                            Label(String(localized: "Delete", bundle: HanlinLocalization.bundle), systemImage: "trash")
                        }
                    }
                }
                Button(String(localized: "Delete all detailed agent logs", bundle: HanlinLocalization.bundle), role: .destructive) {
                    confirmsDeleteAll = true
                }
            }
        }
        .navigationTitle(String(localized: "Agent Diagnostics", bundle: HanlinLocalization.bundle))
        .task { _ = AgentDiagnosticsConfiguration.level; _ = AgentDiagnosticsConfiguration.retentionLimit; reload() }
        .confirmationDialog(String(localized: "Automatically delete older diagnostic sessions?", bundle: HanlinLocalization.bundle), isPresented: Binding(get: { proposedRetention != nil }, set: { if !$0 { proposedRetention = nil } }), titleVisibility: .visible) {
            Button(String(localized: "Enable automatic deletion", bundle: HanlinLocalization.bundle), role: .destructive) {
                if let value = proposedRetention { retention = value }
                proposedRetention = nil
            }
        } message: {
            Text(String(localized: "This deletes older conversations and their encrypted source files when the selected session limit is exceeded. Export anything you want to keep first.", bundle: HanlinLocalization.bundle))
        }
        .confirmationDialog(
            String(localized: "Delete all detailed agent logs?", bundle: HanlinLocalization.bundle),
            isPresented: $confirmsDeleteAll,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete all", bundle: HanlinLocalization.bundle), role: .destructive) { deleteAll() }
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
            Section(String(localized: "Overview", bundle: HanlinLocalization.bundle)) {
                LabeledContent(String(localized: "Provider", bundle: HanlinLocalization.bundle), value: file.session.providerID)
                LabeledContent(String(localized: "Model", bundle: HanlinLocalization.bundle), value: file.session.modelID)
                LabeledContent(String(localized: "Status", bundle: HanlinLocalization.bundle), value: file.session.status)
                LabeledContent(String(localized: "Rounds", bundle: HanlinLocalization.bundle), value: "\(file.session.rounds.count)")
                LabeledContent(String(localized: "Tools", bundle: HanlinLocalization.bundle), value: "\(file.session.efficiency.toolCallCount)")
                LabeledContent(String(localized: "Tokens", bundle: HanlinLocalization.bundle), value: file.session.totals.totalTokens.map(String.init) ?? String(localized: "Unavailable", bundle: HanlinLocalization.bundle))
            }
            Section(String(localized: "Prompt cache", bundle: HanlinLocalization.bundle)) {
                cacheUsageRows(file.session.promptCacheSummary)
                Text(String(localized: "Cache tokens are provider-reported input tokens. Missing data is unavailable, not zero. These counts are not a price or a cost estimate.", bundle: HanlinLocalization.bundle))
                    .font(HanlinTypography.caption).foregroundStyle(.secondary)
            }
            Section(String(localized: "Model rounds", bundle: HanlinLocalization.bundle)) {
                ForEach(file.session.rounds.sorted(by: { $0.index < $1.index })) { round in
                    DisclosureGroup("Round \(round.index) — \(round.trigger)") {
                        Text("Input: \(round.usage.inputTokens.map(String.init) ?? "—") · Output: \(round.usage.outputTokens.map(String.init) ?? "—") · \(round.usage.source.rawValue)", bundle: HanlinLocalization.bundle)
                            .font(HanlinTypography.caption)
                        cacheUsageRows(AgentPromptCacheSummary(usages: [round.usage]))
                        if let request = round.request.sanitizedJSON {
                            diagnosticsBlock(String(localized: "Request", bundle: HanlinLocalization.bundle), request)
                        }
                        if let response = round.response.visibleContent {
                            diagnosticsBlock(String(localized: "Response", bundle: HanlinLocalization.bundle), response)
                        }
                        ForEach(round.toolCalls) { tool in
                            diagnosticsBlock(tool.toolName, tool.resultForModel ?? tool.status)
                        }
                    }
                }
            }
            Section(String(localized: "Files", bundle: HanlinLocalization.bundle)) {
                Picker(String(localized: "Offline replay API format", bundle: HanlinLocalization.bundle), selection: $replayAPIType) {
                    ForEach(["OpenAI", "Anthropic", "Gemini"], id: \.self) { Text($0).tag($0) }
                }
                Text(String(localized: "Choose the format actually used by the recorded provider. This response-only replay does not recreate the original request or timing.", bundle: HanlinLocalization.bundle))
                    .font(HanlinTypography.caption).foregroundStyle(.secondary)
                Button { showsRawConfirmation = true } label: {
                    Label(String(localized: "Review encrypted capture", bundle: HanlinLocalization.bundle), systemImage: "lock.doc")
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
                            exportError = String(localized: "The local archive could not be created. No files were shared. Check available storage and try again after the session finishes.", bundle: HanlinLocalization.bundle)
                        }
                    }
                } label: {
                    Label(String(localized: "Prepare sanitized ZIP", bundle: HanlinLocalization.bundle), systemImage: "archivebox")
                }
                .disabled(isExporting)
                if isExporting { ProgressView() }
                if let exportError {
                    Text(exportError).foregroundStyle(.red).accessibilityIdentifier("hanlin-diagnostics-export-error")
                }
                ShareLink(item: file.jsonURL) { Label(String(localized: "Open JSON", bundle: HanlinLocalization.bundle), systemImage: "curlybraces") }
                ShareLink(item: file.textURL) { Label(String(localized: "Open readable log", bundle: HanlinLocalization.bundle), systemImage: "doc.text") }
            }
            if !file.session.efficiency.warnings.isEmpty {
                Section(String(localized: "Warnings", bundle: HanlinLocalization.bundle)) {
                    ForEach(file.session.efficiency.warnings, id: \.self) { warning in
                        Text(warning)
                    }
                }
            }
        }
        .navigationTitle(file.session.modelID)
        .onDisappear { exportTask?.cancel() }
        .confirmationDialog(String(localized: "Open encrypted capture locally?", bundle: HanlinLocalization.bundle), isPresented: $showsRawConfirmation) {
            Button(String(localized: "Open local review", bundle: HanlinLocalization.bundle)) {
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
                        exportError = String(localized: "The capture could not be authenticated or exceeds the local review budget. The original files remain unchanged.", bundle: HanlinLocalization.bundle)
                    }
                }
            }
            .accessibilityIdentifier("hanlin-diagnostics-confirm-local-review")
        } message: {
            Text(String(localized: "Only this run will be decrypted in memory with this device's key. Requests and conversation text may contain private information. Nothing is uploaded or executed. Credentials are masked before review; sharing the reviewed report is optional.", bundle: HanlinLocalization.bundle))
        }
        .sheet(item: $preparedExport, onDismiss: {
            if let exportDirectory { try? FileManager.default.removeItem(at: exportDirectory) }
            exportDirectory = nil
            preparedExport = nil
        }) { export in
            NavigationStack {
                List {
                    Section(String(localized: "Review before sharing", bundle: HanlinLocalization.bundle)) {
                        Text(export.preview).font(HanlinTypography.caption).textSelection(.enabled)
                    }
                    Section(String(localized: "Conversation preview", bundle: HanlinLocalization.bundle)) {
                        Text(String(localized: "Preview shows up to 65,536 characters from the readable log. The archive may contain additional conversation content.", bundle: HanlinLocalization.bundle))
                            .font(HanlinTypography.caption).foregroundStyle(.secondary)
                        Text(export.conversationPreview).font(HanlinTypography.caption.monospaced()).textSelection(.enabled)
                    }
                    Section(String(localized: "Files", bundle: HanlinLocalization.bundle)) {
                        ForEach(export.includedFiles, id: \.self) { Text($0).font(HanlinTypography.caption) }
                        ForEach(export.missingFiles, id: \.self) { Text($0).font(HanlinTypography.caption).foregroundStyle(.orange) }
                    }
                    ShareLink(item: export.archive) {
                        Label(String(localized: "Share reviewed archive", bundle: HanlinLocalization.bundle), systemImage: "square.and.arrow.up")
                    }
                }
                .navigationTitle(String(localized: "Diagnostic export", bundle: HanlinLocalization.bundle))
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: HanlinLocalization.bundle)) { export.discard(); preparedExport = nil }
                } }
            }
        }
        .sheet(item: $rawReview) { review in
            NavigationStack {
                List {
                    Section(String(localized: "Review before sharing", bundle: HanlinLocalization.bundle)) {
                        Text(String(localized: "Preview shows up to 65,536 characters. Sharing includes the full redacted report, not the encrypted source or device key.", bundle: HanlinLocalization.bundle))
                            .font(HanlinTypography.caption).foregroundStyle(.secondary)
                        Text(String(review.text.prefix(65_536))).font(HanlinTypography.caption.monospaced()).textSelection(.enabled)
                            .accessibilityIdentifier("hanlin-diagnostics-local-review-text")
                    }
                }
                .navigationTitle(String(localized: "Local capture review", bundle: HanlinLocalization.bundle))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: review.text) {
                            Label(String(localized: "Share reviewed report", bundle: HanlinLocalization.bundle), systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("hanlin-diagnostics-share-reviewed-report")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done", bundle: HanlinLocalization.bundle)) { rawReview = nil }
                    }
                }
            }
        }
    }

    private func cacheUsageRows(_ summary: AgentPromptCacheSummary) -> some View {
        Group {
            LabeledContent(String(localized: "Reported cache read tokens", bundle: HanlinLocalization.bundle),
                           value: summary.cachedInputTokens.map(String.init) ?? String(localized: "Unavailable", bundle: HanlinLocalization.bundle))
            LabeledContent(String(localized: "Reported cache write tokens", bundle: HanlinLocalization.bundle),
                           value: summary.cacheWriteTokens.map(String.init) ?? String(localized: "Unavailable", bundle: HanlinLocalization.bundle))
            LabeledContent(String(localized: "Cache read fraction of input", bundle: HanlinLocalization.bundle),
                           value: summary.cacheReadFraction.map { $0.formatted(.percent.precision(.fractionLength(1))) }
                            ?? String(localized: "Unavailable", bundle: HanlinLocalization.bundle))
            LabeledContent(String(localized: "Rounds with cache read data", bundle: HanlinLocalization.bundle),
                           value: "\(summary.readReportedRoundCount)/\(summary.roundCount)")
            LabeledContent(String(localized: "Rounds with cache write data", bundle: HanlinLocalization.bundle),
                           value: "\(summary.writeReportedRoundCount)/\(summary.roundCount)")
        }
    }

    private func diagnosticsBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(HanlinTypography.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(HanlinTypography.caption.monospaced()).textSelection(.enabled)
        }
    }
}
