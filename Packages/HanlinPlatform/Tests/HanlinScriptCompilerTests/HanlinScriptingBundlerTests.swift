import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import Testing

@Suite("Deterministic Scripting bundler")
struct HanlinScriptingBundlerTests {
    @Test("Builds a closed virtual project and deterministic artifact manifest")
    func deterministicBundle() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.package.stagingRoot) }
        let compiler = CompilerStub(result: successfulResult())
        let bundler = makeBundler(compiler: compiler)

        let first = try await bundler.bundle(package: fixture.package, preview: fixture.preview, context: .app)
        let second = try await bundler.bundle(package: fixture.package, preview: fixture.preview, context: .app)

        #expect(first == second)
        #expect(first.manifest.compilerVersion == "6.0.3")
        #expect(first.manifest.compilerOptionsHash.count == 64)
        #expect(first.manifest.cacheFingerprint.count == 64)
        let receivedProject = await compiler.lastProject()
        let request = try #require(receivedProject)
        #expect(request.packageRoot == "/package")
        #expect(request.entrypoints == ["index.tsx"])
        #expect(request.sources.map(\.logicalPath) == ["index.tsx", "lib/value.ts"])
        #expect(request.declarationFiles.map(\.logicalPath) == ["virtual/scripting.d.ts"])
        #expect(request.options.skipLibCheck == false)
    }

    @Test("Fails closed on preview errors and compiler identity mismatch")
    func failClosed() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.package.stagingRoot) }
        let rejected = HanlinImportPreview(
            source: fixture.preview.source,
            archive: fixture.preview.archive,
            manifest: fixture.preview.manifest,
            entrypoints: fixture.preview.entrypoints,
            dependencyGraph: fixture.preview.dependencyGraph,
            requestedCapabilities: [],
            findings: [.init(state: .unsupported, severity: .error, message: "blocked")],
            sourceBytes: fixture.preview.sourceBytes,
            extractedBytes: fixture.preview.extractedBytes
        )
        let compiler = CompilerStub(result: successfulResult())
        await #expect(throws: HanlinScriptingBundlerError.previewRejected) {
            try await makeBundler(compiler: compiler).bundle(
                package: fixture.package,
                preview: rejected,
                context: .app
            )
        }

        let wrongCompiler = CompilerStub(result: result(compilerVersion: "6.0.4"))
        await #expect(throws: HanlinScriptingBundlerError.compilerVersionMismatch(
            expected: "6.0.3",
            actual: "6.0.4"
        )) {
            try await makeBundler(compiler: wrongCompiler).bundle(
                package: fixture.package,
                preview: fixture.preview,
                context: .app
            )
        }
    }

    @Test("Rejects unresolved graphs and compiler output traversal")
    func rejectsUnsafeCompilerOutput() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.package.stagingRoot) }
        let unresolved = CompilerStub(result: result(graph: .init(
            modules: ["index.tsx", "lib/value.ts"],
            edges: [],
            unresolvedSpecifiers: ["arbitrary-npm"]
        )))
        await #expect(throws: HanlinScriptingBundlerError.graphMismatch) {
            try await makeBundler(compiler: unresolved).bundle(
                package: fixture.package,
                preview: fixture.preview,
                context: .app
            )
        }

        let escaping = CompilerStub(result: result(modules: [
            .init(logicalPath: "../escape.js", javaScript: Data("export default 1".utf8))
        ]))
        await #expect(throws: HanlinScriptingBundlerError.invalidLogicalPath("../escape.js")) {
            try await makeBundler(compiler: escaping).bundle(
                package: fixture.package,
                preview: fixture.preview,
                context: .app
            )
        }
    }

    @Test("Writes only validated JavaScript, maps, and a sorted manifest")
    func artifactWrite() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.package.stagingRoot) }
        let output = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-bundle-output-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: output) }
        let bundler = makeBundler(compiler: CompilerStub(result: successfulResult()))
        let bundle = try await bundler.bundle(package: fixture.package, preview: fixture.preview, context: .app)
        try bundler.write(bundle, to: output)
        #expect(FileManager.default.fileExists(atPath: output.appending(path: "index.js").path()))
        #expect(FileManager.default.fileExists(atPath: output.appending(path: "index.js.map").path()))
        let decoded = try JSONDecoder().decode(
            HanlinPackageArtifactManifest.self,
            from: Data(contentsOf: output.appending(path: "artifact-manifest.json"))
        )
        #expect(decoded == bundle.manifest)
    }

    private func makeBundler(compiler: some HanlinTrustedCompilerClient) -> HanlinScriptingBundler {
        HanlinScriptingBundler(
            baseline: .init(
                baselineID: "scripting-ios-2026",
                baselineDigest: String(repeating: "a", count: 64),
                symbols: []
            ),
            abiVersion: "2",
            scriptingDeclarations: Data("declare module \"scripting\" {}".utf8),
            compiler: compiler
        )
    }

    private func makeFixture() throws -> (package: HanlinStagedPackage, preview: HanlinImportPreview) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-bundler-tests-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let packageRoot = root.appending(path: "package", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: packageRoot.appending(path: "lib", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try Data("import { value } from './lib/value'; export default value".utf8)
            .write(to: packageRoot.appending(path: "index.tsx"))
        try Data("export const value = 42".utf8)
            .write(to: packageRoot.appending(path: "lib/value.ts"))
        let source = HanlinImportedPackageSource(
            originalFileName: "fixture.scripting",
            format: .scripting,
            contentSHA256: String(repeating: "b", count: 64),
            byteCount: 80,
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let archive = HanlinArchiveInspection(
            fileCount: 2,
            directoryCount: 1,
            compressedBytes: 40,
            uncompressedBytes: 80,
            maximumDepth: 2,
            manifestPath: "script.json"
        )
        let entrypoint = HanlinPackageEntrypointDescriptor(
            id: "app",
            kind: .app,
            sourcePath: "index.tsx",
            supportedContexts: [.mainApplication],
            runtimePolicyID: "foreground-app-v1",
            compatibility: .supported
        )
        let graph = HanlinPackageDependencyGraph(
            modules: ["index.tsx", "lib/value.ts"],
            edges: [.init(importer: "index.tsx", specifier: "./lib/value", resolvedPath: "lib/value.ts")]
        )
        let package = HanlinStagedPackage(
            source: source,
            stagingRoot: root,
            archiveURL: root.appending(path: "source.scripting"),
            packageRoot: packageRoot,
            inspection: archive,
            manifest: .init(name: "Fixture", version: "1.0.0", entry: "index.tsx")
        )
        return (package, .init(
            source: source,
            archive: archive,
            manifest: nil,
            entrypoints: [entrypoint],
            dependencyGraph: graph,
            requestedCapabilities: [],
            findings: [],
            sourceBytes: 80,
            extractedBytes: 80
        ))
    }

    private func successfulResult() -> HanlinTrustedCompilerResult { result() }

    private func result(
        compilerVersion: String = "6.0.3",
        graph: HanlinPackageDependencyGraph = .init(
            modules: ["index.tsx", "lib/value.ts"],
            edges: [.init(importer: "index.tsx", specifier: "./lib/value", resolvedPath: "lib/value.ts")]
        ),
        modules: [HanlinCompiledModule] = [
            .init(
                logicalPath: "index.js",
                javaScript: Data("import { value } from './lib/value.js'; export default value".utf8),
                sourceMap: Data(#"{"version":3}"#.utf8),
                imports: ["./lib/value.js"]
            ),
            .init(logicalPath: "lib/value.js", javaScript: Data("export const value = 42".utf8))
        ]
    ) -> HanlinTrustedCompilerResult {
        .init(
            compilerVersion: compilerVersion,
            compilerIntegrity: HanlinScriptingBundler.compilerIntegrity,
            buildFingerprint: String(repeating: "c", count: 64),
            diagnostics: [],
            resolvedGraph: graph,
            modules: modules
        )
    }
}

private actor CompilerStub: HanlinTrustedCompilerClient {
    private let result: HanlinTrustedCompilerResult
    private var receivedProject: HanlinVirtualTypeScriptProject?

    init(result: HanlinTrustedCompilerResult) {
        self.result = result
    }

    func compile(_ project: HanlinVirtualTypeScriptProject) async throws -> HanlinTrustedCompilerResult {
        receivedProject = project
        return result
    }

    func lastProject() -> HanlinVirtualTypeScriptProject? { receivedProject }
}
