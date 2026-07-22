import Foundation

struct RuntimeFileLayout: Sendable {
    enum Client: String, CaseIterable, Sendable {
        case executions
        case agents
        case tools
        case mcp
    }

    let root: URL

    static let `default`: RuntimeFileLayout = {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return RuntimeFileLayout(
            root: applicationSupport
                .appending(path: "HanlinRuntime", directoryHint: .isDirectory)
                .appending(path: "v1", directoryHint: .isDirectory)
        )
    }()

    static let legacyMCPRoot: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "HanlinMCP", directoryHint: .isDirectory)

    var runtime: URL { directory("runtime") }
    var nodeRuntime: URL { runtime.appending(path: "node", directoryHint: .isDirectory) }
    var pythonRuntime: URL { runtime.appending(path: "python", directoryHint: .isDirectory) }
    var packages: URL { directory("packages") }
    var nodeGlobalPackages: URL { packages.appending(path: "node-global", directoryHint: .isDirectory) }
    var pythonPackages: URL { packages.appending(path: "python", directoryHint: .isDirectory) }
    var mcpPackages: URL { packages.appending(path: "mcp", directoryHint: .isDirectory) }
    var clients: URL { directory("clients") }
    var cache: URL { directory("cache") }
    var npmCache: URL { cache.appending(path: "npm", directoryHint: .isDirectory) }
    var pypiCache: URL { cache.appending(path: "pypi", directoryHint: .isDirectory) }
    var typeScriptCache: URL { cache.appending(path: "typescript", directoryHint: .isDirectory) }
    var staging: URL { directory("staging") }
    var temporary: URL { directory("tmp") }
    var logs: URL { directory("logs") }
    var registry: URL { directory("registry") }
    var environmentRegistry: URL { registry.appending(path: "RuntimeEnvironment.json") }
    var lifecycleApprovalRegistry: URL { registry.appending(path: "LifecycleApprovals.json") }

    var legacyMCPDataExists: Bool {
        FileManager.default.fileExists(atPath: Self.legacyMCPRoot.path)
    }

    func prepareIfNeeded() throws {
        let manager = FileManager.default
        let persistentDirectories = [
            root, runtime, nodeRuntime, pythonRuntime, packages, nodeGlobalPackages,
            pythonPackages, mcpPackages, clients, registry
        ]
        let reproducibleDirectories = [cache, npmCache, pypiCache, typeScriptCache, staging, temporary, logs]

        for directory in persistentDirectories + reproducibleDirectories {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for directory in [runtime, packages] + reproducibleDirectories {
            try excludeFromBackup(directory)
        }
    }

    func workspace(client: Client, identifier: String) throws -> URL {
        guard Self.isSafeIdentifier(identifier) else { throw RuntimeCoreError.invalidIdentifier }
        let clientRoot = clients.appending(path: client.rawValue, directoryHint: .isDirectory)
        let workspace = clientRoot.appending(path: identifier, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return try validatedDescendant(workspace, of: clientRoot, allowRoot: false)
    }

    func validatedDescendant(_ candidate: URL, of allowedRoot: URL, allowRoot: Bool = false) throws -> URL {
        guard candidate.isFileURL, allowedRoot.isFileURL else { throw RuntimeCoreError.invalidPath }
        let rootURL = allowedRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidateURL = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = rootURL.path
        let candidatePath = candidateURL.path
        let isRoot = candidatePath == rootPath
        let isChild = candidatePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
        guard (allowRoot && isRoot) || isChild else { throw RuntimeCoreError.pathEscapesRoot }
        try rejectSymbolicLinks(from: rootURL, to: candidate.standardizedFileURL)
        return candidateURL
    }

    private func directory(_ component: String) -> URL {
        root.appending(path: component, directoryHint: .isDirectory)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    private func rejectSymbolicLinks(from allowedRoot: URL, to candidate: URL) throws {
        let manager = FileManager.default
        var current = allowedRoot
        let rootComponents = allowedRoot.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        guard candidateComponents.starts(with: rootComponents) else { throw RuntimeCoreError.pathEscapesRoot }

        for component in candidateComponents.dropFirst(rootComponents.count) {
            current.append(path: component)
            guard manager.fileExists(atPath: current.path) else { continue }
            let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw RuntimeCoreError.symbolicLinkRejected }
        }
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil
            && value != "."
            && value != ".."
    }
}
