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
        case .downloadExceedsLimit(let bytes): return "Skill download size (\(bytes) bytes) exceeds maximum 25 MB limit."
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
}

public final class SkillImporter: @unchecked Sendable {
    public static let shared = SkillImporter()
    public static let maxDownloadBytes: Int64 = 25 * 1_048_576

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

    public func stageAndInspect(fileURL: URL, originURL: String? = nil) throws -> StagedSkillPackage {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }

        let ext = fileURL.pathExtension.lowercased()
        guard ext == "zip" || ext == "md" else {
            throw SkillImportError.unsupportedFileType(ext)
        }

        let stagingDir = fileManager.temporaryDirectory.appendingPathComponent("skill-stage-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard Int64(data.count) <= Self.maxDownloadBytes else {
            throw SkillImportError.downloadExceedsLimit(Int64(data.count))
        }

        let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        if ext == "md" {
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
            // ZIP handling
            let stagedArchiveURL = stagingDir.appendingPathComponent("archive.zip")
            try data.write(to: stagedArchiveURL)

            let extractedRoot = stagingDir.appendingPathComponent("extracted", isDirectory: true)
            try fileManager.createDirectory(at: extractedRoot, withIntermediateDirectories: true)

            guard let archive = try? Archive(url: stagedArchiveURL, accessMode: .read) else {
                throw SkillImportError.archiveInspectionFailed(["Unable to open zip archive."])
            }

            let policy = HanlinArchivePolicy(limits: HanlinArchiveLimits(
                maximumArchiveBytes: Self.maxDownloadBytes,
                maximumFiles: 1_024,
                maximumDirectories: 256,
                maximumDepth: 16,
                maximumUncompressedBytes: 64 * 1_048_576,
                maximumCompressionRatio: 100
            ))

            let zipEntries = Array(archive)
            let entryMetadatas = zipEntries.map { entry in
                HanlinArchiveEntryMetadata(
                    path: entry.path,
                    kind: Self.mapEntryKind(entry.type),
                    compressedBytes: Int64(entry.compressedSize),
                    uncompressedBytes: Int64(entry.uncompressedSize)
                )
            }

            let inspection = policy.inspect(
                entries: entryMetadatas,
                centralDirectoryEntryCount: zipEntries.count,
                archiveBytes: Int64(data.count)
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
            for entry in zipEntries where !ignored.contains(entry.path) {
                guard let normalized = HanlinArchivePolicy.normalizedRelativePath(entry.path) else {
                    throw SkillImportError.extractionEscapedRoot(entry.path)
                }
                let dest = extractedRoot.appendingPathComponent(normalized)
                guard Self.isContained(dest, in: extractedRoot) else {
                    throw SkillImportError.extractionEscapedRoot(entry.path)
                }
                if entry.type == .directory {
                    try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
                } else {
                    try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    _ = try archive.extract(entry, to: dest, allowUncontainedSymlinks: false)
                }
            }

            // Find skill root: either wrapper directory containing SKILL.md or extractedRoot
            let skillMDEntry = skillMarkdownEntries[0]
            let normSkillMDPath = skillMDEntry.path.replacingOccurrences(of: "\\", with: "/")
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
               let parsedMeta = try? JSONDecoder().decode(HanlinSkillMetadata.self, from: metaData) {
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
            let resources = Self.scanResources(in: skillRoot)

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
    }

    // MARK: - Download from HTTPS URL

    public func downloadAndStage(from httpsURL: URL) async throws -> StagedSkillPackage {
        guard let scheme = httpsURL.scheme?.lowercased(), scheme == "https" else {
            throw SkillImportError.nonHTTPSURLForbidden
        }

        var request = URLRequest(url: httpsURL)
        request.httpMethod = "GET"

        let config = URLSessionConfiguration.ephemeral
        let delegate = HTTPSRedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SkillImportError.downloadFailed(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw SkillImportError.downloadFailed("HTTP Status \(httpResponse.statusCode)")
            }
        }

        guard Int64(data.count) <= Self.maxDownloadBytes else {
            throw SkillImportError.downloadExceedsLimit(Int64(data.count))
        }

        let tempFile = fileManager.temporaryDirectory.appendingPathComponent("download-\(UUID().uuidString).\(httpsURL.pathExtension.isEmpty ? "zip" : httpsURL.pathExtension)")
        try data.write(to: tempFile)
        defer { try? fileManager.removeItem(at: tempFile) }

        return try stageAndInspect(fileURL: tempFile, originURL: httpsURL.absoluteString)
    }

    // MARK: - Final Installation into SkillStore

    @MainActor
    public func install(staged: StagedSkillPackage, store: SkillStore = .shared) throws -> HanlinSkillDescriptor {
        let targetDir = store.rootDirectoryURL.appendingPathComponent("skills", isDirectory: true).appendingPathComponent(staged.skillID.rawValue, isDirectory: true)

        if fileManager.fileExists(atPath: targetDir.path) {
            try fileManager.removeItem(at: targetDir)
        }
        try fileManager.createDirectory(at: targetDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: staged.skillRootDirectoryURL, to: targetDir)

        try? fileManager.removeItem(at: staged.stagingDirectoryURL)

        store.setSkillEnabled(id: staged.skillID, enabled: true)
        try store.saveCustomSkill(
            id: staged.skillID,
            title: staged.parsedMarkdown.name,
            description: staged.parsedMarkdown.description,
            instructions: staged.parsedMarkdown.body,
            preferredToolIDs: staged.metadata.preferredToolIDs,
            triggerHints: staged.metadata.triggerHints,
            keywords: staged.metadata.keywords,
            originURL: staged.originURL,
            sha256: staged.sha256
        )

        HanlinSkillCatalog.shared.refreshFromStore()

        return try HanlinSkillDescriptor(
            id: staged.skillID,
            title: staged.parsedMarkdown.name,
            summary: staged.parsedMarkdown.description,
            instructions: .inline(staged.parsedMarkdown.body),
            keywords: staged.metadata.keywords,
            triggerHints: staged.metadata.triggerHints,
            preferredToolIDs: staged.metadata.preferredToolIDs
        )
    }

    // MARK: - Private Helpers

    private static func isContained(_ url: URL, in parent: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        return urlPath == parentPath || urlPath.hasPrefix(parentPath + "/") || urlPath.hasPrefix(parentPath + "\\")
    }

    private static func mapEntryKind(_ type: Entry.EntryType) -> HanlinArchiveEntryKind {
        switch type {
        case .directory: return .directory
        case .file: return .file
        case .symlink: return .symbolicLink
        }
    }

    private static func scanResources(in root: URL) -> [SkillResourceFile] {
        var result: [SkillResourceFile] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles])
        while let fileURL = enumerator?.nextObject() as? URL {
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

private final class HTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let scheme = request.url?.scheme?.lowercased(), scheme == "https" else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
