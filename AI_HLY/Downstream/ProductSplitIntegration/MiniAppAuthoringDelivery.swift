import CryptoKit
import Foundation
import HanlinProductSplit
import UIKit

@MainActor
enum MiniAppAuthoringDelivery {
    enum DeliveryError: LocalizedError {
        case companionUnavailable, packageChanged
        var errorDescription: String? {
            switch self {
            case .companionUnavailable:
                "Hanlin MiniApps could not be opened. The package is saved in the delivery queue."
            case .packageChanged:
                "The package bytes no longer match the saved import request."
            }
        }
    }

    static func store() throws -> MiniAppAuthoringTransferStore {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.itorah.shared")
        return try .init(transportRoot: SplitAppStorageLayout.transportRoot(appGroupContainer: container))
    }

    static func digest(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func prepareRepair(archive: URL, originalFileName: String, diagnostics: Data) throws -> URL {
        let transfer = MiniAppAuthoringTransfer(purpose: .repair,
            originalFileName: originalFileName, archiveSHA256: try digest(archive))
        try store().enqueue(transfer, archive: archive, diagnosticsJSON: diagnostics)
        return transfer.wakeURL
    }

    static func verifiedArchive(_ id: UUID, purpose: MiniAppAuthoringTransfer.Purpose)
        throws -> (MiniAppAuthoringTransferStore, MiniAppAuthoringTransfer, URL) {
        let store = try store()
        let transfer = try store.request(id)
        guard transfer.purpose == purpose else { throw MiniAppAuthoringTransferStore.StoreError.invalidRequest }
        let archive = try store.archiveURL(for: id)
        guard try digest(archive) == transfer.archiveSHA256 else { throw DeliveryError.packageChanged }
        return (store, transfer, archive)
    }

    /// The tool succeeds at queueing; only the receiver's durable receipt can
    /// report an installation. It uses exactly the regular import/install path.
    static func importArchive(at url: URL) async throws -> String {
        let transfer = MiniAppAuthoringTransfer(purpose: .install,
            originalFileName: url.lastPathComponent, archiveSHA256: try digest(url))
        let store = try store()
        try store.enqueue(transfer, archive: url, diagnosticsJSON: Data("{}".utf8))
        let opened = await withCheckedContinuation { continuation in
            UIApplication.shared.open(transfer.wakeURL, options: [:]) {
                continuation.resume(returning: $0)
            }
        }
        let receipt = try store.receipt(for: transfer.id)
        let message: String
        switch receipt.status {
        case .installed:
            message = receipt.message ?? "Hanlin MiniApps installed the original package and published its catalog entry."
        case .failed:
            message = receipt.message ?? "Hanlin MiniApps could not install the original package."
        case .received:
            message = "Hanlin MiniApps received the package and is validating/installing it. Query import_miniapp with transfer_id for the result."
        case .submitted:
            message = receipt.message ?? "The receiver submitted this request. Query import_miniapp with transfer_id for its result."
        case .queued:
            message = opened
                ? "The original package is queued in Hanlin MiniApps. Query import_miniapp with transfer_id for its actual installation result."
                : "The original package remains queued. Open Hanlin MiniApps and retry this wake URL."
        }
        var payload: [String: Any] = [
            "transfer_id": transfer.id.uuidString.lowercased(),
            "status": receipt.status.rawValue,
            "companion_opened": opened,
            "wake_url": transfer.wakeURL.absoluteString,
            "message": message,
            "receipt": try JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt))
        ]
        if let installedID = receipt.installedPackageID { payload["installedPackageID"] = installedID }
        return String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self)
    }

    static func status(transferID: UUID) throws -> String {
        let receipt = try store().receipt(for: transferID)
        return String(decoding: try JSONEncoder().encode(receipt), as: UTF8.self)
    }

    private static var activeImports: [UUID: Task<Void, Error>] = [:]
    private static var importTail: Task<Void, Never>?

    static func receiveImport(_ id: UUID, platform: HanlinScriptingPlatform) async throws {
        if let active = activeImports[id] {
            try await active.value
            return
        }
        let predecessor = importTail
        let task = Task { @MainActor in
            if let predecessor { await predecessor.value }
            try await performImport(id, platform: platform)
        }
        activeImports[id] = task
        importTail = Task { _ = await task.result }
        defer { activeImports[id] = nil }
        try await task.value
    }

    private static func performImport(_ id: UUID, platform: HanlinScriptingPlatform) async throws {
        let (store, transfer, archive) = try verifiedArchive(id, purpose: .install)
        let previous = try store.receipt(for: id)
        if previous.status == .installed { return }
        try store.record(.init(transferID: id, status: .received))
        await platform.importPackage(from: archive)
        guard platform.preview?.source.contentSHA256 == transfer.archiveSHA256 else {
            let message: String
            if case .failed(let reason) = platform.activity { message = reason }
            else { message = "The import was replaced by another package before installation." }
            try store.record(.init(transferID: id, status: .failed, message: message))
            return
        }
        guard platform.canInstallPreview else {
            let description = platform.importDiagnostics.map(\.message).joined(separator: "\n")
            try store.record(.init(transferID: id, status: .failed,
                message: description.isEmpty ? "Import validation did not succeed." : description))
            return
        }
        let sourceDigest = platform.preview?.source.contentSHA256
        await platform.installPreview()
        if platform.activity == .idle, let sourceDigest,
           let package = platform.installedPackages.first(where: { $0.record.sourceDigest == sourceDigest }) {
            // Publish the same actual installed registry before telling the agent
            // that the package is available in the companion catalog.
            try await HanlinMiniAppsProvider(platform: platform).refreshCatalog()
            let publicationMessage = platform.widgetPublicationDiagnostics[package.record.installedPackageID].map {
                "The package is installed, but an extension could not be published: " + $0.redactedReportString
            }
            try store.record(.init(transferID: id, status: .installed,
                installedPackageID: package.record.installedPackageID.rawValue, message: publicationMessage))
        } else {
            let message: String
            if case .failed(let reason) = platform.activity { message = reason }
            else { message = "Installation did not return an installed package." }
            try store.record(.init(transferID: id, status: .failed, message: message))
        }
    }
}
