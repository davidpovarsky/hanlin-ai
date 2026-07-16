import SwiftUI
import UIKit

struct AgentDiagnosticsView: View {
    @AppStorage(AgentDiagnosticsConfiguration.levelKey) private var levelRaw = AgentDiagnosticsLevel.metadataOnly.rawValue
    @AppStorage(AgentDiagnosticsConfiguration.retentionKey) private var retention = 50
    @State private var sessions: [AgentDiagnosticsSessionFile] = []
    @State private var confirmsDeleteAll = false

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
                Text(String(localized: "Detailed diagnostics may include conversation text, prompts, tool inputs and tool outputs. Sensitive credentials are always redacted. Logs remain on this device until deleted."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(String(localized: "Keep sessions"), selection: $retention) {
                    Text("10").tag(10)
                    Text("25").tag(25)
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text(String(localized: "No automatic deletion")).tag(0)
                }
            }

            Section(String(localized: "Log folder")) {
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
        .task { reload() }
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        sessions = urls.filter { $0.lastPathComponent.hasPrefix("agent-session-") && $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      var session = try? decoder.decode(AgentDiagnosticsSession.self, from: data) else { return nil }
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
        try? FileManager.default.removeItem(at: file.jsonURL)
        try? FileManager.default.removeItem(at: file.textURL)
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
    }

    private func diagnosticsBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced()).textSelection(.enabled)
        }
    }
}
