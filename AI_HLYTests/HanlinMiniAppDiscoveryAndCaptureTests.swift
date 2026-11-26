import CryptoKit
import Foundation
import HanlinCameraCaptureUI
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptExtensions
import HanlinScriptStore
import UIKit
import XCTest
@testable import AI_Hanlin

/// Installed-data and durable-transfer tests. These do not substitute for actual
/// Spotlight search/tap, lock-screen launch or physical Camera Control acceptance.
@MainActor
final class HanlinMiniAppDiscoveryAndCaptureTests: XCTestCase {
    func testSystemEntrypointPublicationIsStandaloneMiniAppsOnly() {
        XCTAssertTrue(HanlinMiniAppSystemEntrypoints.supportsProduct(identifier: "com.itorah.hanlinminiapps"))
        for identifier in ["com.itorah.chavrusachat", "com.itorah.hanlinminiapps.widgets", "", "foreign.app"] {
            XCTAssertFalse(HanlinMiniAppSystemEntrypoints.supportsProduct(identifier: identifier), identifier)
        }
    }

    func testInstalledCatalogDoesNotDependOnWidgetInstancesAndReconcilesIdentity() throws {
        let installation = UUID().uuidString.lowercased()
        let expo = try package(installation: installation, runtime: .hanlinExpo, generation: 1, name: "Original title")
        let nativeScript = try package(installation: UUID().uuidString.lowercased(), runtime: .hanlinNativeScript, generation: 1, name: "Native app")
        let first = HanlinMiniAppSystemCatalog.records(packages: [expo, nativeScript], productIdentifier: "com.itorah.chavrusachat", artifactRoot: { _ in nil })
        XCTAssertEqual(first.count, 4)
        XCTAssertEqual(first.filter { $0.entrypoint.kind == .spotlight }.count, 2)
        XCTAssertEqual(first.filter { $0.cameraTarget != nil }.count, 2)
        XCTAssertFalse(expo.hasWidgetEntrypoint)
        let updated = try package(installation: installation, runtime: .hanlinExpo, generation: 2, name: "Updated title")
        let next = HanlinMiniAppSystemCatalog.records(packages: [updated], productIdentifier: "com.itorah.chavrusachat", artifactRoot: { _ in nil })
        let oldSpotlight = try XCTUnwrap(first.first { $0.installedPackageID == expo.record.installedPackageID && $0.entrypoint.kind == .spotlight })
        let newSpotlight = try XCTUnwrap(next.first { $0.entrypoint.kind == .spotlight })
        XCTAssertEqual(oldSpotlight.id, newSpotlight.id)
        XCTAssertEqual(newSpotlight.generation, 2)
        XCTAssertEqual(newSpotlight.title, "Updated title")
        XCTAssertEqual(newSpotlight.keywords, ["texts", "חיפוש"])
        let mini = HanlinMiniAppSystemCatalog.records(packages: [updated], productIdentifier: "com.itorah.hanlinminiapps", artifactRoot: { _ in nil })
        XCTAssertNotEqual(newSpotlight.id, mini.first { $0.entrypoint.kind == .spotlight }?.id)
        let disabled = try package(installation: installation, runtime: .hanlinExpo, generation: 2, name: "Updated title", enabled: false)
        XCTAssertTrue(HanlinMiniAppSystemCatalog.records(packages: [disabled], productIdentifier: "com.itorah.chavrusachat", artifactRoot: { _ in nil }).isEmpty)
        XCTAssertTrue(HanlinMiniAppSystemCatalog.records(packages: [], productIdentifier: "com.itorah.chavrusachat", artifactRoot: { _ in nil }).isEmpty)
        XCTAssertNotEqual(first.first { $0.installedPackageID == expo.record.installedPackageID && $0.cameraTarget != nil }?.cameraTarget,
                          next.first { $0.cameraTarget != nil }?.cameraTarget)
    }

    func testCaptureCatalogRequiresAnActualUnambiguousPreparedAction() throws {
        let absent = try package(installation: UUID().uuidString.lowercased(), runtime: .hanlinExpo,
            generation: 1, name: "Missing action", actionCount: 0)
        let duplicate = try package(installation: UUID().uuidString.lowercased(), runtime: .hanlinExpo,
            generation: 1, name: "Ambiguous action", actionCount: 2)
        for snapshot in [absent, duplicate] {
            let records = HanlinMiniAppSystemCatalog.records(packages: [snapshot], productIdentifier: "com.itorah.chavrusachat", artifactRoot: { _ in nil })
            XCTAssertEqual(records.map(\.entrypoint.kind), [.spotlight]) // Plain app-open exposure remains valid.
        }
        XCTAssertNotEqual(HanlinMiniAppSystemCatalog.identifier(productIdentifier: "a:b", installation: "c", entrypoint: "d"),
                          HanlinMiniAppSystemCatalog.identifier(productIdentifier: "a", installation: "b:c", entrypoint: "d"))
    }

    func testCapturedBytesAreDurableBeforeSessionInvalidationAndRetryKeepsIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString.lowercased(), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "system-session", directoryHint: .isDirectory)
        let target = HanlinCameraCaptureTarget(productIdentifier: "com.itorah.chavrusachat", installedPackageID: UUID().uuidString.lowercased(),
            packageID: "test.camera", generation: 7, entrypointID: "capture", actionID: "consumeCapture")
        let writer = try HanlinCameraSessionFiles(directory: source, productIdentifier: target.productIdentifier,
            source: .lockedCamera, target: target)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3)).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        }
        let bytes = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let firstPhoto = try await writer.saveJPEG(bytes, width: 2, height: 3)
        let reopenedWriter = try HanlinCameraSessionFiles(directory: source, productIdentifier: target.productIdentifier,
            source: .lockedCamera, target: target)
        let retained = await reopenedWriter.currentManifest()
        XCTAssertEqual(retained.photos, [firstPhoto])
        let secondPhoto = try await reopenedWriter.saveJPEG(bytes, width: 2, height: 3)
        let inboxRoot = root.appending(path: "inbox", directoryHint: .isDirectory)
        let inbox = HanlinMiniAppCaptureInbox(root: inboxRoot, productIdentifier: target.productIdentifier)
        let received = try await inbox.receive(directory: source)
        let retried = try await inbox.receive(directory: source)
        XCTAssertEqual(received, retried)
        XCTAssertEqual(received.manifest.photos, [firstPhoto, secondPhoto])
        XCTAssertEqual(received.selectedTarget, target)
        // The system may remove its copy only now. The app's independently opened
        // inbox and owned Documents bytes must still be intact.
        try FileManager.default.removeItem(at: source)
        let reopenedInbox = HanlinMiniAppCaptureInbox(root: inboxRoot, productIdentifier: target.productIdentifier)
        let restored = try await reopenedInbox.read(received.id)
        XCTAssertEqual(restored.invocationID, received.invocationID)
        XCTAssertEqual(restored.invocationCreatedAt, received.invocationCreatedAt)
        let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
        let files = try await reopenedInbox.copyPhotos(for: received.id, documents: documents)
        XCTAssertEqual(files.count, 2)
        for url in files { XCTAssertEqual(try Data(contentsOf: url), bytes) }
        try await reopenedInbox.markSubmitted(received.id, invocationID: received.invocationID)
        let submitted = try await reopenedInbox.read(received.id)
        XCTAssertTrue(submitted.submitted)
        XCTAssertEqual(submitted.invocationID, received.invocationID)
        let altered = inboxRoot.appending(path: received.id.uuidString.lowercased()).appending(path: firstPhoto.filename)
        try Data("changed".utf8).write(to: altered)
        do {
            _ = try await reopenedInbox.copyPhotos(for: received.id, documents: documents)
            XCTFail("Changed captured content must not reach an installed action")
        } catch HanlinCameraCaptureError.changedContent { }
    }

    func testCaptureManifestRejectsForeignProductAndUnownedPath() throws {
        let photo = HanlinCapturedPhoto(id: UUID(), filename: "../outside.jpg", contentType: "public.jpeg", byteCount: 1,
            sha256: String(repeating: "0", count: 64), width: 1, height: 1)
        let manifest = HanlinCameraCaptureManifest(productIdentifier: "com.itorah.chavrusachat", source: .lockedCamera, target: nil, photos: [photo])
        XCTAssertThrowsError(try manifest.validate(productIdentifier: "com.itorah.chavrusachat"))
        XCTAssertThrowsError(try manifest.validate(productIdentifier: "com.itorah.hanlinminiapps"))
    }


    func testSystemEntrypointsReloadAnotherStoreBeforeGenerationAndEnabledAdmission() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "system-entry-admission-" + UUID().uuidString.lowercased(), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let installedID = try HanlinInstalledPackageID(validating: UUID().uuidString.lowercased())
        let artifact = root.appending(path: "artifact", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: true)
        // Rejected input must never reach runtime preparation or this program.
        let bytes = Data("throw new Error('stale system entrypoint reached runtime');".utf8)
        try bytes.write(to: artifact.appending(path: "bundle.js"))
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let artifactManifest = HanlinPackageArtifactManifest(compilerVersion: "system-entry-admission-fixture",
            compilerIntegrity: "fixture", compilerOptionsHash: digest,
            baselineID: "system-entry-admission", baselineDigest: digest, hanlinABIVersion: "2",
            packageContentDigest: digest, cacheFingerprint: digest,
            files: [.init(logicalPath: "bundle.js", sha256: digest, byteCount: Int64(bytes.count), context: .app)])
        try JSONEncoder().encode(artifactManifest).write(to: artifact.appending(path: "artifact-manifest.json"))
        let capability = try HanlinCapabilityID(validating: "inter-app.share")
        let request = HanlinCapabilityRequest(capabilityID: capability, required: true, purpose: "Capture delivery.")
        let entries = try package(installation: installedID.rawValue, runtime: .hanlinExpo,
                                  generation: 1, name: "Admission fixture").entrypoints
        func plan(_ version: String) throws -> HanlinInstallPlan {
            .init(installedPackageID: installedID, packageID: try .init(validating: "test.camera"),
                version: try .init(validating: version), sourceDigest: digest, entrypoints: entries,
                requestedCapabilities: [request], grantedCapabilities: [capability],
                manifest: .init(name: "Admission fixture", version: version, entry: "bundle.js", runInApp: true,
                    unknownFields: ["hanlinRuntime": .string("hanlin-expo"),
                        "actions": .array([.object(["id": .string("consumeCapture"), "handler": .string("bundle.js"),
                                                   "capability": .string("inter-app.share")])])]))
        }
        let writer = try HanlinAtomicScriptStore(root: root.appending(path: "Installed", directoryHint: .isDirectory))
        _ = try await writer.install(plan: plan("1.0.0"), artifactDirectory: artifact, artifactManifest: artifactManifest)
        let extensions = HanlinScriptExtensionStore(root: root.appending(path: "Extensions", directoryHint: .isDirectory))
        // The platform's own real store loads generation1 before a separate
        // writer commits generation2. No test-only snapshot is injected.
        let platform = HanlinScriptingPlatform(rootOverride: root,
            initialization: .init(registerExpoDefines: {}, makeExtensionStore: { extensions },
                                  enqueuePublication: { _ in }))
        XCTAssertNil(platform.bootstrapError)
        _ = try await writer.update(plan: plan("1.0.1"), artifactDirectory: artifact, artifactManifest: artifactManifest)
        for entry in ["spotlight", "capture"] {
            do {
                _ = try await platform.openSystemEntrypoint(installedPackageID: installedID, entrypointID: entry,
                    generation: 1, parameters: .null)
                XCTFail("An obsolete generation reached system-entrypoint execution.")
            } catch HanlinMiniAppSystemEntrypointError.staleGeneration { }
        }
        XCTAssertEqual(platform.installedPackages.first?.record.activeGeneration, 2)
        try await writer.setEnabled(false, for: installedID)
        for entry in ["spotlight", "capture"] {
            do {
                _ = try await platform.openSystemEntrypoint(installedPackageID: installedID, entrypointID: entry,
                    generation: 2, parameters: .null)
                XCTFail("A disabled package reached system-entrypoint execution.")
            } catch HanlinMiniAppSystemEntrypointError.unavailable { }
        }
        XCTAssertEqual(platform.installedPackages.first?.enabled, false)
        XCTAssertNil(platform.activeApplicationID)
        XCTAssertNil(platform.activeExpoController)
        XCTAssertNil(platform.activeNativeScriptController)
        XCTAssertEqual(platform.activity, .idle)
        XCTAssertTrue(try extensions.scanPendingCommands(limit: 8).commands.isEmpty)
    }

    func testInactiveSystemWindowReleasesPresentationWithoutTakingTheNewOwner() {
        let entrypoints = HanlinMiniAppSystemEntrypoints()
        let captures = HanlinMiniAppCaptureCoordinator()
        let first = UUID(), second = UUID()
        // This is the same transition used by the actual scene modifier.
        entrypoints.updateWindowActivity(true, windowID: first, captures: captures)
        XCTAssertEqual(entrypoints.presentationWindowID, first)
        entrypoints.updateWindowActivity(false, windowID: first, captures: captures)
        XCTAssertNil(entrypoints.presentationWindowID)
        entrypoints.updateWindowActivity(true, windowID: second, captures: captures)
        XCTAssertEqual(entrypoints.presentationWindowID, second)
        // The first scene's later disappearance cannot release the new owner.
        entrypoints.updateWindowActivity(false, windowID: first, captures: captures)
        XCTAssertEqual(entrypoints.presentationWindowID, second)
        entrypoints.updateWindowActivity(false, windowID: second, captures: captures)
        XCTAssertNil(entrypoints.presentationWindowID)
    }

    func testUnrelatedAndLateCameraDismissalsPreserveOwnedCaptureAndPhotos() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "camera-window-" + UUID().uuidString.lowercased(), directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let product = "com.itorah.hanlinminiapps"
        let files = try HanlinCameraSessionFiles(directory: directory, productIdentifier: product,
                                                 source: .applicationCamera, target: nil)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3)).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        }
        let bytes = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let photo = try await files.saveJPEG(bytes, width: 2, height: 3)
        let captures = HanlinMiniAppCaptureCoordinator()
        let entrypoints = HanlinMiniAppSystemEntrypoints()
        let first = UUID(), second = UUID(), unrelated = UUID()
        let presentation = HanlinMiniAppCameraPresentation(directory: directory, target: nil)
        captures.cameraPresentation = presentation
        entrypoints.updateWindowActivity(true, windowID: first, captures: captures)
        await captures.claimCameraRequest(windowID: first)
        XCTAssertEqual(captures.cameraWindowID, first)
        await captures.cameraDidDismiss(windowID: unrelated)
        // A late callback from an older cover in the same window must also
        // leave a currently presented camera intact.
        await captures.cameraDidDismiss(windowID: first)
        XCTAssertEqual(captures.cameraWindowID, first)
        XCTAssertEqual(captures.cameraPresentation?.id, presentation.id)

        entrypoints.updateWindowActivity(false, windowID: first, captures: captures)
        XCTAssertNil(captures.cameraWindowID)
        XCTAssertEqual(captures.cameraPresentation?.id, presentation.id)
        entrypoints.updateWindowActivity(true, windowID: second, captures: captures)
        await captures.claimCameraRequest(windowID: second)
        await captures.cameraDidDismiss(windowID: first)
        XCTAssertEqual(captures.cameraWindowID, second)
        XCTAssertEqual(captures.cameraPresentation?.id, presentation.id)
        XCTAssertEqual(try Data(contentsOf: directory.appending(path: photo.filename)), bytes)
        let reopened = try HanlinCameraSessionFiles(directory: directory, productIdentifier: product,
                                                    source: .applicationCamera, target: nil)
        let manifest = await reopened.currentManifest()
        XCTAssertEqual(manifest.photos, [photo])
        // Complete only the matching dismissed camera; keep the actual inbox
        // outside this isolated ownership test.
        captures.cameraPresentation = nil
        captures.showsInbox = true
        await captures.cameraDidDismiss(windowID: second)
        XCTAssertNil(captures.cameraWindowID)
        XCTAssertTrue(captures.showsInbox)
    }


    func testCameraContextLoadRemainsSingleAcrossWindowReleaseAndNewRequest() async throws {
        let firstWindow = UUID(), secondWindow = UUID()
        let firstTarget = HanlinCameraCaptureTarget(productIdentifier: "com.itorah.hanlinminiapps",
            installedPackageID: UUID().uuidString.lowercased(), packageID: "test.camera.first",
            generation: 1, entrypointID: "capture", actionID: "consumeCapture")
        let secondTarget = HanlinCameraCaptureTarget(productIdentifier: "com.itorah.hanlinminiapps",
            installedPackageID: UUID().uuidString.lowercased(), packageID: "test.camera.second",
            generation: 1, entrypointID: "capture", actionID: "consumeCapture")
        let contextStarted = expectation(description: "Original coordinator requested camera context")
        var pendingRequests = 1
        var contextLoads = 0
        var firstContext: CheckedContinuation<HanlinCameraCaptureTarget?, any Error>?
        let captures = HanlinMiniAppCaptureCoordinator(consumeCameraRequest: {
            guard pendingRequests > 0 else { return false }
            pendingRequests -= 1
            return true
        }, loadCameraContext: {
            contextLoads += 1
            // A second context call deliberately finishes immediately. Without
            // serialization its presentation is overwritten by the first one.
            if contextLoads > 1 { return secondTarget }
            return try await withCheckedThrowingContinuation { continuation in
                firstContext = continuation
                contextStarted.fulfill()
            }
        })
        defer { firstContext?.resume(throwing: CancellationError()) }
        let firstRequest = Task { await captures.claimCameraRequest(windowID: firstWindow) }
        await fulfillment(of: [contextStarted], timeout: 3)
        guard let continuation = firstContext else {
            await firstRequest.value
            XCTFail("The original context loader was not reached.")
            return
        }
        XCTAssertTrue(captures.cameraContextLoading)
        captures.releaseWindow(firstWindow)
        XCTAssertNil(captures.cameraWindowID)
        pendingRequests += 1
        await captures.claimCameraRequest(windowID: secondWindow)
        XCTAssertEqual(contextLoads, 1)
        XCTAssertEqual(pendingRequests, 1, "The newer request must remain pending, not be lost.")
        XCTAssertTrue(captures.cameraContextLoading)
        XCTAssertNil(captures.cameraPresentation)

        firstContext = nil
        continuation.resume(returning: firstTarget)
        await firstRequest.value
        XCTAssertFalse(captures.cameraContextLoading)
        let firstPresentation = try XCTUnwrap(captures.cameraPresentation)
        defer { try? FileManager.default.removeItem(at: firstPresentation.directory) }
        XCTAssertEqual(firstPresentation.target, firstTarget)
        await captures.claimCameraRequest(windowID: secondWindow)
        XCTAssertEqual(captures.cameraWindowID, secondWindow)
        XCTAssertEqual(captures.cameraPresentation?.id, firstPresentation.id)
        XCTAssertEqual(contextLoads, 1)
        captures.cameraPresentation = nil
        captures.showsInbox = true
        await captures.cameraDidDismiss(windowID: secondWindow)

        await captures.claimCameraRequest(windowID: secondWindow)
        let secondPresentation = try XCTUnwrap(captures.cameraPresentation)
        defer { try? FileManager.default.removeItem(at: secondPresentation.directory) }
        XCTAssertEqual(contextLoads, 2)
        XCTAssertEqual(pendingRequests, 0)
        XCTAssertEqual(secondPresentation.target, secondTarget)
        XCTAssertNotEqual(secondPresentation.id, firstPresentation.id)
        XCTAssertEqual(captures.cameraWindowID, secondWindow)
        captures.releaseWindow(secondWindow)
    }

    private func package(installation: String, runtime: HanlinRuntimeProfile, generation: UInt64,
                         name: String, enabled: Bool = true, actionCount: Int = 1) throws -> HanlinStoredPackageSnapshot {
        let source = runtime == .hanlinExpo ? "bundle.js" : "nativescript/app/bundle.mjs"
        let app = HanlinPackageEntrypointDescriptor(id: "app", kind: .app, sourcePath: source,
            supportedContexts: [.mainApplication], runtimePolicyID: "prepared-app-v1", runtimeProfile: runtime, compatibility: .supported)
        let spotlight = HanlinPackageEntrypointDescriptor(id: "spotlight", kind: .spotlight, sourcePath: source,
            supportedContexts: [.mainApplication], runtimePolicyID: "prepared-spotlight-v1", runtimeProfile: runtime, compatibility: .supported)
        let capture = HanlinPackageEntrypointDescriptor(id: "capture", kind: .capture, sourcePath: source, exportedSymbol: "consumeCapture",
            supportedContexts: [.mainApplication], runtimePolicyID: "prepared-capture-v1", runtimeProfile: runtime, compatibility: .supported)
        let action: HanlinJSONValue = .object(["id": .string("consumeCapture"), "handler": .string(source)])
        return .init(record: .init(installedPackageID: try .init(validating: installation), packageID: try .init(validating: "test.camera"),
            version: try .init(validating: "1.0.0"), sourceDigest: String(repeating: "0", count: 64),
            artifactDigest: String(repeating: "1", count: 64), activeGeneration: generation,
            installedAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            entrypoints: [app, spotlight, capture], enabled: enabled, availableGenerations: [generation],
            manifest: .init(name: name, version: "1.0.0", description: "Search installed texts", unknownFields: [
                "actions": .array(Array(repeating: action, count: actionCount)),
                "keywords": .array([.string("texts"), .string("חיפוש")])]))
    }
}
