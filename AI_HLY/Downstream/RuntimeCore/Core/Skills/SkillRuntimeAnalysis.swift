import Foundation

/// Executes only trusted bundled parsers on original engine jobs. Imported bytes travel
/// as base64 data; no analyzed source is evaluated, imported or resolved as a module.
enum SkillRuntimeAnalysis {
    static func scan(path: String, bytes: Data) async throws -> SkillSyntaxReport {
        guard bytes.count <= 1_048_576 else { throw RuntimeCoreError.invalidRequest("Analysis source budget") }
        let ext = (path as NSString).pathExtension.lowercased()
        if ["sh", "bash"].contains(ext) { return await BashSkillSyntaxAnalyzer().scan(file: path, utf8: bytes) }
        let payload = try JSONSerialization.data(withJSONObject: ["file": path, "base64": bytes.base64EncodedString()])
        let workspace = FileManager.default.temporaryDirectory.appending(path: "skill-analysis-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let result: RuntimeExecutionResult
        if ["requirements.txt", "pyproject.toml"].contains((path as NSString).lastPathComponent) {
            result = try await AppRuntimeCore.shared.python.analyzeSkillManifest(payload: payload, workspace: workspace)
        } else if ext == "py" {
            result = try await AppRuntimeCore.shared.python.analyzeSkillSyntax(payload: payload, workspace: workspace)
        } else if ["js", "mjs", "cjs", "ts"].contains(ext) || (path as NSString).lastPathComponent == "package.json" {
            result = try await AppRuntimeCore.shared.node.analyzeSkillSyntax(payload: payload, workspace: workspace)
        } else { throw RuntimeCoreError.invalidRequest("No original syntax helper for this language") }
        try Task.checkCancellation()
        guard result.exitCode == 0, !result.wasCancelled, !result.didTimeOut,
              result.stdout.utf8.count <= 1_048_576 else { throw RuntimeCoreError.runtimeFailure("Passive source analysis failed") }
        let report = try JSONDecoder().decode(SkillSyntaxReport.self, from: Data(result.stdout.utf8))
        guard report.file == path, report.sourceSHA256 == SkillRuntimeRequirements.digest(bytes) else {
            throw RuntimeCoreError.invalidRequest("Syntax provenance does not match original bytes")
        }
        return report
    }
}
