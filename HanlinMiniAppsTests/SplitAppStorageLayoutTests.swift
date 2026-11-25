import Foundation
import HanlinPlatformContracts
import HanlinProductSplit
import HanlinScriptExtensions
import XCTest
@testable import HanlinMiniApps

@MainActor
final class SplitAppStorageLayoutTests: XCTestCase {
    func testTrustedBundleAndUnavailableContainer() throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let ai = try root("com.itorah.chavrusachat", group)
        let mini = try root(SplitAppStorageLayout.miniAppsBundleIdentifier, group)
        XCTAssertEqual(ai, group.appending(path: "ScriptingExtensions", directoryHint: .isDirectory))
        XCTAssertEqual(mini, group.appending(path: "HanlinMiniApps/v1/ScriptingExtensions", directoryHint: .isDirectory))
        XCTAssertThrowsError(try root("com.itorah.hanlinminiapps.attacker", group))
        XCTAssertThrowsError(try root(nil, group))
        XCTAssertThrowsError(try root(SplitAppStorageLayout.miniAppsBundleIdentifier, nil))
    }

    func testRejectsNamespaceSymlinksDanglingLinksAndNonDirectories() throws {
        for path in ["HanlinMiniApps", "HanlinMiniApps/v1", "HanlinMiniApps/v1/ScriptingExtensions"] {
            for kind in ["link", "dangling", "file"] {
                let group = try fixture()
                defer { try? FileManager.default.removeItem(at: group) }
                let candidate = group.appending(path: path)
                try FileManager.default.createDirectory(at: candidate.deletingLastPathComponent(), withIntermediateDirectories: true)
                let ai = try root("com.itorah.chavrusachat", group)
                try FileManager.default.createDirectory(at: ai, withIntermediateDirectories: true)
                if kind == "file" {
                    try Data("alias-file-fixture".utf8).write(to: candidate)
                } else {
                    let target = kind == "link" ? ai : group.appending(path: "absent")
                    try FileManager.default.createSymbolicLink(at: candidate, withDestinationURL: target)
                }
                XCTAssertThrowsError(try root(SplitAppStorageLayout.miniAppsBundleIdentifier, group), "\(path): \(kind)")
            }
        }
    }

    func testPlatformRestoreAndEmptyPublicationPreserveAIBytes() async throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let ai = HanlinScriptExtensionStore(root: try root("com.itorah.chavrusachat", group))
        let aiCommand = try seed(ai)
        let original = try bytes(ai.root)
        let mini = HanlinScriptExtensionStore(root: try root(SplitAppStorageLayout.miniAppsBundleIdentifier, group))
        let platform = HanlinScriptingPlatform(rootOverride: group.appending(path: "private-mini"), initialization: .init(registerExpoDefines: {}, makeExtensionStore: { mini }, enqueuePublication: { $0() }))
        XCTAssertNil(platform.bootstrapError)
        await platform.restore()
        XCTAssertNil(platform.bootstrapError)
        XCTAssertTrue(platform.pendingResumeCommands.isEmpty)
        // An empty installed-package store still publishes the original
        // compiled Swift Parity intent. Assert its exact identity, while the
        // foreign AI fixture and its queued command must remain isolated.
        let snapshot = try XCTUnwrap(try mini.load())
        XCTAssertEqual(snapshot.intentEntities.map(\.id), ["ReadSwiftParityState"])
        XCTAssertEqual(snapshot.intentEntities.map { $0.identity.installedPackageID.rawValue },
                       ["compiled.hanlin.demo.swift-parity"])
        XCTAssertEqual(snapshot.intentEntities.map { $0.identity.packageID.rawValue },
                       ["hanlin.demo.swift-parity"])
        XCTAssertEqual(snapshot.intentEntities.map { $0.identity.generation }, [0])
        XCTAssertTrue(try mini.pendingCommands().isEmpty)
        XCTAssertEqual(try ai.pendingCommands().map(\.id), [aiCommand.id])
        XCTAssertEqual(try bytes(ai.root), original)
    }

    func testOwnSnapshotQueueAndDiagnosticsPersistIndependently() async throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let ai = HanlinScriptExtensionStore(root: try root("com.itorah.chavrusachat", group))
        _ = try seed(ai)
        let original = try bytes(ai.root)
        let miniRoot = try root(SplitAppStorageLayout.miniAppsBundleIdentifier, group)
        let mini = HanlinScriptExtensionStore(root: miniRoot)
        let miniCommand = try seed(mini)
        let reopened = HanlinScriptExtensionStore(root: try root(SplitAppStorageLayout.miniAppsBundleIdentifier, group))
        XCTAssertEqual(try reopened.pendingCommands().map(\.id), [miniCommand.id])
        XCTAssertEqual(try reopened.load()?.intentEntities.count, 1)
        let receipt = try await HanlinInvocationExecutor(store: reopened).execute(miniCommand.id) { _ in
            .string("miniapps-only")
        }
        XCTAssertEqual(receipt?.status, .succeeded)
        XCTAssertEqual(receipt?.value, .string("miniapps-only"))
        XCTAssertTrue(try reopened.pendingCommands().isEmpty)
        _ = reopened.generateConsistencyReport()
        XCTAssertEqual(try bytes(ai.root), original)
    }

    func testUnavailableNamespaceCannotConsumeOrWriteAIState() async throws {
        let group = try fixture()
        defer { try? FileManager.default.removeItem(at: group) }
        let ai = HanlinScriptExtensionStore(root: try root("com.itorah.chavrusachat", group))
        let command = try seed(ai)
        let original = try bytes(ai.root)
        let storage = NotificationStorageAvailability()
        let platform = HanlinScriptingPlatform(rootOverride: group.appending(path: "private-mini"), initialization: .init(registerExpoDefines: {}, makeExtensionStore: {
            let unavailable = try self.root(SplitAppStorageLayout.miniAppsBundleIdentifier, storage.available ? group : nil)
            return HanlinScriptExtensionStore(root: unavailable)
        }, enqueuePublication: { $0() }))
        await platform.restore()
        XCTAssertTrue(platform.pendingResumeCommands.isEmpty)
        XCTAssertThrowsError(try platform.submitResumeCommand(command))
        XCTAssertEqual(try bytes(ai.root), original)

        // A cold notification response can arrive before App Group access.
        // Retain it without relying on the OS to keep a tapped notification.
        let now = Date.now
        let event = try HanlinNotificationEvent(id: UUID(), createdAt: now, expiresAt: now.addingTimeInterval(300),
            appID: .init(validating: "notification.demo"),
            identity: .init(installedPackageID: .init(validating: "installed.notification.demo"),
                            packageID: .init(validating: "notification.demo"), generation: 1, entrypointID: "notify"),
            actionID: .init(validating: "receiveNotification"), parameters: .string("retained-original"))
        try platform.receiveNotificationEvent(event)
        XCTAssertNil(try platform.resumeReceipt(event.id))
        let conflicting = try HanlinNotificationEvent(id: event.id, createdAt: event.createdAt, expiresAt: event.expiresAt,
            appID: event.appID, identity: event.identity, actionID: event.actionID, parameters: .string("must-not-replace"))
        XCTAssertThrowsError(try platform.receiveNotificationEvent(conflicting)) { error in
            XCTAssertEqual(error as? HanlinInvocationQueueError, .duplicateIdentity)
        }

        storage.available = true
        await platform.restore()
        let mini = HanlinScriptExtensionStore(root: try root(SplitAppStorageLayout.miniAppsBundleIdentifier, group))
        let persisted = try XCTUnwrap(try mini.command(for: event.id))
        XCTAssertEqual(persisted.id, event.id)
        XCTAssertEqual(persisted.invocation.parameters, .string("retained-original"))
        XCTAssertEqual(persisted.invocation.delivery?.source, .notification)
        XCTAssertNotNil(try mini.receipt(for: event.id))
        XCTAssertNil(try ai.receipt(for: event.id))
        XCTAssertEqual(try bytes(ai.root), original)
    }

    @MainActor
    private final class NotificationStorageAvailability {
        var available = false
    }

    private func root(_ bundle: String?, _ group: URL?) throws -> URL {
        try SplitAppStorageLayout.extensionStoreRoot(trustedBundleIdentifier: bundle, appGroupContainer: group)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "split-storage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root.resolvingSymlinksInPath().standardizedFileURL
    }

    private func seed(_ store: HanlinScriptExtensionStore) throws -> HanlinScriptResumeCommand {
        let identity = HanlinScriptExtensionIdentity(installedPackageID: try .init(validating: "installed.fixture"),
            packageID: try .init(validating: "fixture.package"), generation: 1, entrypointID: "intents.main")
        try store.save(.init(schemaVersion: 2, generatedAt: .now,
            intentEntities: [.init(identity: identity, id: "fixture", displayName: "Fixture")]))
        let command = HanlinScriptResumeCommand(id: UUID(), createdAt: .now,
            invocation: .init(identity: identity, continueInForeground: true))
        try store.enqueue(command)
        try Data("synthetic-config-retention-fixture".utf8).write(to: store.root.appending(path: "compact-agent-config.json"))
        return command
    }

    private func bytes(_ root: URL) throws -> [String: Data] {
        let items = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let file as URL in items where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[String(file.path.dropFirst(root.path.count))] = try Data(contentsOf: file)
        }
        return result
    }
}
