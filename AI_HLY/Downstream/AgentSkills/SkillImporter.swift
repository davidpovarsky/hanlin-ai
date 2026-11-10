import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import ZIPFoundation

public enum SkillImportError: Error, LocalizedError, Hashable, Sendable {
    case invalidURL(String)
    case nonHTTPSURLForbidden
    case downloadExceedsLimit(Int64)
    case downloadFailed(String)
    case unsupportedFileType(String)
    case missingSkillMarkdown
    case multipleSkillMarkdownFiles([String])
    case invalidFrontmatter(String)
    case archiveInspectionFailed([String])
    case extractionEscapedRoot(String)
    case stagingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let u): return "Invalid URL: \(u)"
        case .nonHTTPSURLForbidden: return "Only secure HTTPS URLs are permitted for skill installation."
        case .downloadExceedsLimit(let bytes): return "Skill download size (\(bytes) bytes) exceeds the configured download budget."
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .unsupportedFileType(let ext): return "Unsupported file type: .\(ext). Expected .zip or .md"
        case .missingSkillMarkdown: return "Skill archive must contain exactly one SKILL.md entrypoint."
        case .multipleSkillMarkdownFiles(let files): return "Multiple SKILL.md files detected in archive: \(files.joined(separator: ", "))"
        case .invalidFrontmatter(let msg): return "Invalid SKILL.md frontmatter: \(msg)"
        case .archiveInspectionFailed(let findings): return "Skill archive failed safety validation: \(findings.joined(separator: "; "))"
        case .extractionEscapedRoot(let path): return "Archive entry escaped extraction staging directory: \(path)"
        case .stagingFailed(let msg): return "Staging failed: \(msg)"
        }
    }
}

public struct StagedSkillPackage: Sendable {
    public let stagingDirectoryURL: URL
    public let skillRootDirectoryURL: URL
    public let skillID: HanlinSkillID
    public let parsedMarkdown: SkillMarkdownParser.ParsedSkillMarkdown
    public let metadata: HanlinSkillMetadata
    public let resources: [SkillResourceFile]
    public let sha256: String
    public let originURL: String?

    public init(
        stagingDirectoryURL: URL,
        skillRootDirectoryURL: URL,
        skillID: HanlinSkillID,
        parsedMarkdown: SkillMarkdownParser.ParsedSkillMarkdown,
        metadata: HanlinSkillMetadata,
        resources: [SkillResourceFile],
        sha256: String,
        originURL: String? = nil
    ) {
        self.stagingDirectoryURL = stagingDirectoryURL
        self.skillRootDirectoryURL = skillRootDirectoryURL
        self.skillID = skillID
        self.parsedMarkdown = parsedMarkdown
        self.metadata = metadata
        self.resources = resources
        self.sha256 = sha256
        self.originURL = originURL
    }

    public func cleanup() {
        try? FileManager.default.removeItem(at: stagingDirectoryURL)
    }
}

public final class SkillImporter: @unchecked Sendable {
    public static let shared = SkillImporter()

    private let fileManager = FileManager.default

    public init() {}

    @MainActor
    public func importSkill(fromArchiveAt fileURL: URL) throws -> HanlinSkillDescriptor {
        let staged = try stageAndInspect(fileURL: fileURL)
        let record = try SkillStore.shared.install(stagedPackage: staged)
        return record.descriptor
    }

    @MainActor
    public func installFromHTTPSURL(_ url: URL) async throws -> HanlinSkillDescriptor {
        let staged = try await downloadAndStage(from: url)
        let record = try SkillStore.shared.install(stagedPackage: staged)
        return record.descriptor
    }

    // MARK: - Staging from Local File / ZIP

    public func stageAndInspect(fileURL: URL, originURL: String? = nil,
                                limits: HanlinArchiveLimits = .autonomousSkillImport) throws -> StagedSkillPackage {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }

        let ext = fileURL.pathExtension.lowercased()
        guard ext == "zip" || ext == "md" else {
            throw SkillImportError.unsupportedFileType(ext)
        }

        let stagingDir = fileManager.temporaryDirectory.appendingPathComponent("skill-stage-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        do {
            let fileAttrs = try fileManager.attributesOfItem(atPath: fileURL.path)
            let fileSize = (fileAttrs[.size] as? NSNumber)?.int64Value ?? 0
            guard fileSize >= 0, fileSize <= limits.maximumArchiveBytes else {
                throw SkillImportError.downloadExceedsLimit(fileSize)
            }

            // Stream SHA-256 calculation in bounded 64KB buffers to avoid loading large archives into memory
            var hasher = SHA256()
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? fileHandle.close() }
            while let chunk = try fileHandle.read(upToCount: 65536), !chunk.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: chunk)
            }
            let sha256 = hasher.finalize().map { String(format: "%02x", $0) }.joined()

            if ext == "md" {
                let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                guard let content = String(data: data, encoding: .utf8) else {
                    throw SkillImportError.invalidFrontmatter("File is not valid UTF-8 text.")
                }
                let parsed: SkillMarkdownParser.ParsedSkillMarkdown
                do {
                    parsed = try SkillMarkdownParser.parse(content)
                } catch {
                    throw SkillImportError.invalidFrontmatter(error.localizedDescription)
                }

                guard let skillID = try? HanlinSkillID(validating: parsed.name) else {
                    throw SkillImportError.invalidFrontmatter("Skill name '\(parsed.name)' is not a valid skill identifier.")
                }

                let skillRoot = stagingDir.appendingPathComponent(skillID.rawValue, isDirectory: true)
                try fileManager.createDirectory(at: skillRoot, withIntermediateDirectories: true)
                try data.write(to: skillRoot.appendingPathComponent("SKILL.md"))

                let meta = HanlinSkillMetadata(
                    preferredToolIDs: [],
                    triggerHints: [],
                    keywords: [],
                    baseSkillID: nil,
                    originURL: originURL,
                    sha256: sha256,
                    isEnabled: true,
                    installedAt: Date(),
                    updatedAt: Date()
                )
                let metaData = try JSONEncoder().encode(meta)
                try metaData.write(to: skillRoot.appendingPathComponent("hanlin.json"))

                return StagedSkillPackage(
                    stagingDirectoryURL: stagingDir,
                    skillRootDirectoryURL: skillRoot,
                    skillID: skillID,
                    parsedMarkdown: parsed,
                    metadata: meta,
                    resources: [],
                    sha256: sha256,
                    originURL: originURL
                )
            } else {
                // ZIP handling: stream file copy directly, avoiding duplicating compressed payload in memory
                let stagedArchiveURL = stagingDir.appendingPathComponent("archive.zip")
                try fileManager.copyItem(at: fileURL, to: stagedArchiveURL)

                let extractedRoot = stagingDir.appendingPathComponent("extracted", isDirectory: true)
                try fileManager.createDirectory(at: extractedRoot, withIntermediateDirectories: true)

                guard let archive = try? Archive(url: stagedArchiveURL, accessMode: .read) else {
                    throw SkillImportError.archiveInspectionFailed(["Unable to open zip archive."])
                }

                let policy = HanlinArchivePolicy(limits: limits)

                let zipEntries = Array(archive)
                let entryMetadatas = try zipEntries.map { entry in
                    try Task.checkCancellation()
                    guard let compressed = Int64(exactly: entry.compressedSize),
                          let expanded = Int64(exactly: entry.uncompressedSize) else {
                        throw SkillImportError.archiveInspectionFailed(["Archive entry byte count cannot be represented: \(entry.path)"])
                    }
                    return HanlinArchiveEntryMetadata(
                        path: entry.path,
                        kind: Self.mapEntryKind(entry.type),
                        compressedBytes: compressed,
                        uncompressedBytes: expanded
                    )
                }

                let inspection = policy.inspectSkillArchive(
                    entries: entryMetadatas,
                    centralDirectoryEntryCount: zipEntries.count,
                    archiveBytes: fileSize
                )

                guard inspection.isInstallable else {
                    throw SkillImportError.archiveInspectionFailed(inspection.findings.map(\.message))
                }

                // Locate SKILL.md entries
                let ignored = Set(inspection.ignoredEntries)
                let validFiles = zipEntries.filter { entry in
                    !ignored.contains(entry.path) && entry.type != .directory
                }

                let skillMarkdownEntries = validFiles.filter { entry in
                    let norm = entry.path.replacingOccurrences(of: "\\", with: "/")
                    let filename = (norm as NSString).lastPathComponent
                    return filename == "SKILL.md"
                }

                guard !skillMarkdownEntries.isEmpty else {
                    throw SkillImportError.missingSkillMarkdown
                }
                guard skillMarkdownEntries.count == 1 else {
                    throw SkillImportError.multipleSkillMarkdownFiles(skillMarkdownEntries.map(\.path))
                }

                // Extract all non-ignored entries safely
                var expandedBytes: Int64 = 0
                for entry in zipEntries where !ignored.contains(entry.path) {
                    try Task.checkCancellation()
                    guard let normalized = HanlinArchivePolicy.normalizedRelativePath(entry.path) else {
                        throw SkillImportError.archiveInspectionFailed(["Archive entry normalization failed: \(entry.path)"])
                    }
                    let dest = extractedRoot.appendingPathComponent(normalized)
                    guard Self.isContained(dest, in: extractedRoot) else {
                        throw SkillImportError.extractionEscapedRoot(entry.path)
                    }
                    if entry.type == .directory {
                        try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
                    } else if entry.type == .symlink {
                        try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                        let checksum = try archive.extract(entry, to: dest, allowUncontainedSymlinks: false)
                        guard checksum == entry.checksum else {
                            throw SkillImportError.archiveInspectionFailed(["Archive checksum mismatch: \(entry.path)"])
                        }
                    } else {
                        try Self.extractFile(entry, archive: archive, to: dest, limits: limits, expandedBytes: &expandedBytes)
                    }
                }

                // Find skill root: either wrapper directory containing SKILL.md or extractedRoot
                let skillMDEntry = skillMarkdownEntries[0]
                let normSkillMDPath = HanlinArchivePolicy.normalizedRelativePath(skillMDEntry.path)
                    ?? skillMDEntry.path.replacingOccurrences(of: "\\", with: "/")
                let skillMDDest = extractedRoot.appendingPathComponent(normSkillMDPath)
                let skillRoot = skillMDDest.deletingLastPathComponent()

                guard let content = try? String(contentsOf: skillMDDest, encoding: .utf8) else {
                    throw SkillImportError.invalidFrontmatter("SKILL.md is not readable or not valid UTF-8.")
                }

                let parsed: SkillMarkdownParser.ParsedSkillMarkdown
                do {
                    parsed = try SkillMarkdownParser.parse(content)
                } catch {
                    throw SkillImportError.invalidFrontmatter(error.localizedDescription)
                }

                guard let skillID = try? HanlinSkillID(validating: parsed.name) else {
                    throw SkillImportError.invalidFrontmatter("Skill name '\(parsed.name)' in frontmatter is not a valid identifier.")
                }

                let hanlinJSONURL = skillRoot.appendingPathComponent("hanlin.json")
                var meta: HanlinSkillMetadata
                if let metaData = try? Data(contentsOf: hanlinJSONURL),
                   let parsedMeta = try? HanlinSkillMetadata.decoder().decode(HanlinSkillMetadata.self, from: metaData) {
                    meta = parsedMeta
                    meta.originURL = originURL
                    meta.sha256 = sha256
                } else {
                    meta = HanlinSkillMetadata(
                        preferredToolIDs: [],
                        triggerHints: [],
                        keywords: [],
                        baseSkillID: nil,
                        originURL: originURL,
                        sha256: sha256,
                        isEnabled: true,
                        installedAt: Date(),
                        updatedAt: Date()
                    )
                    if let encoded = try? JSONEncoder().encode(meta) {
                        try? encoded.write(to: hanlinJSONURL)
                    }
                }

                // List resources
                let resources = try Self.scanResources(in: skillRoot)

                return StagedSkillPackage(
                    stagingDirectoryURL: stagingDir,
                    skillRootDirectoryURL: skillRoot,
                    skillID: skillID,
                    parsedMarkdown: parsed,
                    metadata: meta,
                    resources: resources,
                    sha256: sha256,
                    originURL: originURL
                )
            }
        } catch {
            try? fileManager.removeItem(at: stagingDir)
            throw error
        }
    }

    /// Hashing and extraction stay off the presentation actor. Cancellation owns
    /// the staging directory until the completed preview is handed to the caller.
    public func stageAndInspectInBackground(fileURL: URL, originURL: String? = nil,
                                            limits: HanlinArchiveLimits = .autonomousSkillImport) async throws -> StagedSkillPackage {
        let worker = Task.detached(priority: .userInitiated) {
            try self.stageAndInspect(fileURL: fileURL, originURL: originURL, limits: limits)
        }
        let staged = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        do { try Task.checkCancellation() }
        catch { staged.cleanup(); throw error }
        return staged
    }

    // MARK: - Download from HTTPS URL

    public func downloadAndStage(from httpsURL: URL, sessionConfiguration: URLSessionConfiguration? = nil,
                                 limits: HanlinArchiveLimits = .autonomousSkillImport,
                                 downloadProgress: (@Sendable (Int64, Int64?) -> Void)? = nil) async throws -> StagedSkillPackage {
        guard let scheme = httpsURL.scheme?.lowercased(), scheme == "https" else {
            throw SkillImportError.nonHTTPSURLForbidden
        }

        var request = URLRequest(url: httpsURL)
        request.httpMethod = "GET"

        let config = sessionConfiguration ?? AgentRuntimeUIAcceptanceProvider.makeSessionConfiguration()
        let downloader = BoundedStreamDownloader(maxBytes: limits.maximumArchiveBytes == .max ? nil : limits.maximumArchiveBytes,
            sessionConfiguration: config, progress: { update in downloadProgress?(update.receivedBytes, update.expectedBytes) })
        let (downloadedFile, response) = try await downloader.download(request: request)
        defer { try? fileManager.removeItem(at: downloadedFile) }

        let ext: String
        if httpsURL.pathExtension.lowercased() == "md" {
            ext = "md"
        } else if let mime = (response.allHeaderFields["Content-Type"] as? String)?.lowercased(),
                  mime.contains("text/markdown") {
            ext = "md"
        } else {
            ext = "zip"
        }

        let tempFile = fileManager.temporaryDirectory.appendingPathComponent("download-\(UUID().uuidString).\(ext)")
        try fileManager.moveItem(at: downloadedFile, to: tempFile)
        defer { try? fileManager.removeItem(at: tempFile) }

        try Task.checkCancellation()
        return try await stageAndInspectInBackground(fileURL: tempFile, originURL: httpsURL.absoluteString, limits: limits)
    }

    // MARK: - Final Installation into SkillStore

    @MainActor
    public func install(staged: StagedSkillPackage, store: SkillStore = .shared) throws -> HanlinSkillDescriptor {
        let record = try store.install(stagedPackage: staged)
        try? fileManager.removeItem(at: staged.stagingDirectoryURL)
        return record.descriptor
    }

    // MARK: - Containment & Private Helpers

    private static func extractFile(_ entry: Entry, archive: Archive, to destination: URL,
                                    limits: HanlinArchiveLimits, expandedBytes: inout Int64) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: destination, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: destination)
        var written: Int64 = 0
        do {
            let checksum = try archive.extract(entry, bufferSize: 65_536, skipCRC32: false) { chunk in
                try Task.checkCancellation()
                let (next, overflow) = expandedBytes.addingReportingOverflow(Int64(chunk.count))
                guard !overflow, next <= limits.maximumUncompressedBytes else {
                    throw SkillImportError.archiveInspectionFailed(["Extracted bytes exceed the configured storage budget."])
                }
                try handle.write(contentsOf: chunk)
                expandedBytes = next
                written += Int64(chunk.count)
            }
            try handle.close()
            guard checksum == entry.checksum, UInt64(written) == entry.uncompressedSize else {
                throw SkillImportError.archiveInspectionFailed(["Archive checksum or length mismatch: \(entry.path)"])
            }
            try FileManager.default.setAttributes(entry.fileAttributes, ofItemAtPath: destination.path)
        } catch {
            try? handle.close()
            throw error
        }
    }

    public static func isContained(_ url: URL, in parent: URL) -> Bool {
        let canonParent = parent.resolvingSymlinksInPath().standardizedFileURL.path
        let parentPath = canonParent.hasSuffix("/") && canonParent.count > 1
            ? String(canonParent.dropLast())
            : canonParent
        let canonChild = url.resolvingSymlinksInPath().standardizedFileURL.path
        return canonChild == parentPath || canonChild.hasPrefix(parentPath + "/") || canonChild.hasPrefix(parentPath + "\\")
    }

    private static func mapEntryKind(_ type: Entry.EntryType) -> HanlinArchiveEntryKind {
        switch type {
        case .directory: return .directory
        case .file: return .file
        case .symlink: return .symbolicLink
        }
    }

    private static func scanResources(in root: URL) throws -> [SkillResourceFile] {
        var result: [SkillResourceFile] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles])
        while let fileURL = enumerator?.nextObject() as? URL {
            try Task.checkCancellation()
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            let name = fileURL.lastPathComponent
            if name == "SKILL.md" || name == "hanlin.json" { continue }

            let basePath = root.standardizedFileURL.path
            let filePath = fileURL.standardizedFileURL.path
            guard filePath.hasPrefix(basePath) else { continue }
            var relative = String(filePath.dropFirst(basePath.count))
            if relative.hasPrefix("/") { relative.removeFirst() }

            let bytes = Int64(values.fileSize ?? 0)
            let isBin = isBinary(path: relative)
            let mime = mime(for: relative)
            result.append(SkillResourceFile(relativePath: relative, byteCount: bytes, isBinary: isBin, mimeType: mime))
        }
        return result.sorted(by: { $0.relativePath < $1.relativePath })
    }

    private static func isBinary(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        let textExtensions: Set<String> = [
            "md", "txt", "json", "js", "ts", "py", "sh", "yaml", "yml", "csv", "xml", "html", "css"
        ]
        return !textExtensions.contains(ext)
    }

    private static func mime(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "md": return "text/markdown"
        case "txt": return "text/plain"
        case "json": return "application/json"
        case "js": return "application/javascript"
        case "ts": return "application/typescript"
        case "py": return "text/x-python"
        case "sh": return "text/x-shellscript"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}
