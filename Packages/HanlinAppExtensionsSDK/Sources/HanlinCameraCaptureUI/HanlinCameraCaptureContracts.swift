import CryptoKit
import Foundation

/// Only identifiers cross the system's small CameraCaptureIntent appContext.
/// Package code, App Group paths, grants and credentials never enter this value.
public struct HanlinCameraCaptureTarget: Codable, Hashable, Sendable {
    public let productIdentifier: String
    public let installedPackageID: String
    public let packageID: String
    public let generation: UInt64
    public let entrypointID: String
    public let actionID: String

    public init(productIdentifier: String, installedPackageID: String, packageID: String,
                generation: UInt64, entrypointID: String, actionID: String) {
        self.productIdentifier = productIdentifier
        self.installedPackageID = installedPackageID
        self.packageID = packageID
        self.generation = generation
        self.entrypointID = entrypointID
        self.actionID = actionID
    }
}

public enum HanlinCameraCaptureSource: String, Codable, Sendable {
    case lockedCamera, applicationCamera
}

public struct HanlinCapturedPhoto: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let filename: String
    public let contentType: String
    public let byteCount: Int
    public let sha256: String
    public let width: Int
    public let height: Int

    public init(id: UUID, filename: String, contentType: String, byteCount: Int,
                sha256: String, width: Int, height: Int) {
        self.id = id; self.filename = filename; self.contentType = contentType
        self.byteCount = byteCount; self.sha256 = sha256; self.width = width; self.height = height
    }
}

public struct HanlinCameraCaptureManifest: Codable, Hashable, Sendable {
    public static let filename = "hanlin-camera-session.json"
    public let schemaVersion: Int
    public let sessionID: UUID
    public let productIdentifier: String
    public let source: HanlinCameraCaptureSource
    public let target: HanlinCameraCaptureTarget?
    public var photos: [HanlinCapturedPhoto]

    public init(sessionID: UUID = UUID(), productIdentifier: String, source: HanlinCameraCaptureSource,
                target: HanlinCameraCaptureTarget?, photos: [HanlinCapturedPhoto] = []) {
        self.schemaVersion = 1; self.sessionID = sessionID; self.productIdentifier = productIdentifier
        self.source = source; self.target = target; self.photos = photos
    }

    public func validate(productIdentifier expectedProduct: String) throws {
        guard schemaVersion == 1, productIdentifier == expectedProduct,
              target == nil || target?.productIdentifier == expectedProduct else {
            throw HanlinCameraCaptureError.wrongProduct
        }
        var ids = Set<UUID>(), names = Set<String>()
        for photo in photos {
            // These are our own generated JPEGs, not arbitrary paths supplied by an activity.
            guard photo.filename == photo.id.uuidString.lowercased() + ".jpg",
                  photo.contentType == "public.jpeg", photo.byteCount > 0,
                  photo.width > 0, photo.height > 0,
                  photo.sha256.count == 64,
                  photo.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                  ids.insert(photo.id).inserted, names.insert(photo.filename).inserted else {
                throw HanlinCameraCaptureError.invalidSession
            }
        }
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum HanlinCameraCaptureError: LocalizedError, Sendable {
    case permissionDenied, cameraUnavailable, cannotConfigureCamera, captureUnavailable
    case invalidPhoto, invalidSession, wrongProduct, changedContent

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Camera access is unavailable. Enable Camera for this app in Settings."
        case .cameraUnavailable: "This device does not have an available camera."
        case .cannotConfigureCamera: "The camera could not be configured."
        case .captureUnavailable: "The camera is not ready to capture a photo."
        case .invalidPhoto: "The camera did not produce a readable photo."
        case .invalidSession: "The captured session is incomplete or cannot be read."
        case .wrongProduct: "This capture belongs to a different application."
        case .changedContent: "The captured file does not match its saved record."
        }
    }
}

/// Used by the real photo output in both the application and locked extension.
/// The extension supplies only its system-provided sessionContentURL. This module
/// deliberately has no App Group/store/network dependency.
public actor HanlinCameraSessionFiles {
    private let directory: URL
    private var manifest: HanlinCameraCaptureManifest

    public init(directory: URL, productIdentifier: String, source: HanlinCameraCaptureSource,
                target: HanlinCameraCaptureTarget?) throws {
        guard directory.isFileURL else { throw HanlinCameraCaptureError.invalidSession }
        self.directory = directory
        self.manifest = .init(productIdentifier: productIdentifier, source: source, target: target)
        try manifest.validate(productIdentifier: productIdentifier)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.requireDirectory(directory)
        let manifestURL = directory.appending(path: HanlinCameraCaptureManifest.filename)
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let attributes = try manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else {
                throw HanlinCameraCaptureError.invalidSession
            }
            let previous = try JSONDecoder().decode(HanlinCameraCaptureManifest.self, from: Data(contentsOf: manifestURL))
            try previous.validate(productIdentifier: productIdentifier)
            guard previous.source == source, previous.target == target else { throw HanlinCameraCaptureError.invalidSession }
            self.manifest = previous
        }
    }

    public func saveJPEG(_ data: Data, width: Int, height: Int) throws -> HanlinCapturedPhoto {
        guard !data.isEmpty, width > 0, height > 0 else { throw HanlinCameraCaptureError.invalidPhoto }
        try Self.requireDirectory(directory)
        let id = UUID()
        let photo = HanlinCapturedPhoto(id: id, filename: id.uuidString.lowercased() + ".jpg",
            contentType: "public.jpeg", byteCount: data.count,
            sha256: HanlinCameraCaptureManifest.digest(data), width: width, height: height)
        let file = directory.appending(path: photo.filename)
        try data.write(to: file, options: .atomic)
        var next = manifest
        next.photos.append(photo)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(next).write(to: directory.appending(path: HanlinCameraCaptureManifest.filename), options: .atomic)
        manifest = next
        return photo
    }

    public func currentManifest() -> HanlinCameraCaptureManifest { manifest }

    private static func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw HanlinCameraCaptureError.invalidSession
        }
    }
}
