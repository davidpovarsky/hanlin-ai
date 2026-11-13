import Foundation
import HanlinExpoRuntime
import Testing

@Suite("Prepared Expo launch entry boundary", .serialized)
@MainActor
struct ExpoPreparedEntrypointTests {
    @Test func malformedAndEscapingMainValuesAreRejectedBeforeRuntimeCreation() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let outside = root.deletingLastPathComponent().appending(path: "outside.js")
        try Data("throw Error('MUST_NOT_LOAD')".utf8).write(to: outside)
        for main: Any in ["../outside.js", outside.path, "file://" + outside.path,
                          "dir\\entry.js", "", "dir//entry.js", "./bundle.js", 42, NSNull(), true] {
            try package(root, main: main)
            #expect(throws: (any Error).self) { _ = try HanlinExpoSession(applicationRoot: root) }
        }
    }

    @Test func symlinkedMetadataOrAnyEntrypointComponentCannotRedirectThePreparedRoot() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let outside = root.deletingLastPathComponent().appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("42".utf8).write(to: outside.appending(path: "entry.js"))
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link.js"), withDestinationURL: outside.appending(path: "entry.js"))
        try FileManager.default.createSymbolicLink(at: root.appending(path: "linked"), withDestinationURL: outside)
        for main in ["link.js", "linked/entry.js", "missing.js", "directory"] {
            if main == "directory" { try FileManager.default.createDirectory(at: root.appending(path: main), withIntermediateDirectories: true) }
            try package(root, main: main)
            #expect(throws: (any Error).self) { _ = try HanlinExpoSession(applicationRoot: root) }
        }
        let json = outside.appending(path: "external-package.json")
        try Data(#"{"hanlinRuntime":"hanlin-expo","main":"bundle.js"}"#.utf8).write(to: json)
        try FileManager.default.removeItem(at: root.appending(path: "package.json"))
        try FileManager.default.createSymbolicLink(at: root.appending(path: "package.json"), withDestinationURL: json)
        #expect(throws: (any Error).self) { _ = try HanlinExpoSession(applicationRoot: root) }
    }

    @Test func defaultAndNestedRegularFilesRemainValidWithoutStartingReactOrHermes() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try package(root, main: nil)
        #expect(try HanlinExpoSession(applicationRoot: root).bundleURL == root.appending(path: "bundle.js"))
        let nested = root.appending(path: "chunks", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("42".utf8).write(to: nested.appending(path: "main.js"))
        try package(root, main: "chunks/main.js")
        #expect(try HanlinExpoSession(applicationRoot: root).bundleURL == nested.appending(path: "main.js"))
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "expo-entry-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("42".utf8).write(to: root.appending(path: "bundle.js"))
        return root
    }

    private func package(_ root: URL, main: Any?) throws {
        var object: [String: Any] = ["hanlinRuntime": "hanlin-expo", "name": "prepared-entry-test"]
        if let main { object["main"] = main }
        try JSONSerialization.data(withJSONObject: object).write(to: root.appending(path: "package.json"))
    }
}
