import Foundation

enum RuntimeJobState: String, Codable, Sendable {
    case queued, running, completed, failed, cancelled, interrupted
    var isTerminal: Bool { [.completed, .failed, .cancelled, .interrupted].contains(self) }
}

struct RuntimeJobSnapshot: Codable, Sendable {
    let executionID: UUID
    var state: RuntimeJobState
    let startedAt: Double
    var completedAt: Double?
    var cancellationRequested: Bool
    var stdoutBytes: Int64
    var stderrBytes: Int64
    var result: RuntimeExecutionResult?
    var error: String?
}

enum RuntimeJobProgress {
    typealias Reporter = @MainActor @Sendable (RuntimeJobSnapshot) -> Void
    @TaskLocal static var reporter: Reporter?
}

/// One journal contract for native engines. Node writes the same header through its Host.
/// Results are loaded on request; starting the app never reads every historical output.
actor RuntimeJobStore {
    private let fileLayout: RuntimeFileLayout
    private var recovered: Set<RuntimeKind> = []

    init(fileLayout: RuntimeFileLayout = .default) { self.fileLayout = fileLayout }

    nonisolated func directory(id: UUID, kind: RuntimeKind) -> URL {
        let engine = kind == .typeScript ? RuntimeKind.node : kind
        return fileLayout.root.appending(path: "jobs/\(engine.rawValue)/\(id.uuidString.lowercased())", directoryHint: .isDirectory)
    }

    func recoverInterrupted(_ kind: RuntimeKind) throws {
        guard !recovered.contains(kind) else { return }
        let root = directory(id: UUID(), kind: kind).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: root.path) {
            for entry in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                guard let id = UUID(uuidString: entry.lastPathComponent),
                      var snapshot = try snapshot(id: id, kind: kind), !snapshot.state.isTerminal else { continue }
                snapshot.state = .interrupted
                snapshot.error = "The app process ended before this job completed. Partial output is retained. Side effects are not replayed automatically."
                try write(snapshot, kind: kind)
            }
        }
        recovered.insert(kind)
    }

    func create(id: UUID, kind: RuntimeKind) throws -> RuntimeJobSnapshot {
        try recoverInterrupted(kind)
        guard try snapshot(id: id, kind: kind) == nil else { throw RuntimeCoreError.invalidRequest("This job ID already exists; jobs are not replayed implicitly.") }
        try FileManager.default.createDirectory(at: directory(id: id, kind: kind), withIntermediateDirectories: true)
        let record = RuntimeJobSnapshot(executionID: id, state: .queued, startedAt: Date().timeIntervalSince1970 * 1000,
            cancellationRequested: false, stdoutBytes: 0, stderrBytes: 0)
        try write(record, kind: kind)
        return record
    }

    func markRunning(id: UUID, kind: RuntimeKind) throws {
        guard var record = try snapshot(id: id, kind: kind), !record.state.isTerminal else { return }
        record.state = .running
        try write(record, kind: kind)
    }

    func refresh(id: UUID, kind: RuntimeKind) throws -> RuntimeJobSnapshot? {
        guard var record = try snapshot(id: id, kind: kind), !record.state.isTerminal else {
            return try snapshot(id: id, kind: kind)
        }
        for channel in ["stdout", "stderr"] {
            let file = directory(id: id, kind: kind).appending(path: channel + ".log")
            let bytes: Int64
            if FileManager.default.fileExists(atPath: file.path) {
                bytes = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
            } else { bytes = 0 }
            if channel == "stdout" { record.stdoutBytes = bytes } else { record.stderrBytes = bytes }
        }
        try write(record, kind: kind)
        return record
    }

    func requestCancellation(id: UUID, kind: RuntimeKind) throws {
        guard var record = try snapshot(id: id, kind: kind), !record.state.isTerminal else { return }
        record.cancellationRequested = true
        try write(record, kind: kind)
    }

    func complete(_ result: RuntimeExecutionResult, kind: RuntimeKind) throws {
        guard var record = try snapshot(id: result.executionID, kind: kind) else { throw RuntimeCoreError.invalidIdentifier }
        record.state = result.wasCancelled ? .cancelled : result.didTimeOut || result.exitCode != 0 ? .failed : .completed
        record.result = result
        record.stdoutBytes = result.outputFiles?["stdout"]?.bytes ?? Int64(result.stdout.utf8.count)
        record.stderrBytes = result.outputFiles?["stderr"]?.bytes ?? Int64(result.stderr.utf8.count)
        record.completedAt = Date().timeIntervalSince1970 * 1000
        try write(record, kind: kind)
    }

    func fail(id: UUID, kind: RuntimeKind, error: Error) throws {
        guard var record = try snapshot(id: id, kind: kind) else { return }
        record.state = error is CancellationError ? .cancelled : .failed
        record.error = error.localizedDescription
        record.completedAt = Date().timeIntervalSince1970 * 1000
        try write(record, kind: kind)
    }

    func snapshot(id: UUID, kind: RuntimeKind) throws -> RuntimeJobSnapshot? {
        let file = directory(id: id, kind: kind).appending(path: "job.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let snapshot = try JSONDecoder().decode(RuntimeJobSnapshot.self, from: Data(contentsOf: file))
        guard snapshot.executionID == id else { throw RuntimeCoreError.invalidIdentifier }
        return snapshot
    }

    func output(id: UUID, kind: RuntimeKind, channel: String, offset: Int64, limit: Int) throws -> [String: String] {
        guard ["stdout", "stderr"].contains(channel), offset >= 0, limit > 0,
              try snapshot(id: id, kind: kind) != nil else { throw RuntimeCoreError.invalidRequest("Invalid job output request.") }
        let url = directory(id: id, kind: kind).appending(path: channel + ".log")
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let total = try file.seekToEnd()
        try file.seek(toOffset: UInt64(offset))
        let data = try file.read(upToCount: min(limit, 65_536)) ?? Data()
        return ["base64": data.base64EncodedString(), "offset": String(offset), "nextOffset": String(offset + Int64(data.count)), "totalBytes": String(total), "hasMore": String(UInt64(offset) + UInt64(data.count) < total)]
    }

    private func write(_ record: RuntimeJobSnapshot, kind: RuntimeKind) throws {
        let data = try JSONEncoder().encode(record)
        try data.write(to: directory(id: record.executionID, kind: kind).appending(path: "job.json"), options: .atomic)
    }
}
