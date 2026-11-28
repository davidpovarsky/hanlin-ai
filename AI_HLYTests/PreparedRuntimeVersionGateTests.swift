import Foundation
import HanlinExpoRuntime
import HanlinNativeScriptRuntime
import Testing

@Suite("Direct prepared runtime version gates", .serialized)
@MainActor
struct PreparedRuntimeVersionGateTests {
    @Test func nativeScriptConstructorRejectsNoncanonicalOrMissingMainBeforeCreatingAVM() throws {
        let root = try fixture(bundle: "bundle.mjs")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("throw new Error('must not run')".utf8).write(to: root.appending(path: "bundle.js"))
        for main: Any in [NSNull(), 1, "", "bundle.js", "nested/bundle.mjs", "../bundle.mjs", "/bundle.mjs"] {
            try write(root, object: ["name": "fixture", "main": main, "hanlinRuntime": "hanlin-nativescript"])
            #expect(throws: (any Error).self) { _ = try HanlinNativeScriptSession(applicationRoot: root) }
        }
        try write(root, object: ["name": "fixture", "hanlinRuntime": "hanlin-nativescript"])
        #expect(throws: (any Error).self) { _ = try HanlinNativeScriptSession(applicationRoot: root) }
        try write(root, object: ["name": "fixture", "main": "bundle.mjs", "hanlinRuntime": "wrong"])
        #expect(throws: (any Error).self) { _ = try HanlinNativeScriptSession(applicationRoot: root) }
    }

    @Test func nativeScriptConstructorUsesTheSameReleasedCoreMinimumAsImport() throws {
        let root = try fixture(bundle: "bundle.mjs")
        defer { try? FileManager.default.removeItem(at: root) }
        for (version, valid) in ["9.1.0": true, "^9.0.0": true, "9.1.0+build": true,
                                 "9.1.1": false, "9.10.0": false, "^9.999.0": false, "*": false,
                                 "latest": false, "9.1.invalid": false, "9.1.0-beta.1": false] {
            try write(root, object: ["name": "fixture", "main": "bundle.mjs", "hanlinRuntime": "hanlin-nativescript",
                                     "dependencies": ["@nativescript/core": version]])
            #expect(HanlinNativeScriptSession.isCoreVersionCompatible(version) == valid)
            if valid { #expect(try !HanlinNativeScriptSession(applicationRoot: root).isActive) }
            else { #expect(throws: (any Error).self) { _ = try HanlinNativeScriptSession(applicationRoot: root) } }
        }
    }

    @Test func malformedNativeScriptDependencyMapsDoNotBypassCoreChecks() throws {
        let root = try fixture(bundle: "bundle.mjs")
        defer { try? FileManager.default.removeItem(at: root) }
        for value: Any in [NSNull(), ["not-a-map"], ["@nativescript/core": 910], ["@nativescript/core": NSNull()]] {
            for key in ["dependencies", "devDependencies"] {
                try write(root, object: ["name": "fixture", "main": "bundle.mjs", "hanlinRuntime": "hanlin-nativescript", key: value])
                #expect(throws: (any Error).self) { _ = try HanlinNativeScriptSession(applicationRoot: root) }
            }
        }
    }

    @Test func expoConstructorRejectsMalformedFutureAndPrereleaseRuntimeContracts() throws {
        let root = try fixture(bundle: "bundle.js")
        defer { try? FileManager.default.removeItem(at: root) }
        let contracts: [Any] = [NSNull(), ["not-an-object"], ["bridgeVersion": "3.0.0"],
            ["runtimeVersion": 58, "plugins": [String: String]()], ["runtimeVersion": "58.1.0", "plugins": [String: String]()],
            ["runtimeVersion": "*", "plugins": [String: String]()], ["runtimeVersion": "latest", "plugins": [String: String]()],
            ["runtimeVersion": "58.0.3-beta.1", "plugins": [String: String]()], ["runtimeVersion": "58.0.3", "plugins": 1]]
        for contract in contracts {
            try write(root, object: ["name": "fixture", "main": "bundle.js", "hanlinRuntime": "hanlin-expo", "hanlinExpo": contract])
            #expect(throws: (any Error).self) { _ = try HanlinExpoSession(applicationRoot: root) }
        }
    }

    @Test func expoBridgeVersionTypeAndCompleteSemverAreCheckedAtConstruction() throws {
        let root = try fixture(bundle: "bundle.js")
        defer { try? FileManager.default.removeItem(at: root) }
        for bridge: Any in [3, NSNull(), "3", "3..0", "3.0.0.extra", "3.0.1", "4.0.0", "3.0.0-beta.1"] {
            try write(root, object: ["name": "fixture", "main": "bundle.js", "hanlinRuntime": "hanlin-expo",
                "hanlinExpo": ["runtimeVersion": "58.0.3", "plugins": [String: String](), "bridgeVersion": bridge]])
            #expect(throws: (any Error).self) { _ = try HanlinExpoSession(applicationRoot: root) }
        }
        for bridge in ["1.0.0", "3.0.0", "3.0.0+build"] {
            try write(root, object: ["name": "fixture", "main": "bundle.js", "hanlinRuntime": "hanlin-expo",
                "hanlinExpo": ["runtimeVersion": "58.0.3", "plugins": [String: String](), "bridgeVersion": bridge]])
            #expect(try !HanlinExpoSession(applicationRoot: root).isActive)
        }
    }

    private func fixture(bundle: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "prepared-version-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("42".utf8).write(to: root.appending(path: bundle))
        return root
    }

    private func write(_ root: URL, object: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: object).write(to: root.appending(path: "package.json"))
    }
}
