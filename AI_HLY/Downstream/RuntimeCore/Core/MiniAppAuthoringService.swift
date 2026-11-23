import Foundation
import HanlinPlatformContracts
import ZIPFoundation

/// One authoring route for agent tools and import preflight. The original Node compiler
/// and the SDK packaged with this app are shared; there is no independent UI typechecker.
@MainActor
enum MiniAppAuthoringService {
    /// Creates a writable project or edits the retained original source of an imported package.
    /// File writes use Foundation directly; no execution tool or new approval flow is involved.
    static func write(project: URL? = nil, files: [HanlinMiniAppSourceFile]) throws -> HanlinMiniAppSourceWriteReport {
        let manager = FileManager.default
        let requested: URL
        if let project {
            requested = project
        } else {
            let layout = RuntimeFileLayout.default
            try layout.prepareIfNeeded()
            requested = try layout.workspace(client: .agents, identifier: "miniapp-" + UUID().uuidString.lowercased())
        }
        guard requested.isFileURL else { throw RuntimeCoreError.invalidRequest("A local project directory is required.") }
        let root = requested.standardizedFileURL.resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = root.appending(path: "hanlin.authoring.json")
        var sourceRoot = root
        if manager.fileExists(atPath: manifest.path) {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest))
            if let source = (object as? [String: Any])?["sourceRoot"] as? String {
                sourceRoot = try relativeURL(source, below: root, allowRoot: true)
            }
        }
        let pending: [(String, URL, Data)] = try files.map { file in
            let destination = try relativeURL(file.path, below: sourceRoot)
            guard (file.content != nil) != (file.base64 != nil) else {
                throw RuntimeCoreError.invalidRequest("Supply exactly one of content or base64 for " + file.path)
            }
            let bytes: Data
            if let content = file.content {
                bytes = Data(content.utf8)
            } else if let encoded = file.base64, let decoded = Data(base64Encoded: encoded) {
                bytes = decoded
            } else {
                throw RuntimeCoreError.invalidRequest("Invalid base64 source resource: " + file.path)
            }
            return (file.path, destination, bytes)
        }
        for (_, destination, bytes) in pending {
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: destination, options: .atomic)
        }
        return HanlinMiniAppSourceWriteReport(projectPath: root.path, sourceRoot: sourceRoot.path,
            writtenFiles: pending.map { $0.0 })
    }

    private static func relativeURL(_ path: String, below root: URL, allowRoot: Bool = false) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else {
            throw RuntimeCoreError.invalidRequest("A relative source path is required: " + path)
        }
        let result = root.appending(path: path).standardizedFileURL.resolvingSymlinksInPath()
        guard result.path.hasPrefix(root.path + "/") || (allowRoot && result.path == root.path) else {
            throw RuntimeCoreError.invalidRequest("Source path leaves its project: " + path)
        }
        return result
    }

    static func sdk(engine: String? = nil, resource: String? = nil) async throws -> RuntimeJSONValue {
        try await AppRuntimeCore.shared.node.miniAppSDK(engine: engine, resource: resource)
    }

    static func validate(project: URL, engine: String) async throws -> HanlinMiniAppAuthoringReport {
        try await AppRuntimeCore.shared.node.authorMiniApp(operation: "validate", engine: engine, project: project)
    }

    static func build(project: URL, engine: String, archive: URL? = nil) async throws -> HanlinMiniAppAuthoringReport {
        let report = try await AppRuntimeCore.shared.node.authorMiniApp(operation: "build", engine: engine, project: project)
        guard report.succeeded, let preparedPath = report.preparedPackagePath else { return report }
        let prepared = URL(fileURLWithPath: preparedPath, isDirectory: true)
        let suffix = engine == "nativescript" ? "hanlinNativeScript" : engine == "expo" ? "hanlinExpo" : "zip"
        let destination = archive ?? prepared.deletingLastPathComponent().appending(path: "MiniApp.\(suffix)")
        guard destination.isFileURL, !destination.path.contains("\0"),
              !FileManager.default.fileExists(atPath: destination.path) else {
            throw RuntimeCoreError.invalidRequest("The output archive already exists or its path is invalid. Choose a new output path.")
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.zipItem(at: prepared, to: destination, shouldKeepParent: false)
        return report.withArchive(at: destination.path)
    }
}
