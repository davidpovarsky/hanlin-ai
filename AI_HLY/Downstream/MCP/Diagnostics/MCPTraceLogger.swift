import Foundation

actor MCPTraceLogger {
    static let shared = MCPTraceLogger()

    private let fileLayout: MCPFileLayout
    private let maximumBytes = 2 * 1_024 * 1_024

    init(fileLayout: MCPFileLayout = .default) {
        self.fileLayout = fileLayout
    }

    func log(_ event: String, fields: [String: String] = [:]) {
        do {
            try fileLayout.prepareIfNeeded()
            try rotateIfNeeded()
            let payload: [String: Any] = [
                "timestamp": ISO8601DateFormatter().string(from: .now),
                "event": event,
                "fields": fields.mapValues(MCPLogRedactor.redact)
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            guard var line = String(data: data, encoding: .utf8) else { return }
            line.append("\n")
            if !FileManager.default.fileExists(atPath: fileLayout.runtimeLog.path) {
                try Data().write(to: fileLayout.runtimeLog)
            }
            let handle = try FileHandle(forWritingTo: fileLayout.runtimeLog)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            // Diagnostics must never interfere with tool execution.
        }
    }

    func contents(limit: Int = 200_000) -> String {
        guard let data = try? Data(contentsOf: fileLayout.runtimeLog) else { return "" }
        return MCPLogRedactor.redact(String(decoding: data.suffix(limit), as: UTF8.self))
    }

    private func rotateIfNeeded() throws {
        let size = (try? fileLayout.runtimeLog.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > maximumBytes else { return }
        let archived = fileLayout.runtime.appending(path: "runtime.previous.log")
        try? FileManager.default.removeItem(at: archived)
        try FileManager.default.moveItem(at: fileLayout.runtimeLog, to: archived)
    }
}
