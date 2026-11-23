import Foundation
import HanlinExtensionContracts
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinScriptStore
import Testing

@Suite("MiniApps native surface routing")
struct HanlinMiniAppSurfaceRoutingTests {
    @Test("App and extensions address the same product, without an AI receipt alias")
    func receiptsRemainProductScoped() throws {
        let group = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: group) }
        let aiRoot = try HanlinExtensionHostConfiguration.hanlin.storageContainer(in: group)
        let miniRoot = try HanlinExtensionHostConfiguration.miniapps.storageContainer(in: group, createIfNeeded: true)
        #expect(aiRoot == group.resolvingSymlinksInPath().standardizedFileURL)
        #expect(miniRoot.path.hasSuffix("/HanlinMiniApps/v1"))
        let ai = HanlinScriptExtensionStore(root: aiRoot.appending(path: "ScriptingExtensions"))
        let mini = HanlinScriptExtensionStore(root: miniRoot.appending(path: "ScriptingExtensions"))
        let id = UUID()
        let identity = HanlinScriptExtensionIdentity(
            installedPackageID: try .init(validating: "installed.same"),
            packageID: try .init(validating: "package.same"), generation: 1, entrypointID: "appIntents")
        for (store, text) in [(ai, "AI"), (mini, "MiniApps")] {
            try store.enqueue(.init(id: id, invocation: .init(identity: identity,
                entityID: "search", parameters: .string(text), continueInForeground: true)))
            let claim = try #require(store.claim(id))
            try store.complete(claim, status: .succeeded, value: .string(text))
        }
        #expect(try ai.receipt(for: id)?.value == .string("AI"))
        #expect(try mini.receipt(for: id)?.value == .string("MiniApps"))
        let extensionConfig = try HanlinExtensionHostConfiguration(infoDictionary: [
            "AppGroupIdentifier": HanlinExtensionHostConfiguration.hanlinAppGroupIdentifier,
            "StorageNamespace": "HanlinMiniApps/v1"
        ])
        let extensionStore = HanlinScriptExtensionStore(root:
            try extensionConfig.storageContainer(in: group).appending(path: "ScriptingExtensions"))
        #expect(try extensionStore.receipt(for: id)?.value == .string("MiniApps"))
    }

    @Test("A first-launch MiniApps share is read by its app without entering the AI inbox")
    func shareInboxUsesSameProductContainer() throws {
        let group = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: group) }
        let configuration = HanlinExtensionHostConfiguration.miniapps
        let writer = try HanlinShareInboxStore(container: configuration.storageContainer(in: group, createIfNeeded: true))
        let id = try writer.begin()
        _ = try writer.commit(id, items: [.text("שלום🙂", ordinal: 0, typeIdentifier: "public.plain-text")])
        let reader = try HanlinShareInboxStore(container: configuration.storageContainer(in: group))
        let ai = try HanlinShareInboxStore(container: HanlinExtensionHostConfiguration.hanlin.storageContainer(in: group))
        #expect(try reader.scan().batches.map(\.id) == [id])
        #expect(try ai.scan().batches.isEmpty)
    }

    @Test("Translation action parameters preserve literal selected text through nested payloads")
    func nestedTranslationPayloadDoesNotReinterpretText() {
        let selected = "שלום🙂 {{origin}} $1 \\ source"
        let root = HanlinScriptUINode(kind: .button, properties: [
            "intent": .object(["parameters": .object([
                "query": .string("{{selectedText}}"),
                "items": .array([.string("before {{selectedText}} / {{origin}}")])
            ])])
        ])
        let resolved = root.substituting(context: ["selectedText": selected, "origin": "translation"])
        #expect(resolved.properties["intent"] == .object(["parameters": .object([
            "query": .string(selected),
            "items": .array([.string("before \(selected) / translation")])
        ])]))
    }
}
