import Foundation
import HanlinCameraCaptureUI
import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
import HanlinScriptExtensions
import LockedCameraCapture
import Observation
import UIKit

struct HanlinMiniAppCameraPresentation: Identifiable {
    let id = UUID()
    let directory: URL
    let target: HanlinCameraCaptureTarget?
}

@MainActor
@Observable
final class HanlinMiniAppCaptureCoordinator {
    static let shared = HanlinMiniAppCaptureCoordinator()
    private(set) var selectedTarget: HanlinCameraCaptureTarget?
    private(set) var deliveries: [HanlinMiniAppCaptureRecord] = []
    private(set) var receipts: [UUID: HanlinInvocationReceipt] = [:]
    private(set) var cameraWindowID: UUID?
    var cameraPresentation: HanlinMiniAppCameraPresentation?
    var showsInbox = false
    private(set) var inboxWindowID: UUID?
    var error: String?
    @ObservationIgnored private var ownedInbox: HanlinMiniAppCaptureInbox?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var processing = false
    @ObservationIgnored private var processAgain = false
    @ObservationIgnored private var cameraDismissing = false

    private var inbox: HanlinMiniAppCaptureInbox {
        get throws {
            if let ownedInbox { return ownedInbox }
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true).appending(path: "Hanlin/CameraCaptures/v1", directoryHint: .isDirectory)
            let result = HanlinMiniAppCaptureInbox(root: root, productIdentifier: HanlinMiniAppSystemEntrypoints.productIdentifier)
            ownedInbox = result
            return result
        }
    }

    func reconcile(records: [HanlinMiniAppSystemRecord]) async {
        do {
            let previous = try await HanlinCameraCaptureIntent.appContext
            let current = previous.flatMap { prior in records.first {
                $0.productIdentifier == prior.productIdentifier &&
                $0.installedPackageID.rawValue == prior.installedPackageID &&
                $0.packageID.rawValue == prior.packageID && $0.entrypoint.id == prior.entrypointID &&
                $0.entrypoint.exportedSymbol == prior.actionID
            }?.cameraTarget }
            if previous != current { try await HanlinCameraCaptureIntent.updateAppContext(current) }
            selectedTarget = current
        } catch { self.error = error.localizedDescription }
    }

    func select(_ record: HanlinMiniAppSystemRecord) async throws {
        guard let target = record.cameraTarget,
              HanlinMiniAppSystemEntrypoints.shared.captureRecords.contains(record) else {
            throw HanlinMiniAppSystemEntrypointError.unavailable
        }
        try await HanlinCameraCaptureIntent.updateAppContext(target)
        selectedTarget = target
    }

    func requestCamera(for record: HanlinMiniAppSystemRecord) async {
        do {
            try await select(record)
            HanlinCameraCaptureRequests.shared.request()
        } catch { self.error = error.localizedDescription }
    }

    /// A process-wide claim prevents one camera intent from presenting in every
    /// SwiftUI window. Only an active receiving window calls this method.
    func claimCameraRequest(windowID: UUID) async {
        guard cameraWindowID == nil else { return }
        if cameraPresentation != nil { cameraWindowID = windowID; return }
        guard HanlinCameraCaptureRequests.shared.consume() else { return }
        cameraWindowID = windowID
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true).appending(path: "Hanlin/CameraIncoming/" + UUID().uuidString.lowercased(), directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = try await HanlinCameraCaptureIntent.appContext
            cameraPresentation = .init(directory: directory, target: target)
        } catch {
            cameraWindowID = nil
            self.error = error.localizedDescription
        }
    }

    func finishApplicationCapture(directory: URL) async throws {
        let record = try await inbox.receive(directory: directory)
        deliveries = try await inbox.records()
        try FileManager.default.removeItem(at: directory)
        cameraDismissing = true
        cameraPresentation = nil
        if record.selectedTarget == nil { showsInbox = true }
    }

    func cancelApplicationCapture(directory: URL) {
        do { try FileManager.default.removeItem(at: directory) }
        catch { self.error = error.localizedDescription }
        cameraDismissing = true
        cameraPresentation = nil
    }

    func cameraDidDismiss() async {
        cameraWindowID = nil; cameraDismissing = false
        await processAvailable()
    }

    func claimInbox(windowID: UUID) {
        guard showsInbox, inboxWindowID == nil, cameraWindowID == nil else { return }
        inboxWindowID = windowID
    }

    func inboxDidDismiss(windowID: UUID) async {
        guard inboxWindowID == windowID else { return }
        inboxWindowID = nil; showsInbox = false
        await processAvailable()
    }

    func releaseWindow(_ windowID: UUID) {
        if inboxWindowID == windowID { inboxWindowID = nil }
        guard cameraWindowID == windowID else { return }
        cameraWindowID = nil; cameraDismissing = false
        // Retain the presentation/directory for another receiving window. The
        // writer reloads its existing manifest, so window loss cannot erase photos.
    }

    func start() async {
        if cameraPresentation == nil { await recoverApplicationCaptures() }
        await reload()
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await update in LockedCameraCaptureManager.shared.sessionContentUpdates {
                guard !Task.isCancelled, let self else { return }
                switch update {
                case .initial(let urls):
                    for url in urls { await self.receiveSystemSession(url) }
                case .added(let url): await self.receiveSystemSession(url)
                case .removed: break // The app-owned copy/receipt remains authoritative.
                @unknown default: break
                }
            }
        }
    }

    private func recoverApplicationCaptures() async {
        do {
            let incoming = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true).appending(path: "Hanlin/CameraIncoming", directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: incoming.path) else { return }
            let directories = try FileManager.default.contentsOfDirectory(at: incoming,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            for directory in directories where UUID(uuidString: directory.lastPathComponent) != nil {
                guard FileManager.default.fileExists(atPath: directory.appending(path: HanlinCameraCaptureManifest.filename).path) else { continue }
                _ = try await inbox.receive(directory: directory)
                try FileManager.default.removeItem(at: directory)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func receiveSystemSession(_ directory: URL) async {
        do {
            _ = try await inbox.receive(directory: directory)
            // This is the actual system URL, received from the manager. It is
            // invalidated only after durable copy and content verification.
            try await LockedCameraCaptureManager.shared.invalidateSessionContent(at: directory)
            await reload()
            await processAvailable()
        } catch { self.error = error.localizedDescription; showsInbox = true }
    }

    func reload() async {
        do {
            deliveries = try await inbox.records()
            for delivery in deliveries {
                if let receipt = try HanlinScriptingPlatform.shared.resumeReceipt(delivery.invocationID) {
                    receipts[delivery.id] = receipt
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func choose(_ target: HanlinMiniAppSystemRecord, for delivery: HanlinMiniAppCaptureRecord) async {
        do {
            guard let cameraTarget = target.cameraTarget else { throw HanlinMiniAppSystemEntrypointError.invalidAction }
            // Only an explicitly stale, never-executed target may be replaced.
            let existing = try HanlinScriptingPlatform.shared.resumeReceipt(delivery.invocationID)
            guard existing == nil || existing?.status == .stale else {
                throw HanlinCameraCaptureError.invalidSession
            }
            _ = try await inbox.select(cameraTarget, for: delivery.id, replacingUnexecutedDelivery: existing?.status == .stale)
            receipts[delivery.id] = nil
            showsInbox = false
            await reload()
        } catch { self.error = error.localizedDescription }
    }

    func processAvailable() async {
        guard UIApplication.shared.applicationState == .active,
              cameraPresentation == nil, !cameraDismissing, !showsInbox else { return }
        if processing { processAgain = true; return }
        processing = true
        defer { processing = false }
        repeat {
            processAgain = false
            await reload()
            for record in deliveries {
                do {
                    if let receipt = try HanlinScriptingPlatform.shared.resumeReceipt(record.invocationID) {
                        receipts[record.id] = receipt
                        if receipt.status.isTerminal { continue }
                    }
                    guard let target = record.selectedTarget else { showsInbox = true; continue }
                    let platform = HanlinScriptingPlatform.shared
                    await platform.restore()
                    guard target.productIdentifier == HanlinMiniAppSystemEntrypoints.productIdentifier,
                          let installedID = try? HanlinInstalledPackageID(validating: target.installedPackageID),
                          let package = platform.installedPackages.first(where: {
                              $0.record.installedPackageID == installedID && $0.record.packageID.rawValue == target.packageID && $0.enabled
                          }) else { throw HanlinMiniAppSystemEntrypointError.unavailable }
                    guard package.record.activeGeneration == target.generation,
                          HanlinMiniAppSystemEntrypoints.shared.captureRecords.contains(where: { $0.cameraTarget == target }) else {
                        throw HanlinMiniAppSystemEntrypointError.staleGeneration
                    }
                    let container = try await HanlinMiniAppHost.shared.dataStore.container(for: package.appID)
                    _ = try await inbox.copyPhotos(for: record.id, documents: container.documents)
                    let files: [HanlinValue] = record.manifest.photos.map { photo in
                        .object(["id": .string(photo.id.uuidString.lowercased()), "area": .string("documents"),
                            "path": .string("captures/" + record.id.uuidString.lowercased() + "/" + photo.filename),
                            "contentType": .string(photo.contentType), "mimeType": .string("image/jpeg"),
                            "byteCount": .number(Double(photo.byteCount)), "sha256": .string(photo.sha256),
                            "width": .number(Double(photo.width)), "height": .number(Double(photo.height))])
                    }
                    let payload: HanlinValue = .object([
                        "source": .string(record.manifest.source.rawValue), "sessionID": .string(record.id.uuidString.lowercased()),
                        "installedPackageID": .string(target.installedPackageID), "packageID": .string(target.packageID),
                        "generation": .number(Double(target.generation)), "entrypointID": .string(target.entrypointID),
                        "files": .array(files)
                    ])
                    _ = try await platform.openSystemEntrypoint(installedPackageID: installedID,
                        entrypointID: target.entrypointID, generation: target.generation, parameters: payload,
                        invocationID: record.invocationID, createdAt: record.invocationCreatedAt)
                    try await inbox.markSubmitted(record.id, invocationID: record.invocationID)
                    if let receipt = try platform.resumeReceipt(record.invocationID) { receipts[record.id] = receipt }
                } catch {
                    self.error = error.localizedDescription
                    showsInbox = true
                }
            }
        } while processAgain && !showsInbox
        await reload()
    }
}
