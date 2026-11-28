import Foundation
import OSLog

/// Persistent JSONL tracing for the chat/native-tool pipeline.
/// Files are written under Documents/Diagnostics and are visible in the Files app
/// when UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace are enabled.
final class NativeToolTraceLogger: @unchecked Sendable {
    static let shared = NativeToolTraceLogger()

    private let queue = DispatchQueue(label: "com.hanlin.native-tool-trace")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.hanlin", category: "NativeToolTrace")
    private let encoder: JSONEncoder
    private let fileManager: FileManager
    private var activeFileURL: URL?

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        queue.sync {
            self.prepareDirectoryAndFile()
        }
    }

    func log(
        _ event: String,
        _ fields: [String: Any] = [:],
        requestID: String? = nil,
        conversationID: String? = nil,
        modelStep: Int? = nil,
        toolName: String? = nil
    ) {
        let record = TraceRecord(
            timestamp: Date(),
            event: AgentDiagnosticsRedactor.sanitize(event),
            requestID: requestID,
            conversationID: conversationID,
            modelStep: modelStep,
            toolName: toolName,
            fields: Self.redactedFields(fields)
        )

        queue.async { [weak self] in
            guard let self else { return }
            do {
                if self.activeFileURL == nil { self.prepareDirectoryAndFile() }
                guard let url = self.activeFileURL else { return }
                var data = try self.encoder.encode(record)
                data.append(0x0A)
                if !self.fileManager.fileExists(atPath: url.path) {
                    try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
                } else {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                }
                self.logger.debug("\(record.event, privacy: .public)")
            } catch {
                self.logger.error("Trace write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func logError(
        _ event: String,
        error: Error,
        toolName: String? = nil,
        fields: [String: Any] = [:]
    ) {
        var values = fields
        values["error"] = String(describing: error)
        if let encodingError = error as? EncodingError {
            values["encodingError"] = describe(encodingError)
        }
        log(event, values, toolName: toolName)
    }

    var diagnosticsDirectoryURL: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    func redactedJSONString(_ json: String) -> String {
        AgentDiagnosticsRedactor.sanitize(json)
    }

    private func prepareDirectoryAndFile() {
        guard let directory = diagnosticsDirectoryURL else { return }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var protectedDirectory = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedDirectory.setResourceValues(values)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            activeFileURL = directory.appendingPathComponent("Hanlin-Chat-\(formatter.string(from: Date())).jsonl")
        } catch {
            logger.error("Unable to prepare diagnostics directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func redactedFields(_ fields: [String: Any]) -> [String: String] {
        // Redact structured values before stringification. Substring matching
        // on "token" used to erase inputTokens/outputTokens while missing
        // credentials nested inside an otherwise innocuous dictionary field.
        let safe = AgentDiagnosticsRedactor.sanitizeJSONObject(fields) as? [String: Any] ?? [:]
        return safe.reduce(into: [:]) { result, item in
            switch item.value {
            case let value as String:
                result[item.key] = value
            case let value as CustomStringConvertible:
                result[item.key] = value.description
            default:
                result[item.key] = String(describing: item.value)
            }
        }
    }

    private func describe(_ error: EncodingError) -> String {
        switch error {
        case .invalidValue(_, let context):
            return "invalidValue at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }
}

private struct TraceRecord: Encodable {
    let timestamp: Date
    let event: String
    let requestID: String?
    let conversationID: String?
    let modelStep: Int?
    let toolName: String?
    let fields: [String: String]
}
