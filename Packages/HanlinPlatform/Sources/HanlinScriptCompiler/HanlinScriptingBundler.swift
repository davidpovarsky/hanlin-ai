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
    public let module: String
    public let moduleResolution: String
    public let strict: Bool
    public let sourceMap: Bool
    public let skipLibCheck: Bool
    public let jsxRuntime: String

    public init(
        target: String = "ES2022",
        module: String = "ESNext",
        moduleResolution: String = "Bundler",
        strict: Bool = true,
        sourceMap: Bool = true,
        skipLibCheck: Bool = false,
        jsxRuntime: String = "react-jsx"
    ) {
        self.target = target
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
    public let compilerVersion: String
    public let compilerIntegrity: String
    public let buildFingerprint: String
    public let diagnostics: [HanlinCompilerDiagnostic]
    public let resolvedGraph: HanlinPackageDependencyGraph
    public let modules: [HanlinCompiledModule]

    public init(
        compilerVersion: String,
        compilerIntegrity: String,
        buildFingerprint: String,
        diagnostics: [HanlinCompilerDiagnostic],
        resolvedGraph: HanlinPackageDependencyGraph,
        modules: [HanlinCompiledModule]
    ) {
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
    public static let compilerVersion = "7.0.2"
    public static let compilerIntegrity = "sha512-8FYau96o3NKOhbjKi/qNvG/W5jhzxkbdm5sj9AbZ/5T5sWqn3hJgLfGx27sRKZWTvyzCP8dLRBTf5tBTSRVUNA=="

    private let baseline: HanlinCompatibilityInventory
    private let abiVersion: String
    private let scriptingDeclarations: Data
    private let compiler: any HanlinTrustedCompilerClient
    private let fileManager: FileManager

    public init(
        baseline: HanlinCompatibilityInventory,
        abiVersion: String,
        scriptingDeclarations: Data,
        compiler: any HanlinTrustedCompilerClient,
        fileManager: FileManager = .default
    ) {
        self.baseline = baseline
        self.abiVersion = abiVersion
        self.scriptingDeclarations = scriptingDeclarations
        self.compiler = compiler
        self.fileManager = fileManager
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
        let options = HanlinVirtualCompilerOptions()
        let project = HanlinVirtualTypeScriptProject(
            sources: sources,
            declarationFiles: [.init(logicalPath: "virtual/scripting.d.ts", bytes: scriptingDeclarations)],
            entrypoints: entrypoints,
            options: options
        )
        let result = try await compiler.compile(project)
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
