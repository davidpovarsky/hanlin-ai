import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import HanlinScriptExtensions
import HanlinWidgetCompiler
import Testing

@Suite("Mixed application and Widget input ownership")
struct HanlinWidgetInputOwnershipTests {
    @Test func mixedNativeWidgetKeepsDynamicImportsAndResourceAliases() throws {
        for inheritedAuthoring in [false, true] {
            var fixture = try mixedPackage()
            if inheritedAuthoring {
                fixture.files.removeValue(forKey: "source/hanlin.authoring.json")
                fixture.files.removeValue(forKey: "source/package.json")
                fixture.files["source/config/app.json"] = fixture.files.removeValue(forKey: "source/tsconfig.json")
                try editJSON("nativescript/app/package.json", in: &fixture) {
                    $0.removeValue(forKey: "name")
                    $0.removeValue(forKey: "version")
                }
                try sealInventories(&fixture)
                try editJSON("hanlin.authoring.json", in: &fixture) { $0["tsconfig"] = "config/app.json" }
            }
            let original = fixture.files
            let program = try prepare(fixture)
            let result = try HanlinScriptWidgetRuntime.shared.run(program: program, values: [:], environment: [:])
            #expect(result.node.tag == "text")
            #expect(result.node.children == [.value(.string("Shared 9"))])
            #expect(result.values["missingImport"] == .bool(false))
            #expect(result.values["mapCount"] == .integer(9))
            #expect(program.resources["assets/payload.bin"] == Data([0, 255, 17, 128]))
            #expect(program.resources["nativescript/app/modules/assets/payload.bin"] == Data([0, 255, 17, 128]))
            #expect(program.resources["assets/record.map"] == original["assets/record.map"])
            #expect(fixture.files == original)
        }
    }

    @Test func compiledInventoryDoesNotHideUnrecognizedPublishedHelpers() throws {
        var fixture = try mixedPackage()
        let helper = "nativescript/app/modules/not-an-app-output.ts"
        fixture.files[helper] = Data("function preserved(value) { return 'Unowned ' + value; }".utf8)
        let widget = """
        const name = ['nativescript', 'app', 'modules', 'not-an-app-output.ts'].join('/');
        if (!$import(name)) throw Error('published helper was removed');
        $render(<text>{preserved(7)}</text>);
        """
        try replaceWidget(widget, in: &fixture)
        try sealInventories(&fixture)
        let result = try HanlinScriptWidgetRuntime.shared.run(program: prepare(fixture), values: [:], environment: [:])
        #expect(result.node.children == [.value(.string("Unowned 7"))])
    }

    @Test func configuredDebuggerSourceRootDoesNotChangeOwnership() throws {
        var fixture = try mixedPackage()
        let location = "https://example.invalid/debug/"
        try editJSON("source/tsconfig.json", in: &fixture) {
            $0["compilerOptions"] = ["strict": true, "sourceRoot": location]
        }
        try editJSON("nativescript/app/modules/index.mjs.map", in: &fixture) {
            $0["sourceRoot"] = location
            $0["sources"] = ["index.ts"]
        }
        try sealInventories(&fixture)
        let program = try prepare(fixture)
        let result = try HanlinScriptWidgetRuntime.shared.run(program: program, values: [:], environment: [:])
        #expect(result.node.children == [.value(.string("Shared 9"))])
        #expect(program.resources["nativescript/app/modules/index.mjs.map"] == nil)
        #expect(fixture.files["nativescript/app/modules/index.mjs.map"] != nil)
    }

    @Test func declaredSharedModuleAndMapOverrideForegroundPairClassification() throws {
        var fixture = try mixedPackage()
        let helper = try #require(fixture.files["source/shared/helper.js"])
        let map = try json([
            "version": 3, "file": "helper.js", "sourceRoot": "",
            "sources": ["../../../../shared/helper.js"],
            "sourcesContent": [String(decoding: helper, as: UTF8.self)], "names": [], "mappings": ""
        ])
        for name in ["source/shared/helper.js.map", "shared/helper.js.map", "nativescript/app/modules/shared/helper.js.map"] {
            fixture.files[name] = map
        }
        let widget = """
        const path = ['nativescript', 'app', 'modules', 'shared', 'helper.js'].join('/');
        if (!$import(path)) throw Error('shared emitted alias was removed');
        const map = $file.readJSON(path + '.map');
        $render(<text>{helper(map.version)}</text>);
        """
        try replaceWidget(widget, in: &fixture)
        try sealInventories(&fixture)
        let result = try HanlinScriptWidgetRuntime.shared.run(program: prepare(fixture), values: [:], environment: [:])
        #expect(result.node.children == [.value(.string("Shared 3"))])
    }

    @Test func incompleteOrChangedVisibleInventoriesFailClosed() throws {
        let original = try mixedPackage()
        for mutation in ["omitted-source", "extra-source", "extra-compiled", "changed-source", "changed-compiled", "file-directory-overlap"] {
            var fixture = original
            switch mutation {
            case "omitted-source":
                try editJSON("hanlin.authoring.json", in: &fixture) { author in
                    var hashes = author["sourceHashes"] as! [String: String]
                    hashes.removeValue(forKey: "index.ts")
                    author["sourceHashes"] = hashes
                }
            case "extra-source": fixture.files["source/unlisted.ts"] = Data("export type Hidden = number;".utf8)
            case "extra-compiled": fixture.files["unlisted-helper.js"] = Data("function visible() {}".utf8)
            case "changed-source": fixture.files["source/index.ts"] = Data("export const changed: number = 2;".utf8)
            case "changed-compiled": fixture.files["nativescript/app/modules/index.mjs"] = Data("export const changed = 2;".utf8)
            default:
                fixture.files["source"] = Data("not a directory".utf8)
                try sealInventories(&fixture)
            }
            try expectOwnershipFailure(fixture, context: mutation)
        }
    }

    @Test func escapingChangedAndAmbiguousResourceCopiesFailClosed() throws {
        let original = try mixedPackage()
        for mutation in ["escape", "changed-root-copy", "changed-native-alias", "retained-root-overlap", "presentation-overlap"] {
            var fixture = original
            switch mutation {
            case "escape":
                try editJSON("source/hanlin.authoring.json", in: &fixture) { $0["resources"] = ["../outside"] }
            case "changed-root-copy": fixture.files["assets/record.map"] = Data("{}".utf8)
            case "changed-native-alias": fixture.files["nativescript/app/modules/assets/record.map"] = Data("{}".utf8)
            case "retained-root-overlap":
                fixture.files["source/source/shared.js"] = Data("function retained() {}".utf8)
                try editJSON("source/hanlin.authoring.json", in: &fixture) { $0["resources"] = ["source"] }
            default:
                for path in ["script.json", "source/script.json"] {
                    try editJSON(path, in: &fixture) {
                        $0["nativePresentations"] = ["panel": ["engine": "scriptwidget", "sourceFormat": "javascript",
                                                              "sourcePath": "nativescript/app/modules/index.mjs"]]
                    }
                }
                fixture.manifest = try JSONDecoder().decode(HanlinScriptingManifest.self, from: fixture.files["script.json"]!)
            }
            try sealInventories(&fixture)
            try expectOwnershipFailure(fixture, context: mutation)
        }
    }

    @Test func explicitlySharedLargeResourceStillHitsOriginalArtifactLimit() throws {
        var fixture = try mixedPackage()
        let bytes = Data(repeating: 0x5a, count: 2_400_000)
        for path in ["source/assets/large.bin", "assets/large.bin", "nativescript/app/modules/assets/large.bin"] {
            fixture.files[path] = bytes
        }
        try sealInventories(&fixture)
        let program = try prepare(fixture)
        #expect(program.resources["assets/large.bin"] == bytes)
        let encoded = try JSONEncoder().encode(program)
        try #require(encoded.count > 3 * 1_024 * 1_024)
        let root = FileManager.default.temporaryDirectory.appending(path: "hanlin-widget-shared-limit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Package")
        for (path, bytes) in fixture.files {
            let target = source.appending(path: path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: target)
        }
        let digest = String(repeating: "a", count: 64)
        let compiled = HanlinScriptingBundle(manifest: .init(
            compilerVersion: "Widget-ABI-1", compilerIntegrity: digest, compilerOptionsHash: digest,
            baselineID: "mixed-widget-ownership", baselineDigest: digest, hanlinABIVersion: "1",
            packageContentDigest: digest, cacheFingerprint: digest, files: []), modules: [], diagnostics: [])
        let bundler = HanlinScriptingBundler(
            baseline: .init(baselineID: "mixed-widget-ownership", baselineDigest: digest, symbols: []),
            abiVersion: "1", scriptingDeclarations: [], compiler: ForbiddenScriptingCompiler())
        do {
            _ = try bundler.writeInstallArtifact(compiled, packageRoot: source,
                to: root.appending(path: "Artifact"), preparedWidgetPrograms: ["widgets/shared.json": encoded])
            Issue.record("An explicitly shared oversized resource bypassed the original artifact limit")
        } catch HanlinScriptingBundlerError.invalidCompilerOutput(let reason) {
            #expect(reason == "invalid_widget_program")
        }
    }

    @Test func bundleOnlyAndUnrecognizedAuthoringKeepOriginalInputs() throws {
        let original = try mixedPackage()
        for envelope in [nil, Data(#"{"schemaVersion":2,"sourceRoot":"source"}"#.utf8),
                         Data(#"{"schemaVersion":1,"sourceRoot":"editable"}"#.utf8)] as [Data?] {
            var fixture = original
            fixture.files = fixture.files.filter { !$0.key.hasPrefix("source/") && !$0.key.hasPrefix("nativescript/") }
            fixture.files["hanlin.authoring.json"] = envelope
            let result = try HanlinScriptWidgetRuntime.shared.run(program: prepare(fixture), values: [:], environment: [:])
            #expect(result.node.children == [.value(.string("Shared 9"))])
            #expect(result.values["missingImport"] == .bool(false))
        }
    }

    private struct Fixture {
        var manifest: HanlinScriptingManifest
        var files: [String: Data]
    }

    private func mixedPackage() throws -> Fixture {
        let script: [String: Any] = [
            "name": "Widget ownership regression", "version": "1.0.0", "hanlinAppID": "hanlin.widget.ownership",
            "entry": "nativescript/app/bundle.mjs", "runInApp": true, "hanlinRuntime": "hanlin-nativescript",
            "widgetEngine": "scriptwidget", "hanlinWidget": ["abiVersion": 1, "sourceFormat": "jsx", "families": ["systemMedium"]]
        ]
        let scriptBytes = try json(script)
        let author: [String: Any] = ["schemaVersion": 1, "engine": "nativescript", "entry": "index.ts",
                                   "tsconfig": "tsconfig.json", "resources": ["widget.jsx", "./shared/", "assets"]]
        let source = "export const foreground: number = 1;\n"
        let widget = """
        const name = ['shared', 'helper.js'].join('/');
        if (!$import(name)) throw Error('shared helper was removed');
        $storage.setJSON('missingImport', $import(['missing', 'helper.js'].join('/')));
        const record = $file.readJSON('assets/record.map');
        $storage.setJSON('mapCount', record.count);
        $render(<text>{helper(record.count)}</text>);
        """
        let sourcePackage: [String: Any] = ["name": "hanlin.widget.ownership", "version": "1.0.0", "main": "index.ts"]
        let preparedPackage: [String: Any] = ["name": "hanlin.widget.ownership", "version": "1.0.0", "main": "bundle.mjs",
                                              "type": "module", "hanlinRuntime": "hanlin-nativescript"]
        var files: [String: Data] = [
            "script.json": scriptBytes, "source/script.json": scriptBytes,
            "source/hanlin.authoring.json": try json(author), "source/package.json": try json(sourcePackage),
            "source/tsconfig.json": try json(["compilerOptions": ["strict": true]]),
            "source/index.ts": Data(source.utf8), "source/widget.jsx": Data(widget.utf8),
            "source/shared/helper.js": Data("function helper(value) { return 'Shared ' + value; }".utf8),
            "source/assets/record.map": Data(#"{"count":9}"#.utf8), "source/assets/payload.bin": Data([0, 255, 17, 128]),
            "nativescript/app/package.json": try json(preparedPackage),
            "nativescript/app/bundle.mjs": Data("import \"./modules/index.mjs\";\n".utf8),
            "nativescript/app/modules/index.mjs": Data("export const foreground = 1;\n//# sourceMappingURL=index.mjs.map\n".utf8),
            "nativescript/app/modules/index.mjs.map": try json([
                "version": 3, "file": "index.mjs", "sourceRoot": "", "sources": ["../../../../index.ts"],
                "sourcesContent": [source], "names": [], "mappings": ""]),
            "hanlin.validation.json": try json(["succeeded": true])
        ]
        for name in ["widget.jsx", "shared/helper.js", "assets/record.map", "assets/payload.bin"] {
            let bytes = files["source/" + name]!
            files[name] = bytes
            files["nativescript/app/modules/" + name] = bytes
        }
        var fixture = Fixture(manifest: try JSONDecoder().decode(HanlinScriptingManifest.self, from: scriptBytes), files: files)
        try sealInventories(&fixture)
        return fixture
    }

    private func sealInventories(_ fixture: inout Fixture) throws {
        var source: [String: String] = [:]
        var compiled: [String: String] = [:]
        for (path, bytes) in fixture.files {
            if path.hasPrefix("source/") { source[String(path.dropFirst("source/".count))] = digest(bytes) }
            else if path != "hanlin.authoring.json" && path != "hanlin.validation.json" { compiled[path] = digest(bytes) }
        }
        fixture.files["hanlin.authoring.json"] = try json([
            "schemaVersion": 1, "engine": "nativescript", "entry": "index.ts", "tsconfig": "tsconfig.json",
            "sourceRoot": "source", "sourceHashes": source, "compiledHashes": compiled
        ])
    }

    private func replaceWidget(_ source: String, in fixture: inout Fixture) throws {
        let bytes = Data(source.utf8)
        for name in ["source/widget.jsx", "widget.jsx", "nativescript/app/modules/widget.jsx"] { fixture.files[name] = bytes }
    }

    private func editJSON(_ path: String, in fixture: inout Fixture, _ body: (inout [String: Any]) -> Void) throws {
        var value = try JSONSerialization.jsonObject(with: fixture.files[path]!) as! [String: Any]
        body(&value)
        fixture.files[path] = try json(value)
    }

    private func prepare(_ fixture: Fixture) throws -> HanlinWidgetProgram {
        try HanlinWidgetCompiler.prepare(manifest: fixture.manifest, entryPath: "widget.jsx", files: fixture.files)
    }

    private func expectOwnershipFailure(_ fixture: Fixture, context: String) throws {
        do {
            _ = try prepare(fixture)
            Issue.record("Ambiguous input ownership was accepted: \(context)")
        } catch HanlinWidgetProgramError.compilationFailed(let message) {
            #expect(message.hasPrefix("Mixed Widget input ownership is invalid:"), "Unexpected failure for \(context): \(message)")
        }
    }

    private func json(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private struct ForbiddenScriptingCompiler: HanlinTrustedCompilerClient {
        func compile(_ project: HanlinVirtualTypeScriptProject) async throws -> HanlinTrustedCompilerResult {
            throw HanlinWidgetProgramError.unsupportedImport
        }
    }
}
