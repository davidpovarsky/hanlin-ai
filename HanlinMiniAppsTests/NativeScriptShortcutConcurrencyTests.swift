import CryptoKit
import Foundation
import HanlinMiniAppCore
import HanlinNativeScriptCoreSupport
@testable import HanlinNativeScriptRuntime
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptExtensions
import HanlinScriptStore
import UIKit
import XCTest
@testable import HanlinMiniApps

/// These tests execute installed prepared modules through the real durable
/// Shortcuts dispatcher, original NativeScript VM and provider-bound JS callbacks.
/// Run in the app test host, with its freshly generated original runtime resources.
@MainActor
final class NativeScriptShortcutConcurrencyTests: XCTestCase {
    func testOriginalWindowSurvivesReverseShortcutsCancellationDeadlineAndStaleGeneration() async throws {
        XCTAssertNil(HanlinNativeScriptSession.activeSessionIdentifier)
        HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let observations = Observations()
        let foreground = fixture.platform(observations: observations, allowsPresentation: true)
        await foreground.restore()
        XCTAssertNil(foreground.bootstrapError)
        await foreground.launch(fixture.first.installedID)
        let controller = try XCTUnwrap(foreground.activeNativeScriptController, "\(foreground.activity)")
        let surface = try attach(controller)
        defer {
            surface.window.isHidden = true
            surface.window.rootViewController = nil
            foreground.dismissActiveApplication()
            surface.previousKey?.makeKey()
        }
        let ownerID = try XCTUnwrap(HanlinNativeScriptSession.activeSessionIdentifier)
        XCTAssertEqual(HanlinNativeScriptWindowSession.activeRuntimeSessionIdentifier, ownerID)
        XCTAssertEqual(HanlinNativeScriptWindowFactoryRegistry.openWindowCount(), 1)

        let packages = [fixture.first, fixture.first, fixture.second]
        let nonces = (0..<3).map { "reverse-\($0)-\(UUID().uuidString)" }
        let platforms = packages.map { _ in fixture.platform(observations: observations) }
        let commands = try zip(packages, nonces).map { try fixture.command($0.0, nonce: $0.1) }
        var returned: [String: Probe] = [:]
        try await withThrowingTaskGroup(of: Completed.self, returning: Void.self) { group in
            for index in commands.indices {
                let platform = platforms[index], command = commands[index], nonce = nonces[index]
                group.addTask { @MainActor in
                    let value = try await platform.executeShortcutCommand(command)
                    return Completed(nonce: nonce, value: value)
                }
            }
            try await observations.wait(for: Set(nonces))
            XCTAssertEqual(HanlinNativeScriptWindowFactoryRegistry.openWindowCount(), 4)
            let started = try nonces.map { try XCTUnwrap(observations.started[$0]) }
            XCTAssertEqual(Set(started.map(\.windowID)).count, 3)
            XCTAssertEqual(Set(started.map(\.statePath)).count, 3)
            XCTAssertEqual(Set(started.map(\.sourcePath)).count, 3)
            for (index, probe) in started.enumerated() {
                XCTAssertEqual(probe.packageID, packages[index].appID.rawValue)
                XCTAssertEqual(probe.processID, Int(ProcessInfo.processInfo.processIdentifier))
                XCTAssertEqual(probe.moduleCalls, 1, "Private modules must have a distinct loader identity.")
                XCTAssertEqual(probe.previous, "", "Equal relative paths must not borrow another window's state.")
                XCTAssertFalse(probe.attached, "A headless action must not attach its native root.")
                XCTAssertEqual(probe.executionMode, "headless-action")
                XCTAssertTrue(probe.statePath.contains("/Windows/\(probe.windowID)/"))
            }
            for index in commands.indices.reversed() {
                try release(started[index])
                let next = try await group.next()
                let completed = try XCTUnwrap(next)
                XCTAssertEqual(completed.nonce, nonces[index])
                let probe = try decode(completed.value)
                returned[completed.nonce] = probe
                XCTAssertEqual(probe.stored, nonces[index])
                XCTAssertEqual(probe.windowID, started[index].windowID)
                XCTAssertEqual(try fixture.extensions.receipt(for: commands[index].id)?.status, .succeeded)
                XCTAssertEqual(HanlinNativeScriptWindowFactoryRegistry.openWindowCount(), index + 1)
                XCTAssertEqual(HanlinNativeScriptSession.activeSessionIdentifier, ownerID)
                XCTAssertTrue(foreground.activeNativeScriptController === controller)
                XCTAssertTrue(controller.view.window === surface.window)
            }
        }

        // Duplicate delivery must read the durable receipt, without a new JS window.
        let repeated = try await platforms[0].executeShortcutCommand(commands[0])
        XCTAssertEqual(try decode(repeated).windowID, returned[nonces[0]]?.windowID)
        XCTAssertEqual(observations.started.count, 3)
        XCTAssertEqual(HanlinNativeScriptWindowFactoryRegistry.openWindowCount(), 1)

        // Cancel an actually admitted handler. Its late original JS completion
        // runs while the foreground owner remains alive and cannot change receipt.
        let cancelledNonce = "cancel-\(UUID().uuidString)"
        let cancelledPlatform = fixture.platform(observations: observations)
        let cancelledCommand = try fixture.command(fixture.first, nonce: cancelledNonce)
        try await withThrowingTaskGroup(of: HanlinValue.self) { group in
            group.addTask { try await cancelledPlatform.executeShortcutCommand(cancelledCommand) }
            try await observations.wait(for: [cancelledNonce])
            XCTAssertEqual(HanlinNativeScriptWindowFactoryRegistry.openWindowCount(), 2)
            group.cancelAll()
            do {
                _ = try await group.next()
                XCTFail("A cancelled action returned a result.")
            } catch is CancellationError { }
        }
        let cancelled = try XCTUnwrap(observations.started[cancelledNonce])
        XCTAssertEqual(try fixture.extensions.receipt(for: cancelledCommand.id)?.status, .cancelled)
        XCTAssertEqual(HanlinNativeScriptWindowFactoryRegistry.openWindowCount(), 1)
        try release(cancelled)
        try await waitForFile(cancelled.statePath + "/completed.txt")
        XCTAssertEqual(try fixture.extensions.receipt(for: cancelledCommand.id)?.status, .cancelled)
        XCTAssertEqual(HanlinNativeScriptSession.activeSessionIdentifier, ownerID)

        let expiredNonce = "deadline-\(UUID().uuidString)"
        let expiredPlatform = fixture.platform(observations: observations)
        let expiredCommand = try fixture.command(fixture.second, nonce: expiredNonce, expiresAfter: 3)
        try await withThrowingTaskGroup(of: HanlinValue.self) { group in
            group.addTask { try await expiredPlatform.executeShortcutCommand(expiredCommand) }
            try await observations.wait(for: [expiredNonce])
            do {
                _ = try await group.next()
                XCTFail("A held action ignored its real invocation deadline.")
            } catch let error as HanlinInvocationDispatchError {
                XCTAssertEqual(error.status, .expired)
                XCTAssertEqual(error.failure, .deadlineExceeded)
            }
        }
        XCTAssertEqual(try fixture.extensions.receipt(for: expiredCommand.id)?.status, .expired)
        let expired = try XCTUnwrap(observations.started[expiredNonce])
        try release(expired)
        try await waitForFile(expired.statePath + "/completed.txt")

        // Stale and disabled commands never execute a new factory or action.
        let beforeRejection = observations.started.count
        let previouslyLoaded = fixture.platform(observations: observations)
        await previouslyLoaded.restore()
        _ = try await fixture.store.update(plan: fixture.plan(fixture.second, version: "1.0.1"),
            artifactDirectory: fixture.second.artifact, artifactManifest: fixture.second.manifest)
        // Reproduce the final admission race using two real store actors: this
        // platform already loaded generation1 before the other actor committed2.
        do {
            _ = try await previouslyLoaded.executeHeadlessAction(
                caller: .init(validating: "hanlin.host"), targetAppID: fixture.second.appID,
                action: .init(validating: "probe"), capability: .init(validating: "inter-app.share"),
                payload: .object(["nonce": .string("stale-cached-store"), "mode": .string("immediate")]))
            XCTFail("Cached registry state admitted an obsolete generation.")
        } catch let error as HanlinInvocationDispatchError {
            XCTAssertEqual(error.status, .stale)
            XCTAssertEqual(error.failure, .staleGeneration)
        }
        let stale = try fixture.command(fixture.second, nonce: "stale")
        await assertRejected(stale, using: fixture.platform(observations: observations),
                             extensions: fixture.extensions, failure: .staleGeneration)
        try await fixture.store.setEnabled(false, for: fixture.second.installedID)
        let disabled = try fixture.command(fixture.second, nonce: "disabled", generation: 2)
        await assertRejected(disabled, using: fixture.platform(observations: observations),
                             extensions: fixture.extensions, failure: .disabledPackage)
        XCTAssertEqual(observations.started.count, beforeRejection)
        XCTAssertEqual(HanlinNativeScriptWindowFactoryRegistry.openWindowCount(), 1)

        // The actual foreground module, provider, state and view still work.
        let value = try await foreground.executeHeadlessAction(
            caller: .init(validating: "hanlin.host"), targetAppID: fixture.first.appID,
            action: .init(validating: "probe"), capability: .init(validating: "inter-app.share"),
            payload: .object(["nonce": .string("foreground-after"), "mode": .string("immediate")]))
        let alive = try decode(value)
        XCTAssertTrue(alive.attached)
        XCTAssertEqual(alive.moduleCalls, 1)
        XCTAssertEqual(alive.previous, "")
        XCTAssertEqual(alive.stored, "foreground-after")
        XCTAssertFalse(observations.started.values.filter { $0.executionMode == "headless-action" }
            .contains { $0.windowID == alive.windowID || $0.statePath == alive.statePath })
        XCTAssertEqual(HanlinNativeScriptSession.activeSessionIdentifier, ownerID)
        XCTAssertTrue(controller.view.window === surface.window)
    }

    func testLegacyOwnerRejectsBothFactoryAndLegacyShortcutsWithoutQueuedReplay() async throws {
        XCTAssertNil(HanlinNativeScriptSession.activeSessionIdentifier)
        HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
        let fixture = try await Fixture(legacyForeground: true)
        defer { fixture.remove() }
        let observations = Observations()
        let foreground = fixture.platform(observations: observations, allowsPresentation: true)
        await foreground.restore()
        await foreground.launch(fixture.first.installedID)
        let controller = try XCTUnwrap(foreground.activeNativeScriptController, "\(foreground.activity)")
        let surface = try attach(controller)
        defer {
            surface.window.isHidden = true
            surface.window.rootViewController = nil
            foreground.dismissActiveApplication()
            surface.previousKey?.makeKey()
        }
        let ownerID = try XCTUnwrap(HanlinNativeScriptSession.activeSessionIdentifier)
        XCTAssertNil(HanlinNativeScriptWindowSession.activeRuntimeSessionIdentifier)
        for package in [fixture.first, fixture.second] {
            let command = try fixture.command(package, nonce: UUID().uuidString)
            do {
                _ = try await fixture.platform(observations: observations).executeShortcutCommand(command)
                XCTFail("A legacy owner must not start a second original main VM.")
            } catch let error as HanlinInvocationDispatchError {
                XCTAssertEqual(error.status, .needsForeground)
                XCTAssertEqual(error.failure, .unavailableHost)
            }
            XCTAssertEqual(try fixture.extensions.receipt(for: command.id)?.status, .cancelled)
            XCTAssertEqual(HanlinNativeScriptSession.activeSessionIdentifier, ownerID)
            XCTAssertTrue(foreground.activeNativeScriptController === controller)
            XCTAssertTrue(controller.view.window === surface.window)
        }
        XCTAssertTrue(observations.started.isEmpty)
    }

    func testForegroundShortcutUsesItsOwnedProviderAndReceiptWithoutReplacingTheOwnerHandler() async throws {
        XCTAssertNil(HanlinNativeScriptSession.activeSessionIdentifier)
        HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let observations = Observations()
        let owner = fixture.platform(observations: observations, allowsPresentation: true)
        await owner.restore()
        owner.externalMiniAppOperation = { _, _ in "ORIGINAL_OWNER_HANDLER" }
        let child = fixture.platform(observations: observations, allowsPresentation: true)
        let store = fixture.extensions
        let command = try fixture.command(fixture.first, nonce: "foreground-owned", foreground: true)
        let progress = Progress(totalUnitCount: 3)
        let configureProgress: @MainActor @Sendable () throws -> Void = {
            let reporter = try MiniAppsShortcutProgressReporter(progress: progress, commandID: command.id, store: store)
            observations.shortcutProgressReporter = reporter
            child.externalMiniAppOperation = { operation, payload in
                _ = try reporter.receive(operation, payload: payload)
                return try observations.receive(operation, payload: payload)
            }
        }
        defer {
            observations.shortcutProgressReporter?.close()
            owner.dismissShortcutPresentation(command.id)
            child.dismissActiveApplication()
        }
        let executor = HanlinInvocationExecutor(store: store)
        try await withThrowingTaskGroup(of: HanlinInvocationReceipt.self) { group in
            group.addTask {
                let receipt = try await executor.execute(command) { owned in
                    try await configureProgress()
                    try await owner.admitShortcutPresentation(child, command: owned, store: store)
                    return try await child.executeClaimedShortcutCommand(owned)
                }
                guard let receipt else { throw Failure.invalidResult }
                return receipt
            }
            defer { group.cancelAll() }
            try await observations.wait(for: ["foreground-owned"])
            let probe = try XCTUnwrap(observations.started["foreground-owned"])
            XCTAssertEqual(probe.executionMode, "foreground")
            XCTAssertEqual(owner.shortcutPresentation?.id, command.id)
            XCTAssertTrue(owner.foregroundPresentationPlatform === child)
            XCTAssertNil(owner.activeApplicationID)
            XCTAssertEqual(child.activeApplicationID, fixture.first.installedID)
            let handlerBefore = try await owner.externalMiniAppOperation?("owner.probe", "{}")
            XCTAssertEqual(handlerBefore, "ORIGINAL_OWNER_HANDLER")
            let controller = try XCTUnwrap(child.activeNativeScriptController)
            let surface = try attach(controller)
            defer {
                surface.window.isHidden = true
                surface.window.rootViewController = nil
                surface.previousKey?.makeKey()
            }
            XCTAssertTrue(controller.view.window === surface.window)
            let running = try XCTUnwrap(store.receipt(for: command.id))
            let drain = try await HanlinInvocationExecutor(store: store).execute(command.id) { _ in
                XCTFail("The foreground drain stole a live Shortcut.")
                return .null
            }
            XCTAssertEqual(drain?.leaseID, running.leaseID)
            XCTAssertEqual(drain?.status, .running)
            try release(probe)
            let next = try await group.next()
            let receipt = try XCTUnwrap(next)
            XCTAssertEqual(receipt.status, .succeeded)
            XCTAssertEqual(try decode(try XCTUnwrap(receipt.value)).stored, "foreground-owned")
            owner.settleShortcutPresentation(receipt)
            XCTAssertTrue(owner.shortcutPresentation?.completed == true)
            owner.dismissShortcutPresentation(UUID())
            XCTAssertEqual(owner.shortcutPresentation?.id, command.id)
            let reporter = try XCTUnwrap(observations.shortcutProgressReporter)
            reporter.close()
            let oldProgress = progress.completedUnitCount
            XCTAssertThrowsError(try reporter.receive("miniapps.shortcutProgress",
                payload: #"{"completedUnitCount":1,"totalUnitCount":1}"#))
            XCTAssertEqual(progress.completedUnitCount, oldProgress)
            owner.dismissShortcutPresentation(command.id)
            XCTAssertNil(owner.shortcutPresentation)
            XCTAssertEqual(try store.receipt(for: command.id), receipt)
            let handlerAfter = try await owner.externalMiniAppOperation?("owner.probe", "{}")
            XCTAssertEqual(handlerAfter, "ORIGINAL_OWNER_HANDLER")
        }
    }

    func testClosingRunningForegroundDrainsBeforeReleasingItsOwnedSession() async throws {
        XCTAssertNil(HanlinNativeScriptSession.activeSessionIdentifier)
        HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let observations = Observations()
        let owner = fixture.platform(observations: observations, allowsPresentation: true)
        let child = fixture.platform(observations: observations, allowsPresentation: true)
        let store = fixture.extensions
        let command = try fixture.command(fixture.first, nonce: "close-running", foreground: true)
        defer {
            owner.dismissShortcutPresentation(command.id, executionFinished: true)
            child.dismissActiveApplication()
        }
        try await withThrowingTaskGroup(of: HanlinInvocationReceipt.self) { group in
            group.addTask {
                let receipt = try await HanlinInvocationExecutor(store: store).execute(command) { owned in
                    try await owner.admitShortcutPresentation(child, command: owned, store: store)
                    return try await child.executeClaimedShortcutCommand(owned)
                }
                guard let receipt else { throw Failure.invalidResult }
                return receipt
            }
            defer { group.cancelAll() }
            try await observations.wait(for: ["close-running"])
            let controller = try XCTUnwrap(child.activeNativeScriptController)
            let surface = try attach(controller)
            defer {
                surface.window.isHidden = true
                surface.window.rootViewController = nil
                surface.previousKey?.makeKey()
            }
            XCTAssertTrue(owner.isForegroundPresentationVisible)
            XCTAssertEqual(HanlinNativeScriptWindowFactoryRegistry.openWindowCount(), 1)
            owner.dismissShortcutPresentation(command.id)
            let running = try XCTUnwrap(store.receipt(for: command.id))
            XCTAssertEqual(running.status, .running)
            XCTAssertTrue(running.cancellationRequested)
            XCTAssertEqual(owner.shortcutPresentation?.id, command.id)
            XCTAssertTrue(owner.shortcutPresentation?.dismissalRequested == true)
            XCTAssertFalse(owner.isForegroundPresentationVisible)
            XCTAssertTrue(child.activeNativeScriptController === controller)

            let next = try await group.next()
            let receipt = try XCTUnwrap(next)
            XCTAssertEqual(receipt.status, .cancelled)
            owner.settleShortcutPresentation(receipt)
            XCTAssertNil(owner.shortcutPresentation)
            XCTAssertNil(child.activeApplicationID)
            XCTAssertNil(child.activeNativeScriptController)
            XCTAssertNil(HanlinNativeScriptSession.activeSessionIdentifier)
            XCTAssertEqual(HanlinNativeScriptWindowFactoryRegistry.openWindowCount(), 0)
            XCTAssertEqual(try store.receipt(for: command.id), receipt)
        }
    }

    func testOccupiedForegroundRejectsOnlyTheNewShortcutAndPreservesLegacyIntentDrain() async throws {
        XCTAssertNil(HanlinNativeScriptSession.activeSessionIdentifier)
        HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let observations = Observations()
        let owner = fixture.platform(observations: observations, allowsPresentation: true)
        await owner.restore()
        await owner.launch(fixture.first.installedID)
        let controller = try XCTUnwrap(owner.activeNativeScriptController)
        let surface = try attach(controller)
        defer {
            surface.window.isHidden = true
            surface.window.rootViewController = nil
            owner.dismissActiveApplication()
            surface.previousKey?.makeKey()
        }
        let child = fixture.platform(observations: observations, allowsPresentation: true)
        defer { child.dismissActiveApplication() }
        let command = try fixture.command(fixture.second, nonce: "must-not-replace", foreground: true)
        let store = fixture.extensions
        let denied = try await HanlinInvocationExecutor(store: store).execute(command) { owned in
            try await owner.admitShortcutPresentation(child, command: owned, store: store)
            return try await child.executeClaimedShortcutCommand(owned)
        }
        XCTAssertEqual(denied?.status, .needsForeground)
        XCTAssertNil(owner.shortcutPresentation)
        XCTAssertNil(child.activeApplicationID)
        XCTAssertTrue(owner.activeNativeScriptController === controller)
        XCTAssertTrue(controller.view.window === surface.window)
        XCTAssertTrue(observations.started.isEmpty)

        // Both shipped Run Script Action forms retain delivery=nil and their
        // original foreground queue, including the installed action handler.
        let identity = try fixture.command(fixture.first, nonce: "unused").invocation.identity
        let legacy = HanlinScriptResumeCommand(invocation: .init(identity: identity,
            entityID: "probe", parameters: .object(["nonce": .string("legacy-action"), "mode": .string("immediate")]),
            continueInForeground: true))
        try store.enqueue(legacy)
        await owner.resumePendingInvocations()
        let result = try XCTUnwrap(store.receipt(for: legacy.id))
        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(try decode(try XCTUnwrap(result.value)).stored, "legacy-action")
        XCTAssertNil(try store.command(for: legacy.id)?.invocation.delivery)
        XCTAssertEqual(try store.receipt(for: command.id), denied)
        XCTAssertTrue(owner.activeNativeScriptController === controller)
        XCTAssertTrue(controller.view.window === surface.window)
    }

    private func assertRejected(_ command: HanlinScriptResumeCommand, using platform: HanlinScriptingPlatform,
                                extensions: HanlinScriptExtensionStore,
                                failure: HanlinInvocationReceipt.Failure) async {
        do { _ = try await platform.executeShortcutCommand(command); XCTFail("Rejected input ran JS.") }
        catch let error as HanlinInvocationDispatchError {
            XCTAssertEqual(error.status, .stale)
            XCTAssertEqual(error.failure, failure)
        } catch { XCTFail("Unexpected rejection: \(error)") }
        XCTAssertEqual(try? extensions.receipt(for: command.id)?.status, .stale)
    }

    private func attach(_ controller: UIViewController) throws -> (window: UIWindow, previousKey: UIWindow?) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return (window, previous)
    }

    private func decode(_ value: HanlinValue) throws -> Probe {
        guard case let .string(json) = value else { throw Failure.invalidResult }
        return try JSONDecoder().decode(Probe.self, from: Data(json.utf8))
    }

    private func release(_ probe: Probe) throws {
        try Data("release".utf8).write(to: URL(fileURLWithPath: probe.statePath).appending(path: "release.txt"),
                                      options: .atomic)
    }

    private func waitForFile(_ path: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !FileManager.default.fileExists(atPath: path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard FileManager.default.fileExists(atPath: path) else { throw Failure.callbackTimedOut }
    }

    private enum Failure: Error { case invalidResult, callbackTimedOut, unexpectedOperation }
    private struct Completed: Sendable { let nonce: String; let value: HanlinValue }
    private struct Probe: Decodable, Sendable {
        let nonce: String
        let windowID: String
        let packageID: String
        let statePath: String
        let sourcePath: String
        let processID: Int
        let moduleCalls: Int
        let previous: String
        let stored: String
        let attached: Bool
        let executionMode: String
    }

    @MainActor private final class Observations {
        var started: [String: Probe] = [:]
        var shortcutProgressReporter: MiniAppsShortcutProgressReporter?
        func receive(_ operation: String, payload: String) throws -> String {
            guard operation == "miniapps.shortcutProgress" else { throw Failure.unexpectedOperation }
            let progress = try JSONDecoder().decode(HanlinShortcutProgress.self, from: Data(payload.utf8))
            try progress.validate()
            let probe = try JSONDecoder().decode(Probe.self, from: Data((progress.message ?? "").utf8))
            started[probe.nonce] = probe
            return #"{"ok":true}"#
        }
        func wait(for nonces: Set<String>) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !nonces.isSubset(of: Set(started.keys)), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            guard nonces.isSubset(of: Set(started.keys)) else { throw Failure.callbackTimedOut }
        }
    }

    @MainActor private final class Fixture {
        struct Package {
            let appID: HanlinAppID
            let installedID: HanlinInstalledPackageID
            let artifact: URL
            let manifest: HanlinPackageArtifactManifest
        }
        let root: URL
        let store: HanlinAtomicScriptStore
        let extensions: HanlinScriptExtensionStore
        let first: Package
        let second: Package
        private let sourcePath = "nativescript/app/bundle.mjs"

        init(legacyForeground: Bool = false) async throws {
            root = FileManager.default.temporaryDirectory.appending(
                path: "original-shortcuts-\(UUID().uuidString.lowercased())", directoryHint: .isDirectory)
                .resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            store = try HanlinAtomicScriptStore(root: root.appending(path: "Installed", directoryHint: .isDirectory))
            extensions = .init(root: root.appending(path: "Extensions", directoryHint: .isDirectory))
            first = try Self.package(at: root, suffix: "a", legacy: legacyForeground)
            second = try Self.package(at: root, suffix: "b", legacy: false)
            for package in [first, second] {
                _ = try await store.install(plan: plan(package), artifactDirectory: package.artifact,
                                            artifactManifest: package.manifest)
            }
        }

        func platform(observations: Observations, allowsPresentation: Bool = false) -> HanlinScriptingPlatform {
            let extensions = extensions
            let platform = HanlinScriptingPlatform(rootOverride: root,
                initialization: .init(registerExpoDefines: {}, makeExtensionStore: { extensions },
                                      enqueuePublication: { work in work() }),
                actionPresentationAllowed: allowsPresentation, registersForegroundContinuation: false)
            platform.externalMiniAppOperation = { operation, payload in
                try observations.receive(operation, payload: payload)
            }
            return platform
        }

        func command(_ package: Package, nonce: String, generation: UInt64 = 1,
                     expiresAfter: TimeInterval = 30, foreground: Bool = false) throws -> HanlinScriptResumeCommand {
            .init(invocation: .init(identity: .init(installedPackageID: package.installedID,
                packageID: try .init(validating: package.appID.rawValue), generation: generation,
                entrypointID: "probe.intent"), entityID: "probe",
                parameters: .object(["nonce": .string(nonce), "mode": .string("held")]),
                continueInForeground: foreground,
                delivery: .init(appID: package.appID, source: .shortcuts,
                    expiresAt: .now.addingTimeInterval(expiresAfter), userGesturePresent: true, canPresentUI: foreground)))
        }

        func plan(_ package: Package, version: String = "1.0.0") throws -> HanlinInstallPlan {
            let capability = try HanlinCapabilityID(validating: "inter-app.share")
            let request = HanlinCapabilityRequest(capabilityID: capability, required: true,
                                                 purpose: "Original native action ownership regression.")
            return HanlinInstallPlan(installedPackageID: package.installedID,
                packageID: try .init(validating: package.appID.rawValue), version: try .init(validating: version),
                sourceDigest: package.manifest.packageContentDigest,
                entrypoints: [
                    .init(id: "app", kind: .app, sourcePath: sourcePath,
                        supportedContexts: [.mainApplication], runtimePolicyID: "nativescript-v1",
                        runtimeProfile: .hanlinNativeScript, compatibility: .supported),
                    .init(id: "probe.intent", kind: .appIntent, sourcePath: sourcePath, exportedSymbol: "probe",
                        supportedContexts: [.appIntent], requiredCapabilities: [request],
                        runtimePolicyID: "prepared-foreground-action-v1",
                        runtimeProfile: .hanlinNativeScript, compatibility: .supported)
                ], requestedCapabilities: [request], grantedCapabilities: [capability],
                manifest: .init(name: "Original NativeScript Shortcut Probe", version: version,
                    entry: sourcePath, runInApp: true, unknownFields: [
                        "hanlinRuntime": .string("hanlin-nativescript"),
                        "actions": .array([.object(["id": .string("probe"), "handler": .string(sourcePath),
                            "capability": .string("inter-app.share"), "title": .string("Probe")])])
                ]))
        }

        private static func package(at root: URL, suffix: String, legacy: Bool) throws -> Package {
            let appID = try HanlinAppID(validating: "test.shortcut.\(UUID().uuidString.lowercased()).\(suffix)")
            let installedID = try HanlinInstalledPackageID(validating: appID.rawValue)
            let artifact = root.appending(path: "artifact-\(suffix)", directoryHint: .isDirectory)
            let app = artifact.appending(path: "nativescript/app", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            let factoryField = legacy ? "" : #","windowFactory":1"#
            let metadata = """
            {"name":"\(appID.rawValue)","version":"1.0.0","type":"module","main":"bundle.mjs",
             "hanlinRuntime":"hanlin-nativescript",
             "hanlinNativeScript":{"runtimeVersion":"\(HanlinNativeScriptHostVersions.runtimeVersion)","plugins":{}\(factoryField)},
             "dependencies":{"@nativescript/core":"\(HanlinNativeScriptHostVersions.coreVersion)"}}
            """
            let source = legacy ? """
            import {Application, Label} from '@nativescript/core';
            Application.run({create() { const root = new Label(); root.text = 'Legacy owner'; return root; }});
            """ : Self.factorySource
            let bytes = ["package.json": Data(metadata.utf8), "bundle.mjs": Data(source.utf8)]
            var files: [HanlinArtifactFile] = []
            for (name, data) in bytes.sorted(by: { $0.key < $1.key }) {
                try data.write(to: app.appending(path: name))
                files.append(.init(logicalPath: "nativescript/app/" + name, sha256: digest(data),
                                   byteCount: Int64(data.count), context: .app))
            }
            let sourceDigest = digest(Data(source.utf8) + Data(metadata.utf8))
            let manifest = HanlinPackageArtifactManifest(compilerVersion: "prepared-original-native",
                compilerIntegrity: "native-fixture", compilerOptionsHash: digest(Data("original".utf8)),
                baselineID: "original-native-concurrency", baselineDigest: digest(Data("fixture".utf8)),
                hanlinABIVersion: "2", packageContentDigest: sourceDigest,
                cacheFingerprint: sourceDigest, files: files)
            try JSONEncoder().encode(manifest).write(to: artifact.appending(path: "artifact-manifest.json"))
            return .init(appID: appID, installedID: installedID, artifact: artifact, manifest: manifest)
        }

        private static func digest(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
            for package in [first, second] where package.appID.rawValue.hasPrefix("test.shortcut.") {
                try? FileManager.default.removeItem(at: support.appending(path: "Hanlin/MiniApps")
                    .appending(path: package.appID.rawValue))
            }
        }

        private static let factorySource = #"""
        import {File, Label} from '@nativescript/core';
        import {registerWindowFactory} from '@hanlin/window-factory';
        let moduleCalls = 0;
        registerWindowFactory(({id, packageID, services, storage, environment, resourcePath}) => {
          const root = new Label();
          root.text = 'Original factory owner';
          services.registerRequestHandler('probe', 'inter-app.share', async ({caller, parameters}) => {
            const statePath = storage.state;
            const file = statePath + '/same-name.txt';
            const previous = File.exists(file) ? File.fromPath(file).readTextSync() : '';
            File.fromPath(file).writeTextSync(parameters.nonce);
            const probe = {nonce: parameters.nonce, windowID: id, packageID, statePath,
              sourcePath: resourcePath('bundle.mjs'), processID: NSProcessInfo.processInfo.processIdentifier,
              moduleCalls: ++moduleCalls, previous, stored: File.fromPath(file).readTextSync(),
              attached: root.ios.window != null, executionMode: environment.HANLIN_EXECUTION_MODE ?? 'foreground'};
            await services.miniapps.reportShortcutProgress({completedUnitCount: 0, totalUnitCount: 1,
              message: JSON.stringify(probe)});
            if (parameters.mode !== 'immediate') {
              await new Promise(resolve => {
                const timer = setInterval(() => {
                  if (File.exists(statePath + '/release.txt')) {
                    clearInterval(timer);
                    File.fromPath(statePath + '/completed.txt').writeTextSync(parameters.nonce);
                    resolve();
                  }
                }, 10);
              });
            }
            return JSON.stringify({...probe, stored: File.fromPath(file).readTextSync()});
          });
          return root;
        });
        """#
    }
}
