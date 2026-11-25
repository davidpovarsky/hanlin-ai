import Foundation
import Testing
@testable import HanlinNativeScriptRuntime

@Suite("NativeScript shared module links")
struct NativeScriptSharedModuleLinksTests {
    @Test func existingUserPackagesAndScopesKeepTheirBytesWhileOriginalCoreRemainsResolvable() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-shared-modules-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appending(path: "shared")
        let app = root.appending(path: "app")
        func file(_ relative: String, _ content: String) throws {
            let url = root.appending(path: relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        try file("shared/@nativescript/core/index.mjs", "original-core")
        try file("shared/tslib/index.mjs", "original-shared-tslib")
        try file("app/node_modules/@nativescript/swift-ui/index.ios.js", "original-plugin")
        try file("app/node_modules/tslib/index.mjs", "user-tslib")
        let links = try HanlinNativeScriptSharedModuleLinks.prepare(sharedRuntime: shared, applicationRoot: app)
        let core = app.appending(path: "node_modules/@nativescript/core")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: core.path) == shared.appending(path: "@nativescript/core").path)
        #expect(try String(contentsOf: core.appending(path: "index.mjs"), encoding: .utf8) == "original-core")
        #expect(try String(contentsOf: app.appending(path: "node_modules/@nativescript/swift-ui/index.ios.js"), encoding: .utf8) == "original-plugin")
        #expect(try String(contentsOf: app.appending(path: "node_modules/tslib/index.mjs"), encoding: .utf8) == "user-tslib")
        for link in links { try FileManager.default.removeItem(at: link) }
        #expect(try String(contentsOf: app.appending(path: "node_modules/@nativescript/swift-ui/index.ios.js"), encoding: .utf8) == "original-plugin")
        #expect(try String(contentsOf: shared.appending(path: "@nativescript/core/index.mjs"), encoding: .utf8) == "original-core")
    }

    @Test func anApplicationWithoutPrivateDependenciesUsesTheExistingWholeSharedTree() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-shared-empty-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appending(path: "shared")
        let app = root.appending(path: "app")
        try FileManager.default.createDirectory(at: shared.appending(path: "tslib"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let links = try HanlinNativeScriptSharedModuleLinks.prepare(sharedRuntime: shared, applicationRoot: app)
        #expect(links.contains { $0.path == app.appending(path: "node_modules").path })
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: app.appending(path: "node_modules").path) == shared.path)
    }

    @Test func aHostResourceLinkLeftByAnInterruptedOldAppRefreshesAfterAnAppUpdate() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-shared-update-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appending(path: "new-bundle/NativeScriptSharedRuntime")
        let app = root.appending(path: "app")
        try FileManager.default.createDirectory(at: shared.appending(path: "@nativescript/core"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: app.appending(path: "node_modules"),
            withDestinationURL: root.appending(path: "old-bundle/NativeScriptSharedRuntime"))
        let links = try HanlinNativeScriptSharedModuleLinks.prepare(sharedRuntime: shared, applicationRoot: app)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: app.appending(path: "node_modules").path) == shared.path)
        #expect(links.contains { $0.path == app.appending(path: "node_modules").path })
        #expect(FileManager.default.fileExists(atPath: app.appending(path: "node_modules/@nativescript/core").path))
    }

}
