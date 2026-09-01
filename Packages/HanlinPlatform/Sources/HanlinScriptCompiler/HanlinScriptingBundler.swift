import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

public struct HanlinVirtualSourceFile: Codable, Hashable, Sendable {
    public let logicalPath: String
    public let bytes: Data

    public init(logicalPath: String, bytes: Data) {
        self.logicalPath = logicalPath
        self.bytes = bytes
    }
}

public struct HanlinVirtualCompilerOptions: Codable, Hashable, Sendable {
    public let target: String
    public let libraries: [String]
    public let module: String
    public let moduleResolution: String
    public let strict: Bool
    public let sourceMap: Bool
    public let skipLibCheck: Bool
    public let jsxRuntime: String

    public init(
        target: String = "ESNext",
        libraries: [String] = ["ESNext"],
        module: String = "CommonJS",
        moduleResolution: String = "Node10",
        strict: Bool = true,
        sourceMap: Bool = true,
        skipLibCheck: Bool = false,
        jsxRuntime: String = "react"
    ) {
        self.target = target
        self.libraries = libraries
        self.module = module
        self.moduleResolution = moduleResolution
        self.strict = strict
        self.sourceMap = sourceMap
        self.skipLibCheck = skipLibCheck
        self.jsxRuntime = jsxRuntime
    }
}

public struct HanlinVirtualTypeScriptProject: Codable, Hashable, Sendable {
    public let packageRoot: String
    public let sources: [HanlinVirtualSourceFile]
    public let declarationFiles: [HanlinVirtualSourceFile]
    public let entrypoints: [String]
    public let options: HanlinVirtualCompilerOptions

    public init(
        packageRoot: String = "/package",
        sources: [HanlinVirtualSourceFile],
        declarationFiles: [HanlinVirtualSourceFile],
        entrypoints: [String],
        options: HanlinVirtualCompilerOptions = .init()
    ) {
        self.packageRoot = packageRoot
        self.sources = sources
        self.declarationFiles = declarationFiles
        self.entrypoints = entrypoints
        self.options = options
    }
}

public struct HanlinCompilerDiagnostic: Codable, Hashable, Sendable {
    public let code: Int
    public let category: String
    public let message: String
    public let file: String?
    public let line: Int?
    public let column: Int?
    public let endLine: Int?
    public let endColumn: Int?

    public init(
        code: Int,
        category: String,
        message: String,
        file: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        endLine: Int? = nil,
        endColumn: Int? = nil
    ) {
        self.code = code
        self.category = category
        self.message = message
        self.file = file
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
    }
}

public struct HanlinCompiledModule: Codable, Hashable, Sendable {
    public let logicalPath: String
    public let javaScript: Data
    public let sourceMap: Data?
    public let imports: [String]

    public init(logicalPath: String, javaScript: Data, sourceMap: Data? = nil, imports: [String] = []) {
        self.logicalPath = logicalPath
        self.javaScript = javaScript
        self.sourceMap = sourceMap
        self.imports = imports
    }
}

public struct HanlinTrustedCompilerResult: Codable, Hashable, Sendable {
    public let typecheckCompilerVersion: String
    public let typecheckCompilerIntegrity: String
    public let compilerVersion: String
    public let compilerIntegrity: String
    public let buildFingerprint: String
    public let diagnostics: [HanlinCompilerDiagnostic]
    public let resolvedGraph: HanlinPackageDependencyGraph
    public let modules: [HanlinCompiledModule]

    public init(
        typecheckCompilerVersion: String = HanlinScriptingBundler.typecheckCompilerVersion,
        typecheckCompilerIntegrity: String = HanlinScriptingBundler.typecheckCompilerIntegrity,
        compilerVersion: String,
        compilerIntegrity: String,
        buildFingerprint: String,
        diagnostics: [HanlinCompilerDiagnostic],
        resolvedGraph: HanlinPackageDependencyGraph,
        modules: [HanlinCompiledModule]
    ) {
        self.typecheckCompilerVersion = typecheckCompilerVersion
        self.typecheckCompilerIntegrity = typecheckCompilerIntegrity
        self.compilerVersion = compilerVersion
        self.compilerIntegrity = compilerIntegrity
        self.buildFingerprint = buildFingerprint
        self.diagnostics = diagnostics
        self.resolvedGraph = resolvedGraph
        self.modules = modules
    }
}

public protocol HanlinTrustedCompilerClient: Sendable {
    func compile(_ project: HanlinVirtualTypeScriptProject) async throws -> HanlinTrustedCompilerResult
}

public struct HanlinScriptingBundle: Codable, Hashable, Sendable {
    public let manifest: HanlinPackageArtifactManifest
    public let modules: [HanlinCompiledModule]
    public let diagnostics: [HanlinCompilerDiagnostic]

    public init(
        manifest: HanlinPackageArtifactManifest,
        modules: [HanlinCompiledModule],
        diagnostics: [HanlinCompilerDiagnostic]
    ) {
        self.manifest = manifest
        self.modules = modules
        self.diagnostics = diagnostics
    }
}

public enum HanlinScriptingBundlerError: Error, Equatable, Sendable {
    case previewRejected
    case invalidLogicalPath(String)
    case compilerVersionMismatch(expected: String, actual: String)
    case compilerIntegrityMismatch
    case compilerFailed([HanlinCompilerDiagnostic])
    case graphMismatch
    case invalidCompilerOutput(String)
}

public struct HanlinScriptingBundler: Sendable {
    public static let typecheckCompilerVersion = "7.0.2"
    public static let typecheckCompilerIntegrity = "sha512-8FYau96o3NKOhbjKi/qNvG/W5jhzxkbdm5sj9AbZ/5T5sWqn3hJgLfGx27sRKZWTvyzCP8dLRBTf5tBTSRVUNA=="
    public static let compilerVersion = "6.0.3"
    public static let compilerIntegrity = "sha512-y2TvuxSZPDyQakkFRPZHKFm+KKVqIisdg9/CZwm9ftvKXLP8NRWj38/ODjNbr43SsoXqNuAisEf1GdCxqWcdBw=="

    private let baseline: HanlinCompatibilityInventory
    private let abiVersion: String
    private let scriptingDeclarations: [HanlinVirtualSourceFile]
    private let compiler: any HanlinTrustedCompilerClient
    private var fileManager: FileManager { .default }

    public init(
        baseline: HanlinCompatibilityInventory,
        abiVersion: String,
        scriptingDeclarations: [HanlinVirtualSourceFile],
        compiler: any HanlinTrustedCompilerClient
    ) {
        self.baseline = baseline
        self.abiVersion = abiVersion
        self.scriptingDeclarations = scriptingDeclarations
        self.compiler = compiler
    }

    public func bundle(
        package: HanlinStagedPackage,
        preview: HanlinImportPreview,
        context: HanlinPackageEntrypointKind
    ) async throws -> HanlinScriptingBundle {
        guard preview.canInstall else { throw HanlinScriptingBundlerError.previewRejected }
        let entrypoints = preview.entrypoints.filter { $0.kind == context }.map(\.sourcePath).sorted()
        guard !entrypoints.isEmpty else { throw HanlinScriptingBundlerError.previewRejected }
        let sources = try loadSources(at: package.packageRoot, paths: preview.dependencyGraph.modules)
        // The authoritative Scripting profile uses skipLibCheck for the exported
        // declaration bundle while retaining strict checking for package source.
        let options = try HanlinProductionCompilerProfile.projectOptions()
        let project = HanlinVirtualTypeScriptProject(
            sources: sources,
            declarationFiles: scriptingDeclarations,
            entrypoints: entrypoints,
            options: options
        )
        let result = try await compiler.compile(project)
        guard result.typecheckCompilerVersion == Self.typecheckCompilerVersion,
              result.typecheckCompilerIntegrity == Self.typecheckCompilerIntegrity else {
            throw HanlinScriptingBundlerError.compilerVersionMismatch(
                expected: Self.typecheckCompilerVersion,
                actual: result.typecheckCompilerVersion
            )
        }
        guard result.compilerVersion == Self.compilerVersion else {
            throw HanlinScriptingBundlerError.compilerVersionMismatch(
                expected: Self.compilerVersion,
                actual: result.compilerVersion
            )
        }
        guard result.compilerIntegrity == Self.compilerIntegrity else {
            throw HanlinScriptingBundlerError.compilerIntegrityMismatch
        }
        let errors = result.diagnostics.filter { $0.category == "error" }
        guard errors.isEmpty else { throw HanlinScriptingBundlerError.compilerFailed(errors) }
        guard Set(result.resolvedGraph.modules) == Set(preview.dependencyGraph.modules),
              result.resolvedGraph.unresolvedSpecifiers.isEmpty
        else { throw HanlinScriptingBundlerError.graphMismatch }

        let modules = try validatedModules(result.modules)
        let optionsHash = try digest(options)
        let fingerprintInput = [
            package.source.contentSHA256,
            Self.typecheckCompilerVersion,
            Self.typecheckCompilerIntegrity,
            Self.compilerVersion,
            Self.compilerIntegrity,
            baseline.baselineID,
            baseline.baselineDigest,
            optionsHash,
            abiVersion,
            context.rawValue,
            result.buildFingerprint
        ].joined(separator: "\n")
        let fingerprint = Self.sha256(Data(fingerprintInput.utf8))
        let files = modules.flatMap { module -> [HanlinArtifactFile] in
            var result = [HanlinArtifactFile(
                logicalPath: module.logicalPath,
                sha256: Self.sha256(module.javaScript),
                byteCount: Int64(module.javaScript.count),
                context: context
            )]
            if let sourceMap = module.sourceMap {
                result.append(.init(
                    logicalPath: "\(module.logicalPath).map",
                    sha256: Self.sha256(sourceMap),
                    byteCount: Int64(sourceMap.count),
                    context: context
                ))
            }
            return result
        }.sorted { $0.logicalPath < $1.logicalPath }
        return .init(
            manifest: .init(
                compilerVersion: Self.compilerVersion,
                compilerIntegrity: Self.compilerIntegrity,
                compilerOptionsHash: optionsHash,
                baselineID: baseline.baselineID,
                baselineDigest: baseline.baselineDigest,
                hanlinABIVersion: abiVersion,
                packageContentDigest: package.source.contentSHA256,
                cacheFingerprint: fingerprint,
                files: files
            ),
            modules: modules,
            diagnostics: result.diagnostics
        )
    }

    public func write(_ bundle: HanlinScriptingBundle, to root: URL) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for module in bundle.modules {
            let destination = try containedURL(module.logicalPath, root: root)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try module.javaScript.write(to: destination, options: .atomic)
            if let sourceMap = module.sourceMap {
                try sourceMap.write(to: try containedURL("\(module.logicalPath).map", root: root), options: .atomic)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(bundle.manifest).write(
            to: root.appending(path: "artifact-manifest.json", directoryHint: .notDirectory),
            options: .atomic
        )
    }

    /// Materializes the exact artifact-directory contract consumed by
    /// `HanlinAtomicScriptStore`. The directory is promoted only after the
    /// complete source-inclusive artifact manifest has been written and
    /// verified, so the store never observes a partially assembled artifact.
    public func writeInstallArtifact(
        _ bundle: HanlinScriptingBundle,
        packageRoot: URL,
        to root: URL
    ) throws -> HanlinPackageArtifactManifest {
        guard !fileManager.fileExists(atPath: root.path(percentEncoded: false)) else {
            throw HanlinScriptingBundlerError.invalidCompilerOutput("artifact_destination_exists")
        }
        let temporary = root.deletingLastPathComponent().appending(
            path: ".hanlin-artifact-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: false)
        try fileManager.copyItem(
            at: packageRoot,
            to: temporary.appending(path: "source", directoryHint: .isDirectory)
        )
        try write(bundle, to: temporary)
        let complete = try completeArtifactManifest(bundle.manifest, artifactRoot: temporary)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(complete).write(
            to: temporary.appending(path: "artifact-manifest.json", directoryHint: .notDirectory),
            options: .atomic
        )
        try verifyArtifactManifest(complete, at: temporary)
        try fileManager.moveItem(at: temporary, to: root)
        return complete
    }

    public func merged(_ bundles: [HanlinScriptingBundle]) throws -> HanlinScriptingBundle {
        guard let first = bundles.first else { throw HanlinScriptingBundlerError.previewRejected }
        let manifests = bundles.map(\.manifest)
        guard manifests.allSatisfy({ manifest in
            manifest.compilerVersion == first.manifest.compilerVersion
                && manifest.compilerIntegrity == first.manifest.compilerIntegrity
                && manifest.compilerOptionsHash == first.manifest.compilerOptionsHash
                && manifest.baselineID == first.manifest.baselineID
                && manifest.baselineDigest == first.manifest.baselineDigest
                && manifest.hanlinABIVersion == first.manifest.hanlinABIVersion
                && manifest.packageContentDigest == first.manifest.packageContentDigest
        }) else { throw HanlinScriptingBundlerError.invalidCompilerOutput("inconsistent_bundle_provenance") }
        let modules = try validatedModules(bundles.flatMap(\.modules))
        let files = manifests.flatMap(\.files).sorted { $0.logicalPath < $1.logicalPath }
        guard Set(files.map(\.logicalPath)).count == files.count else {
            throw HanlinScriptingBundlerError.invalidCompilerOutput("duplicate_artifact_path")
        }
        let fingerprint = Self.sha256(Data(manifests.map(\.cacheFingerprint).sorted().joined(separator: "\n").utf8))
        return .init(
            manifest: .init(
                compilerVersion: first.manifest.compilerVersion,
                compilerIntegrity: first.manifest.compilerIntegrity,
                compilerOptionsHash: first.manifest.compilerOptionsHash,
                baselineID: first.manifest.baselineID,
                baselineDigest: first.manifest.baselineDigest,
                hanlinABIVersion: first.manifest.hanlinABIVersion,
                packageContentDigest: first.manifest.packageContentDigest,
                cacheFingerprint: fingerprint,
                files: files
            ),
            modules: modules,
            diagnostics: bundles.flatMap(\.diagnostics)
        )
    }

    private func completeArtifactManifest(
        _ compiled: HanlinPackageArtifactManifest,
        artifactRoot: URL
    ) throws -> HanlinPackageArtifactManifest {
        let sourceRoot = artifactRoot.appending(path: "source", directoryHint: .isDirectory)
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw HanlinScriptingBundlerError.invalidCompilerOutput("artifact_source_enumeration_failed")
        }
        var files = compiled.files
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw HanlinScriptingBundlerError.invalidCompilerOutput("artifact_source_symlink")
            }
            guard values.isRegularFile == true else { continue }
            let depth = enumerator.level
            guard depth > 0, url.pathComponents.count >= depth else {
                throw HanlinScriptingBundlerError.invalidCompilerOutput("artifact_source_escaped")
            }
            let relative = url.pathComponents.suffix(depth).joined(separator: "/")
                .replacingOccurrences(of: "\\", with: "/")
            guard HanlinArchivePolicy.normalizedRelativePath(relative) == relative else {
                throw HanlinScriptingBundlerError.invalidCompilerOutput("artifact_source_escaped")
            }
            let data = try Data(contentsOf: url)
            files.append(.init(
                logicalPath: "source/\(relative)",
                sha256: Self.sha256(data),
                byteCount: Int64(data.count),
                context: .app
            ))
        }
        files.sort { $0.logicalPath < $1.logicalPath }
        guard Set(files.map(\.logicalPath)).count == files.count else {
            throw HanlinScriptingBundlerError.invalidCompilerOutput("duplicate_artifact_path")
        }
        let fingerprint = Self.sha256(Data(
            files.map { "\($0.logicalPath):\($0.sha256)" }.joined(separator: "\n").utf8
        ))
        return .init(
            schemaVersion: compiled.schemaVersion,
            compilerVersion: compiled.compilerVersion,
            compilerIntegrity: compiled.compilerIntegrity,
            compilerOptionsHash: compiled.compilerOptionsHash,
            baselineID: compiled.baselineID,
            baselineDigest: compiled.baselineDigest,
            hanlinABIVersion: compiled.hanlinABIVersion,
            packageContentDigest: compiled.packageContentDigest,
            cacheFingerprint: fingerprint,
            files: files
        )
    }

    private func verifyArtifactManifest(
        _ manifest: HanlinPackageArtifactManifest,
        at root: URL
    ) throws {
        let manifestURL = root.appending(path: "artifact-manifest.json", directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            throw HanlinScriptingBundlerError.invalidCompilerOutput("artifact_manifest_missing")
        }
        for file in manifest.files {
            let url = try containedURL(file.logicalPath, root: root)
            let data = try Data(contentsOf: url)
            guard Int64(data.count) == file.byteCount, Self.sha256(data) == file.sha256 else {
                throw HanlinScriptingBundlerError.invalidCompilerOutput("artifact_file_mismatch:\(file.logicalPath)")
            }
        }
    }

    private func loadSources(at root: URL, paths: [String]) throws -> [HanlinVirtualSourceFile] {
        try paths.sorted().map { logicalPath in
            let sourceURL = try containedURL(logicalPath, root: root)
            return .init(logicalPath: logicalPath, bytes: try Data(contentsOf: sourceURL))
        }
    }

    private func validatedModules(_ modules: [HanlinCompiledModule]) throws -> [HanlinCompiledModule] {
        var seen = Set<String>()
        return try modules.sorted { $0.logicalPath < $1.logicalPath }.map { module in
            _ = try containedURL(module.logicalPath, root: URL(filePath: "/artifact", directoryHint: .isDirectory))
            guard module.logicalPath.hasSuffix(".js"), seen.insert(module.logicalPath.lowercased()).inserted else {
                throw HanlinScriptingBundlerError.invalidCompilerOutput(module.logicalPath)
            }
            return module
        }
    }

    private func containedURL(_ logicalPath: String, root: URL) throws -> URL {
        guard !logicalPath.isEmpty,
              !logicalPath.contains("\\"),
              !logicalPath.contains("\0"),
              !logicalPath.hasPrefix("/"),
              logicalPath.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil
        else { throw HanlinScriptingBundlerError.invalidLogicalPath(logicalPath) }
        let components = logicalPath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains("") else {
            throw HanlinScriptingBundlerError.invalidLogicalPath(logicalPath)
        }
        return components.reduce(root) { partial, component in
            partial.appending(path: String(component), directoryHint: .notDirectory)
        }
    }

    private func digest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return Self.sha256(try encoder.encode(value))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
