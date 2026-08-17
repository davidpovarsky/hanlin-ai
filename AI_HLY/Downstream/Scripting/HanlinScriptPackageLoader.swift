import CryptoKit
import Foundation
import HanlinPlatformContracts

struct HanlinLoadedScriptPackage: Sendable {
    let manifest: HanlinScriptPackageManifest
    let installedPackageID: HanlinInstalledPackageID
    let providerInstanceID: HanlinProviderInstanceID
    let javaScript: String
}

enum HanlinScriptPackageLoader {
    static let support = HanlinScriptContractSupport(
        manifestVersion: .init(major: 1, minor: 0),
        abiVersion: .init(major: 1, minor: 0),
        engine: "quickjs-ng",
        engineVersion: "0.16.1",
        compilerLane: "scripting-original",
        compilerVersion: "7.0.2"
    )

    static let compilerConfigurationHash =
        "ea250be3f93de1703163734fe2d0e31c9cc7b599aa09fce203d3ff8bdfbfcbea"

    static func load(packageDirectory: URL) throws -> HanlinLoadedScriptPackage {
        let manifestURL = packageDirectory.appending(
            path: "hanlin-script.json",
            directoryHint: .notDirectory
        )
        let manifestData = try readBounded(manifestURL, maximumBytes: 512 * 1_024)
        let manifest: HanlinScriptPackageManifest
        do {
            manifest = try HanlinScriptPackageManifest.decodeAndValidate(
                manifestData,
                support: support
            )
        } catch {
            throw HanlinScriptingError.invalidPackage("manifest_invalid")
        }
        guard manifest.entrypoint.compilerConfigurationHash
            == compilerConfigurationHash else {
            throw HanlinScriptingError.compilerArtifactMismatch
        }
        guard manifest.entrypoint.exportedTools.count == 1 else {
            throw HanlinScriptingError.unsupportedABI("one_tool_per_entrypoint")
        }
        let exportedTool = manifest.entrypoint.exportedTools[0]
        guard !exportedTool.requiresApproval,
              exportedTool.requiredCapabilities.isEmpty else {
            throw HanlinScriptingError.unsupportedABI("privileged_tool")
        }

        let sourceURL = packageDirectory.appending(
            path: manifest.entrypoint.sourcePath,
            directoryHint: .notDirectory
        )
        let compiledURL = packageDirectory.appending(
            path: manifest.entrypoint.compiledPath,
            directoryHint: .notDirectory
        )
        try verifyContainment(sourceURL, inside: packageDirectory)
        try verifyContainment(compiledURL, inside: packageDirectory)
        let source = try readBounded(sourceURL, maximumBytes: 512 * 1_024)
        let compiled = try readBounded(compiledURL, maximumBytes: 2 * 1_024 * 1_024)
        guard sha256(source) == manifest.entrypoint.sourceIntegrity.digest,
              sha256(compiled) == manifest.entrypoint.compiledIntegrity.digest else {
            throw HanlinScriptingError.compilerArtifactMismatch
        }
        guard sha256(try manifest.integrityMaterialJSONData())
            == manifest.integrity.digest else {
            throw HanlinScriptingError.compilerArtifactMismatch
        }
        guard let javaScript = String(data: compiled, encoding: .utf8) else {
            throw HanlinScriptingError.invalidPackage("compiled_source_not_utf8")
        }

        let identitySuffix = String(manifest.integrity.digest.prefix(32))
        return HanlinLoadedScriptPackage(
            manifest: manifest,
            installedPackageID: try HanlinInstalledPackageID(
                validating: "script-package.\(identitySuffix)"
            ),
            providerInstanceID: try HanlinProviderInstanceID(
                validating: "script.\(identitySuffix)"
            ),
            javaScript: javaScript
        )
    }

    private static func readBounded(_ url: URL, maximumBytes: Int) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path())
        guard let size = attributes[.size] as? NSNumber,
              size.intValue <= maximumBytes else {
            throw HanlinScriptingError.resourceLimit("package_file_size")
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func verifyContainment(_ file: URL, inside directory: URL) throws {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = file.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path().hasSuffix("/") ? root.path() : root.path() + "/"
        guard candidate.path().hasPrefix(rootPath) else {
            throw HanlinScriptingError.invalidPackage("entrypoint_escape")
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
