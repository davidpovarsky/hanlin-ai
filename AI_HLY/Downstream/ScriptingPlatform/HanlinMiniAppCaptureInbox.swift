import Foundation
import HanlinCameraCaptureUI

/// Durable application-container ownership before the OS session is invalidated.
/// This file is app-only; none of its storage is linked into the locked extension.
struct HanlinMiniAppCaptureRecord: Codable, Hashable, Identifiable, Sendable {
    var id: UUID { manifest.sessionID }
    let manifest: HanlinCameraCaptureManifest
    var selectedTarget: HanlinCameraCaptureTarget?
    var invocationID: UUID
    var invocationCreatedAt: Date
    var submitted: Bool
}

actor HanlinMiniAppCaptureInbox {
    let root: URL
    let productIdentifier: String

    init(root: URL, productIdentifier: String) {
        self.root = root; self.productIdentifier = productIdentifier
    }

    /// Returns only after exact photo bytes and a durable record are in our own
    /// container. A caller may then invalidate the system's session directory.
    func receive(directory: URL) throws -> HanlinMiniAppCaptureRecord {
        try Self.requireDirectory(directory)
        let manifestURL = directory.appending(path: HanlinCameraCaptureManifest.filename)
        try Self.requireRegularFile(manifestURL)
        let manifest = try JSONDecoder().decode(HanlinCameraCaptureManifest.self, from: Data(contentsOf: manifestURL))
        try manifest.validate(productIdentifier: productIdentifier)
        guard !manifest.photos.isEmpty else { throw HanlinCameraCaptureError.invalidSession }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.requireDirectory(root)
        let destination = directoryURL(manifest.sessionID)
        if FileManager.default.fileExists(atPath: destination.path) {
            let prior = try read(manifest.sessionID)
            guard prior.manifest == manifest else { throw HanlinCameraCaptureError.changedContent }
            try verifyPhotos(manifest, directory: destination)
            return prior
        }
        let temporary = root.appending(path: ".incoming-" + UUID().uuidString.lowercased(), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for photo in manifest.photos {
            let source = directory.appending(path: photo.filename)
            try Self.requireRegularFile(source)
            try FileManager.default.copyItem(at: source, to: temporary.appending(path: photo.filename))
        }
        try verifyPhotos(manifest, directory: temporary)
        let record = HanlinMiniAppCaptureRecord(manifest: manifest, selectedTarget: manifest.target,
            invocationID: UUID(), invocationCreatedAt: .now, submitted: false)
        try Self.write(record, directory: temporary)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return try read(manifest.sessionID)
    }

    func records() throws -> [HanlinMiniAppCaptureRecord] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        try Self.requireDirectory(root)
        let children = try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        return try children.compactMap { url -> HanlinMiniAppCaptureRecord? in
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            return try read(id)
        }.sorted { $0.invocationCreatedAt < $1.invocationCreatedAt }
    }

    func read(_ id: UUID) throws -> HanlinMiniAppCaptureRecord {
        let directory = directoryURL(id)
        try Self.requireDirectory(directory)
        let url = directory.appending(path: "delivery.json")
        try Self.requireRegularFile(url)
        let record = try JSONDecoder().decode(HanlinMiniAppCaptureRecord.self, from: Data(contentsOf: url))
        guard record.id == id else { throw HanlinCameraCaptureError.invalidSession }
        try record.manifest.validate(productIdentifier: productIdentifier)
        return record
    }

    func select(_ target: HanlinCameraCaptureTarget, for id: UUID, replacingUnexecutedDelivery: Bool) throws -> HanlinMiniAppCaptureRecord {
        guard target.productIdentifier == productIdentifier else { throw HanlinCameraCaptureError.wrongProduct }
        var record = try read(id)
        guard !record.submitted || replacingUnexecutedDelivery else { throw HanlinCameraCaptureError.invalidSession }
        record.selectedTarget = target
        record.invocationID = UUID()
        record.invocationCreatedAt = .now
        record.submitted = false
        try Self.write(record, directory: directoryURL(id))
        return record
    }

    func markSubmitted(_ id: UUID, invocationID: UUID) throws {
        var record = try read(id)
        guard record.invocationID == invocationID else { throw HanlinCameraCaptureError.invalidSession }
        record.submitted = true
        try Self.write(record, directory: directoryURL(id))
    }

    /// Copy into the selected package's existing Documents container. No extension
    /// path or NSUserActivity-supplied URL is ever passed to the package runtime.
    func copyPhotos(for id: UUID, documents: URL) throws -> [URL] {
        let record = try read(id)
        let source = directoryURL(id)
        try verifyPhotos(record.manifest, directory: source)
        let captures = documents.appending(path: "captures", directoryHint: .isDirectory)
        let destination = captures.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
        try Self.ensureDirectory(documents)
        try Self.ensureDirectory(captures)
        try Self.ensureDirectory(destination)
        for photo in record.manifest.photos {
            let to = destination.appending(path: photo.filename)
            if !FileManager.default.fileExists(atPath: to.path) {
                let temp = destination.appending(path: "." + UUID().uuidString.lowercased())
                defer { try? FileManager.default.removeItem(at: temp) }
                try FileManager.default.copyItem(at: source.appending(path: photo.filename), to: temp)
                try FileManager.default.moveItem(at: temp, to: to)
            }
        }
        try verifyPhotos(record.manifest, directory: destination)
        return record.manifest.photos.map { destination.appending(path: $0.filename) }
    }

    private func directoryURL(_ id: UUID) -> URL {
        root.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    private static func write(_ record: HanlinMiniAppCaptureRecord, directory: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: directory.appending(path: "delivery.json"), options: .atomic)
    }

    private func verifyPhotos(_ manifest: HanlinCameraCaptureManifest, directory: URL) throws {
        for photo in manifest.photos {
            let file = directory.appending(path: photo.filename)
            try Self.requireRegularFile(file)
            let data = try Data(contentsOf: file)
            guard data.count == photo.byteCount, HanlinCameraCaptureManifest.digest(data) == photo.sha256 else {
                throw HanlinCameraCaptureError.changedContent
            }
        }
    }

    private static func ensureDirectory(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        try requireDirectory(url)
    }

    private static func requireDirectory(_ url: URL) throws {
        guard url.isFileURL else { throw HanlinCameraCaptureError.invalidSession }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw HanlinCameraCaptureError.invalidSession }
    }

    private static func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw HanlinCameraCaptureError.invalidSession }
    }
}
