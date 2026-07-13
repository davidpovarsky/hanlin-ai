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
            self.rotateLogsIfNeeded()
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
            event: event,
            requestID: requestID,
            conversationID: conversationID,
            modelStep: modelStep,
            toolName: toolName,
            fields: redact(stringify(fields))
        )

        queue.async { [weak self] in
            guard let self else { return }
            do {
                if self.activeFileURL == nil { self.prepareDirectoryAndFile() }
                guard let url = self.activeFileURL else { return }
                var data = try self.encoder.encode(record)
                data.append(0x0A)
                if !self.fileManager.fileExists(atPath: url.path) {
                    try data.write(to: url, options: .atomic)
                } else {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                }
                self.logger.debug("\(event, privacy: .public)")
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
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return json
        }
        let redacted = redactJSONValue(object)
        guard JSONSerialization.isValidJSONObject(redacted),
              let output = try? JSONSerialization.data(withJSONObject: redacted),
              let string = String(data: output, encoding: .utf8) else {
            return "<unserializable-json>"
        }
        return string
    }

    private func prepareDirectoryAndFile() {
        guard let directory = diagnosticsDirectoryURL else { return }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            activeFileURL = directory.appendingPathComponent("Hanlin-Chat-\(formatter.string(from: Date())).jsonl")
        } catch {
            logger.error("Unable to prepare diagnostics directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rotateLogsIfNeeded() {
        guard let directory = diagnosticsDirectoryURL,
              let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else { return }

        let sorted = files.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }

        var totalBytes = 0
        for (index, file) in sorted.enumerated() {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            totalBytes += size
            if index >= 30 || totalBytes > 20 * 1024 * 1024 {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func stringify(_ fields: [String: Any]) -> [String: String] {
        fields.reduce(into: [:]) { result, item in
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

    private func redact(_ fields: [String: String]) -> [String: String] {
        let sensitive = ["api_key", "apikey", "authorization", "token", "access_token", "refresh_token", "cookie", "secret", "password"]
        return fields.reduce(into: [:]) { result, item in
            let key = item.key.lowercased()
            result[item.key] = sensitive.contains(where: key.contains) ? "<redacted>" : item.value
        }
    }

    private func redactJSONValue(_ value: Any) -> Any {
        let sensitive = ["api_key", "apikey", "authorization", "token", "access_token", "refresh_token", "cookie", "secret", "password"]
        if let dict = value as? [String: Any] {
            return dict.reduce(into: [String: Any]()) { result, item in
                let key = item.key.lowercased()
                if sensitive.contains(where: key.contains) {
                    result[item.key] = "<redacted>"
                } else {
                    result[item.key] = redactJSONValue(item.value)
                }
            }
        }
        if let array = value as? [Any] {
            return array.map { redactJSONValue($0) }
        }
        return value
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
