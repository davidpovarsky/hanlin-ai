import Foundation
import HanlinPlatformContracts
@testable import HanlinScriptExtensions
import Testing

struct HanlinMiniAppStorageCapacityTests {
    @Test func largeArtifactsResourcesAndSnapshotsRetainIntegrity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HanlinMiniAppCapacity-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        let identity = HanlinScriptExtensionIdentity(
            installedPackageID: try .init(validating: "installed.capacity"),
            packageID: try .init(validating: "package.capacity"),
            generation: 1, entrypointID: "widget")
        let artifactBytes = Data(repeating: 0x41, count: 3 * 1_024 * 1_024 + 1_024)
        let artifact = try store.storeArtifact(data: artifactBytes,
            installedPackageID: identity.installedPackageID, generation: identity.generation)
        #expect(try store.loadVerifiedArtifact(ref: artifact.ref, sha256: artifact.sha256,
            installedPackageID: identity.installedPackageID, generation: identity.generation) == artifactBytes)

        let resources = Dictionary(uniqueKeysWithValues: (0..<129).map {
            ("assets/item-\($0).bin", Data([UInt8($0)]))
        })
        let materialized = try store.materializeResources(resources, identity: identity)
        #expect(materialized.count == resources.count)
        for (name, expected) in resources {
            let location = try #require(materialized[name])
            #expect(try Data(contentsOf: location) == expected)
        }

        let document = String(repeating: "x", count: 4 * 1_024 * 1_024 + 1_024)
        let snapshot = HanlinScriptExtensionSnapshot(schemaVersion: 2, generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            widgetInstances: [.init(identity: identity, engine: .expo, displayName: "Capacity")],
            widgetStates: [.init(identity: identity, engine: .expo, artifactSHA256: artifact.sha256,
                revision: 1, values: ["document": .string(document)])])
        try store.save(snapshot)
        #expect(try HanlinScriptExtensionStore(root: root).load() == snapshot)

        // The same active ingress stores large/deep action data and more than
        // 128 pending commands; the existing read limit remains a batch size.
        let nestedJSON = String(repeating: "[", count: 65) + "true" + String(repeating: "]", count: 65)
        let parametersJSON = "{\"document\":\"" + document + "\",\"nested\":" + nestedJSON + "}"
        let parameters = try HanlinInvokeScriptActionIntent.decodeParameters(parametersJSON)
        var nested: HanlinValue = .bool(true)
        for _ in 0..<65 { nested = .array([nested]) }
        #expect(parameters == .object(["document": .string(document), "nested": nested]))
        #expect(throws: (any Error).self) { try HanlinInvokeScriptActionIntent.decodeParameters("[") }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = HanlinScriptResumeCommand(createdAt: now,
            invocation: .init(identity: identity, entityID: "action.capacity", parameters: parameters))
        try store.enqueue(first)
        var commandIDs = Set([first.id])
        for ordinal in 1..<129 {
            let next = HanlinScriptResumeCommand(createdAt: now,
                invocation: .init(identity: identity, entityID: "action.capacity", parameters: .integer(Int64(ordinal))))
            try store.enqueue(next)
            commandIDs.insert(next.id)
        }
        #expect(try store.pendingCommands().count == 64)
        let scan = try store.scanPendingCommands(limit: 129)
        #expect(scan.rejections.isEmpty && Set(scan.commands.map(\.id)) == commandIDs)
        let claim = try #require(try store.claim(first.id, now: now))
        try store.complete(claim, status: .succeeded, value: parameters, now: now)
        let reopened = HanlinScriptExtensionStore(root: root)
        #expect(try reopened.command(for: first.id)?.invocation.parameters == parameters)
        #expect(try reopened.receipt(for: first.id)?.value == parameters)
        #expect(try reopened.scanPendingCommands(limit: 129).commands.count == 128)

        #expect(throws: HanlinScriptExtensionStoreError.invalidArtifactReference) {
            try store.materializeResources(["../outside.bin": Data([1])], identity: identity)
        }
        #expect(throws: HanlinScriptExtensionStoreError.invalidArtifactReference) {
            try store.loadVerifiedArtifact(ref: artifact.ref, sha256: artifact.sha256,
                installedPackageID: identity.installedPackageID, generation: identity.generation + 1)
        }

        var changed = artifactBytes
        changed[0] = 0x42
        try changed.write(to: root.appendingPathComponent(artifact.ref), options: .atomic)
        #expect(throws: HanlinScriptExtensionStoreError.integrityMismatch) {
            try HanlinScriptExtensionStore(root: root).loadVerifiedArtifact(
                ref: artifact.ref, sha256: artifact.sha256,
                installedPackageID: identity.installedPackageID, generation: identity.generation)
        }
    }
}
