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

    func testCatalogPublicationAwaitsCaptureButNotSpotlight() async throws {
        let snapshot = try package(installation: UUID().uuidString.lowercased(), runtime: .hanlinExpo,
                                   generation: 1, name: "Published before indexing")
        let writeStarted = expectation(description: "Real projection boundary entered")
        let captureStarted = expectation(description: "Existing Capture boundary entered")
        let publicationFinished = expectation(description: "Capture completed without an index acknowledgment")
        let writeGate = SpotlightTestGate(), captureGate = SpotlightTestGate()
        defer {
            writeGate.finish(.failure(CancellationError()))
            captureGate.finish(.failure(CancellationError()))
        }
        var publicationReturned = false
        var capturedRecords: [HanlinMiniAppSystemRecord] = []
        let entrypoints = HanlinMiniAppSystemEntrypoints(productIdentifier: "com.itorah.hanlinminiapps",
            isProductTransferActive: { false }, indexOperation: { records in
                XCTAssertEqual(records.map(\.entrypoint.kind), [.spotlight])
                writeStarted.fulfill()
                try await writeGate.wait()
            }, reconcileCapture: { records in
                capturedRecords = records
                captureStarted.fulfill()
                try? await captureGate.wait()
            })
        let publication = Task {
            await entrypoints.reconcile(packages: [snapshot], artifactRoot: { _ in nil })
            publicationReturned = true
            publicationFinished.fulfill()
        }
        await fulfillment(of: [writeStarted, captureStarted], timeout: 3)
        XCTAssertEqual(entrypoints.records.count, 2)
        XCTAssertEqual(capturedRecords.map(\.entrypoint.kind), [.capture])
        XCTAssertFalse(publicationReturned, "The existing Capture await must remain a readiness boundary.")
        XCTAssertTrue(entrypoints.hasPendingWork)

        captureGate.finish(.success(()))
        await fulfillment(of: [publicationFinished], timeout: 3)
        XCTAssertTrue(publicationReturned, "Spotlight is optional OS maintenance, not catalog readiness.")
        XCTAssertTrue(entrypoints.hasPendingWork, "A pending system operation still prevents product transfer.")
        writeGate.finish(.success(()))
        await publication.value
        await entrypoints.waitForPendingSpotlightReconciliation()
        XCTAssertFalse(entrypoints.hasPendingWork)
        XCTAssertNil(entrypoints.spotlightError)
    }

    func testSpotlightWorkerCoalescesToLatestPublishedRecords() async throws {
        let installation = UUID().uuidString.lowercased()
        let snapshots = try (1...3).map {
            try package(installation: installation, runtime: .hanlinNativeScript,
                        generation: UInt64($0), name: "Generation \($0)")
        }
        let firstWriteStarted = expectation(description: "First index write held")
        let firstWrite = SpotlightTestGate()
        defer { firstWrite.finish(.failure(CancellationError())) }
        var writes: [[UInt64]] = []
        var activeWrites = 0, maximumActiveWrites = 0
        let entrypoints = HanlinMiniAppSystemEntrypoints(productIdentifier: "com.itorah.hanlinminiapps",
            isProductTransferActive: { false }, indexOperation: { records in
                activeWrites += 1
                maximumActiveWrites = max(maximumActiveWrites, activeWrites)
                defer { activeWrites -= 1 }
                writes.append(records.map(\.generation))
                if writes.count == 1 {
                    firstWriteStarted.fulfill()
                    try await firstWrite.wait()
                }
            }, reconcileCapture: { _ in })
        await entrypoints.reconcile(packages: [snapshots[0]], artifactRoot: { _ in nil })
        await fulfillment(of: [firstWriteStarted], timeout: 3)
        await entrypoints.reconcile(packages: [snapshots[1]], artifactRoot: { _ in nil })
        await entrypoints.reconcile(packages: [snapshots[2]], artifactRoot: { _ in nil })
        XCTAssertEqual(entrypoints.spotlightRecords.map(\.generation), [3])
        XCTAssertEqual(writes, [[1]], "Publications must not start competing index writes.")
        firstWrite.finish(.success(()))
        await entrypoints.waitForPendingSpotlightReconciliation()
        XCTAssertEqual(writes, [[1], [3]], "The single worker must drain the latest desired generation.")
        XCTAssertEqual(maximumActiveWrites, 1)
        XCTAssertFalse(entrypoints.hasPendingWork)
    }

    func testFailedSpotlightWriteCannotReusePreviousSuccessfulProjection() async throws {
        let snapshot = try package(installation: UUID().uuidString.lowercased(), runtime: .hanlinExpo,
                                   generation: 1, name: "Still installed")
        let deletionStarted = expectation(description: "A potentially partial deletion is held")
        let deletion = SpotlightTestGate()
        defer { deletion.finish(.failure(CancellationError())) }
        var writes: [[UInt64]] = []
        let entrypoints = HanlinMiniAppSystemEntrypoints(productIdentifier: "com.itorah.hanlinminiapps",
            isProductTransferActive: { false }, indexOperation: { records in
                writes.append(records.map(\.generation))
                if writes.count == 2 {
                    deletionStarted.fulfill()
                    try await deletion.wait()
                }
            }, reconcileCapture: { _ in })
        await entrypoints.reconcile(packages: [snapshot], artifactRoot: { _ in nil })
        await entrypoints.waitForPendingSpotlightReconciliation()
        await entrypoints.reconcile(packages: [], artifactRoot: { _ in nil })
        await fulfillment(of: [deletionStarted], timeout: 3)
        await entrypoints.reconcile(packages: [snapshot], artifactRoot: { _ in nil })
        deletion.finish(.failure(SpotlightTestFailure.rejected))
        await entrypoints.waitForPendingSpotlightReconciliation()
        XCTAssertEqual(writes, [[1], [], [1]], "A partial failed write invalidates the older success cache.")
        XCTAssertEqual(entrypoints.spotlightRecords.map(\.generation), [1])
        XCTAssertNil(entrypoints.spotlightError, "Only the real subsequent successful write clears the error.")
        XCTAssertFalse(entrypoints.hasPendingWork)
    }

    func testSpotlightFailureRemainsVisibleUntilRealRetry() async throws {
        let snapshot = try package(installation: UUID().uuidString.lowercased(), runtime: .hanlinExpo,
                                   generation: 1, name: "Retry")
        var rejectNextWrite = true
        var writes = 0
        let entrypoints = HanlinMiniAppSystemEntrypoints(productIdentifier: "com.itorah.hanlinminiapps",
            isProductTransferActive: { false }, indexOperation: { _ in
                writes += 1
                if rejectNextWrite {
                    rejectNextWrite = false
                    throw SpotlightTestFailure.rejected
                }
            }, reconcileCapture: { _ in })
        await entrypoints.reconcile(packages: [snapshot], artifactRoot: { _ in nil })
        await entrypoints.waitForPendingSpotlightReconciliation()
        XCTAssertEqual(writes, 1, "A failed worker must not retry indefinitely by itself.")
        XCTAssertNotNil(entrypoints.spotlightError)
        XCTAssertFalse(entrypoints.hasPendingWork)
        await entrypoints.reconcile(packages: [snapshot], artifactRoot: { _ in nil })
        await entrypoints.waitForPendingSpotlightReconciliation()
        XCTAssertEqual(writes, 2, "A failed attempt must not be cached as indexed.")
        XCTAssertNil(entrypoints.spotlightError)

        rejectNextWrite = true
        do {
            try await entrypoints.reindexSpotlight()
            XCTFail("The explicit system reindex callback must receive the actual failure.")
        } catch SpotlightTestFailure.rejected { }
        XCTAssertFalse(entrypoints.hasPendingWork)
        await entrypoints.reconcile(packages: [snapshot], artifactRoot: { _ in nil })
        await entrypoints.waitForPendingSpotlightReconciliation()
        XCTAssertEqual(writes, 4, "The explicit failed write also invalidates an earlier successful cache.")
    }

    func testExplicitReindexAcknowledgesOnlyCompletedLatestProjection() async throws {
        let installation = UUID().uuidString.lowercased()
        let initial = try package(installation: installation, runtime: .hanlinNativeScript,
                                  generation: 1, name: "Initial")
        let latest = try package(installation: installation, runtime: .hanlinNativeScript,
                                 generation: 2, name: "Latest")
        let explicitStarted = expectation(description: "Explicit reindex actually entered its write")
        let latestStarted = expectation(description: "Latest-generation write actually entered")
        let explicitGate = SpotlightTestGate(), latestGate = SpotlightTestGate()
        defer {
            explicitGate.finish(.failure(CancellationError()))
            latestGate.finish(.failure(CancellationError()))
        }
        var writes: [[UInt64]] = []
        var activeWrites = 0, maximumActiveWrites = 0
        var latestObserved = false, acknowledged = false
        let entrypoints = HanlinMiniAppSystemEntrypoints(productIdentifier: "com.itorah.hanlinminiapps",
            isProductTransferActive: { false }, indexOperation: { records in
                activeWrites += 1
                maximumActiveWrites = max(maximumActiveWrites, activeWrites)
                defer { activeWrites -= 1 }
                writes.append(records.map(\.generation))
                if writes.count == 2 {
                    explicitStarted.fulfill()
                    try await explicitGate.wait()
                }
                if records.first?.generation == 2 {
                    if !latestObserved {
                        latestObserved = true
                        latestStarted.fulfill()
                    }
                    try await latestGate.wait()
                }
            }, reconcileCapture: { _ in })
        await entrypoints.reconcile(packages: [initial], artifactRoot: { _ in nil })
        await entrypoints.waitForPendingSpotlightReconciliation()
        let explicit = Task {
            try await entrypoints.reindexSpotlight()
            acknowledged = true
        }
        await fulfillment(of: [explicitStarted], timeout: 3)
        XCTAssertFalse(acknowledged)
        XCTAssertTrue(entrypoints.hasPendingWork)
        await entrypoints.reconcile(packages: [latest], artifactRoot: { _ in nil })
        explicitGate.finish(.success(()))
        await fulfillment(of: [latestStarted], timeout: 3)
        XCTAssertFalse(acknowledged, "The callback cannot acknowledge an outdated generation.")
        latestGate.finish(.success(()))
        try await explicit.value
        await entrypoints.waitForPendingSpotlightReconciliation()
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(writes.last, [2])
        XCTAssertEqual(maximumActiveWrites, 1)
        XCTAssertFalse(entrypoints.hasPendingWork)
        let completedWrites = writes.count
        await entrypoints.reconcile(packages: [latest], artifactRoot: { _ in nil })
        await entrypoints.waitForPendingSpotlightReconciliation()
        XCTAssertEqual(writes.count, completedWrites, "A late older caller cannot replace the newest success cache.")
    }

    func testSpotlightWorkOwnsTransferAdmissionUntilCompletion() async throws {
        let installation = UUID().uuidString.lowercased()
        let initial = try package(installation: installation, runtime: .hanlinExpo,
                                  generation: 1, name: "Initial")
        let replacement = try package(installation: installation, runtime: .hanlinExpo,
                                      generation: 2, name: "After transfer")
        let writeStarted = expectation(description: "Index operation is pending")
        let writeGate = SpotlightTestGate()
        defer { writeGate.finish(.failure(CancellationError())) }
        var transferActive = false
        var writes = 0, captures = 0
        let entrypoints = HanlinMiniAppSystemEntrypoints(productIdentifier: "com.itorah.hanlinminiapps",
            isProductTransferActive: { transferActive }, indexOperation: { _ in
                writes += 1
                if writes == 1 {
                    writeStarted.fulfill()
                    try await writeGate.wait()
                }
            }, reconcileCapture: { _ in captures += 1 })
        await entrypoints.reconcile(packages: [initial], artifactRoot: { _ in nil })
        XCTAssertTrue(entrypoints.hasPendingWork, "Ownership begins before the worker's first suspension.")
        await fulfillment(of: [writeStarted], timeout: 3)
        XCTAssertTrue(entrypoints.hasPendingWork)
        writeGate.finish(.success(()))
        await entrypoints.waitForPendingSpotlightReconciliation()
        XCTAssertFalse(entrypoints.hasPendingWork, "A retained completed serialization tail is not active work.")
        transferActive = true
        do {
            try await entrypoints.reindexSpotlight()
            XCTFail("An explicit callback cannot start an index write during product transfer.")
        } catch HanlinProductTransferError.busy { }
        await entrypoints.reconcile(packages: [replacement], artifactRoot: { _ in nil })
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(captures, 1)
        XCTAssertEqual(entrypoints.spotlightRecords.map(\.generation), [1])
        XCTAssertFalse(entrypoints.hasPendingWork)
        transferActive = false
        await entrypoints.reconcile(packages: [replacement], artifactRoot: { _ in nil })
        await entrypoints.waitForPendingSpotlightReconciliation()
        XCTAssertEqual(writes, 2)
        XCTAssertEqual(captures, 2)
        XCTAssertEqual(entrypoints.spotlightRecords.map(\.generation), [2])
    }

    private enum SpotlightTestFailure: Error { case rejected }

    @MainActor
    private final class SpotlightTestGate {
        private var result: Result<Void, any Error>?
        private var waiters: [CheckedContinuation<Void, any Error>] = []

        func wait() async throws {
            if let result { return try result.get() }
            try await withCheckedThrowingContinuation { waiters.append($0) }
        }

        func finish(_ result: Result<Void, any Error>) {
            guard self.result == nil else { return }
            self.result = result
            let current = waiters
            waiters.removeAll()
            for waiter in current { waiter.resume(with: result) }
        }
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
