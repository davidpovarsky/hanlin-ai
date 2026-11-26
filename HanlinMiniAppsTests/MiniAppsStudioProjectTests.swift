import Foundation
@testable import HanlinMiniApps
import Testing

@MainActor
@Suite("MiniApps Studio document lifecycle", .serialized)
struct MiniAppsStudioProjectTests {
    @Test func renamingTheOpenFileRebindsLaterEditsAndSaves() throws {
        let workspace = try temporary()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try workspace.createFile("hanlin.authoring.json",
            text: #"{"schemaVersion":1,"engine":"nativescript","entry":"index.ts"}"#)
        try workspace.createFile("index.ts", text: "export const value = 1;")
        let project = try MiniAppsStudioProject(project: workspace.root)
        try project.moveSelectedFile(to: "nested/renamed.ts")
        #expect(project.selectedPath == "nested/renamed.ts")
        project.text = "export const value = 2;"
        project.edited()
        try project.save()
        #expect(try workspace.read("nested/renamed.ts").text == "export const value = 2;")
        #expect(!FileManager.default.fileExists(atPath: workspace.root.appending(path: "index.ts").path))
        #expect(!project.isDirty)
    }

    @Test(arguments: [false, true])
    func outerDescriptorRemainsAvailableWhenSourceRootHasNoCompleteDescriptor(hasPartialInnerDescriptor: Bool) throws {
        let workspace = try temporary()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try workspace.createFile("hanlin.authoring.json",
            text: #"{"schemaVersion":1,"engine":"nativescript","entry":"main.ts","sourceRoot":"source"}"#)
        try workspace.createFile("source/main.ts", text: "export const value = 1;")
        if hasPartialInnerDescriptor {
            try workspace.createFile("source/hanlin.authoring.json", text: #"{"schemaVersion":1,"engine":"nativescript"}"#)
        }
        let project = try MiniAppsStudioProject(project: workspace.root)
        #expect(project.engine == "nativescript")
        #expect(project.selectedPath == "main.ts")
        #expect(project.authoringRoot.path == workspace.root.path)
        #expect(project.workspace.root.path == workspace.root.appending(path: "source").path)
    }

    @Test func malformedRecoveryDoesNotHideOrAlterAnotherWindowsDraft() throws {
        let workspace = try temporary()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let draft = MiniAppsStudioDraft(id: UUID(), projectPath: workspace.root.path, path: "index.ts",
            text: "unsaved text", original: Data("original".utf8), savedAt: .now)
        let validFile = workspace.root.appending(path: draft.id.uuidString + ".json")
        try JSONEncoder().encode(draft).write(to: validFile)
        let damagedFile = workspace.root.appending(path: UUID().uuidString + ".json")
        let damaged = Data("{ incomplete".utf8)
        try damaged.write(to: damagedFile)
        let listing = try MiniAppsStudioDraft.readAll(from: workspace.root)
        #expect(listing.drafts.map(\.id) == [draft.id])
        #expect(listing.issues.count == 1)
        #expect(listing.issues.first?.file == damagedFile)
        #expect(try Data(contentsOf: damagedFile) == damaged)
        #expect(try JSONDecoder().decode(MiniAppsStudioDraft.self, from: Data(contentsOf: validFile)).text == "unsaved text")
    }

    @Test(arguments: ["validate", "build"])
    func changedRevisionCannotPublishAnOriginalAuthoringResult(operation: String) async throws {
        let workspace = try temporary()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try workspace.createFile("hanlin.authoring.json",
            text: #"{"schemaVersion":1,"engine":"nativescript","entry":"index.ts","tsconfig":"tsconfig.json"}"#)
        try workspace.createFile("tsconfig.json", text: #"{"include":["index.ts"]}"#)
        try workspace.createFile("package.json",
            text: #"{"name":"studio-revision-test","version":"1.0.0","private":true,"type":"module","dependencies":{"@nativescript/core":"9.1.4"}}"#)
        try workspace.createFile("script.json",
            text: #"{"name":"Studio revision test","version":"1.0.0","entry":"nativescript/app/bundle.mjs","runInApp":true,"hanlinRuntime":"hanlin-nativescript"}"#)
        try workspace.createFile("index.ts", text: """
        import { Application, Label, Page } from '@nativescript/core';
        Application.run({create: () => {
          const page = new Page();
          const label = new Label();
          label.text = 'Original saved source';
          page.content = label;
          return page;
        }});
        """)
        let project = try MiniAppsStudioProject(project: workspace.root)
        var finished = false
        let request = Task<URL?, Never> {
            defer { finished = true }
            if operation == "build" { return await project.build() }
            await project.validate()
            return nil
        }
        // Wait for the real model to cross into the original Node authoring
        // service. No fake compiler or predetermined reply participates.
        while !project.isBusy && !finished && !Task.isCancelled { await Task.yield() }
        try #require(project.isBusy, "The original authoring service must be exercised asynchronously.")
        project.text += "\n// Edited while the original authoring request was running."
        project.edited()
        let archive = await request.value
        #expect(archive == nil, "A stale compiled archive must never reach the install handoff.")
        #expect(project.report == nil, "An old result must not restore Validation succeeded for a new revision.")
        #expect(project.error?.localizedCaseInsensitiveContains("source changed") == true,
            "The original authoring request must complete; infrastructure errors do not pass this regression.")
        try project.save()
    }

    private func temporary() throws -> MiniAppsDeveloperWorkspace {
        try .init(root: FileManager.default.temporaryDirectory.appending(path: "MiniApps-Studio-Lifecycle-" + UUID().uuidString))
    }
}
