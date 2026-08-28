import CryptoKit
import Foundation
import HanlinScriptCompiler
import HanlinScriptContracts

/// The production on-device emitter lane. TypeScript 7 remains the host/CI
/// compatibility authority; the embedded, integrity-pinned TypeScript 6.0.3
/// Program API emits a closed CommonJS graph that is bundled for Apple runtimes.
actor HanlinNodeMobileScriptingCompiler: HanlinTrustedCompilerClient {
    private let node: NodeRuntimeService
    private let layout: RuntimeFileLayout
    private let fileManager: FileManager

    init(
        node: NodeRuntimeService = AppRuntimeCore.shared.node,
        layout: RuntimeFileLayout = .default,
        fileManager: FileManager = .default
    ) {
        self.node = node
        self.layout = layout
        self.fileManager = fileManager
    }

    func compile(_ project: HanlinVirtualTypeScriptProject) async throws -> HanlinTrustedCompilerResult {
        try layout.prepareIfNeeded()
        let workspace = try layout.workspace(
            client: .scripting,
            identifier: "compile-\(UUID().uuidString.lowercased())"
        )
        defer { try? fileManager.removeItem(at: workspace) }

        for file in project.sources + project.declarationFiles {
            let destination = try containedURL(file.logicalPath, root: workspace)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.bytes.write(to: destination, options: .atomic)
        }
        let configuration = try compilerConfiguration(project)
        try configuration.write(
            to: workspace.appending(path: "tsconfig.json", directoryHint: .notDirectory),
            options: .atomic
        )
        let response = try await node.compileTypeScriptProject(
            workspace: workspace,
            arguments: ["--project", "tsconfig.json"]
        )
        let diagnostics = response.diagnostics.map { diagnostic in
            HanlinCompilerDiagnostic(
                code: diagnostic.code,
                category: diagnostic.category ?? (response.succeeded ? "warning" : "error"),
                message: diagnostic.message,
                file: diagnostic.file,
                line: diagnostic.line,
                column: diagnostic.column
            )
        }
        let compilerIntegrity = response.compilerIntegrity ?? "unknown"
        // nodejs-mobile can expose a CommonJS module namespace without the
        // synthetic `version` named export even though the pinned TypeScript
        // compiler itself loaded and emitted successfully. The integrity value
        // is the stronger identity signal: recover the canonical version only
        // when it exactly matches the trusted compiler pin. Missing or altered
        // integrity still fails closed in HanlinScriptingBundler.
        let compilerVersion = response.compilerVersion
            ?? (compilerIntegrity == HanlinScriptingBundler.compilerIntegrity
                ? HanlinScriptingBundler.compilerVersion
                : "unknown")
        let modules = response.succeeded
            ? try bundledEntrypoints(project: project, workspace: workspace, emittedFiles: response.emittedFiles)
            : []
        let fingerprintMaterial = try JSONEncoder.sorted.encode(Fingerprint(
            compilerVersion: compilerVersion,
            compilerIntegrity: compilerIntegrity,
            project: project,
            modules: modules
        ))
        return .init(
            typecheckCompilerVersion: HanlinScriptingBundler.typecheckCompilerVersion,
            typecheckCompilerIntegrity: HanlinScriptingBundler.typecheckCompilerIntegrity,
            compilerVersion: compilerVersion,
            compilerIntegrity: compilerIntegrity,
            buildFingerprint: Self.sha256(fingerprintMaterial),
            diagnostics: diagnostics,
            resolvedGraph: .init(modules: project.sources.map(\.logicalPath).sorted(), edges: []),
            modules: modules
        )
    }

    private func compilerConfiguration(_ project: HanlinVirtualTypeScriptProject) throws -> Data {
        let files = (project.sources + project.declarationFiles).map(\.logicalPath).sorted()
        let json: [String: Any] = [
            "compilerOptions": [
                "target": project.options.target,
                "module": project.options.module,
                "moduleResolution": project.options.moduleResolution,
                "strict": project.options.strict,
                "sourceMap": project.options.sourceMap,
                "inlineSources": true,
                "skipLibCheck": project.options.skipLibCheck,
                "jsx": project.options.jsxRuntime,
                "jsxFactory": "createElement",
                "jsxFragmentFactory": "Fragment",
                "allowJs": true,
                "checkJs": true,
                "resolveJsonModule": true,
                "esModuleInterop": true,
                "types": [],
                "paths": ["scripting": ["./virtual/scripting.d.ts"]],
                "rootDir": ".",
                "outDir": "dist",
                "newLine": "lf",
            ],
            "files": files,
        ]
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    private func bundledEntrypoints(
        project: HanlinVirtualTypeScriptProject,
        workspace: URL,
        emittedFiles: [String]
    ) throws -> [HanlinCompiledModule] {
        var emittedModules: [String: String] = [:]
        for relativePath in emittedFiles where relativePath.hasSuffix(".js") {
            let url = try containedURL(relativePath, root: workspace)
            let logicalPath = String(relativePath.dropFirst("dist/".count))
            emittedModules[logicalPath] = try String(contentsOf: url, encoding: .utf8)
        }
        for source in project.sources where source.logicalPath.hasSuffix(".json") {
            let logicalPath = source.logicalPath.replacingOccurrences(of: #"\.json$"#, with: ".js", options: .regularExpression)
            let object = try JSONSerialization.jsonObject(with: source.bytes)
            let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            emittedModules[logicalPath] = "module.exports = \(String(decoding: canonical, as: UTF8.self));"
        }
        let definitions = try emittedModules.keys.sorted().map { logicalPath in
            let id = try Self.javascriptString(logicalPath)
            return "__define(\(id), function(require, module, exports) {\n\(emittedModules[logicalPath]!)\n});"
        }.joined(separator: "\n")
        let sourcePaths = try Self.javascriptString(project.sources.map(\.logicalPath).sorted().joined(separator: "\n"))

        return try project.entrypoints.sorted().map { entrypoint in
            let emittedEntrypoint = entrypoint.replacingOccurrences(
                of: #"\.(?:tsx?|jsx?)$"#,
                with: ".js",
                options: .regularExpression
            )
            guard emittedModules[emittedEntrypoint] != nil else {
                throw HanlinScriptingBundlerError.invalidCompilerOutput(entrypoint)
            }
            let entryLiteral = try Self.javascriptString(emittedEntrypoint)
            let javaScript = #"""
            (() => {
              "use strict";
              const __modules = Object.create(null);
              const __cache = Object.create(null);
              const __define = (id, factory) => { __modules[id] = factory; };
              const __normalize = (value) => {
                const output = [];
                for (const part of value.split("/")) {
                  if (!part || part === ".") continue;
                  if (part === "..") { if (!output.length) throw new Error("HANLIN_MODULE:escape"); output.pop(); }
                  else output.push(part);
                }
                return output.join("/");
              };
              const __resolve = (from, specifier) => {
                if (specifier === "scripting") return specifier;
                if (!specifier.startsWith(".")) throw new Error("HANLIN_MODULE:bare_specifier");
                const base = from.split("/").slice(0, -1).join("/");
                const candidate = __normalize(`${base}/${specifier}`);
                for (const value of [candidate, `${candidate}.js`, `${candidate}/index.js`]) {
                  if (Object.hasOwn(__modules, value)) return value;
                }
                throw new Error("HANLIN_MODULE:not_found");
              };
              const __load = (id, from = "") => {
                if (id === "scripting") return globalThis;
                const resolved = from ? __resolve(from, id) : id;
                if (Object.hasOwn(__cache, resolved)) return __cache[resolved].exports;
                const factory = __modules[resolved];
                if (typeof factory !== "function") throw new Error("HANLIN_MODULE:not_found");
                const module = { exports: {} };
                __cache[resolved] = module;
                factory((specifier) => __load(specifier, resolved), module, module.exports);
                return module.exports;
              };
            \#(definitions)
              __load(\#(entryLiteral));
              Object.defineProperty(globalThis, "__hanlinCompiledSources", { value: \#(sourcePaths) });
            })();
            """#
            let map: [String: Any] = [
                "version": 3,
                "file": emittedEntrypoint,
                "sources": project.sources.map(\.logicalPath).sorted(),
                "names": [],
                "mappings": "",
            ]
            return .init(
                logicalPath: "compiled/\(emittedEntrypoint)",
                javaScript: Data(javaScript.utf8),
                sourceMap: try JSONSerialization.data(withJSONObject: map, options: [.sortedKeys]),
                imports: []
            )
        }
    }

    private func containedURL(_ logicalPath: String, root: URL) throws -> URL {
        guard !logicalPath.isEmpty,
              !logicalPath.hasPrefix("/"),
              !logicalPath.contains("\\"),
              !logicalPath.contains("\0"),
              logicalPath.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil
        else { throw HanlinScriptingBundlerError.invalidLogicalPath(logicalPath) }
        let components = logicalPath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains("") else {
            throw HanlinScriptingBundlerError.invalidLogicalPath(logicalPath)
        }
        return components.reduce(root) { $0.appending(path: String($1), directoryHint: .notDirectory) }
    }

    private static func javascriptString(_ value: String) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct Fingerprint: Codable {
        let compilerVersion: String
        let compilerIntegrity: String
        let project: HanlinVirtualTypeScriptProject
        let modules: [HanlinCompiledModule]
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
