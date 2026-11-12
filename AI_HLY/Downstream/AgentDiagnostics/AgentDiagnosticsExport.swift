import CryptoKit
import Darwin
import Foundation
import ZIPFoundation

struct AgentDiagnosticsExport: Sendable, Identifiable {
    var id: URL { directory }
    let directory: URL
    let archive: URL
    let preview: String
    let includedFiles: [String]
    let missingFiles: [String]
    let conversationPreview: String

    func discard() { try? FileManager.default.removeItem(at: directory) }
}

/// User-initiated, local-only exports. Never copies the device key or encrypted
/// vault into a normal share, and never follows session-owned symlinks.
enum AgentDiagnosticsExporter {
    private static let suffixes = [".json", ".txt", "-manifest.json", "-stage-events.jsonl", "-stage-snapshots.json"]
    private static let maximumFileBytes = 64 * 1024 * 1024
    private static let maximumExportBytes = 256 * 1024 * 1024

    static func prepareLocally(sessionJSON: URL) async throws -> AgentDiagnosticsExport {
        let work = Task.detached(priority: .utility) { try prepare(sessionJSON: sessionJSON) }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: { work.cancel() }
    }

    static func prepare(sessionJSON: URL) throws -> AgentDiagnosticsExport {
        let fm = FileManager.default
        let source = sessionJSON.deletingPathExtension()
        guard sessionJSON.pathExtension == "json", source.lastPathComponent.hasPrefix("agent-session-"),
              source.lastPathComponent.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
              !source.lastPathComponent.hasSuffix("-manifest"), !source.lastPathComponent.hasSuffix("-stage-snapshots") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let directory = fm.temporaryDirectory.appending(path: "hanlin-diagnostics-export-" + UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedDirectory = directory
        try protectedDirectory.setResourceValues(values)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        do {
            let archiveURL = directory.appending(path: "diagnostics-sanitized.zip")
            let archive = try Archive(url: archiveURL, accessMode: .create)
            var included: [String] = [], missing: [String] = []
            var records: [[String: Any]] = [], total = 0
            var capture: [String: Any] = [:]
            var session: [String: Any] = [:]
            var conversationPreview = ""
            for suffix in suffixes {
                try Task.checkCancellation()
                let input = URL(filePath: source.path + suffix)
                let name = source.lastPathComponent + suffix
                guard fm.fileExists(atPath: input.path) else { missing.append(name); continue }
                let attributes = try fm.attributesOfItem(atPath: input.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      input.resolvingSymlinksInPath().deletingLastPathComponent() == source.deletingLastPathComponent().resolvingSymlinksInPath() else {
                    throw CocoaError(.fileReadNoPermission)
                }
                let size = (attributes[.size] as? NSNumber)?.intValue ?? maximumFileBytes + 1
                guard size <= maximumFileBytes, total + size <= maximumExportBytes else {
                    throw CocoaError(.fileReadTooLarge)
                }
                let data = try readOwnedAsset(input)
                guard data.count <= maximumFileBytes, total + data.count <= maximumExportBytes,
                      let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
                let sanitized: Data
                if suffix.hasSuffix(".jsonl") {
                    // Redact complete JSON records, never deltas in isolation.
                    // A partial crash tail is omitted and explicitly reported.
                    var lines = Data()
                    let parts = text.split(separator: "\n", omittingEmptySubsequences: true)
                    for (index, line) in parts.enumerated() {
                        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else {
                            guard index == parts.count - 1, !text.hasSuffix("\n") else { throw CocoaError(.fileReadCorruptFile) }
                            missing.append(name + ": incomplete final event omitted")
                            break
                        }
                        lines.append(try JSONSerialization.data(withJSONObject: AgentDiagnosticsRedactor.sanitizeJSONObject(object), options: [.sortedKeys]))
                        lines.append(0x0A)
                    }
                    sanitized = lines
                } else if suffix.hasSuffix(".json") {
                    let object = try JSONSerialization.jsonObject(with: data)
                    let safe = AgentDiagnosticsRedactor.sanitizeJSONObject(object)
                    sanitized = try JSONSerialization.data(withJSONObject: safe, options: [.prettyPrinted, .sortedKeys])
                    if suffix == "-manifest.json" { capture = safe as? [String: Any] ?? [:] }
                    if suffix == ".json" { session = safe as? [String: Any] ?? [:] }
                } else {
                    sanitized = Data(AgentDiagnosticsRedactor.sanitize(text).utf8)
                    conversationPreview = String(String(decoding: sanitized, as: UTF8.self).prefix(65_536))
                }
                total += sanitized.count
                guard total <= maximumExportBytes else { throw CocoaError(.fileReadTooLarge) }
                try add(sanitized, named: name, to: archive)
                included.append(name)
                records.append(["name": name, "bytes": sanitized.count, "sha256": hash(sanitized),
                                "sourceSHA256": hash(data), "redactionChangedBytes": data != sanitized])
            }
            guard included.contains(source.lastPathComponent + ".json") else { throw CocoaError(.fileNoSuchFile) }
            let summary = """
            Sanitized diagnostic export
            This archive contains conversation text, prompts and tool content. Review before sharing.
            Credentials are redacted again during export. Encrypted raw bytes and the device key are excluded.
            Included files: \(included.count). Missing/incomplete assets: \(missing.count).
            Capture status: \(capture["status"] as? String ?? "legacy capture; coverage unknown").
            Dropped bytes: \(capture["droppedByteCount"] as? Int ?? 0). Capture error: \(capture["captureError"] as? String ?? "unknown").
            Source hashes describe local files; exported hashes describe the sanitized bytes.
            Files are read independently; a running session may advance during export.
            Compare stage snapshots with Scripts/Diagnostics/compare_chat_stages.py from the matching repository.
            No network request or tool execution is performed by export. Actual rendered UI parity is not verified.
            """
            let provenance = (session["buildProvenanceJSON"] as? String)?.data(using: .utf8)
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let manifest: [String: Any] = [
                "schemaVersion": 1, "createdAt": ISO8601DateFormatter().string(from: Date()),
                "kind": "sanitized", "rawIncluded": false, "keyIncluded": false,
                "redactionApplied": true, "files": records, "missingOrIncomplete": missing,
                "capture": capture, "snapshotConsistency": "independent files; live session may advance",
                "appVersion": session["appVersion"] ?? "unavailable", "buildNumber": session["buildNumber"] ?? "unavailable",
                "buildProvenance": provenance,
                "captureEnvironment": session["captureEnvironment"] ?? "unavailable in legacy recording",
                "exportEnvironment": ["os": ProcessInfo.processInfo.operatingSystemVersionString, "locale": Locale.current.identifier],
                "model": session["modelID"] ?? "unavailable", "provider": session["providerID"] ?? "unavailable",
                "sessionSchemaVersion": session["schemaVersion"] ?? 2,
                "uiParity": "NOT_VERIFIED", "networkOrToolExecution": false
            ]
            try add(try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]), named: "export-manifest.json", to: archive)
            try add(Data(summary.utf8), named: "README.txt", to: archive)
            return AgentDiagnosticsExport(directory: directory, archive: archiveURL, preview: summary, includedFiles: included, missingFiles: missing, conversationPreview: conversationPreview)
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }

    private static func add(_ data: Data, named name: String, to archive: Archive) throws {
        try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
            let start = Int(position)
            return data.subdata(in: start ..< min(start + size, data.count))
        }
    }

    private static func readOwnedAsset(_ url: URL) throws -> Data {
        // Keep the opened inode, even if a live recorder atomically replaces
        // its path. O_NOFOLLOW closes the lstat/open symlink substitution race.
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              status.st_size >= 0, status.st_size <= maximumFileBytes else { throw CocoaError(.fileReadTooLarge) }
        var result = Data()
        let expected = Int(status.st_size)
        while result.count < expected {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: min(65_536, expected - result.count)), !chunk.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            result.append(chunk)
        }
        return result
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
