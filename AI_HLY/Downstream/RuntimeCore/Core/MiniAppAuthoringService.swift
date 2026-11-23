import Foundation
import HanlinPlatformContracts
import ZIPFoundation

/// One authoring route for agent tools and import preflight. The original Node compiler
/// and the SDK packaged with this app are shared; there is no independent UI typechecker.
@MainActor
enum MiniAppAuthoringService {
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
