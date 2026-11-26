import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
@testable import HanlinScriptExtensions
import Testing

@Suite("Keyboard and notification native presentations")
struct HanlinKeyboardNotificationPresentationTests {
    @Test("Read-only catalog does not create a shared container, lock or diagnostic")
    func readOnlyCatalogDoesNotWriteEvenOnFailure() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        #expect(try store.loadReadOnly() == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("invalid JSON".utf8).write(to: root.appending(path: "commit.json"))
        let before = try image(root)
        #expect(throws: (any Error).self) { _ = try store.loadReadOnly() }
        #expect(try image(root) == before)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".transaction.lock").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "diagnostics").path))
    }

    @Test("Pending publication is neither repaired nor admitted by the keyboard reader")
    func readOnlyCatalogUsesCommittedImmutableRevision() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        let expected = HanlinScriptExtensionSnapshot(schemaVersion: 2, generatedAt: Date(timeIntervalSince1970: 123))
        try store.save(expected)
        try FileManager.default.removeItem(at: root.appending(path: ".transaction.lock"))
        let pending: [String: Any] = [
            "candidate": ["version": 1, "snapshotHash": String(repeating: "a", count: 64),
                          "shadowHash": String(repeating: "b", count: 64)],
            "previousShadowHash": NSNull()
        ]
        try JSONSerialization.data(withJSONObject: pending).write(to: root.appending(path: "pending.json"))
        let before = try image(root)
        #expect(try store.loadReadOnly() == expected)
        #expect(try image(root) == before)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".transaction.lock").path))
    }

    @Test("Original keyboard stays local, keeps state across text changes and does not repeat edits")
    func originalKeyboardExecutesLocallyAndDoesNotRepeatAnEdit() throws {
        let root = temporary(), local = temporary()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: local)
        }
        let store = HanlinScriptExtensionStore(root: root)
        let identity = try identity(entrypoint: "keyboard")
        let program = HanlinWidgetProgram(engine: .scriptwidget,
            sourceSHA256: String(repeating: "a", count: 64), compilerSHA256: String(repeating: "b", count: 64),
            javaScript: """
            async function $main() {
              if (__hanlinAction === "insert") {
                const count = ($storage.get("count") || 0) + 1;
                $storage.set("count", count);
                $presentation.keyboard.insertText($file.read("keyboard.txt") + String(count));
              }
              $render(ScriptWidget.createElement("text", {}, "Keyboard"));
            }
            """,
            actions: [.init(id: "insert", kind: .function, handler: "insert")],
            families: ["systemLarge"], resources: ["keyboard.txt": Data("שלום".utf8)])
        try publish(program, identity: identity, kind: .keyboard, store: store)
        try FileManager.default.removeItem(at: root.appending(path: ".transaction.lock"))
        let before = try image(root)
        let session = UUID()
        func request(_ text: String) -> HanlinNativePresentationRequest {
            .init(identity: identity, kind: .keyboard, sessionID: session,
                keyboard: .init(documentContextBeforeInput: text, hasFullAccess: false))
        }
        let firstRequest = request("")
        let prepared = try HanlinNativePresentationExecutor.prepare(firstRequest, store: store,
            storage: .extensionLocal(root: local))
        let firstContext = try context(prepared)
        let resource = try #require(firstContext.resources["keyboard.txt"])
        let localPath = local.resolvingSymlinksInPath().standardizedFileURL.path
        #expect(resource.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(localPath + "/"))
        #expect(try Data(contentsOf: resource) == Data("שלום".utf8))
        let command = HanlinWidgetActionCommand(context: firstContext, actionID: "insert", nonce: UUID().uuidString)
        let first = try HanlinNativePresentationExecutor.prepare(firstRequest, store: store, action: command,
            storage: .extensionLocal(root: local))
        #expect(first.effect.keyboardEdits == [.init(operation: .insertText, text: "שלום1")])
        let replay = try HanlinNativePresentationExecutor.prepare(firstRequest, store: store, action: command,
            storage: .extensionLocal(root: local))
        #expect(replay.effect.keyboardEdits.isEmpty)
        let secondRequest = request("שלום1")
        let secondPrepared = try HanlinNativePresentationExecutor.prepare(secondRequest, store: store,
            storage: .extensionLocal(root: local))
        let secondCommand = HanlinWidgetActionCommand(context: try context(secondPrepared),
            actionID: "insert", nonce: UUID().uuidString)
        let second = try HanlinNativePresentationExecutor.prepare(secondRequest, store: store, action: secondCommand,
            storage: .extensionLocal(root: local))
        #expect(second.effect.keyboardEdits == [.init(operation: .insertText, text: "שלום2")])
        #expect(try image(root) == before)
        #expect(FileManager.default.fileExists(atPath: local.appending(path: "ScriptWidgetOriginal/v1").path))
    }

    @Test("Extension-local execution cannot accidentally target the shared directory")
    func localModeRejectsSharedRoot() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        let request = HanlinNativePresentationRequest(identity: try identity(entrypoint: "keyboard"), kind: .keyboard,
            keyboard: .init(hasFullAccess: false))
        for candidate in [root, root.appending(path: "child")] {
            #expect(throws: HanlinNativePresentationError.self) {
                _ = try HanlinNativePresentationExecutor.prepare(request, store: store,
                    storage: .extensionLocal(root: candidate))
            }
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test("Absent keyboard document text is omitted, matching its optional SDK fields")
    func keyboardContextEncodingMatchesSDKShape() throws {
        let context = HanlinKeyboardContext(hasFullAccess: false)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any])
        #expect(Set(object.keys) == ["hasFullAccess"])
        #expect(object["hasFullAccess"] as? Bool == false)
        let populated = HanlinKeyboardContext(documentContextBeforeInput: "before",
            documentContextAfterInput: "after", selectedText: "selected", hasFullAccess: true)
        let encoded = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(populated)) as? [String: Any])
        #expect(encoded["documentContextBeforeInput"] as? String == "before")
        #expect(encoded["documentContextAfterInput"] as? String == "after")
        #expect(encoded["selectedText"] as? String == "selected")
    }

    @Test("Old effects decode and keyboard commands cannot target a notification")
    func typedEffectsPreserveOldPanelsAndSurfaceBoundaries() throws {
        let old = try JSONDecoder().decode(HanlinNativePresentationEffect.self,
            from: Data(#"{"expandsSheet":true,"finishRequested":true,"replacementText":"שלום"}"#.utf8))
        #expect(old.expandsSheet && old.finishRequested)
        #expect(old.keyboardEdits.isEmpty && old.notificationAction == nil)
        let effect = try JSONDecoder().decode(HanlinNativePresentationEffect.self,
            from: Data(#"{"keyboardEdits":[{"operation":"insertText","text":"a"}]}"#.utf8))
        let keyboard = HanlinNativePresentationRequest(identity: try identity(entrypoint: "keyboard"),
            kind: .keyboard, keyboard: .init(hasFullAccess: false))
        try effect.validate(for: keyboard)
        let notification = HanlinNativePresentationRequest(identity: try identity(entrypoint: "notificationUI"),
            kind: .notificationUI)
        #expect(throws: HanlinNativePresentationError.self) { try effect.validate(for: notification) }
        #expect(throws: HanlinNativePresentationError.self) {
            try HanlinKeyboardEdit(operation: .insertText).validate()
        }
        #expect(throws: HanlinNativePresentationError.self) {
            try HanlinKeyboardEdit(operation: .deleteBackward, text: "unexpected").validate()
        }
    }

    @Test("Notification selection uses plain JSON and matches action installation, package and generation")
    func notificationPayloadRoundTripAndTargetMatch() throws {
        let target = try identity(entrypoint: "notificationUI")
        let payload = try HanlinNotificationPresentationPayload(identity: target,
            parameters: .object(["text": .string("שלום🙂"), "ordered": .array([.integer(3), .null])]))
        #expect(try HanlinNotificationPresentationPayload.decode(userInfo: payload.userInfo()) == payload)
        let object = try #require(try payload.userInfo()[HanlinNotificationPresentationPayload.userInfoKey] as? [String: Any])
        #expect((object["parameters"] as? [String: Any])?["text"] as? String == "שלום🙂")
        try payload.validateContinuation(event(identity: identity(entrypoint: "receiveNotification")))
        for changed in [
            try identity(entrypoint: "receiveNotification", installation: "installed.other"),
            try identity(entrypoint: "receiveNotification", package: "package.other"),
            try identity(entrypoint: "receiveNotification", generation: 2)
        ] {
            #expect(throws: HanlinNativePresentationError.self) {
                try payload.validateContinuation(event(identity: changed))
            }
        }
        #expect(try HanlinNotificationPresentationPayload.decode(userInfo: ["ordinary": true]) == nil)
    }

    @Test("Notification continuation keeps its queued and actual terminal receipt")
    func notificationContinuationUsesTheExistingReceipt() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        let target = try identity(entrypoint: "notificationUI")
        try publish(textProgram(), identity: target, kind: .notificationUI, store: store)
        let payload = try HanlinNotificationPresentationPayload(identity: target)
        let event = try event(identity: identity(entrypoint: "receiveNotification"))
        let queued = try payload.enqueueContinuation(event, in: store)
        #expect(queued.status == .queued && queued.attempt == 0)
        #expect(try payload.enqueueContinuation(event, in: store) == queued)
        let claim = try #require(try store.claim(event.id))
        try store.complete(claim, status: .succeeded, value: .string("actual handler value"))
        let completed = try payload.enqueueContinuation(event, in: store)
        #expect(completed.status == .succeeded)
        #expect(completed.value == .string("actual handler value"))
        #expect(completed.attempt == 1)
    }

    @Test("A removed presentation cannot enqueue a new notification continuation")
    func removedPresentationDoesNotEnqueue() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        let payload = try HanlinNotificationPresentationPayload(identity: identity(entrypoint: "notificationUI"))
        let event = try event(identity: identity(entrypoint: "receiveNotification"))
        try store.save(.init(schemaVersion: 2, generatedAt: .now))
        #expect(throws: HanlinNativePresentationError.self) {
            _ = try payload.enqueueContinuation(event, in: store)
        }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "ResumeQueue").path))
    }

    private func temporary() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "hanlin-new-surfaces-" + UUID().uuidString).resolvingSymlinksInPath()
    }

    private func identity(entrypoint: String, installation: String = "installed.presentation",
                          package: String = "package.presentation", generation: UInt64 = 1) throws -> HanlinScriptExtensionIdentity {
        .init(installedPackageID: try .init(validating: installation), packageID: try .init(validating: package),
            generation: generation, entrypointID: entrypoint)
    }

    private func event(identity: HanlinScriptExtensionIdentity) throws -> HanlinNotificationEvent {
        try .init(id: UUID(), createdAt: .now, expiresAt: Date.now.addingTimeInterval(300),
            appID: .init(validating: "presentation.demo"), identity: identity,
            actionID: .init(validating: "receiveNotification"), parameters: .string("input"))
    }

    private func textProgram() -> HanlinWidgetProgram {
        .init(engine: .scriptwidget, sourceSHA256: String(repeating: "a", count: 64),
            compilerSHA256: String(repeating: "b", count: 64),
            javaScript: "async function $main() { $render(ScriptWidget.createElement('text', {}, 'Notification')); }",
            actions: [], families: ["systemLarge"])
    }

    private func publish(_ program: HanlinWidgetProgram, identity: HanlinScriptExtensionIdentity,
                         kind: HanlinNativePresentationKind, store: HanlinScriptExtensionStore) throws {
        let artifact = try store.storeArtifact(data: JSONEncoder().encode(program),
            installedPackageID: identity.installedPackageID, generation: identity.generation)
        let record = HanlinNativePresentationSnapshot(identity: identity, displayName: "Original native presentation",
            kind: kind, nativePresentation: .init(engine: program.engine, programRef: artifact.ref,
                programSHA256: artifact.sha256))
        try store.save(.init(schemaVersion: 2, generatedAt: .now, nativePresentations: [record]))
    }

    private func context(_ execution: HanlinNativePresentationExecution) throws -> HanlinWidgetActionContext {
        switch execution.prepared {
        case let .scriptwidget(_, context), let .expo(_, context): return context
        default: throw HanlinNativePresentationError.unavailable
        }
    }

    private func image(_ root: URL) throws -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        var result: [String: Data] = [:]
        for case let file as URL in enumerator {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(file.path.dropFirst(root.path.count))] = try Data(contentsOf: file)
            }
        }
        return result
    }
}
