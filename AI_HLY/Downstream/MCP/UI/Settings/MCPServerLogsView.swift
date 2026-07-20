import SwiftUI

struct MCPServerLogsView: View {
    let server: MCPServerDescriptor?
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? MCPL10n.string("No logs") : text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(server?.displayName ?? MCPL10n.string("Runtime logs"))
        .task { await load() }
        .toolbar { Button(MCPL10n.string("Refresh")) { Task { await load() } } }
    }

    private func load() async {
        if let server,
           let connection = try? await MCPRuntimeProvider.shared.nodeRuntime.currentConnection(),
           let data = try? await connection.data(path: "/v1/servers/\(server.id.uuidString.lowercased())/logs"),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let lines = object["lines"] as? [String] {
            text = MCPLogRedactor.redact(lines.joined(separator: "\n"))
        } else {
            text = await MCPTraceLogger.shared.contents()
        }
    }
}
