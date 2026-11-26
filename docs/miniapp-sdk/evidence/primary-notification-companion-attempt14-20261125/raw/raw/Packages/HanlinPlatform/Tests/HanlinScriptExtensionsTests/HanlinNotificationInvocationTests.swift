import Foundation
import HanlinExtensionContracts
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptExtensions
import HanlinScriptStore
import Testing

@Suite("Notification ingress on the canonical durable queue")
struct HanlinNotificationInvocationTests {
    @Test(arguments: [HanlinRuntimeProfile.hanlinExpo, .hanlinNativeScript])
    func typedEventExecutesOnceAndKeepsItsActualResultAfterReopen(_ runtime: HanlinRuntimeProfile) async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        let package = try package(runtime: runtime)
        let event = try event(parameters: .object([
            "text": .string("שלום🙂"), "url": .string("https://example.test/source"),
            "ordered": .array([.integer(3), .bool(true), .null])
        ]))
        let decoded = try #require(try HanlinNotificationEvent.decode(userInfo: event.userInfo()))
        #expect(decoded == event)
        try publish(event, in: store)
        #expect(try HanlinNotificationInvocation.enqueue(decoded, in: store).status == .queued)
        let reopened = HanlinScriptExtensionStore(root: root)
        #expect(try HanlinNotificationInvocation.enqueue(decoded, in: reopened).attempt == 0)
        let result = try await HanlinInvocationExecutor(store: reopened).execute(event.id) { command in
            try HanlinNotificationInvocation.validateTarget(command, packages: [package], hostIsActive: true)
            #expect(command.invocation.delivery?.source == .notification)
            #expect(command.invocation.delivery?.userGesturePresent == false)
            #expect(command.invocation.delivery?.canPresentUI == false)
            return .object(["handled": command.invocation.parameters])
        }
        let expected = try HanlinValue(jsonValue: event.parameters)
        #expect(result?.status == .succeeded)
        #expect(result?.value == .object(["handled": expected]))
        #expect(try HanlinNotificationInvocation.enqueue(decoded, in: reopened) == result)
        let replay = try await HanlinInvocationExecutor(store: reopened).execute(event.id) { _ in
            Issue.record("The same delivered event/tap executed twice")
            return .null
        }
        #expect(replay == result)
        let changed = try HanlinNotificationEvent(id: event.id, createdAt: event.createdAt, expiresAt: event.expiresAt,
            appID: event.appID, identity: event.identity, actionID: event.actionID, parameters: .string("changed"))
        #expect(throws: HanlinInvocationQueueError.duplicateIdentity) {
            try HanlinNotificationInvocation.enqueue(changed, in: reopened)
        }
        #expect(try reopened.receipt(for: event.id) == result)
    }

    @Test func foregroundAdmissionLeavesUnstartedWorkQueuedWithoutConsumingAnAttempt() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), event = try event()
        let package = try package()
        try publish(event, in: store)
        try HanlinNotificationInvocation.enqueue(event, in: store)
        let executor = HanlinInvocationExecutor(store: store)
        let waiting = try await executor.execute(event.id) { command in
            try HanlinNotificationInvocation.validateTarget(command, packages: [package], hostIsActive: false)
            Issue.record("An inactive Host started the package action")
            return .null
        }
        #expect(waiting?.status == .queued && waiting?.attempt == 0)
        #expect(waiting?.leaseID == nil)
        let result = try await executor.execute(event.id) { command in
            try HanlinNotificationInvocation.validateTarget(command, packages: [package], hostIsActive: true)
            return .string("foreground-result")
        }
        #expect(result?.status == .succeeded && result?.attempt == 1)
        #expect(result?.value == .string("foreground-result"))
    }

    @Test func changedInstallationsAndUndeclaredTargetsProduceRealFailureReceipts() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        let executor = HanlinInvocationExecutor(store: store)
        let cases = ["removed", "disabled", "generation", "app", "action", "entrypoint", "runtime", "symbol", "handler"]
        for scenario in cases {
            let package = try package(
                runtime: scenario == "runtime" ? .scriptingJSC : .hanlinExpo,
                enabled: scenario != "disabled", generation: scenario == "generation" ? 2 : 1,
                symbol: scenario == "symbol" ? "otherAction" : "receiveNotification",
                handler: scenario == "handler" ? "source/other.js" : nil,
                action: scenario == "action" ? "removedAction" : "receiveNotification",
                intentKind: scenario == "entrypoint" ? .app : .appIntent)
            let event = try event(app: scenario == "app" ? "another.app" : "notification.demo")
            try publish(event, in: store)
            try HanlinNotificationInvocation.enqueue(event, in: store)
            let packages = scenario == "removed" ? [] : [package]
            let result = try await executor.execute(event.id) { command in
                try HanlinNotificationInvocation.validateTarget(command, packages: packages, hostIsActive: true)
                Issue.record("Invalid notification target started an action: \(scenario)")
                return .null
            }
            let expectedFailure: HanlinInvocationReceipt.Failure
            switch scenario {
            case "removed": expectedFailure = .invalidTarget
            case "disabled": expectedFailure = .disabledPackage
            case "generation": expectedFailure = .staleGeneration
            default: expectedFailure = .unsupportedEntrypoint
            }
            #expect(result?.failure == expectedFailure, "Scenario: \(scenario)")
            #expect(result?.status == (["removed", "disabled", "generation"].contains(scenario) ? .stale : .failed))
            #expect(result?.value == nil)
        }
    }

    @Test func malformedTaggedEventsAndUnknownVersionsDoNotBecomeCommands() throws {
        #expect(try HanlinNotificationEvent.decode(userInfo: ["message": "ordinary notification"]) == nil)
        let event = try event()
        let original = try #require(try event.userInfo()[HanlinNotificationEvent.userInfoKey] as? [String: Any])
        for field in ["schemaVersion", "unknownField", "actionID", "identity", "parameters"] {
            var object = original
            switch field {
            case "schemaVersion": object[field] = 2
            case "unknownField": object[field] = "not part of the contract"
            case "actionID": object[field] = "bad/action"
            case "identity": object.removeValue(forKey: field)
            default: object[field] = ["invalid": Double.infinity]
            }
            #expect(throws: (any Error).self) {
                _ = try HanlinNotificationEvent.decode(userInfo: [HanlinNotificationEvent.userInfoKey: object])
            }
        }
        #expect(throws: HanlinInvocationQueueError.invalidEnvelope) {
            _ = try HanlinNotificationEvent.decode(userInfo: [HanlinNotificationEvent.userInfoKey: "not an object"])
        }
    }

    @Test func cancellationExpiryAndActionErrorsRemainDistinct() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        let expired = try event(createdAt: .now.addingTimeInterval(-120), expiresAt: .now.addingTimeInterval(-60))
        let cancelled = try event()
        for event in [expired, cancelled] {
            try publish(event, in: store)
            try HanlinNotificationInvocation.enqueue(event, in: store)
        }
        _ = try store.requestCancellation(cancelled.id)
        let executor = HanlinInvocationExecutor(store: store)
        for event in [expired, cancelled] {
            let result = try await executor.execute(event.id) { _ in
                Issue.record("Expired or cancelled notification executed an action")
                return .null
            }
            #expect(result?.status == (event.id == expired.id ? .expired : .cancelled))
            #expect(result?.attempt == 0)
        }
        let failed = try event(), package = try package()
        try publish(failed, in: store)
        try HanlinNotificationInvocation.enqueue(failed, in: store)
        let result = try await executor.execute(failed.id) { command in
            try HanlinNotificationInvocation.validateTarget(command, packages: [package], hostIsActive: true)
            throw TestActionFailure()
        }
        #expect(result?.status == .failed && result?.failure == .actionFailed)
        #expect(result?.value == nil)
    }

    @Test func identicalEventIDsStayInsideTheirProductNamespace() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let event = try event()
        let ai = HanlinScriptExtensionStore(root:
            try HanlinExtensionHostConfiguration.hanlin.storageContainer(in: root).appending(path: "ScriptingExtensions"))
        let mini = HanlinScriptExtensionStore(root:
            try HanlinExtensionHostConfiguration.miniapps.storageContainer(in: root, createIfNeeded: true).appending(path: "ScriptingExtensions"))
        try publish(event, in: mini)
        try publish(event, in: ai)
        try HanlinNotificationInvocation.enqueue(event, in: mini)
        #expect(try ai.receipt(for: event.id) == nil)
        #expect(try mini.receipt(for: event.id)?.status == .queued)
        try HanlinNotificationInvocation.enqueue(event, in: ai)
        _ = try mini.requestCancellation(event.id)
        #expect(try mini.receipt(for: event.id)?.status == .cancelled)
        #expect(try ai.receipt(for: event.id)?.status == .queued)
    }

    @Test func missingCatalogStillDurablyRetainsTheEventForLiveHostValidation() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), event = try event()
        #expect(try store.load() == nil)
        #expect(try HanlinNotificationInvocation.enqueue(event, in: store).status == .queued)
        let reopened = HanlinScriptExtensionStore(root: root)
        let package = try package()
        let result = try await HanlinInvocationExecutor(store: reopened).execute(event.id) { command in
            try HanlinNotificationInvocation.validateTarget(command, packages: [package], hostIsActive: true)
            return .string("restored-current-action")
        }
        #expect(result?.value == .string("restored-current-action"))
        #expect(result?.status == .succeeded && result?.attempt == 1)
    }

    @Test func cachedCatalogCannotOverrideLiveInstallationOrItsFailureReceipt() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        let current = try event(generation: 2)
        let older = HanlinScriptExtensionIdentity(installedPackageID: current.identity.installedPackageID,
            packageID: current.identity.packageID, generation: 1, entrypointID: current.identity.entrypointID)
        try store.save(.init(generatedAt: .now, intentEntities: [
            .init(identity: older, id: "previousAction", displayName: "Older published action")
        ]))
        #expect(try HanlinNotificationInvocation.enqueue(current, in: store).status == .queued)
        let live = try package(generation: 2)
        let result = try await HanlinInvocationExecutor(store: store).execute(current.id) { command in
            try HanlinNotificationInvocation.validateTarget(command, packages: [live], hostIsActive: true)
            return .string("new-installed-generation")
        }
        #expect(result?.status == .succeeded && result?.value == .string("new-installed-generation"))

        // The inverse race cannot grant authority: a cached matching target
        // still receives a real stale receipt after the live installation moves.
        let stale = try event(generation: 2)
        try publish(stale, in: store)
        #expect(try HanlinNotificationInvocation.enqueue(stale, in: store).status == .queued)
        let upgraded = try package(generation: 3)
        let rejected = try await HanlinInvocationExecutor(store: store).execute(stale.id) { command in
            try HanlinNotificationInvocation.validateTarget(command, packages: [upgraded], hostIsActive: true)
            Issue.record("A cached catalog authorized an old installed generation")
            return .null
        }
        #expect(rejected?.status == .stale && rejected?.failure == .staleGeneration)
        #expect(rejected?.value == nil)
        #expect(try store.receipt(for: stale.id) == rejected)
    }

    private func publish(_ event: HanlinNotificationEvent, in store: HanlinScriptExtensionStore) throws {
        try store.save(.init(generatedAt: .now, intentEntities: [
            .init(identity: event.identity, id: event.actionID.rawValue, displayName: "Declared installed action")
        ]))
    }

    private struct TestActionFailure: Error {}

    private func event(app: String = "notification.demo", action: String = "receiveNotification",
                       entrypoint: String = "notify", generation: UInt64 = 1, parameters: HanlinJSONValue = .null,
                       createdAt: Date = .now, expiresAt: Date? = nil) throws -> HanlinNotificationEvent {
        try .init(id: UUID(), createdAt: createdAt, expiresAt: expiresAt ?? createdAt.addingTimeInterval(300),
                  appID: .init(validating: app),
                  identity: .init(installedPackageID: .init(validating: "installed.notification.demo"),
                                  packageID: .init(validating: "notification.demo"),
                                  generation: generation, entrypointID: entrypoint),
                  actionID: .init(validating: action), parameters: parameters)
    }

    private func package(runtime: HanlinRuntimeProfile = .hanlinExpo, enabled: Bool = true,
                         generation: UInt64 = 1, symbol: String = "receiveNotification",
                         handler: String? = nil, action: String = "receiveNotification",
                         intentKind: HanlinPackageEntrypointKind = .appIntent) throws -> HanlinStoredPackageSnapshot {
        let source = runtime == .hanlinExpo ? "source/bundle.js" : "nativescript/app/bundle.mjs"
        let capability = try HanlinCapabilityID(validating: "inter-app.share")
        let record = HanlinInstalledPackageRecord(schemaVersion: 1,
            installedPackageID: try .init(validating: "installed.notification.demo"),
            packageID: try .init(validating: "notification.demo"), version: try .init(validating: "1.0.0"),
            sourceDigest: String(repeating: "a", count: 64), artifactDigest: String(repeating: "b", count: 64),
            activeGeneration: generation, installedAt: .now, updatedAt: .now)
        let manifest = HanlinScriptingManifest(name: "Notification delivery", version: "1.0.0",
            entry: source, runInApp: true, unknownFields: [
                "hanlinRuntime": .string(runtime.rawValue),
                "actions": .array([.object([
                    "id": .string(action), "handler": .string(handler ?? source),
                    "capability": .string(capability.rawValue)
                ])])
            ])
        return .init(record: record, entrypoints: [
            .init(id: "app", kind: .app, sourcePath: source, supportedContexts: [.mainApplication],
                  runtimePolicyID: "foreground-app-v1", runtimeProfile: runtime, compatibility: .supported),
            .init(id: "notify", kind: intentKind, sourcePath: source, exportedSymbol: symbol,
                  supportedContexts: [.mainApplication, .appIntent],
                  runtimePolicyID: "prepared-foreground-action-v1", runtimeProfile: runtime, compatibility: .supported)
        ], enabled: enabled, availableGenerations: [generation], grantedCapabilities: [capability], manifest: manifest)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "notification-delivery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
