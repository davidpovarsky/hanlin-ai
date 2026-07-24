import Foundation

struct MCPResolvedServerPaths: Hashable, Sendable {
    let packageRoot: URL
    let entryPoint: URL
    let entryPointRelativePath: String
    let requiredMigration: Bool
}

struct MCPServerPathDiagnostics: Sendable {
    let serverID: UUID
    let packageName: String
    let persistedPackageRoot: String
    let expectedCanonicalPackageRoot: String
    let persistedEntryPoint: String
    let derivedRelativeEntryPoint: String?
    let canonicalEntryPoint: String?
    let packageDirectoryExists: Bool
    let entryPointExists: Bool
    let persistedRootMatchesServerID: Bool
    let canonicalEntryPointIsInsideRoot: Bool

    var logFields: [String: String] {
        [
            "serverID": serverID.uuidString.lowercased(),
            "packageName": packageName,
            "persistedPackageRoot": persistedPackageRoot,
            "expectedCanonicalPackageRoot": expectedCanonicalPackageRoot,
            "persistedEntryPoint": persistedEntryPoint,
            "derivedRelativeEntryPoint": derivedRelativeEntryPoint ?? "<unresolved>",
            "canonicalEntryPoint": canonicalEntryPoint ?? "<unresolved>",
            "packageDirectoryExists": String(packageDirectoryExists),
            "entryPointExists": String(entryPointExists),
            "persistedRootMatchesServerID": String(persistedRootMatchesServerID),
            "canonicalEntryPointIsInsideRoot": String(canonicalEntryPointIsInsideRoot)
        ]
    }
}

enum MCPServerPathResolutionError: LocalizedError, Sendable, Equatable {
    case packageRootInvalid
    case packageDirectoryMissing
    case entryPointInvalid
    case entryPointMissing
    case symbolicLinkEscape
    case migrationFailed(String)

    var failureKind: MCPServerFailureKind {
        switch self {
        case .packageRootInvalid:
            .packagePathInvalid
        case .packageDirectoryMissing:
            .packageInstallationMissing
        case .entryPointInvalid, .symbolicLinkEscape:
            .entryPointInvalid
        case .entryPointMissing:
            .entryPointMissing
        case .migrationFailed:
            .registryMigrationFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .packageRootInvalid:
            "The saved package path does not belong to this MCP server."
        case .packageDirectoryMissing:
            "The MCP server package directory is missing. Repair or reinstall the server."
        case .entryPointInvalid:
            "The saved MCP entry point is not a safe relative package path."
        case .entryPointMissing:
            "The MCP server entry point is missing. Repair or reinstall the server."
        case .symbolicLinkEscape:
            "The MCP server entry point escapes its package through a symbolic link."
        case .migrationFailed(let reason):
            "The MCP package path could not be migrated: \(reason)"
        }
    }
}

struct MCPServerPathResolver: Sendable {
    private let fileLayout: MCPFileLayout

    init(fileLayout: MCPFileLayout = .default) {
        self.fileLayout = fileLayout
    }

    func resolve(_ descriptor: MCPServerDescriptor) throws -> MCPResolvedServerPaths {
        try fileLayout.prepareIfNeeded()
        let packageRoot = fileLayout.serverDirectory(id: descriptor.id).standardizedFileURL
        try validatePackageRoot(packageRoot)
        let layoutMigrated = try migrateNestedPackageIfNeeded(at: packageRoot)
        try validatePackageRoot(packageRoot)
        guard isDirectory(packageRoot) else {
            throw MCPServerPathResolutionError.packageDirectoryMissing
        }

        let relativePath = try resolveRelativeEntryPoint(
            descriptor: descriptor,
            packageRoot: packageRoot
        )
        let entryPoint = try validatedEntryPoint(
            relativePath: relativePath,
            packageRoot: packageRoot
        )
        let requiredMigration = layoutMigrated
            || descriptor.packageRoot != packageRoot.path
            || descriptor.entryPoint != entryPoint.path
            || descriptor.entryPointRelativePath != relativePath

        return MCPResolvedServerPaths(
            packageRoot: packageRoot,
            entryPoint: entryPoint,
            entryPointRelativePath: relativePath,
            requiredMigration: requiredMigration
        )
    }

    func diagnostics(for descriptor: MCPServerDescriptor) -> MCPServerPathDiagnostics {
        let packageRoot = fileLayout.serverDirectory(id: descriptor.id).standardizedFileURL
        let relative = try? resolveRelativeEntryPoint(
            descriptor: descriptor,
            packageRoot: packageRoot
        )
        let entryPoint = relative.flatMap {
            try? validatedEntryPoint(relativePath: $0, packageRoot: packageRoot)
        }
        return MCPServerPathDiagnostics(
            serverID: descriptor.id,
            packageName: descriptor.packageName,
            persistedPackageRoot: descriptor.packageRoot,
            expectedCanonicalPackageRoot: packageRoot.path,
            persistedEntryPoint: descriptor.entryPoint,
            derivedRelativeEntryPoint: relative,
            canonicalEntryPoint: entryPoint?.path,
            packageDirectoryExists: isDirectory(packageRoot)
                || isDirectory(packageRoot.appending(path: "package", directoryHint: .isDirectory)),
            entryPointExists: entryPoint.map { isRegularFile($0) } ?? false,
            persistedRootMatchesServerID: storedRootBelongsToServer(
                descriptor.packageRoot,
                serverID: descriptor.id
            ),
            canonicalEntryPointIsInsideRoot: entryPoint.map {
                isDescendant($0, of: packageRoot, allowRoot: false)
            } ?? false
        )
    }

    func migratedDescriptor(
        _ descriptor: MCPServerDescriptor,
        paths: MCPResolvedServerPaths
    ) -> MCPServerDescriptor {
        guard paths.requiredMigration else { return descriptor }
        var migrated = descriptor
        migrated.packageRoot = paths.packageRoot.path
        migrated.entryPoint = paths.entryPoint.path
        migrated.entryPointRelativePath = paths.entryPointRelativePath
        migrated.entryPointOptions = descriptor.entryPointOptions?.compactMap { option in
            guard let candidate = relativeEntryPointOption(
                entryPoint: option.entryPoint,
                packageRoot: descriptor.packageRoot
            ), let relative = try? validateRelativePath(candidate) else {
                return nil
            }
            var migratedOption = option
            migratedOption.entryPoint = paths.packageRoot.appending(path: relative).path
            return migratedOption
        }
        migrated.updatedAt = .now
        return migrated
    }

    private func resolveRelativeEntryPoint(
        descriptor: MCPServerDescriptor,
        packageRoot: URL
    ) throws -> String {
        if let persistedRelative = descriptor.entryPointRelativePath {
            return try validateRelativePath(persistedRelative)
        }

        if !storedRootBelongsToServer(descriptor.packageRoot, serverID: descriptor.id) {
            throw MCPServerPathResolutionError.packageRootInvalid
        }
        if let legacyRelative = relativePath(
            entryPoint: descriptor.entryPoint,
            packageRoot: descriptor.packageRoot
        ) {
            return try validateRelativePath(legacyRelative)
        }
        if let compatibilityEntry = descriptor.compatibility.entryPoint,
           !compatibilityEntry.isEmpty {
            return try validateRelativePath(compatibilityEntry)
        }

        let manifest = try installedManifest(at: packageRoot)
        if let binName = descriptor.binName,
           let bin = manifest["bin"] as? [String: Any],
           let value = bin[binName] as? String {
            return try validateRelativePath(value)
        }
        if let option = descriptor.entryPointOptions?.first(where: {
            $0.binName == descriptor.binName
        }), let relative = relativeEntryPointOption(
            entryPoint: option.entryPoint,
            packageRoot: descriptor.packageRoot
        ) {
            return try validateRelativePath(relative)
        }
        return try validateRelativePath(try manifestEntryPoint(manifest))
    }

    private func validatedEntryPoint(
        relativePath: String,
        packageRoot: URL
    ) throws -> URL {
        let safeRelative = try validateRelativePath(relativePath)
        let candidate = packageRoot.appending(path: safeRelative).standardizedFileURL
        guard isDescendant(candidate, of: packageRoot, allowRoot: false) else {
            throw MCPServerPathResolutionError.entryPointInvalid
        }
        let resolvedRoot = packageRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedEntryPoint = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard isDescendant(resolvedEntryPoint, of: resolvedRoot, allowRoot: false) else {
            throw MCPServerPathResolutionError.symbolicLinkEscape
        }
        try rejectSymbolicLinks(from: packageRoot, to: candidate)
        guard isRegularFile(candidate) else {
            throw MCPServerPathResolutionError.entryPointMissing
        }
        return candidate
    }

    private func validatePackageRoot(_ packageRoot: URL) throws {
        let serversRoot = fileLayout.servers.standardizedFileURL
        guard isDescendant(packageRoot, of: serversRoot, allowRoot: false) else {
            throw MCPServerPathResolutionError.packageRootInvalid
        }
        guard FileManager.default.fileExists(atPath: packageRoot.path) else { return }
        if try packageRoot.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw MCPServerPathResolutionError.packageRootInvalid
        }
        let resolvedServersRoot = serversRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedPackageRoot = packageRoot.resolvingSymlinksInPath().standardizedFileURL
        guard isDescendant(
            resolvedPackageRoot,
            of: resolvedServersRoot,
            allowRoot: false
        ) else {
            throw MCPServerPathResolutionError.packageRootInvalid
        }
    }

    private func validateRelativePath(_ value: String) throws -> String {
        var normalized = value.replacingOccurrences(of: "\\", with: "/")
        while normalized.hasPrefix("./") {
            normalized.removeFirst(2)
        }
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !(normalized as NSString).isAbsolutePath,
              !normalized.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".."
              }) else {
            throw MCPServerPathResolutionError.entryPointInvalid
        }
        return normalized
    }

    private func relativeEntryPointOption(
        entryPoint: String,
        packageRoot: String
    ) -> String? {
        if !(entryPoint as NSString).isAbsolutePath {
            return entryPoint
        }
        return relativePath(entryPoint: entryPoint, packageRoot: packageRoot)
    }

    private func storedRootBelongsToServer(_ path: String, serverID: UUID) -> Bool {
        let components = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL.pathComponents.map { $0.lowercased() }
        let id = serverID.uuidString.lowercased()
        guard let idIndex = components.lastIndex(of: id) else { return false }
        let suffix = Array(components.suffix(from: idIndex))
        guard suffix == [id] || suffix == [id, "package"] else { return false }
        guard idIndex > 0 else { return false }
        return ["mcp", "servers"].contains(components[idIndex - 1])
    }

    private func relativePath(entryPoint: String, packageRoot: String) -> String? {
        let root = URL(fileURLWithPath: packageRoot, isDirectory: true).standardizedFileURL.path
        let entry = URL(fileURLWithPath: entryPoint).standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard entry.hasPrefix(prefix) else { return nil }
        return String(entry.dropFirst(prefix.count))
    }

    private func installedManifest(at packageRoot: URL) throws -> [String: Any] {
        let url = packageRoot.appending(path: "package.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let manifest = object as? [String: Any] else {
            throw MCPServerPathResolutionError.entryPointMissing
        }
        return manifest
    }

    private func manifestEntryPoint(_ manifest: [String: Any]) throws -> String {
        if let bin = manifest["bin"] as? String { return bin }
        if let bin = manifest["bin"] as? [String: Any] {
            let values = bin.values.compactMap { $0 as? String }
            if values.count == 1, let value = values.first { return value }
        }
        if let exports = manifest["exports"] as? String { return exports }
        if let exports = manifest["exports"] as? [String: Any] {
            let rootExport: Any = exports["."] ?? exports
            if let value = rootExport as? String { return value }
            if let variants = rootExport as? [String: Any] {
                for key in ["import", "require", "default"] {
                    if let value = variants[key] as? String { return value }
                }
            }
        }
        if let main = manifest["main"] as? String { return main }
        throw MCPServerPathResolutionError.entryPointInvalid
    }

    private func migrateNestedPackageIfNeeded(at canonicalRoot: URL) throws -> Bool {
        let manager = FileManager.default
        let canonicalManifest = canonicalRoot.appending(path: "package.json")
        if manager.fileExists(atPath: canonicalManifest.path) { return false }

        let nestedPackage = canonicalRoot.appending(path: "package", directoryHint: .isDirectory)
        let nestedManifest = nestedPackage.appending(path: "package.json")
        guard manager.fileExists(atPath: nestedManifest.path) else { return false }
        do {
            try rejectSymbolicLinks(from: canonicalRoot, to: nestedPackage)
            try manager.createDirectory(at: fileLayout.staging, withIntermediateDirectories: true)
            let operationID = UUID().uuidString.lowercased()
            let staged = fileLayout.staging.appending(
                path: "path-migration-\(operationID)",
                directoryHint: .isDirectory
            )
            let backup = fileLayout.staging.appending(
                path: "path-migration-backup-\(operationID)",
                directoryHint: .isDirectory
            )
            try manager.copyItem(at: nestedPackage, to: staged)
            try manager.moveItem(at: canonicalRoot, to: backup)
            do {
                try manager.moveItem(at: staged, to: canonicalRoot)
                try? manager.removeItem(at: backup)
            } catch {
                try? manager.removeItem(at: canonicalRoot)
                try? manager.moveItem(at: backup, to: canonicalRoot)
                try? manager.removeItem(at: staged)
                throw error
            }
            return true
        } catch {
            throw MCPServerPathResolutionError.migrationFailed(error.localizedDescription)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func isDescendant(_ candidate: URL, of root: URL, allowRoot: Bool) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        if allowRoot, candidatePath == rootPath { return true }
        return candidatePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    private func rejectSymbolicLinks(from root: URL, to candidate: URL) throws {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        guard candidateComponents.starts(with: rootComponents) else {
            throw MCPServerPathResolutionError.symbolicLinkEscape
        }
        var current = root.standardizedFileURL
        for component in candidateComponents.dropFirst(rootComponents.count) {
            current.append(path: component)
            guard FileManager.default.fileExists(atPath: current.path) else { continue }
            if try current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw MCPServerPathResolutionError.symbolicLinkEscape
            }
        }
    }
}
