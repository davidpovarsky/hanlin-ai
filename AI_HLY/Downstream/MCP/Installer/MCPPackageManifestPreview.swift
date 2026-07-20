import Foundation
import SWCompression

struct MCPPackageManifestPreview: Codable, Hashable, Sendable {
    var packageName: String
    var version: String
    var summary: String?
    var nodeRequirement: String?
    var entryPoints: [String]
    var dependencyCount: Int
    var compatibility: MCPCompatibilityReport

    static func readTGZ(at url: URL, maximumArchiveBytes: Int = 100 * 1_024 * 1_024) throws -> Self {
        let archive = try Data(contentsOf: url, options: .mappedIfSafe)
        guard archive.count <= maximumArchiveBytes else { throw MCPError.archiveTooLarge }
        let tar = try GzipArchive.unarchive(archive: archive)
        let entries = try TarContainer.open(container: tar)
        var extractedSize = 0

        for entry in entries {
            let normalized = entry.info.name.replacingOccurrences(of: "\\", with: "/")
            let parts = normalized.split(separator: "/", omittingEmptySubsequences: false)
            guard !normalized.hasPrefix("/"), !parts.contains("..") else {
                throw MCPError.unsafeArchivePath
            }
            extractedSize += entry.data?.count ?? 0
            guard extractedSize <= 500 * 1_024 * 1_024 else { throw MCPError.archiveTooLarge }
        }

        guard let manifestData = entries.first(where: {
            $0.info.name == "package/package.json" || $0.info.name == "package.json"
        })?.data else {
            throw MCPError.invalidPackageSpec
        }
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        guard let manifest, let name = manifest["name"] as? String,
              let version = manifest["version"] as? String else {
            throw MCPError.invalidPackageSpec
        }
        let dependencies = manifest["dependencies"] as? [String: Any] ?? [:]
        let engines = manifest["engines"] as? [String: Any]
        var entriesFound: [String] = []
        if let bin = manifest["bin"] as? String { entriesFound.append(bin) }
        if let bins = manifest["bin"] as? [String: String] { entriesFound.append(contentsOf: bins.values) }
        if let main = manifest["main"] as? String { entriesFound.append(main) }
        let report = MCPCompatibilityReport(
            verdict: entriesFound.isEmpty ? .unsupported : .compatibleWithWarnings,
            findings: entriesFound.isEmpty
                ? [.init(severity: .unsupported, message: "No executable entry point was found.")]
                : [.init(severity: .warning, message: "Static archive preview passed; runtime probe is still required.")],
            runtimeProbePassed: false
        )
        return MCPPackageManifestPreview(
            packageName: name,
            version: version,
            summary: manifest["description"] as? String,
            nodeRequirement: engines?["node"] as? String,
            entryPoints: Array(Set(entriesFound)).sorted(),
            dependencyCount: dependencies.count,
            compatibility: report
        )
    }
}
