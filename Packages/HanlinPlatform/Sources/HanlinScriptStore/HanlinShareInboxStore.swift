import CryptoKit
import Darwin
import Foundation

/// Immutable ingress, before any installed action has been selected or executed.
public struct HanlinShareBatch: Codable, Identifiable, Sendable, Equatable {
    public let schemaVersion: Int
    public let id: UUID
    public let createdAt: Date
    public let items: [HanlinShareItem]
}

public struct HanlinShareItem: Codable, Identifiable, Sendable, Equatable {
    public enum Content: String, Codable, Sendable { case text, url, file, rejected }
    public enum Failure: String, Codable, Sendable { case unsupportedType, providerFailed, copyFailed }
    public let id: UUID
    public let ordinal: Int
    public let content: Content
    public let typeIdentifier: String
    public let name: String?
    public let text: String?
    public let file: String?
    public let bytes: Int64?
    public let sha256: String?
    public let failure: Failure?

    public static func text(_ value: String, ordinal: Int, typeIdentifier: String, isURL: Bool = false) -> Self {
        .init(id: UUID(), ordinal: ordinal, content: isURL ? .url : .text, typeIdentifier: typeIdentifier,
              name: nil, text: value, file: nil, bytes: nil, sha256: nil, failure: nil)
    }

    public static func rejected(ordinal: Int, typeIdentifier: String, failure: Failure) -> Self {
        .init(id: UUID(), ordinal: ordinal, content: .rejected, typeIdentifier: typeIdentifier,
              name: nil, text: nil, file: nil, bytes: nil, sha256: nil, failure: failure)
    }
}

public enum HanlinShareInboxError: Error, Sendable, Equatable { case invalidPath, invalidBatch, invalidFile, integrityMismatch }

/// The existing ScriptStore product owns ingress files; no runtime is linked or
/// launched by this store. Each extension instance has its own private staging
/// directory and publishes the complete batch with one same-volume rename.
public struct HanlinShareInboxStore: Sendable {
    public let directory: URL

    public init(container: URL) throws {
        try Self.requireDirectory(container)
        directory = container.appending(path: "ShareInbox", directoryHint: .isDirectory)
        try Self.createDirectory(directory)
        try Self.createDirectory(directory.appending(path: "Staging", directoryHint: .isDirectory))
        try Self.createDirectory(directory.appending(path: "Batches", directoryHint: .isDirectory))
    }

    public func begin() throws -> UUID {
        let id = UUID()
        let staging = try stagingDirectory(id)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: Self.protection)
        try Self.createDirectory(staging.appending(path: "Files", directoryHint: .isDirectory))
        return id
    }

    /// Call *inside* NSItemProvider's file-representation completion handler.
    /// Neither this URL nor the provider's temporary URL is saved in metadata.
    public func copyFile(_ source: URL, batchID: UUID, ordinal: Int, typeIdentifier: String,
                         suggestedName: String? = nil) throws -> HanlinShareItem {
        guard source.isFileURL else { throw HanlinShareInboxError.invalidFile }
        let staging = try stagingDirectory(batchID)
        try Self.requireDirectory(staging)
        let files = staging.appending(path: "Files", directoryHint: .isDirectory)
        try Self.requireDirectory(files)
        let id = UUID()
        let destination = files.appending(path: id.uuidString.lowercased())
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let inputFD = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard inputFD >= 0 else { throw HanlinShareInboxError.invalidFile }
        let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
        defer { try? input.close() }
        var info = stat()
        guard fstat(inputFD, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw HanlinShareInboxError.invalidFile
        }
        let outputFD = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard outputFD >= 0 else { throw HanlinShareInboxError.invalidFile }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        var complete = false
        defer {
            try? output.close()
            if !complete { try? FileManager.default.removeItem(at: destination) }
        }
        if !Self.protection.isEmpty { try FileManager.default.setAttributes(Self.protection, ofItemAtPath: destination.path) }
        var hash = SHA256(), count: Int64 = 0
        while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
            try output.write(contentsOf: data)
            hash.update(data: data)
            count += Int64(data.count)
        }
        try output.synchronize()
        complete = true
        return .init(id: id, ordinal: ordinal, content: .file, typeIdentifier: typeIdentifier,
                     name: suggestedName ?? source.lastPathComponent, text: nil,
                     file: id.uuidString.lowercased(), bytes: count,
                     sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(), failure: nil)
    }

    public func commit(_ id: UUID, items: [HanlinShareItem], createdAt: Date = .now) throws -> HanlinShareBatch {
        let staging = try stagingDirectory(id)
        try Self.requireDirectory(staging)
        let batch = HanlinShareBatch(schemaVersion: 1, id: id, createdAt: createdAt, items: items)
        try validate(batch, at: staging, verifyFiles: true)
        let metadata = staging.appending(path: "batch.json")
        try JSONEncoder().encode(batch).write(to: metadata, options: .atomic)
        if !Self.protection.isEmpty { try FileManager.default.setAttributes(Self.protection, ofItemAtPath: metadata.path) }
        let destination = try batchDirectory(id)
        try FileManager.default.moveItem(at: staging, to: destination)
        return batch
    }

    public func abort(_ id: UUID) throws {
        let staging = try stagingDirectory(id)
        try Self.requireDirectory(staging)
        try FileManager.default.removeItem(at: staging)
    }

    /// A malformed batch is reported separately; it cannot starve healthy ingress.
    /// Original staging, historical share-inbox.json and rejected batches stay put.
    public func scan() throws -> (batches: [HanlinShareBatch], rejected: [UUID?]) {
        let batches = directory.appending(path: "Batches", directoryHint: .isDirectory)
        try Self.requireDirectory(batches)
        var accepted: [HanlinShareBatch] = [], rejected: [UUID?] = []
        for child in try FileManager.default.contentsOfDirectory(at: batches, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: child.lastPathComponent), child.lastPathComponent == id.uuidString.lowercased() else {
                rejected.append(nil); continue
            }
            do {
                try Self.requireDirectory(child)
                let metadata = child.appending(path: "batch.json")
                let batch = try JSONDecoder().decode(HanlinShareBatch.self, from: Self.readRegularFile(metadata))
                guard batch.id == id else { throw HanlinShareInboxError.invalidBatch }
                try validate(batch, at: child, verifyFiles: false)
                accepted.append(batch)
            } catch { rejected.append(id) }
        }
        return (accepted.sorted { $0.createdAt < $1.createdAt }, rejected)
    }

    public func ownedFile(batchID: UUID, itemID: UUID) throws -> URL {
        let root = try batchDirectory(batchID)
        try Self.requireDirectory(root)
        let batch = try JSONDecoder().decode(HanlinShareBatch.self, from: Self.readRegularFile(root.appending(path: "batch.json")))
        guard batch.id == batchID else { throw HanlinShareInboxError.invalidBatch }
        try validate(batch, at: root, verifyFiles: false)
        guard let item = batch.items.first(where: { $0.id == itemID && $0.content == .file }) else {
            throw HanlinShareInboxError.invalidFile
        }
        return try verify(item, at: root)
    }

    private func validate(_ batch: HanlinShareBatch, at root: URL, verifyFiles: Bool) throws {
        guard batch.schemaVersion == 1, !batch.items.isEmpty,
              batch.createdAt.timeIntervalSince1970.isFinite,
              Set(batch.items.map(\.id)).count == batch.items.count,
              batch.items.map(\.ordinal) == Array(0..<batch.items.count) else { throw HanlinShareInboxError.invalidBatch }
        for item in batch.items {
            guard !item.typeIdentifier.isEmpty else { throw HanlinShareInboxError.invalidBatch }
            switch item.content {
            case .file:
                guard item.file == item.id.uuidString.lowercased(), let bytes = item.bytes, bytes >= 0,
                      let sha = item.sha256, sha.count == 64, sha.allSatisfy({ $0.isHexDigit }),
                      item.text == nil, item.failure == nil else { throw HanlinShareInboxError.invalidBatch }
                if verifyFiles { _ = try verify(item, at: root) }
            case .text, .url:
                guard item.text != nil, item.file == nil, item.bytes == nil, item.sha256 == nil, item.failure == nil else {
                    throw HanlinShareInboxError.invalidBatch
                }
            case .rejected:
                guard item.failure != nil, item.text == nil, item.file == nil, item.bytes == nil, item.sha256 == nil else {
                    throw HanlinShareInboxError.invalidBatch
                }
            }
        }
    }

    private func verify(_ item: HanlinShareItem, at root: URL) throws -> URL {
        let files = root.appending(path: "Files", directoryHint: .isDirectory)
        try Self.requireDirectory(files)
        guard item.file == item.id.uuidString.lowercased() else { throw HanlinShareInboxError.invalidFile }
        let url = files.appending(path: item.id.uuidString.lowercased())
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw HanlinShareInboxError.invalidFile }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_nlink == 1 else {
            throw HanlinShareInboxError.invalidFile
        }
        var hash = SHA256(), bytes: Int64 = 0
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hash.update(data: data); bytes += Int64(data.count)
        }
        guard bytes == item.bytes, hash.finalize().map({ String(format: "%02x", $0) }).joined() == item.sha256 else {
            throw HanlinShareInboxError.integrityMismatch
        }
        return url
    }

    private func stagingDirectory(_ id: UUID) throws -> URL { try child("Staging", id) }
    private func batchDirectory(_ id: UUID) throws -> URL { try child("Batches", id) }
    private func child(_ parent: String, _ id: UUID) throws -> URL {
        try Self.requireDirectory(directory)
        let base = directory.appending(path: parent, directoryHint: .isDirectory)
        try Self.requireDirectory(base)
        return base.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    private static var protection: [FileAttributeKey: Any] {
        #if os(iOS)
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        [:]
        #endif
    }

    private static func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: protection)
        try requireDirectory(url)
    }

    private static func requireDirectory(_ url: URL) throws {
        guard url.isFileURL else { throw HanlinShareInboxError.invalidPath }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw HanlinShareInboxError.invalidPath }
    }

    private static func readRegularFile(_ url: URL) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw HanlinShareInboxError.invalidFile }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_nlink == 1 else {
            throw HanlinShareInboxError.invalidFile
        }
        return try handle.readToEnd() ?? Data()
    }
}
