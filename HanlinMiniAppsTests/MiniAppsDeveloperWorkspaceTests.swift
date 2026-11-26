import Foundation
@testable import HanlinMiniApps
import Testing

@Suite("MiniApps developer source preservation")
struct MiniAppsDeveloperWorkspaceTests {
    @Test func savingRejectsAnotherWritersChangesAndRetainsBothDrafts() throws {
        let workspace = try temporary()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try workspace.createFile("src/index.ts", text: "original")
        let firstWindow = try workspace.read("src/index.ts")
        let secondWindow = try workspace.read("src/index.ts")
        let saved = try workspace.save("second window", document: secondWindow)
        #expect(try workspace.read(saved.path).text == "second window")
        #expect(throws: MiniAppsDeveloperWorkspace.Failure.changedOnDisk) {
            _ = try workspace.save("first window draft", document: firstWindow)
        }
        try workspace.createFile("src/index-copy.ts", text: "first window draft")
        #expect(try workspace.read("src/index.ts").text == "second window")
        #expect(try workspace.read("src/index-copy.ts").text == "first window draft")
    }

    @Test func nestedMovesPreserveSourceAndFolderAppearanceWithoutReplacingDestination() throws {
        let workspace = try temporary()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try workspace.createFolder("one/nested")
        try workspace.createFile("one/nested/main.ts", text: "const שלום = 1;")
        let style = MiniAppsDeveloperWorkspace.FolderStyle(symbol: "star.fill", color: "purple")
        try workspace.setStyle(style, for: "one/nested")
        try workspace.move("one/nested", to: "two/renamed")
        #expect(try workspace.read("two/renamed/main.ts").text == "const שלום = 1;")
        #expect(try workspace.style(for: "two/renamed") == style)
        try workspace.createFile("occupied", text: "keep")
        #expect(throws: MiniAppsDeveloperWorkspace.Failure.alreadyExists) {
            try workspace.move("two/renamed/main.ts", to: "occupied")
        }
        #expect(try workspace.read("occupied").text == "keep")
    }

    @Test func boundariesAndExistingFilesCannotBeOverwrittenThroughCreation() throws {
        let workspace = try temporary()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try workspace.createFile("one.ts", text: "keep")
        #expect(throws: (any Error).self) { try workspace.createFile("one.ts", text: "replace") }
        #expect(try workspace.read("one.ts").text == "keep")
        for path in ["../outside.ts", "/absolute.ts", "folder/../../outside", "bad\0path"] {
            #expect(throws: MiniAppsDeveloperWorkspace.Failure.invalidPath) { _ = try workspace.url(for: path) }
        }
        try FileManager.default.createSymbolicLink(atPath: workspace.root.appending(path: "link").path,
            withDestinationPath: workspace.root.deletingLastPathComponent().path)
        #expect(throws: MiniAppsDeveloperWorkspace.Failure.symbolicLink) { _ = try workspace.url(for: "link/outside") }
        try FileManager.default.createSymbolicLink(atPath: workspace.root.appending(path: ".miniapps-folder.json").path,
            withDestinationPath: workspace.root.appending(path: "one.ts").path)
        #expect(throws: MiniAppsDeveloperWorkspace.Failure.symbolicLink) { _ = try workspace.style(for: "") }
        #expect(throws: MiniAppsDeveloperWorkspace.Failure.symbolicLink) { try workspace.setStyle(.init(), for: "") }
        #expect(try workspace.read("one.ts").text == "keep")
    }

    @Test func exampleCopyKeepsOriginalAndIndependentVersions() throws {
        let original = try temporary()
        let library = try temporary()
        defer {
            try? FileManager.default.removeItem(at: original.root)
            try? FileManager.default.removeItem(at: library.root)
        }
        try original.createFile("index.ts", text: "original example")
        let copy = try library.copyProject(from: original.root, named: "example-v1")
        let document = try library.read(copy + "/index.ts")
        _ = try library.save("my revision", document: document)
        #expect(try original.read("index.ts").text == "original example")
        #expect(try library.read(copy + "/index.ts").text == "my revision")
        #expect(throws: MiniAppsDeveloperWorkspace.Failure.alreadyExists) {
            _ = try library.copyProject(from: original.root, named: "example-v1")
        }
        try FileManager.default.createSymbolicLink(atPath: original.root.appending(path: ".hidden-link").path,
            withDestinationPath: library.root.path)
        #expect(throws: MiniAppsDeveloperWorkspace.Failure.symbolicLink) {
            _ = try library.copyProject(from: original.root, named: "unsafe-example")
        }
        #expect(!FileManager.default.fileExists(atPath: library.root.appending(path: "unsafe-example").path))
    }

    private func temporary() throws -> MiniAppsDeveloperWorkspace {
        try .init(root: FileManager.default.temporaryDirectory.appending(path: "MiniApps-Studio-" + UUID().uuidString))
    }
}
