import Foundation
import HanlinPlatformContracts

/// Persistent store managing user-created, imported, and overridden Agent Skills.
/// Storage root: `Application Support/AgentSkills/`
/// Structure:
///   `skills/<id>/SKILL.md`
///   `skills/<id>/hanlin.json`
///   `skills/<id>/references/...`
///   `skills/<id>/scripts/...`
///   `skills/<id>/assets/...`
///   `overrides/<id>/SKILL.md`
///   `overrides/<id>/hanlin.json`
///   `state.json` (enabled toggles and metadata)
@MainActor
public final class SkillStore {
    public static let shared = SkillStore()

    public let rootDirectoryURL: URL
    private let skillsDirectoryURL: URL
    private let overridesDirectoryURL: URL
    private let stateFileURL: URL
    private let fileManager = FileManager.default

    public struct StoreState: Codable, Sendable {
        public var disabledSkillIDs: Set<String>
        public var metadataBySkillID: [String: HanlinSkillMetadata]

        public init(
            disabledSkillIDs: Set<String> = [],
            metadataBySkillID: [String: HanlinSkillMetadata] = [:]
        ) {
            self.disabledSkillIDs = disabledSkillIDs
            self.metadataBySkillID = metadataBySkillID
        }
    }

    private var cachedState: StoreState

    public init(rootDirectoryURL: URL? = nil) {
        let base: URL
        if let rootDirectoryURL {
            base = rootDirectoryURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            base = appSupport.appendingPathComponent("AgentSkills", isDirectory: true)
        }
        self.rootDirectoryURL = base
        self.skillsDirectoryURL = base.appendingPathComponent("skills", isDirectory: true)
        self.overridesDirectoryURL = base.appendingPathComponent("overrides", isDirectory: true)
        self.stateFileURL = base.appendingPathComponent("state.json", isDirectory: false)

        try? fileManager.createDirectory(at: skillsDirectoryURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: overridesDirectoryURL, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: stateFileURL),
           let loaded = try? HanlinSkillMetadata.decoder().decode(StoreState.self, from: data) {
            self.cachedState = loaded
        } else {
            self.cachedState = StoreState()
        }
    }

    // MARK: - State Persistence

    private func saveState() {
        let encoder = HanlinSkillMetadata.encoder()
        if let data = try? encoder.encode(cachedState) {
            try? data.write(to: stateFileURL, options: .atomic)
        }
    }

    // MARK: - Enable / Disable

    public func isSkillEnabled(id: HanlinSkillID) -> Bool {
        !cachedState.disabledSkillIDs.contains(id.rawValue)
    }

    public func setSkillEnabled(id: HanlinSkillID, enabled: Bool) {
        if enabled {
            cachedState.disabledSkillIDs.remove(id.rawValue)
        } else {
            cachedState.disabledSkillIDs.insert(id.rawValue)
        }
        saveState()
        HanlinSkillCatalog.shared.refreshFromStore()
    }

    // MARK: - Query

    public func hasOverride(for skillID: HanlinSkillID) -> Bool {
        let dir = overridesDirectoryURL.appendingPathComponent(skillID.rawValue, isDirectory: true)
        let skillFile = dir.appendingPathComponent("SKILL.md", isDirectory: false)
        return fileManager.fileExists(atPath: skillFile.path)
    }

    public func overrideDescriptor(for skillID: HanlinSkillID) -> HanlinSkillDescriptor? {
        guard hasOverride(for: skillID) else { return nil }
        let dir = overridesDirectoryURL.appendingPathComponent(skillID.rawValue, isDirectory: true)
        return loadDescriptor(from: dir, skillID: skillID, isOverride: true)
    }

    public func allCustomSkillDescriptors() -> [HanlinSkillDescriptor] {
        guard let subdirs = try? fileManager.contentsOfDirectory(at: skillsDirectoryURL, includingPropertiesForKeys: nil) else {
            return []
        }
        var descriptors: [HanlinSkillDescriptor] = []
        for dir in subdirs {
            guard let skillID = try? HanlinSkillID(validating: dir.lastPathComponent) else { continue }
            if let desc = loadDescriptor(from: dir, skillID: skillID, isOverride: false) {
                descriptors.append(desc)
            }
        }
        return descriptors.sorted(by: { $0.id.rawValue < $1.id.rawValue })
    }

    public func allOverrideDescriptors() -> [(HanlinSkillID, HanlinSkillDescriptor)] {
        guard let subdirs = try? fileManager.contentsOfDirectory(at: overridesDirectoryURL, includingPropertiesForKeys: nil) else {
            return []
        }
        var overrides: [(HanlinSkillID, HanlinSkillDescriptor)] = []
        for dir in subdirs {
            guard let skillID = try? HanlinSkillID(validating: dir.lastPathComponent) else { continue }
            if let desc = loadDescriptor(from: dir, skillID: skillID, isOverride: true) {
                overrides.append((skillID, desc))
            }
        }
        return overrides
    }

    public func disabledSkillIDs() -> Set<HanlinSkillID> {
        var result = Set<HanlinSkillID>()
        for raw in cachedState.disabledSkillIDs {
            if let id = try? HanlinSkillID(validating: raw) {
                result.insert(id)
            }
        }
        return result
    }

    public func allStoredRecords() -> [StoredSkillRecord] {
        var records: [StoredSkillRecord] = []
        let customDescriptors = allCustomSkillDescriptors()
        for desc in customDescriptors {
            let dir = skillsDirectoryURL.appendingPathComponent(desc.id.rawValue, isDirectory: true)
            let meta = cachedState.metadataBySkillID[desc.id.rawValue]
            let resources = listResources(for: desc.id)
            let isEnabled = isSkillEnabled(id: desc.id)
            let sourceKind: SkillSourceKind = (meta?.originURL != nil) ? .imported : .custom
            records.append(StoredSkillRecord(
                descriptor: desc,
                sourceKind: sourceKind,
                isEnabled: isEnabled,
                isOverride: false,
                baseSkillID: meta?.baseSkillID,
                originURL: meta?.originURL,
                sha256: meta?.sha256,
                directoryURL: dir,
                resources: resources,
                installedAt: meta?.installedAt ?? Date(),
                updatedAt: meta?.updatedAt ?? Date()
            ))
        }
        return records
    }

    // MARK: - Resource Paths & Progress Loading

    public func directoryURL(for skillID: HanlinSkillID) -> URL? {
        let overrideDir = overridesDirectoryURL.appendingPathComponent(skillID.rawValue, isDirectory: true)
        if fileManager.fileExists(atPath: overrideDir.path) {
            return overrideDir
        }
        let customDir = skillsDirectoryURL.appendingPathComponent(skillID.rawValue, isDirectory: true)
        if fileManager.fileExists(atPath: customDir.path) {
            return customDir
        }
        return nil
    }

    public func safeResourceURL(for skillID: HanlinSkillID, relativePath: String) -> URL? {
        guard let base = directoryURL(for: skillID) else { return nil }
        let cleanRelative = relativePath.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !cleanRelative.isEmpty,
              !cleanRelative.hasPrefix("/"),
              !cleanRelative.contains("\0") else {
            return nil
        }
        let components = cleanRelative.split(separator: "/")
        guard !components.contains(".."), !components.contains("."), !components.contains("") else {
            return nil
        }
        let candidate = base.appendingPathComponent(cleanRelative)
        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedBase = base.standardizedFileURL.resolvingSymlinksInPath()

        let basePath = resolvedBase.path
        let candidatePath = resolvedCandidate.path
        let basePathWithSlash = basePath.hasSuffix("/") ? basePath : basePath + "/"

        guard candidatePath == basePath || candidatePath.hasPrefix(basePathWithSlash) else {
            return nil
        }
        guard fileManager.fileExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }

    public func listResources(for skillID: HanlinSkillID) -> [SkillResourceFile] {
        guard let base = directoryURL(for: skillID) else { return [] }
        var result: [SkillResourceFile] = []
        let enumerator = fileManager.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles])
        while let fileURL = enumerator?.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            let name = fileURL.lastPathComponent
            if name == "SKILL.md" || name == "hanlin.json" { continue }

            let basePath = base.standardizedFileURL.path
            let filePath = fileURL.standardizedFileURL.path
            guard filePath.hasPrefix(basePath) else { continue }
            var relative = String(filePath.dropFirst(basePath.count))
            if relative.hasPrefix("/") { relative.removeFirst() }

            let bytes = Int64(values.fileSize ?? 0)
            let isBin = Self.isBinaryFile(path: relative)
            let mime = Self.mimeType(for: relative)
            result.append(SkillResourceFile(relativePath: relative, byteCount: bytes, isBinary: isBin, mimeType: mime))
        }
        return result.sorted(by: { $0.relativePath < $1.relativePath })
    }

    // MARK: - Mutations

    public func saveCustomSkill(
        id: HanlinSkillID,
        title: String,
        description: String,
        instructions: String,
        preferredToolIDs: [String] = [],
        triggerHints: [String] = [],
        keywords: [String] = [],
        originURL: String? = nil,
        sha256: String? = nil
    ) throws {
        let dir = skillsDirectoryURL.appendingPathComponent(id.rawValue, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let effectiveDesc = description.isEmpty ? title : description
        let skillMD = SkillMarkdownParser.serialize(name: id.rawValue, title: title, description: effectiveDesc, body: instructions)
        let skillMDURL = dir.appendingPathComponent("SKILL.md")
        try skillMD.data(using: .utf8)?.write(to: skillMDURL, options: .atomic)

        let existingMeta = cachedState.metadataBySkillID[id.rawValue]
        let meta = HanlinSkillMetadata(
            preferredToolIDs: preferredToolIDs,
            triggerHints: triggerHints,
            keywords: keywords,
            baseSkillID: nil,
            originURL: originURL ?? existingMeta?.originURL,
            sha256: sha256 ?? existingMeta?.sha256,
            isEnabled: isSkillEnabled(id: id),
            installedAt: existingMeta?.installedAt ?? Date(),
            updatedAt: Date()
        )
        let metaURL = dir.appendingPathComponent("hanlin.json")
        let encoder = HanlinSkillMetadata.encoder()
        let metaData = try encoder.encode(meta)
        try metaData.write(to: metaURL, options: .atomic)

        cachedState.metadataBySkillID[id.rawValue] = meta
        saveState()
        HanlinSkillCatalog.shared.refreshFromStore()
    }

    public func install(stagedPackage: StagedSkillPackage) throws -> StoredSkillRecord {
        let id = stagedPackage.skillID
        let targetDir = skillsDirectoryURL.appendingPathComponent(id.rawValue, isDirectory: true)
        let backupDir = skillsDirectoryURL.appendingPathComponent(".backup-\(id.rawValue)-\(UUID().uuidString)", isDirectory: true)

        let hadExisting = fileManager.fileExists(atPath: targetDir.path)
        let previousMeta = cachedState.metadataBySkillID[id.rawValue]
        if hadExisting {
            try fileManager.moveItem(at: targetDir, to: backupDir)
        }

        do {
            try fileManager.moveItem(at: stagedPackage.skillRootDirectoryURL, to: targetDir)

            guard let descriptor = loadDescriptor(from: targetDir, skillID: id, isOverride: false) else {
                throw SkillImportError.invalidFrontmatter("Could not load installed skill descriptor.")
            }

            var meta = stagedPackage.metadata
            meta.originURL = stagedPackage.originURL ?? meta.originURL
            meta.sha256 = stagedPackage.sha256 ?? meta.sha256
            meta.updatedAt = Date()
            cachedState.metadataBySkillID[id.rawValue] = meta
            saveState()
            HanlinSkillCatalog.shared.refreshFromStore()

            if hadExisting {
                try? fileManager.removeItem(at: backupDir)
            }

            return StoredSkillRecord(
                descriptor: descriptor,
                sourceKind: stagedPackage.originURL != nil ? .imported : .custom,
                isEnabled: isSkillEnabled(id: id),
                isOverride: false,
                baseSkillID: nil,
                originURL: meta.originURL,
                sha256: meta.sha256,
                directoryURL: targetDir,
                resources: listResources(for: id),
                installedAt: meta.installedAt,
                updatedAt: meta.updatedAt
            )
        } catch {
            if fileManager.fileExists(atPath: targetDir.path) {
                try? fileManager.removeItem(at: targetDir)
            }
            if hadExisting && fileManager.fileExists(atPath: backupDir.path) {
                try? fileManager.moveItem(at: backupDir, to: targetDir)
            }
            cachedState.metadataBySkillID[id.rawValue] = previousMeta
            saveState()
            HanlinSkillCatalog.shared.refreshFromStore()
            throw error
        }
    }

    public func addOrUpdateTextResource(for skillID: HanlinSkillID, relativePath: String, content: String) throws {
        guard let base = directoryURL(for: skillID) else {
            throw SkillImportError.stagingFailed("Skill '\(skillID.rawValue)' directory not found.")
        }
        let clean = relativePath.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !clean.isEmpty, !clean.split(separator: "/").contains(".."), !clean.contains("\0"), !clean.hasPrefix("/") else {
            throw SkillImportError.stagingFailed("Invalid resource path '\(relativePath)'.")
        }
        let fileURL = base.appendingPathComponent(clean)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        HanlinSkillCatalog.shared.refreshFromStore()
    }

    public func addResourceFile(for skillID: HanlinSkillID, relativePath: String, sourceFileURL: URL) throws {
        guard let base = directoryURL(for: skillID) else {
            throw SkillImportError.stagingFailed("Skill '\(skillID.rawValue)' directory not found.")
        }
        let clean = relativePath.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !clean.isEmpty, !clean.split(separator: "/").contains(".."), !clean.contains("\0"), !clean.hasPrefix("/") else {
            throw SkillImportError.stagingFailed("Invalid resource path '\(relativePath)'.")
        }
        let fileURL = base.appendingPathComponent(clean)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        try fileManager.copyItem(at: sourceFileURL, to: fileURL)
        HanlinSkillCatalog.shared.refreshFromStore()
    }

    public func deleteResource(for skillID: HanlinSkillID, relativePath: String) throws {
        guard let url = safeResourceURL(for: skillID, relativePath: relativePath) else {
            throw SkillImportError.stagingFailed("Resource '\(relativePath)' not found.")
        }
        try fileManager.removeItem(at: url)
        HanlinSkillCatalog.shared.refreshFromStore()
    }

    public func createOrUpdateOverride(
        for baseSkill: HanlinSkillDescriptor,
        newTitle: String? = nil,
        newDescription: String? = nil,
        newInstructions: String,
        preferredToolIDs: [String]? = nil,
        triggerHints: [String]? = nil,
        keywords: [String]? = nil
    ) throws {
        let dir = overridesDirectoryURL.appendingPathComponent(baseSkill.id.rawValue, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let title = newTitle ?? baseSkill.title.preferredValue()
        let desc = newDescription ?? baseSkill.summary.preferredValue()
        let skillMD = SkillMarkdownParser.serialize(name: baseSkill.id.rawValue, title: title, description: desc, body: newInstructions)
        let skillMDURL = dir.appendingPathComponent("SKILL.md")
        try skillMD.data(using: .utf8)?.write(to: skillMDURL, options: .atomic)

        let tools = preferredToolIDs ?? baseSkill.preferredToolIDs
        let hints = triggerHints ?? baseSkill.triggerHints
        let kw = keywords ?? baseSkill.keywords

        let meta = HanlinSkillMetadata(
            preferredToolIDs: tools,
            triggerHints: hints,
            keywords: kw,
            baseSkillID: baseSkill.id.rawValue,
            originURL: nil,
            sha256: nil,
            isEnabled: isSkillEnabled(id: baseSkill.id),
            installedAt: cachedState.metadataBySkillID[baseSkill.id.rawValue]?.installedAt ?? Date(),
            updatedAt: Date()
        )
        let metaURL = dir.appendingPathComponent("hanlin.json")
        let encoder = HanlinSkillMetadata.encoder()
        let metaData = try encoder.encode(meta)
        try metaData.write(to: metaURL, options: .atomic)

        cachedState.metadataBySkillID[baseSkill.id.rawValue] = meta
        saveState()
        HanlinSkillCatalog.shared.refreshFromStore()
    }

    public func resetOverride(skillID: HanlinSkillID) {
        let dir = overridesDirectoryURL.appendingPathComponent(skillID.rawValue, isDirectory: true)
        try? fileManager.removeItem(at: dir)
        cachedState.metadataBySkillID.removeValue(forKey: skillID.rawValue)
        saveState()
        HanlinSkillCatalog.shared.refreshFromStore()
    }

    public func deleteCustomSkill(skillID: HanlinSkillID) {
        let dir = skillsDirectoryURL.appendingPathComponent(skillID.rawValue, isDirectory: true)
        try? fileManager.removeItem(at: dir)
        cachedState.metadataBySkillID.removeValue(forKey: skillID.rawValue)
        cachedState.disabledSkillIDs.remove(skillID.rawValue)
        saveState()
        HanlinSkillCatalog.shared.refreshFromStore()
    }

    // MARK: - Private Helpers

    private func loadDescriptor(from dir: URL, skillID: HanlinSkillID, isOverride: Bool) -> HanlinSkillDescriptor? {
        let skillFile = dir.appendingPathComponent("SKILL.md", isDirectory: false)
        guard let content = try? String(contentsOf: skillFile, encoding: .utf8),
              let parsed = try? SkillMarkdownParser.parse(content) else {
            return nil
        }
        let metaFile = dir.appendingPathComponent("hanlin.json", isDirectory: false)
        let meta: HanlinSkillMetadata?
        if let metaData = try? Data(contentsOf: metaFile) {
            meta = try? HanlinSkillMetadata.decoder().decode(HanlinSkillMetadata.self, from: metaData)
        } else {
            meta = cachedState.metadataBySkillID[skillID.rawValue]
        }

        let tools = meta?.preferredToolIDs ?? []
        let hints = meta?.triggerHints ?? []
        let keywords = meta?.keywords ?? []

        return try? HanlinSkillDescriptor(
            id: skillID,
            title: parsed.displayTitle,
            summary: parsed.description,
            instructions: .inline(parsed.body),
            keywords: keywords,
            triggerHints: hints,
            preferredToolIDs: tools
        )
    }

    private static func isBinaryFile(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        let textExtensions: Set<String> = [
            "md", "txt", "json", "js", "ts", "py", "sh", "yaml", "yml", "csv", "xml", "html", "css"
        ]
        return !textExtensions.contains(ext)
    }

    private static func mimeType(for path: String) -> String {
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
