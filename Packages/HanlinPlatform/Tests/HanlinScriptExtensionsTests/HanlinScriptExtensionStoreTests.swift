import Foundation
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinScriptUI
import Testing

@Suite("Scripting extension snapshot store")
struct HanlinScriptExtensionStoreTests {
    @Test("Persists an integrity-checked extension-safe snapshot")
    func roundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-extension-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = HanlinScriptExtensionIdentity(
            installedPackageID: try .init(validating: "installed.demo"),
            packageID: try .init(validating: "package.demo"),
            generation: 7,
            entrypointID: "widget.main"
        )
        let snapshot = HanlinScriptExtensionSnapshot(
            generatedAt: Date(timeIntervalSince1970: 12),
            widgets: [.init(
                identity: identity,
                displayName: "Demo",
                validUntil: Date(timeIntervalSince1970: 120),
                root: .init(kind: .text, properties: ["text": .string("Hello")])
            )],
            intentEntities: [.init(identity: identity, id: "demo", displayName: "Demo")]
        )
        let store = HanlinScriptExtensionStore(root: root)
        try store.save(snapshot)
        #expect(try store.load() == snapshot)

        let invocation = HanlinScriptIntentInvocation(identity: identity, continueInForeground: true)
        let commandID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let command = HanlinScriptResumeCommand(
            id: commandID,
            createdAt: Date(timeIntervalSince1970: 13),
            invocation: invocation
        )
        try store.enqueue(command)
        #expect(try store.pendingCommands() == [command])
        try store.acknowledge(command.id)
        #expect(try store.pendingCommands().isEmpty)
    }
}
