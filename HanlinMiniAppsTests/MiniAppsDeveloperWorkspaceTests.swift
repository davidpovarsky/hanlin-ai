import Foundation
import Dispatch
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


@Suite("MiniApps library root lifecycle")
@MainActor
struct MiniAppsStudioLibraryResolutionTests {
    private enum ProbeFailure: Error {
        case mainActorBlocked
        case releaseTimedOut
    }

    private func root() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "MiniAppsLibraryResolution-" + UUID().uuidString, directoryHint: .isDirectory)
    }

    @Test func rootLookupLeavesTheMainActorAvailable() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try await MiniAppsStudioLibraryLoadState.resolveWorkspace {
            let progress = DispatchSemaphore(value: 0)
            Task { @MainActor in progress.signal() }
            guard progress.wait(timeout: .now() + 2) == .success else {
                throw ProbeFailure.mainActorBlocked
            }
            return root
        }
        #expect(workspace.root == root.standardizedFileURL.resolvingSymlinksInPath())
        #expect(FileManager.default.fileExists(atPath: root.path))
    }

    @Test func cancellingAnInFlightLookupRejectsItsLateRoot() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let release = DispatchSemaphore(value: 0)
        let lookup = Task {
            defer { started.continuation.finish() }
            return try await MiniAppsStudioLibraryLoadState.resolveWorkspace {
                started.continuation.yield(())
                guard release.wait(timeout: .now() + 5) == .success else {
                    throw ProbeFailure.releaseTimedOut
                }
                return root
            }
        }
        for await _ in started.stream { break }
        lookup.cancel()
        release.signal()
        do {
            _ = try await lookup.value
            Issue.record("A cancelled root lookup must not deliver a workspace.")
        } catch is CancellationError {}
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func lateLookupAndCancellationCannotReplaceTheOpenedWorkspace() throws {
        let first = try MiniAppsDeveloperWorkspace(root: root())
        let second = try MiniAppsDeveloperWorkspace(root: root())
        defer {
            try? FileManager.default.removeItem(at: first.root)
            try? FileManager.default.removeItem(at: second.root)
        }
        try first.createFile("index.ts", text: "first project")
        try second.createFile("index.ts", text: "second project")
        let openDocument = try second.read("index.ts")
        let unsavedText = "unsaved editor revision"
        var state = MiniAppsStudioLibraryLoadState()
        let oldRequestValue = state.begin()
        let oldRequest = try #require(oldRequestValue)
        let currentRequestValue = state.begin()
        let currentRequest = try #require(currentRequestValue)
        state.succeed(second, for: currentRequest)
        state.cancel(oldRequest)
        state.fail("stale cloud error", for: oldRequest)
        state.succeed(first, for: oldRequest)
        state.cancelCurrentRequest()
        #expect(state.workspace?.root == second.root)
        #expect(state.error == nil)
        let reopenedRequest = state.begin()
        #expect(reopenedRequest == nil)
        let retained = try #require(state.workspace)
        _ = try retained.save(unsavedText, document: openDocument)
        #expect(try second.read("index.ts").text == unsavedText)
        #expect(try first.read("index.ts").text == "first project")
    }

    @Test func anUnavailableLibraryCanRetryWithoutAcceptingAnOldCompletion() throws {
        let workspace = try MiniAppsDeveloperWorkspace(root: root())
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        var state = MiniAppsStudioLibraryLoadState()
        let unavailableValue = state.begin()
        let unavailable = try #require(unavailableValue)
        state.fail("iCloud document storage is unavailable.", for: unavailable)
        #expect(state.error != nil)
        let retryValue = state.begin()
        let retry = try #require(retryValue)
        #expect(state.error == nil)
        state.succeed(workspace, for: unavailable)
        #expect(state.workspace == nil)
        state.succeed(workspace, for: retry)
        #expect(state.workspace?.root == workspace.root)
        let reopenedRequest = state.begin()
        #expect(reopenedRequest == nil)
    }
}
