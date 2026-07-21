import SwiftUI

struct RuntimeLogsView: View {
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? RuntimeL10n.string("No runtime logs") : text)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle(RuntimeL10n.string("Runtime logs"))
        .toolbar { Button(RuntimeL10n.string("Refresh")) { load() } }
        .task { load() }
    }

    private func load() {
        let root = RuntimeFileLayout.default.logs
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { text = ""; return }
        text = files.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return "=== \(url.lastPathComponent) ===\n\(String(decoding: data.suffix(512 * 1_024), as: UTF8.self))"
        }.joined(separator: "\n\n")
    }
}
