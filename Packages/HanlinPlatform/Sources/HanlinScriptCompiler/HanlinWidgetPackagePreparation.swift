import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinWidgetCompiler

/// The same compiler used by Import Preview prepares installed immutable
/// programs. There is no fixture-specific or source-extension engine bypass.
public enum HanlinWidgetPackagePreparation {
    public static func installedEntrypoints(preview: HanlinImportPreview, artifactDigest: String) -> [HanlinPackageEntrypointDescriptor] {
        preview.entrypoints.map { entry in
            .init(id: entry.id, kind: entry.kind,
                sourcePath: entry.kind == .widget && entry.widgetEngine != nil && entry.widgetEngine != .legacy
                    ? "widgets/\(entry.id).json" : "source/\(entry.sourcePath)",
                exportedSymbol: entry.exportedSymbol, supportedContexts: entry.supportedContexts,
                requiredCapabilities: entry.requiredCapabilities, runtimePolicyID: entry.runtimePolicyID,
                runtimeProfile: entry.runtimeProfile, artifactDigest: artifactDigest,
                compatibility: entry.compatibility, widgetEngine: entry.widgetEngine)
        }
    }

    public static func programs(packageRoot: URL, preview: HanlinImportPreview) throws -> [String: Data] {
        guard let manifest = preview.manifest else { throw HanlinWidgetProgramError.invalidProgram }
        var files: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(at: packageRoot, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else {
            throw HanlinWidgetProgramError.invalidSource
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw HanlinWidgetProgramError.invalidSource }
            guard values.isRegularFile == true else { continue }
            let path = url.pathComponents.suffix(enumerator.level).joined(separator: "/")
            guard HanlinArchivePolicy.normalizedRelativePath(path) == path else { throw HanlinWidgetProgramError.invalidSource }
            guard url.resolvingSymlinksInPath().path.hasPrefix(packageRoot.resolvingSymlinksInPath().path + "/") else {
                throw HanlinWidgetProgramError.invalidSource
            }
            files[path] = try Data(contentsOf: url)
        }
        var programs: [String: Data] = [:]
        for entrypoint in preview.entrypoints where entrypoint.kind == .widget && entrypoint.widgetEngine != nil && entrypoint.widgetEngine != .legacy {
            let program = try HanlinWidgetCompiler.prepare(manifest: manifest, entryPath: entrypoint.sourcePath, files: files)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            programs["widgets/\(entrypoint.id).json"] = try encoder.encode(program)
        }
        return programs
    }
}
