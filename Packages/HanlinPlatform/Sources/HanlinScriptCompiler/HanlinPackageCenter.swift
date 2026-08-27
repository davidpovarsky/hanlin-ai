import CryptoKit
import Foundation
import HanlinScriptContracts
import ZIPFoundation

public enum HanlinPackageCenterError: Error, Hashable, Sendable {
    case unsupportedSourceFormat
    case sourceTooLarge
    case unreadableArchive
    case unsafeArchive([HanlinArchiveFinding])
    case extractionEscapedRoot(String)
    case malformedManifest
    case stagingFailed
}

public struct HanlinStagedPackage: Sendable {
    public let source: HanlinImportedPackageSource
    public let stagingRoot: URL
    public let archiveURL: URL
    public let packageRoot: URL
    public let inspection: HanlinArchiveInspection
    public let manifest: HanlinScriptingManifest

    public init(
        source: HanlinImportedPackageSource,
        stagingRoot: URL,
        archiveURL: URL,
        packageRoot: URL,
        inspection: HanlinArchiveInspection,
        manifest: HanlinScriptingManifest
    ) {
        self.source = source
        self.stagingRoot = stagingRoot
        self.archiveURL = archiveURL
        self.packageRoot = packageRoot
        self.inspection = inspection
        self.manifest = manifest
    }
}

public struct HanlinPackageCenter: Sendable {
    public let archivePolicy: HanlinArchivePolicy
    private var fileManager: FileManager { .default }

    public init(
        archivePolicy: HanlinArchivePolicy = .init()
    ) {
        self.archivePolicy = archivePolicy
    }

    public func stageAndInspect(
        sourceURL: URL,
        stagingParent: URL,
        importedAt: Date = .now
    ) throws -> HanlinStagedPackage {
        let format: HanlinScriptingSourceFormat
        switch sourceURL.pathExtension.lowercased() {
        case "scripting": format = .scripting
        case "zip": format = .zip
        default: throw HanlinPackageCenterError.unsupportedSourceFormat
        }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let stagingRoot = stagingParent.appending(
            path: "scripting-import-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let archiveURL = stagingRoot.appending(
            path: "source.\(sourceURL.pathExtension.lowercased())",
            directoryHint: .notDirectory
        )
        let extractedRoot = stagingRoot.appending(path: "extracted", directoryHint: .isDirectory)
        do {
            // Keep the Files/Document Picker URL as a URL. Converting it through
            // URL.path() yields a percent-encoded filesystem path on modern
            // Foundation (for example "File%20Provider%20Storage"), which
            // FileManager then treats as a literal path and re-encodes as %2520.
            // Reading URL resource values also keeps security-scoped and File
            // Provider URLs on the URL-based API surface.
            let sourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
            let byteCount = Int64(sourceValues.fileSize ?? 0)
            guard byteCount >= 0, byteCount <= archivePolicy.limits.maximumArchiveBytes else {
                throw HanlinPackageCenterError.sourceTooLarge
            }

            try fileManager.createDirectory(
                at: stagingRoot,
                withIntermediateDirectories: false
            )
            try fileManager.copyItem(at: sourceURL, to: archiveURL)
            let archiveData = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
            let digest = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
            let centralCount = try Self.centralDirectoryEntryCount(in: archiveData)
            let archive = try Archive(url: archiveURL, accessMode: .read)
            let zipEntries = Array(archive)
            let entries = try zipEntries.map { entry in
                HanlinArchiveEntryMetadata(
                    path: entry.path,
                    kind: Self.kind(entry.type),
                    compressedBytes: try Self.int64(entry.compressedSize),
                    uncompressedBytes: try Self.int64(entry.uncompressedSize)
                )
            }
            let inspection = archivePolicy.inspect(
                entries: entries,
                centralDirectoryEntryCount: centralCount,
                archiveBytes: byteCount
            )
            guard inspection.isInstallable else {
                throw HanlinPackageCenterError.unsafeArchive(inspection.findings)
            }
            try fileManager.createDirectory(at: extractedRoot, withIntermediateDirectories: false)
            let ignored = Set(inspection.ignoredEntries)
            for (entry, metadata) in zip(zipEntries, entries) where !ignored.contains(metadata.path) {
                guard let normalized = HanlinArchivePolicy.normalizedRelativePath(metadata.path) else {
                    throw HanlinPackageCenterError.extractionEscapedRoot(metadata.path)
                }
                let destination = extractedRoot.appending(
                    path: normalized,
                    directoryHint: metadata.kind == .directory ? .isDirectory : .notDirectory
                )
                guard Self.contains(destination, in: extractedRoot) else {
                    throw HanlinPackageCenterError.extractionEscapedRoot(metadata.path)
                }
                _ = try archive.extract(entry, to: destination, allowUncontainedSymlinks: false)
            }
            let packageRoot = inspection.wrapperDirectory.map {
                extractedRoot.appending(path: $0, directoryHint: .isDirectory)
            } ?? extractedRoot
            let manifestURL = packageRoot.appending(path: "script.json", directoryHint: .notDirectory)
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest: HanlinScriptingManifest
            do {
                manifest = try JSONDecoder().decode(HanlinScriptingManifest.self, from: manifestData)
            } catch {
                throw HanlinPackageCenterError.malformedManifest
            }
            return HanlinStagedPackage(
                source: .init(
                    originalFileName: sourceURL.lastPathComponent,
                    format: format,
                    contentSHA256: digest,
                    byteCount: byteCount,
                    importedAt: importedAt
                ),
                stagingRoot: stagingRoot,
                archiveURL: archiveURL,
                packageRoot: packageRoot,
                inspection: inspection,
                manifest: manifest
            )
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }
    }

    public func discard(_ package: HanlinStagedPackage) throws {
        guard Self.contains(package.stagingRoot, in: package.stagingRoot.deletingLastPathComponent()) else {
            throw HanlinPackageCenterError.stagingFailed
        }
        if fileManager.fileExists(atPath: package.stagingRoot.path(percentEncoded: false)) {
            try fileManager.removeItem(at: package.stagingRoot)
        }
    }

    private static func kind(_ type: Entry.EntryType) -> HanlinArchiveEntryKind {
        switch type {
        case .file: .file
        case .directory: .directory
        case .symlink: .symbolicLink
        }
    }

    private static func int64(_ value: UInt64) throws -> Int64 {
        guard value <= UInt64(Int64.max) else {
            throw HanlinPackageCenterError.sourceTooLarge
        }
        return Int64(value)
    }

    private static func contains(_ child: URL, in root: URL) -> Bool {
        let standardizedRootPath = root.standardizedFileURL.path(percentEncoded: false)
        let rootPath = standardizedRootPath.hasSuffix("/") && standardizedRootPath.count > 1
            ? String(standardizedRootPath.dropLast())
            : standardizedRootPath
        let childPath = child.standardizedFileURL.path(percentEncoded: false)
        return childPath == rootPath || childPath.hasPrefix(rootPath + "/")
    }

    private static func centralDirectoryEntryCount(in data: Data) throws -> Int {
        let signature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        guard data.count >= 22 else { throw HanlinPackageCenterError.unreadableArchive }
        let earliest = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= earliest {
            if data[offset ..< offset + 4].elementsEqual(signature) {
                let diskNumber = littleEndianUInt16(data, offset + 4)
                let centralDisk = littleEndianUInt16(data, offset + 6)
                let entries = littleEndianUInt16(data, offset + 10)
                let commentLength = Int(littleEndianUInt16(data, offset + 20))
                guard diskNumber == 0, centralDisk == 0,
                      entries != UInt16.max,
                      offset + 22 + commentLength == data.count
                else {
                    throw HanlinPackageCenterError.unreadableArchive
                }
                return Int(entries)
            }
            if offset == 0 { break }
            offset -= 1
        }
        throw HanlinPackageCenterError.unreadableArchive
    }

    private static func littleEndianUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
}
