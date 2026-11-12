import CryptoKit
import Foundation
import HanlinChatCore
import Security

/// Append-only companions of AgentDiagnosticsRecorder. All serialization,
/// encryption and disk I/O happen on its private queue, outside the stream/UI.
final class AgentDiagnosticsJournal: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.hanlin.agent-diagnostics.journal", qos: .utility)
    private let lock = NSLock()
    private var queuedBytes = 0
    private var rejectedBytes = 0
    private let baseURL: URL
    private let runID: UUID
    private let groupID: UUID
    private let full: Bool
    private let keyProvider: @Sendable () throws -> SymmetricKey
    private var key: SymmetricKey?
    private var sequence = 0
    private var storedBytes = 0
    private var droppedBytes = 0
    private var writeError: String?
    private var roundID: UUID?
    private var requests: [UUID: (round: UUID?, offset: Int, chunk: Int, pending: Data)] = [:]
    private var rawHasher = SHA256()
    private var lastCheckpoint = Date.distantPast
    private var initialized = false
    private var terminalStatus: String?
    private var readableSnapshots: [String: String] = [:]
    private var credentials: Set<String> = []
    private var snapshotBytes = 0
    private let queueBudget = 16 * 1024 * 1024
    private let diskBudget = 256 * 1024 * 1024

    init(baseURL: URL, runID: UUID, groupID: UUID, full: Bool,
         keyProvider: @escaping @Sendable () throws -> SymmetricKey = AgentDiagnosticsJournal.deviceKey) {
        self.baseURL = baseURL
        self.runID = runID
        self.groupID = groupID
        self.full = full
        self.keyProvider = keyProvider
    }

    var transportObserver: HanlinChatTransportObserver {
        { [self] event in
            let cost: Int
            switch event {
            case .bytes(_, let data): cost = data.count
            case .request(_, let request): cost = request.httpBody?.count ?? 0
            default: cost = 1024
            }
            enqueue(bytes: cost) { self.transport(event) }
        }
    }

    func setRound(_ id: UUID) { enqueue { self.roundID = id } }

    func stage(_ name: String, round: UUID? = nil, text: String, fields: [String: String] = [:]) {
        enqueue(bytes: text.utf8.count) {
            self.encrypted(Data(text.utf8), request: round ?? self.runID, kind: "stage_" + name)
            var record: [String: Any] = fields
            let snapshotKey = "\(round?.uuidString ?? "run").\(name)"
            if self.full && (name.hasSuffix(".content") || name.hasSuffix(".reasoning")) {
                self.updateSnapshot(snapshotKey, text: text)
            } else if self.full && name.hasSuffix("snapshot") {
                self.updateSnapshot(snapshotKey, text: text, replace: true)
            }
            // Individual deltas can split a credential across events. Exact
            // events stay encrypted; readable content uses coalesced snapshots
            // so redaction sees the complete string before publishing it.
            record["snapshotFile"] = self.baseURL.lastPathComponent + "-stage-snapshots.json"
            record["text"] = self.full && name.contains("request") ? AgentDiagnosticsRedactor.sanitize(text) : nil
            record["byteCount"] = text.utf8.count
            record["unicodeScalars"] = text.unicodeScalars.count
            record["sha256"] = Self.hash(Data(text.utf8))
            record["containsReplacementCharacter"] = text.contains("\u{FFFD}")
            self.event(name, round: round, fields: record)
        }
    }

    func checkpoint(status: String) async {
        await withCheckedContinuation { continuation in
            // The serial barrier drains all accepted events, including when the
            // normal queue budget is exhausted, before a terminal snapshot.
            queue.async {
                self.initialize()
                if status == "completed" || status == "failed" || status == "cancelled" { self.terminalStatus = status }
                self.event("checkpoint", fields: ["status": status])
                self.manifest(status: status)
                continuation.resume()
            }
        }
    }

    private func enqueue(bytes: Int = 0, _ operation: @escaping @Sendable () -> Void) {
        lock.lock()
        guard queuedBytes + bytes <= queueBudget else {
            rejectedBytes += bytes
            lock.unlock()
            return
        }
        queuedBytes += bytes
        lock.unlock()
        queue.async {
            self.initialize()
            operation()
            self.lock.lock()
            self.queuedBytes -= bytes
            self.lock.unlock()
            if Date().timeIntervalSince(self.lastCheckpoint) >= 1 {
                self.manifest(status: "recording_or_interrupted")
            }
        }
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        do {
            try FileManager.default.createDirectory(at: baseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var directory = baseURL.deletingLastPathComponent()
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            if full { key = try keyProvider() }
        } catch {
            // Fail closed: raw bytes are never written in plaintext on key loss.
            writeError = "initialization_failed_\((error as NSError).code)"
        }
    }

    private func transport(_ observation: HanlinChatTransportEvent) {
        switch observation {
        case .request(let id, let request):
            requests[id] = (roundID, 0, 0, Data())
            let body = request.httpBody ?? Data()
            let rawHeaders = request.allHTTPHeaderFields ?? [:]
            for (name, value) in rawHeaders where name.lowercased().contains("authorization") || name.lowercased().contains("api-key") {
                let secret = value.hasPrefix("Bearer ") ? String(value.dropFirst(7)) : value
                if secret.count >= 4 { credentials.insert(secret) }
            }
            let raw: [String: Any] = ["url": request.url?.absoluteString ?? "", "headers": rawHeaders,
                                      "method": request.httpMethod ?? "", "bodyBase64": body.base64EncodedString()]
            if let data = try? JSONSerialization.data(withJSONObject: raw) { encrypted(data, request: id, kind: "request") }
            let object = (try? JSONSerialization.jsonObject(with: body)) ?? [:]
            event("transport.request", request: id, fields: [
                "url": AgentDiagnosticsRedactor.sanitize(request.url?.absoluteString ?? ""),
                "headers": AgentDiagnosticsRedactor.sanitizeJSONObject(rawHeaders),
                "body": full ? AgentDiagnosticsRedactor.sanitizeJSONObject(object) : [:],
                "bodyBytes": body.count, "rawSHA256": Self.hash(body),
                "boundaryKind": "adapter_delivery_not_TLS_packet"
            ])
        case .response(let id, let response):
            let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                result[String(describing: entry.key)] = String(describing: entry.value)
            }
            event("transport.response", request: id, fields: ["status": response.statusCode,
                "headers": AgentDiagnosticsRedactor.sanitizeJSONObject(headers)])
        case .bytes(let id, let data):
            guard var state = requests[id] else { return }
            encrypted(data, request: id, kind: "response_chunk")
            event("transport.bytes", request: id, fields: ["offset": state.offset, "chunkIndex": state.chunk,
                "byteCount": data.count, "rawSHA256": Self.hash(data)])
            state.offset += data.count
            state.chunk += 1
            if full {
                state.pending.append(data)
                // Decode only complete UTF-8 lines; a network split within an
                // emoji or RTL scalar never introduces a replacement character.
                while let newline = state.pending.firstIndex(of: 0x0A) {
                    let line = Data(state.pending[...newline])
                    state.pending.removeSubrange(...newline)
                    decodedLine(line, request: id)
                }
                if state.pending.count > queueBudget {
                    droppedBytes += state.pending.count
                    event("capture.warning", request: id, fields: ["reason": "oversized_unterminated_SSE_line",
                        "droppedByteCount": state.pending.count, "exactBytesInEncryptedSidecar": true])
                    state.pending.removeAll()
                }
            }
            requests[id] = state
        case .end(let id, let error):
            if let pending = requests[id]?.pending, !pending.isEmpty { decodedLine(pending, request: id, partial: true) }
            event("transport.end", request: id, fields: ["error": error.map(AgentDiagnosticsRedactor.sanitize) ?? "",
                "byteCount": requests[id]?.offset ?? 0, "status": error == nil ? "EOF" : "error_or_cancel"])
            requests.removeValue(forKey: id)
            manifest(status: "recording_or_interrupted")
        }
    }

    private func decodedLine(_ bytes: Data, request: UUID, partial: Bool = false) {
        let valid = String(data: bytes, encoding: .utf8)
        let text = valid ?? String(decoding: bytes, as: UTF8.self)
        let payload = text.hasPrefix("data:") ? String(text.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines) : text
        let object = payload.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        let safePayload = object.map { snapshotSSE($0, request: request, path: "response") }
        event("SSE.line", request: request, fields: [
            "payload": safePayload ?? (payload == "[DONE]" ? "[DONE]" : "<exact unparsed source in encrypted raw>"),
            "rawSHA256": Self.hash(bytes), "validUTF8": valid != nil,
            "containsReplacementCharacter": text.contains("\u{FFFD}"), "partialAtEOF": partial
        ])
    }

    private func snapshotSSE(_ object: Any, request: UUID, path: String) -> Any {
        if let values = object as? [String: Any] {
            return values.reduce(into: [String: Any]()) { result, entry in
                let key = "\(request.uuidString).\(path).\(entry.key)"
                if let text = entry.value as? String,
                   ["content", "text", "reasoning", "reasoning_content", "thinking", "arguments", "partial_json"].contains(entry.key) {
                    updateSnapshot(key, text: text)
                    result[entry.key] = "<see stage-snapshots.json: \(key)>"
                } else { result[entry.key] = snapshotSSE(entry.value, request: request, path: path + "." + entry.key) }
            }
        }
        if let values = object as? [Any] {
            return values.enumerated().map { snapshotSSE($0.element, request: request, path: path + "." + String($0.offset)) }
        }
        return AgentDiagnosticsRedactor.sanitizeJSONObject(object)
    }

    private func updateSnapshot(_ key: String, text: String, replace: Bool = false) {
        let previous = replace ? readableSnapshots[key]?.utf8.count ?? 0 : 0
        guard snapshotBytes - previous + text.utf8.count <= 32 * 1024 * 1024 else {
            droppedBytes += text.utf8.count
            return
        }
        snapshotBytes += text.utf8.count - previous
        if replace { readableSnapshots[key] = text } else { readableSnapshots[key, default: ""] += text }
    }

    private func encrypted(_ bytes: Data, request: UUID, kind: String) {
        guard full else { return }
        guard let key else { droppedBytes += bytes.count; return }
        do {
            let header = "\(runID.uuidString)|\(request.uuidString)|\(sequence)|\(kind)"
            let sealed = try AES.GCM.seal(bytes, using: key, authenticating: Data(header.utf8))
            guard let combined = sealed.combined else { throw CocoaError(.fileWriteUnknown) }
            let frame: [String: Any] = ["schemaVersion": 1, "aad": header, "combined": combined.base64EncodedString(),
                "byteCount": bytes.count, "sha256": Self.hash(bytes)]
            var line = try JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys])
            line.append(0x0A)
            if append(line, suffix: ".raw.enc") { rawHasher.update(data: line) }
        } catch { writeError = "encryption_failed_\((error as NSError).code)"; droppedBytes += bytes.count }
    }

    private func event(_ stage: String, request: UUID? = nil, round: UUID? = nil, fields: [String: Any] = [:]) {
        sequence += 1
        var record = fields
        record["schemaVersion"] = 1
        record["sequence"] = sequence
        record["stage"] = stage
        record["runID"] = runID.uuidString
        record["groupID"] = groupID.uuidString
        record["roundID"] = (round ?? request.flatMap { requests[$0]?.round } ?? roundID)?.uuidString
        record["attemptID"] = request?.uuidString
        record["timestamp"] = Date().timeIntervalSince1970
        record["monotonic"] = ProcessInfo.processInfo.systemUptime
        let safe = AgentDiagnosticsRedactor.redactKnownCredentials(in: AgentDiagnosticsRedactor.sanitizeJSONObject(record), credentials: credentials)
        if var line = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys, .fragmentsAllowed]) {
            line.append(0x0A)
            _ = append(line, suffix: "-stage-events.jsonl")
        }
    }

    @discardableResult private func append(_ data: Data, suffix: String) -> Bool {
        guard storedBytes + data.count <= diskBudget else { droppedBytes += data.count; return false }
        let url = URL(filePath: baseURL.path + suffix)
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            storedBytes += data.count
            return true
        } catch { writeError = "write_failed_\((error as NSError).code)"; droppedBytes += data.count; return false }
    }

    private func manifest(status: String) {
        var digestState = rawHasher
        let rawDigest = digestState.finalize().map { String(format: "%02x", $0) }.joined()
        lock.lock()
        let rejected = rejectedBytes
        lock.unlock()
        let manifest: [String: Any] = ["schemaVersion": 1, "runID": runID.uuidString, "groupID": groupID.uuidString,
            "status": terminalStatus ?? status, "lastSequence": sequence, "storedBytes": storedBytes,
            "droppedByteCount": droppedBytes + rejected, "truncated": droppedBytes + rejected > 0,
            "captureError": writeError ?? "", "encryptedRaw": full,
            "rawFile": baseURL.lastPathComponent + ".raw.enc",
            "eventsFile": baseURL.lastPathComponent + "-stage-events.jsonl",
            "snapshotsFile": baseURL.lastPathComponent + "-stage-snapshots.json",
            "rawFileSHA256": rawDigest,
            "encryption": "AES-256-GCM, per-record nonce and authenticated aad; device-only Keychain key",
            "sharing": "Local only. Raw decryption/sharing requires deliberate user action.",
            "diskBudgetBytes": diskBudget, "queueBudgetBytes": queueBudget]
        do {
            if full {
                var snapshots = readableSnapshots.mapValues(AgentDiagnosticsRedactor.sanitize)
                for (name, value) in snapshots {
                    var safe = value
                    for credential in credentials { safe = safe.replacingOccurrences(of: credential, with: "<redacted>") }
                    snapshots[name] = safe
                }
                let snapshotData = try JSONSerialization.data(withJSONObject: snapshots, options: [.prettyPrinted, .sortedKeys])
                try snapshotData.write(to: URL(filePath: baseURL.path + "-stage-snapshots.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(filePath: baseURL.path + "-manifest.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { writeError = "manifest_failed_\((error as NSError).code)" }
        lastCheckpoint = Date()
    }

    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func deviceKey() throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.hanlin.agent-diagnostics.raw.v1", kSecAttrAccount as String: "device-key"]
        var result: CFTypeRef?
        var lookup = query
        lookup[kSecReturnData as String] = true
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let bytes = result as? Data, bytes.count == 32 { return SymmetricKey(data: bytes) }
        guard status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        let generated = SymmetricKey(size: .bits256)
        var insert = query
        insert[kSecValueData as String] = generated.withUnsafeBytes { Data($0) }
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        if added == errSecDuplicateItem { return try deviceKey() }
        guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
        return generated
    }
}
