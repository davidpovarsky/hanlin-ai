import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

public enum HanlinProductTransferError: Error, Equatable, Sendable {
    case busy
    case restartRequired
    case unsafePath
    case invalidCheckpoint
    case destinationConflict
    case recoveryConflict
    case anotherTransferPending
    case rollbackWouldLoseChanges
}

public struct HanlinProductTransferReceipt: Codable, Equatable, Sendable {
    public let id: UUID
    public let packageCount: Int
    public let fileCount: Int
    public let byteCount: Int64
}

public enum HanlinProductTransferFaultPoint: String, CaseIterable, Sendable {
    case intentPersisted, installedBackedUp, installedPromoted, dataBackedUp, dataPromoted
    case committed, rollbackIntentPersisted, installedRestored, dataRestored
}

public protocol HanlinProductTransferFaultInjector: Sendable {
    func check(_ point: HanlinProductTransferFaultPoint) throws
}

public struct HanlinNoProductTransferFaults: HanlinProductTransferFaultInjector {
    public init() {}
    public func check(_: HanlinProductTransferFaultPoint) throws {}
}

/// These manifests describe actual owned files, not fixture snapshots.
/// Bytes are streamed for hashes and copied to a private staging directory.
struct HanlinTransferTree: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        let bytes: Int64
        let sha256: String
    }

    var exists: Bool
    var directories: Set<String>
    var files: [String: File]

    static func capture(_ root: URL, durableSQLiteData: Bool = false) throws -> Self {
        let manager = FileManager.default
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try manager.attributesOfItem(atPath: root.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return Self(exists: false, directories: [], files: [:])
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw HanlinProductTransferError.unsafePath
        }
        var failed = false
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: keys,
            options: [], errorHandler: { _, _ in failed = true; return false }) else {
            throw HanlinProductTransferError.invalidCheckpoint
        }
        var result = Self(exists: true, directories: [], files: [:])
        let prefix = root.standardizedFileURL.path + "/"
        for case let item as URL in enumerator {
            guard item.standardizedFileURL.path.hasPrefix(prefix) else {
                throw HanlinProductTransferError.unsafePath
            }
            let path = String(item.standardizedFileURL.path.dropFirst(prefix.count))
            _ = try child(root, path)
            let values = try item.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else { throw HanlinProductTransferError.unsafePath }
            if values.isDirectory == true {
                result.directories.insert(path)
            } else if values.isRegularFile == true {
                result.files[path] = try fingerprint(item)
            } else {
                throw HanlinProductTransferError.unsafePath
            }
        }
        guard !failed else { throw HanlinProductTransferError.invalidCheckpoint }
        guard durableSQLiteData else { return result }
        // SQLite's WAL index is shared-memory coordination, not durable data.
        // Apple's VFS may retain it and an empty WAL after the last clean close;
        // even a read-only reopen changes that index. Keep every database byte
        // and every nonempty WAL. Only omit reserved sidecars of an actual
        // WAL-format SQLite database, after validating the entire tree above.
        // https://www.sqlite.org/walformat.html
        for (path, file) in result.files {
            guard path.hasSuffix("-shm") || (path.hasSuffix("-wal") && file.bytes == 0) else { continue }
            let databasePath = String(path.dropLast(4))
            guard let database = result.files[databasePath], database.bytes >= 100 else { continue }
            let stream = try FileHandle(forReadingFrom: child(root, databasePath))
            let header: Data
            do {
                header = try stream.read(upToCount: 20) ?? Data()
                try stream.close()
            } catch {
                try? stream.close()
                throw error
            }
            guard header.count == 20,
                  header.prefix(16) == Data("SQLite format 3\0".utf8),
                  header[18] == 2, header[19] == 2 else { continue }
            result.files.removeValue(forKey: path)
        }
        return result
    }

    static func fingerprint(_ url: URL) throws -> File {
        let stream = try FileHandle(forReadingFrom: url)
        defer { try? stream.close() }
        var hash = SHA256()
        var bytes: Int64 = 0
        while let chunk = try stream.read(upToCount: 1_048_576), !chunk.isEmpty {
            bytes += Int64(chunk.count)
            hash.update(data: chunk)
        }
        return File(bytes: bytes, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }

    static func child(_ root: URL, _ path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.contains("\\"), !path.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw HanlinProductTransferError.unsafePath
        }
        return parts.reduce(root) { $0.appending(path: String($1)) }
    }

    func copy(from source: URL, to destination: URL, excluding: Set<String> = []) throws {
        guard exists else { return }
        let manager = FileManager.default
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        for path in directories.sorted() {
            try manager.createDirectory(at: Self.child(destination, path), withIntermediateDirectories: true)
        }
        for (path, expected) in files.sorted(by: { $0.key < $1.key }) where !excluding.contains(path) {
            let output = try Self.child(destination, path)
            if manager.fileExists(atPath: output.path) {
                guard try Self.fingerprint(output) == expected else {
                    throw HanlinProductTransferError.destinationConflict
                }
            } else {
                try manager.copyItem(at: Self.child(source, path), to: output)
                guard try Self.fingerprint(output) == expected else {
                    throw HanlinProductTransferError.invalidCheckpoint
                }
            }
        }
    }

    static func validateMerge(_ first: Self, _ second: Self, excluding: Set<String> = []) throws {
        let directories = first.directories.union(second.directories)
        let files = Set(first.files.keys).union(second.files.keys)
        guard directories.isDisjoint(with: files) else { throw HanlinProductTransferError.destinationConflict }
        for (path, file) in first.files where !excluding.contains(path) {
            if let other = second.files[path], other != file {
                throw HanlinProductTransferError.destinationConflict
            }
        }
    }
}

struct HanlinTransferCheckpoint: Codable, Equatable, Sendable {
    let version: Int
    let receipt: HanlinProductTransferReceipt
    let installed: HanlinTransferTree
    let data: HanlinTransferTree

    static func read(_ root: URL) throws -> Self {
        // Reject a linked checkpoint root or any linked descendant before
        // following the manifest's fixed Installed/MiniApps children.
        guard try HanlinTransferTree.capture(root).exists else {
            throw HanlinProductTransferError.invalidCheckpoint
        }
        let value = try JSONDecoder().decode(Self.self,
            from: Data(contentsOf: root.appending(path: "checkpoint.json")))
        guard value.version == 1,
              value.receipt.packageCount >= 0,
              value.installed.exists,
              try HanlinTransferTree.capture(root.appending(path: "Installed")) == value.installed,
              try HanlinTransferTree.capture(root.appending(path: "MiniApps"), durableSQLiteData: true) == value.data,
              value.receipt.fileCount == value.installed.files.count + value.data.files.count,
              value.receipt.byteCount == value.installed.files.values.reduce(0, { $0 + $1.bytes })
                + value.data.files.values.reduce(0, { $0 + $1.bytes }) else {
            throw HanlinProductTransferError.invalidCheckpoint
        }
        return value
    }

    static func publish(installedRoot: URL, dataRoot: URL, outbox: URL,
                        packageCount: Int) throws -> Self {
        try HanlinProductTransferRecovery.distinct([installedRoot, dataRoot, outbox])
        let installed = try HanlinTransferTree.capture(installedRoot)
        let data = try HanlinTransferTree.capture(dataRoot, durableSQLiteData: true)
        let latest = outbox.appending(path: "latest.json")
        if let bytes = try? Data(contentsOf: latest),
           let previous = try? JSONDecoder().decode(HanlinProductTransferReceipt.self, from: bytes),
           let saved = try? read(outbox.appending(path: previous.id.uuidString.lowercased())),
           saved.installed == installed, saved.data == data,
           saved.receipt.packageCount == packageCount {
            return saved
        }
        let receipt = HanlinProductTransferReceipt(id: UUID(), packageCount: packageCount,
            fileCount: installed.files.count + data.files.count,
            byteCount: installed.files.values.reduce(0, { $0 + $1.bytes })
                + data.files.values.reduce(0, { $0 + $1.bytes }))
        let checkpoint = Self(version: 1, receipt: receipt, installed: installed, data: data)
        let manager = FileManager.default
        try manager.createDirectory(at: outbox, withIntermediateDirectories: true)
        let staging = outbox.appending(path: ".preparing-" + receipt.id.uuidString.lowercased())
        let final = outbox.appending(path: receipt.id.uuidString.lowercased())
        try installed.copy(from: installedRoot, to: staging.appending(path: "Installed"))
        try data.copy(from: dataRoot, to: staging.appending(path: "MiniApps"))
        try JSONEncoder().encode(checkpoint).write(to: staging.appending(path: "checkpoint.json"), options: .atomic)
        guard try read(staging) == checkpoint,
              try HanlinTransferTree.capture(installedRoot) == installed,
              try HanlinTransferTree.capture(dataRoot, durableSQLiteData: true) == data else {
            throw HanlinProductTransferError.invalidCheckpoint
        }
        try manager.moveItem(at: staging, to: final)
        // A failed index write leaves only a complete, addressable checkpoint.
        try JSONEncoder().encode(receipt).write(to: outbox.appending(path: "latest.json"), options: .atomic)
        return checkpoint
    }
}

/// A write-ahead journal covers both owned roots. Recovery runs before either
/// store is initialized. Source user data stays in its original store; normal
/// SQLite connection closure may checkpoint its WAL before the immutable copy.
public enum HanlinProductTransferRecovery {
    struct Journal: Codable, Sendable {
        enum State: String, Codable, Sendable { case committing, committed, rollingBack, rolledBack }
        let version: Int
        let checkpoint: HanlinTransferCheckpoint
        let beforeInstalled: HanlinTransferTree
        let afterInstalled: HanlinTransferTree
        let beforeData: HanlinTransferTree
        let afterData: HanlinTransferTree
        var state: State
    }

    public static func checkpointReceipt(at checkpointRoot: URL) throws -> HanlinProductTransferReceipt {
        try HanlinStoreFileAccess.withExclusiveAccess {
            try HanlinTransferCheckpoint.read(checkpointRoot).receipt
        }
    }

    public static func committedReceipt(at transactionRoot: URL) throws -> HanlinProductTransferReceipt? {
        try HanlinStoreFileAccess.withExclusiveAccess {
            guard let value = try load(transactionRoot), value.state == .committed else { return nil }
            return value.checkpoint.receipt
        }
    }

    public static func recover(installedRoot: URL, dataRoot: URL, transactionRoot: URL,
        faults: any HanlinProductTransferFaultInjector = HanlinNoProductTransferFaults()) throws {
        try HanlinStoreFileAccess.withExclusiveAccess {
            try distinct([installedRoot, dataRoot, transactionRoot])
            guard var journal = try load(transactionRoot) else { return }
            switch journal.state {
            case .committing:
                HanlinSQLiteService.closeConnections(under: dataRoot)
                try promote(current: installedRoot, stage: transactionRoot.appending(path: "new-installed"),
                    backup: transactionRoot.appending(path: "old-installed"),
                    before: journal.beforeInstalled, after: journal.afterInstalled,
                    afterBackup: .installedBackedUp, afterPromotion: .installedPromoted, faults: faults)
                try promote(current: dataRoot, stage: transactionRoot.appending(path: "new-data"),
                    backup: transactionRoot.appending(path: "old-data"),
                    before: journal.beforeData, after: journal.afterData,
                    afterBackup: .dataBackedUp, afterPromotion: .dataPromoted,
                    durableSQLiteData: true, faults: faults)
                journal.state = .committed
                try persist(journal, at: transactionRoot)
                try faults.check(.committed)
            case .rollingBack:
                HanlinSQLiteService.closeConnections(under: dataRoot)
                try restore(current: installedRoot, backup: transactionRoot.appending(path: "old-installed"),
                    retained: transactionRoot.appending(path: "rolled-forward-installed"),
                    before: journal.beforeInstalled, after: journal.afterInstalled)
                try faults.check(.installedRestored)
                try restore(current: dataRoot, backup: transactionRoot.appending(path: "old-data"),
                    retained: transactionRoot.appending(path: "rolled-forward-data"),
                    before: journal.beforeData, after: journal.afterData, durableSQLiteData: true)
                try faults.check(.dataRestored)
                journal.state = .rolledBack
                try persist(journal, at: transactionRoot)
            case .committed, .rolledBack:
                // Later user edits belong to the live store. A normal launch
                // must never replace them with the checkpoint's older bytes.
                break
            }
        }
    }

    public static func rollback(installedRoot: URL, dataRoot: URL, transactionRoot: URL,
        faults: any HanlinProductTransferFaultInjector = HanlinNoProductTransferFaults()) throws {
        try HanlinStoreFileAccess.withExclusiveAccess {
            try recover(installedRoot: installedRoot, dataRoot: dataRoot, transactionRoot: transactionRoot)
            guard var journal = try load(transactionRoot) else { throw HanlinProductTransferError.invalidCheckpoint }
            if journal.state == .rolledBack { return }
            HanlinSQLiteService.closeConnections(under: dataRoot)
            guard journal.state == .committed,
                  try HanlinTransferTree.capture(installedRoot) == journal.afterInstalled,
                  try HanlinTransferTree.capture(dataRoot, durableSQLiteData: true) == journal.afterData else {
                throw HanlinProductTransferError.rollbackWouldLoseChanges
            }
            journal.state = .rollingBack
            try persist(journal, at: transactionRoot)
            try faults.check(.rollbackIntentPersisted)
            try recover(installedRoot: installedRoot, dataRoot: dataRoot,
                        transactionRoot: transactionRoot, faults: faults)
        }
    }

    static func load(_ root: URL) throws -> Journal? {
        let path = root.appending(path: "journal.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let value = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: path))
        guard value.version == 1, value.checkpoint.version == 1 else {
            throw HanlinProductTransferError.invalidCheckpoint
        }
        return value
    }

    static func persist(_ journal: Journal, at root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(journal).write(to: root.appending(path: "journal.json"), options: .atomic)
    }

    static func distinct(_ roots: [URL]) throws {
        let paths = roots.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        for i in paths.indices {
            for j in paths.indices where i != j {
                guard paths[i] != paths[j], !paths[i].hasPrefix(paths[j] + "/") else {
                    throw HanlinProductTransferError.unsafePath
                }
            }
        }
    }

    private static func promote(current: URL, stage: URL, backup: URL,
        before: HanlinTransferTree, after: HanlinTransferTree,
        afterBackup: HanlinProductTransferFaultPoint, afterPromotion: HanlinProductTransferFaultPoint,
        durableSQLiteData: Bool = false, faults: any HanlinProductTransferFaultInjector) throws {
        let manager = FileManager.default
        var actual = try HanlinTransferTree.capture(current, durableSQLiteData: durableSQLiteData)
        if actual == after { return }
        guard try HanlinTransferTree.capture(stage, durableSQLiteData: durableSQLiteData) == after else {
            throw HanlinProductTransferError.recoveryConflict
        }
        if actual.exists {
            guard actual == before, !(try HanlinTransferTree.capture(backup, durableSQLiteData: durableSQLiteData)).exists else {
                throw HanlinProductTransferError.recoveryConflict
            }
            try manager.moveItem(at: current, to: backup)
            actual = try HanlinTransferTree.capture(current, durableSQLiteData: durableSQLiteData)
            try faults.check(afterBackup)
        }
        let saved = try HanlinTransferTree.capture(backup, durableSQLiteData: durableSQLiteData)
        guard !actual.exists, !before.exists || saved == before else {
            throw HanlinProductTransferError.recoveryConflict
        }
        if after.exists {
            try manager.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.moveItem(at: stage, to: current)
        }
        guard try HanlinTransferTree.capture(current, durableSQLiteData: durableSQLiteData) == after else {
            throw HanlinProductTransferError.recoveryConflict
        }
        try faults.check(afterPromotion)
    }

    private static func restore(current: URL, backup: URL, retained: URL,
                                before: HanlinTransferTree, after: HanlinTransferTree,
                                durableSQLiteData: Bool = false) throws {
        let manager = FileManager.default
        let actual = try HanlinTransferTree.capture(current, durableSQLiteData: durableSQLiteData)
        if actual == before { return }
        let saved = try HanlinTransferTree.capture(backup, durableSQLiteData: durableSQLiteData)
        guard !actual.exists || actual == after, !before.exists || saved == before else {
            throw HanlinProductTransferError.recoveryConflict
        }
        if actual.exists {
            guard !(try HanlinTransferTree.capture(retained, durableSQLiteData: durableSQLiteData)).exists else {
                throw HanlinProductTransferError.recoveryConflict
            }
            try manager.moveItem(at: current, to: retained)
        } else if after.exists {
            guard try HanlinTransferTree.capture(retained, durableSQLiteData: durableSQLiteData) == after else {
                throw HanlinProductTransferError.recoveryConflict
            }
        }
        if before.exists { try manager.moveItem(at: backup, to: current) }
        guard try HanlinTransferTree.capture(current, durableSQLiteData: durableSQLiteData) == before else {
            throw HanlinProductTransferError.recoveryConflict
        }
    }
}
