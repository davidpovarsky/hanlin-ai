import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import Testing

@Suite("Static Scripting analyzer")
struct HanlinScriptAnalyzerTests {
    @Test("Discovers entrypoints, resolves modules, and derives capabilities deterministically")
    func preview() throws {
        let fixture = try package(files: [
            "script.json": #"{"name":"Fixture","version":"1.0.0","entry":"index.tsx"}"#,
            "index.tsx": #"import { Storage, Assistant } from "scripting"; import { value } from "./lib/value"; export default value"#,
            "lib/value.ts": "export const value = 1",
            "assistant_tool.tsx": #"import { AssistantTool } from "scripting"; export default AssistantTool"#,
            "widget.tsx": #"import { Storage } from "scripting"; export default Storage"#
        ])
        defer { try? FileManager.default.removeItem(at: fixture.stagingRoot) }
        let inventory = HanlinCompatibilityInventory(
            baselineID: "fixture-baseline",
            baselineDigest: String(repeating: "a", count: 64),
            symbols: ["Storage", "Assistant", "AssistantTool"].map {
                .init(symbol: $0, state: .supported)
            }
        )
        let preview = try HanlinScriptAnalyzer(inventory: inventory).analyze(fixture)
        #expect(preview.canInstall)
        #expect(preview.entrypoints.map(\.kind) == [.app, .assistantTool, .widget])
        #expect(preview.entrypoints.allSatisfy { $0.runtimeProfile == .scriptingJSC })
        #expect(preview.dependencyGraph.unresolvedSpecifiers.isEmpty)
        #expect(Set(preview.requestedCapabilities.map { $0.capabilityID.rawValue }) == [
            "assistant", "storage"
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(preview) == encoder.encode(preview))
    }

    @Test("Routes original Python entrypoint deterministically without engine fallback")
    func pythonProfile() throws {
        let fixture = try package(files: [
            "script.json": #"{"name":"Python Fixture","version":"1.0.0","entry":"index.py"}"#,
            "index.py": "from scripting import Script\nScript.exit(0)"
        ])
        defer { try? FileManager.default.removeItem(at: fixture.stagingRoot) }
        let preview = try HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "d", count: 64),
            symbols: []
        )).analyze(fixture)
        let entrypoint = try #require(preview.entrypoints.first)
        #expect(entrypoint.sourcePath == "index.py")
        #expect(entrypoint.runtimeProfile == .hanlinPython)
        #expect(entrypoint.runtimeProfile.runtimeKind == .localPython)
    }

    @Test("Routes only explicitly declared NativeScript packages to the native runtime")
    func nativeScriptProfile() throws {
        let fixture = try package(files: [
            "script.json": #"{"name":"NativeScript Fixture","version":"1.0.0","entry":"nativescript/app/bundle.mjs","hanlinRuntime":"hanlin-nativescript"}"#,
            "nativescript/app/bundle.mjs": #"import "./local-module.mjs"; console.log("native")"#,
            "nativescript/app/local-module.mjs": "export const value = 1",
            "nativescript/app/package.json": #"{"name":"fixture","main":"bundle.mjs","hanlinRuntime":"hanlin-nativescript"}"#
        ])
        defer { try? FileManager.default.removeItem(at: fixture.stagingRoot) }
        let preview = try HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "f", count: 64),
            symbols: []
        )).analyze(fixture)
        let entrypoint = try #require(preview.entrypoints.first)
        #expect(preview.canInstall)
        #expect(entrypoint.sourcePath == "nativescript/app/bundle.mjs")
        #expect(entrypoint.runtimeProfile == .hanlinNativeScript)
        #expect(entrypoint.runtimeProfile.runtimeKind == .native)
        #expect(preview.dependencyGraph.unresolvedSpecifiers.isEmpty)

        let ordinaryFixture = try package(files: [
            "script.json": #"{"name":"Ordinary Fixture","version":"1.0.0","entry":"index.mjs"}"#,
            "index.mjs": "console.log('ordinary')"
        ])
        defer { try? FileManager.default.removeItem(at: ordinaryFixture.stagingRoot) }
        let ordinaryPreview = try HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "f", count: 64),
            symbols: []
        )).analyze(ordinaryFixture)
        #expect(ordinaryPreview.entrypoints.first?.runtimeProfile == .scriptingJSC)
    }

    @Test("Validates the embedded NativeScript SwiftUI plugin contract without changing ordinary Scripting")
    func nativeScriptSwiftUIContract() throws {
        let supported = try package(files: [
            "script.json": #"{"name":"SwiftUI Fixture","version":"1.0.0","entry":"nativescript/app/bundle.mjs","hanlinRuntime":"hanlin-nativescript"}"#,
            "nativescript/app/bundle.mjs": "console.log('swiftui')",
            "nativescript/app/package.json": #"{"name":"fixture","main":"bundle.mjs","hanlinRuntime":"hanlin-nativescript","hanlinNativeScript":{"runtimeVersion":"9.1.0","plugins":{"@nativescript/swift-ui":"4.0.2"}}}"#
        ])
        defer { try? FileManager.default.removeItem(at: supported.stagingRoot) }
        let analyzer = HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "a", count: 64),
            symbols: []
        ))
        let supportedPreview = try analyzer.analyze(supported)
        #expect(supportedPreview.canInstall)
        #expect(supportedPreview.findings.contains { $0.message.contains("embedded native provider support") })

        let unsupported = try package(files: [
            "script.json": #"{"name":"Unsupported Fixture","version":"1.0.0","entry":"nativescript/app/bundle.mjs","hanlinRuntime":"hanlin-nativescript"}"#,
            "nativescript/app/bundle.mjs": "console.log('unsupported')",
            "nativescript/app/package.json": #"{"name":"fixture","main":"bundle.mjs","hanlinRuntime":"hanlin-nativescript","hanlinNativeScript":{"runtimeVersion":"9.1.0","plugins":{"@nativescript/swift-ui":"99.0.0"}}}"#
        ])
        defer { try? FileManager.default.removeItem(at: unsupported.stagingRoot) }
        let unsupportedPreview = try analyzer.analyze(unsupported)
        #expect(!unsupportedPreview.canInstall)
        #expect(unsupportedPreview.findings.contains {
            $0.message == "This Hanlin build supports @nativescript/swift-ui 4.0.2, but the package requires @nativescript/swift-ui 99.0.0."
        })
    }

    @Test("Validates declared @nativescript/core dependency compatibility")
    func nativeScriptCoreContract() throws {
        let supported = try package(files: [
            "script.json": #"{"name":"Core Fixture","version":"1.0.0","entry":"nativescript/app/bundle.mjs","hanlinRuntime":"hanlin-nativescript"}"#,
            "nativescript/app/bundle.mjs": "console.log('core')",
            "nativescript/app/package.json": #"{"name":"fixture","main":"bundle.mjs","hanlinRuntime":"hanlin-nativescript","dependencies":{"@nativescript/core":"9.1.0"}}"#
        ])
        defer { try? FileManager.default.removeItem(at: supported.stagingRoot) }
        let analyzer = HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "a", count: 64),
            symbols: []
        ))
        let supportedPreview = try analyzer.analyze(supported)
        #expect(supportedPreview.canInstall)
        #expect(supportedPreview.findings.contains { $0.message.contains("supported by embedded runtime 9.1.0") })

        let unsupported = try package(files: [
            "script.json": #"{"name":"Unsupported Core Fixture","version":"1.0.0","entry":"nativescript/app/bundle.mjs","hanlinRuntime":"hanlin-nativescript"}"#,
            "nativescript/app/bundle.mjs": "console.log('unsupported')",
            "nativescript/app/package.json": #"{"name":"fixture","main":"bundle.mjs","hanlinRuntime":"hanlin-nativescript","dependencies":{"@nativescript/core":"^10.0.0"}}"#
        ])
        defer { try? FileManager.default.removeItem(at: unsupported.stagingRoot) }
        let unsupportedPreview = try analyzer.analyze(unsupported)
        #expect(!unsupportedPreview.canInstall)
        #expect(unsupportedPreview.findings.contains {
            $0.message == "This Hanlin build supports @nativescript/core 9.1.0, but the package requires ^10.0.0."
        })
    }

    @Test("Validates the embedded Expo SwiftUI plugin contract")
    func expoSwiftUIContract() throws {
        let supported = try package(files: [
            "script.json": #"{"name":"Expo SwiftUI Fixture","version":"1.0.0","entry":"expo/app/bundle.js","hanlinRuntime":"hanlin-expo"}"#,
            "expo/app/bundle.js": "console.log('expo swiftui')",
            "expo/app/package.json": #"{"name":"fixture","main":"bundle.js","hanlinRuntime":"hanlin-expo","hanlinExpo":{"runtimeVersion":"58.0.3","bridgeVersion":"1.0.0","plugins":{"@expo/ui":"58.0.3","@hanlin/expo-ui":"1.0.0"}}}"#
        ])
        defer { try? FileManager.default.removeItem(at: supported.stagingRoot) }
        let analyzer = HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "a", count: 64),
            symbols: []
        ))
        let supportedPreview = try analyzer.analyze(supported)
        #expect(supportedPreview.canInstall)
        #expect(supportedPreview.entrypoints.first?.runtimeProfile == .hanlinExpo)
        #expect(supportedPreview.findings.contains { $0.message.contains("embedded native SwiftUI support") })

        let currentBridge = try package(files: [
            "script.json": #"{"name":"Current Expo Bridge Fixture","version":"1.0.0","entry":"expo/app/bundle.js","hanlinRuntime":"hanlin-expo"}"#,
            "expo/app/bundle.js": "console.log('current bridge')",
            "expo/app/package.json": #"{"name":"fixture","main":"bundle.js","hanlinRuntime":"hanlin-expo","hanlinExpo":{"runtimeVersion":"58.0.3","bridgeVersion":"3.0.0","plugins":{"@expo/ui":"58.0.3","@hanlin/expo-ui":"1.0.0"}}}"#
        ])
        defer { try? FileManager.default.removeItem(at: currentBridge.stagingRoot) }
        let currentBridgePreview = try analyzer.analyze(currentBridge)
        #expect(currentBridgePreview.canInstall)

        let newerBridge = try package(files: [
            "script.json": #"{"name":"Newer Expo Bridge Fixture","version":"1.0.0","entry":"expo/app/bundle.js","hanlinRuntime":"hanlin-expo"}"#,
            "expo/app/bundle.js": "console.log('newer bridge')",
            "expo/app/package.json": #"{"name":"fixture","main":"bundle.js","hanlinRuntime":"hanlin-expo","hanlinExpo":{"runtimeVersion":"58.0.3","bridgeVersion":"4.0.0","plugins":{"@hanlin/expo-ui":"1.0.0"}}}"#
        ])
        defer { try? FileManager.default.removeItem(at: newerBridge.stagingRoot) }
        let newerBridgePreview = try analyzer.analyze(newerBridge)
        #expect(!newerBridgePreview.canInstall)
        #expect(newerBridgePreview.findings.contains {
            $0.message.contains("bridge 3.0.0") && $0.message.contains("requires 4.0.0")
        })

        let unsupported = try package(files: [
            "script.json": #"{"name":"Unsupported Expo Fixture","version":"1.0.0","entry":"expo/app/bundle.js","hanlinRuntime":"hanlin-expo"}"#,
            "expo/app/bundle.js": "console.log('unsupported')",
            "expo/app/package.json": #"{"name":"fixture","main":"bundle.js","hanlinRuntime":"hanlin-expo","hanlinExpo":{"runtimeVersion":"58.0.3","plugins":{"@expo/ui":"99.0.0"}}}"#
        ])
        defer { try? FileManager.default.removeItem(at: unsupported.stagingRoot) }
        let unsupportedPreview = try analyzer.analyze(unsupported)
        #expect(!unsupportedPreview.canInstall)
        #expect(unsupportedPreview.findings.contains {
            $0.message.contains("supports @expo/ui 58.0.3") && $0.message.contains("@expo/ui 99.0.0")
        })
    }

    @Test("Detects capability-bearing ambient Scripting globals")
    func ambientGlobals() throws {
        let fixture = try package(files: [
            "script.json": #"{"name":"Ambient Fixture","version":"1.0.0"}"#,
            "index.ts": "Storage.set('key', 'value'); FileManager.readAsString('file.txt'); DocumentPicker.pickFiles(); QuickLook.previewURLs([]); Photos.pickPhotos(1); new Reminder().save()"
        ])
        defer { try? FileManager.default.removeItem(at: fixture.stagingRoot) }
        let preview = try HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "e", count: 64),
            symbols: [
                .init(symbol: "Storage", state: .partial),
                .init(symbol: "FileManager", state: .partial),
                .init(symbol: "DocumentPicker", state: .partial),
                .init(symbol: "QuickLook", state: .partial),
                .init(symbol: "Photos", state: .partial),
                .init(symbol: "Reminder", state: .partial)
            ]
        )).analyze(fixture)
        #expect(Set(preview.requestedCapabilities.map { $0.capabilityID.rawValue }) == [
            "files", "photos", "reminders", "storage"
        ])
        #expect(preview.findings.contains { $0.symbol == "Storage" })
        #expect(preview.findings.contains { $0.symbol == "FileManager" })
        #expect(preview.findings.contains { $0.symbol == "DocumentPicker" })
        #expect(preview.findings.contains { $0.symbol == "QuickLook" })
        #expect(preview.findings.contains { $0.symbol == "Photos" })
        #expect(preview.findings.contains { $0.symbol == "Reminder" })
    }

    @Test("Rejects dynamic imports, eval, unresolved paths, and arbitrary bare modules")
    func forbiddenModules() throws {
        let fixture = try package(files: [
            "script.json": #"{"name":"Fixture","version":"1.0.0"}"#,
            "index.tsx": #"import thing from "arbitrary-npm"; import("./late"); eval("1"); import "./missing""#
        ])
        defer { try? FileManager.default.removeItem(at: fixture.stagingRoot) }
        let preview = try HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "b", count: 64),
            symbols: []
        )).analyze(fixture)
        #expect(!preview.canInstall)
        #expect(Set(preview.dependencyGraph.unresolvedSpecifiers) == ["./late", "./missing", "arbitrary-npm"])
        #expect(preview.findings.contains { $0.message.contains("Dynamic import") })
        #expect(preview.findings.contains { $0.message.contains("eval") })
    }

    @Test("Extracts declared capabilities from script.json manifest")
    func declaredCapabilitiesInManifest() throws {
        let fixture = try package(files: [
            "script.json": #"{"name":"NativeScript Parity Fixture","version":"1.0.0","entry":"nativescript/app/bundle.mjs","hanlinRuntime":"hanlin-nativescript","capabilities":["storage","network","node","python","javascript","inter-app.share"]}"#,
            "nativescript/app/bundle.mjs": "export default 42;"
        ])
        defer { try? FileManager.default.removeItem(at: fixture.stagingRoot) }
        let preview = try HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "b", count: 64),
            symbols: []
        )).analyze(fixture)
        let requestedIDs = Set(preview.requestedCapabilities.map(\.capabilityID.rawValue))
        #expect(requestedIDs == ["storage", "network", "node", "python", "javascript", "inter-app.share"])
    }

    @Test("Expo import evaluates foreground app and multi-exposure support fail-closed")
    func expoMultiExposureMatrix() throws {
        let analyzer = HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "f", count: 64),
            symbols: []
        ))

        // 1. App only (PASS)
        let appOnly = try package(files: [
            "script.json": #"{"name":"Expo App Only","version":"1.0.0","entry":"expo/app/bundle.js","hanlinRuntime":"hanlin-expo"}"#,
            "expo/app/bundle.js": "console.log('app')",
            "expo/app/package.json": #"{"name":"fixture","main":"bundle.js","hanlinRuntime":"hanlin-expo","hanlinExpo":{"runtimeVersion":"58.0.3","bridgeVersion":"3.0.0","plugins":{"@hanlin/expo-ui":"1.0.0"}}}"#
        ])
        defer { try? FileManager.default.removeItem(at: appOnly.stagingRoot) }
        let appOnlyPreview = try analyzer.analyze(appOnly)
        #expect(appOnlyPreview.canInstall)
        #expect(appOnlyPreview.entrypoints.count == 1)
        #expect(appOnlyPreview.entrypoints.first?.kind == .app)
        #expect(appOnlyPreview.entrypoints.first?.runtimeProfile == .hanlinExpo)
        #expect(appOnlyPreview.entrypoints.first?.sourcePath == "expo/app/bundle.js")

        // 2. App + widget.tsx (PASS)
        let appAndWidget = try package(files: [
            "script.json": #"{"name":"Expo App And Widget","version":"1.0.0","entry":"expo/app/bundle.js","hanlinRuntime":"hanlin-expo"}"#,
            "expo/app/bundle.js": "console.log('app')",
            "expo/app/package.json": #"{"name":"fixture","main":"bundle.js","hanlinRuntime":"hanlin-expo","hanlinExpo":{"runtimeVersion":"58.0.3","bridgeVersion":"3.0.0","plugins":{"@hanlin/expo-ui":"1.0.0"}}}"#,
            "widget.tsx": "export const renderWidget = () => ({});"
        ])
        defer { try? FileManager.default.removeItem(at: appAndWidget.stagingRoot) }
        let appAndWidgetPreview = try analyzer.analyze(appAndWidget)
        #expect(appAndWidgetPreview.canInstall)
        #expect(appAndWidgetPreview.entrypoints.count == 2)
        let kinds = Set(appAndWidgetPreview.entrypoints.map(\.kind))
        #expect(kinds == [.app, .widget])
        #expect(appAndWidgetPreview.entrypoints.allSatisfy { $0.runtimeProfile == .hanlinExpo })
        let widgetEntry = appAndWidgetPreview.entrypoints.first { $0.kind == .widget }
        #expect(widgetEntry?.sourcePath == "widget.tsx")

        // 3. App + widget.tsx + app_intents.tsx (All discovered, but canInstall == false because no native executor)
        let appWidgetIntents = try package(files: [
            "script.json": #"{"name":"Expo App Widget Intents","version":"1.0.0","entry":"expo/app/bundle.js","hanlinRuntime":"hanlin-expo"}"#,
            "expo/app/bundle.js": "console.log('app')",
            "expo/app/package.json": #"{"name":"fixture","main":"bundle.js","hanlinRuntime":"hanlin-expo","hanlinExpo":{"runtimeVersion":"58.0.3","bridgeVersion":"3.0.0","plugins":{"@hanlin/expo-ui":"1.0.0"}}}"#,
            "widget.tsx": "export const renderWidget = () => ({});",
            "app_intents.tsx": "export const performIntent = () => ({});"
        ])
        defer { try? FileManager.default.removeItem(at: appWidgetIntents.stagingRoot) }
        let appWidgetIntentsPreview = try analyzer.analyze(appWidgetIntents)
        #expect(!appWidgetIntentsPreview.canInstall)
        #expect(appWidgetIntentsPreview.entrypoints.count == 3)
        let allKinds = Set(appWidgetIntentsPreview.entrypoints.map(\.kind))
        #expect(allKinds == [.app, .widget, .appIntent])
        #expect(appWidgetIntentsPreview.entrypoints.allSatisfy { $0.runtimeProfile == .hanlinExpo })
        let intentEntry = appWidgetIntentsPreview.entrypoints.first { $0.kind == .appIntent }
        #expect(intentEntry?.sourcePath == "app_intents.tsx")
        #expect(appWidgetIntentsPreview.findings.contains {
            $0.severity == .error && $0.message.contains("appIntent") && $0.message.contains("unsupported")
        })

        // 4. Widget only (FAIL: no foreground app)
        let widgetOnly = try package(files: [
            "script.json": #"{"name":"Expo Widget Only","version":"1.0.0","hanlinRuntime":"hanlin-expo"}"#,
            "widget.tsx": "export const renderWidget = () => ({});"
        ])
        defer { try? FileManager.default.removeItem(at: widgetOnly.stagingRoot) }
        let widgetOnlyPreview = try analyzer.analyze(widgetOnly)
        #expect(!widgetOnlyPreview.canInstall)
        #expect(widgetOnlyPreview.entrypoints.count == 1)
        #expect(widgetOnlyPreview.entrypoints.first?.kind == .widget)
        #expect(widgetOnlyPreview.entrypoints.first?.runtimeProfile == .hanlinExpo)
        #expect(widgetOnlyPreview.findings.contains {
            $0.severity == .error && $0.message.contains("Expo requires exactly one foreground app entrypoint")
        })
    }

    private func package(files: [String: String]) throws -> HanlinStagedPackage {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-analyzer-tests-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let packageRoot = root.appending(path: "package", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        for (path, source) in files {
            let url = packageRoot.appending(path: path, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(source.utf8).write(to: url)
        }
        let manifest = try JSONDecoder().decode(
            HanlinScriptingManifest.self,
            from: Data((try #require(files["script.json"])).utf8)
        )
        return HanlinStagedPackage(
            source: .init(
                originalFileName: "fixture.scripting",
                format: .scripting,
                contentSHA256: String(repeating: "c", count: 64),
                byteCount: 100,
                importedAt: Date(timeIntervalSince1970: 1)
            ),
            stagingRoot: root,
            archiveURL: root.appending(path: "source.scripting"),
            packageRoot: packageRoot,
            inspection: .init(
                fileCount: files.count,
                directoryCount: 1,
                compressedBytes: 100,
                uncompressedBytes: 200,
                maximumDepth: 2,
                manifestPath: "script.json"
            ),
            manifest: manifest
        )
    }
}
