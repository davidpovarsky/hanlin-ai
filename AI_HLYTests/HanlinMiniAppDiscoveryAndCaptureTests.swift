import Foundation
import HanlinCameraCaptureUI
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
import UIKit
import XCTest
@testable import AI_Hanlin

/// Installed-data and durable-transfer tests. These do not substitute for actual
/// Spotlight search/tap, lock-screen launch or physical Camera Control acceptance.
@MainActor
final class HanlinMiniAppDiscoveryAndCaptureTests: XCTestCase {
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
